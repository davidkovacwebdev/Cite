extends Node

signal opponent_vitals_updated(hp: int, max_hp: int, mana: int, max_mana: int)
signal opponent_guess_result(correct: bool, damage: int)
signal opponent_match_over(outcome: String)
signal dummy_damage_taken(amount: int)
signal you_were_frozen(duration: float)
signal chunks_scrambled(duration: float)
signal card_reward_received(winner_action: int, loser_action: int)

# Round-win reward picker sync (see MultiplayerBoard) - lets the non-guesser
# watch the same choice happen instead of just silently racing ahead into
# the next round while their opponent is still picking.
signal reward_picker_started(key_a: String, key_b: String)
signal reward_none

# In-match chat (MultiplayerBoard's ChatPanel). The board is rebuilt every
# round, so the history lives here instead and the board replays it on load.
signal chat_message_added(sender_name: String, text: String)

# Fired by MultiplayerLobby's own handshake (see start_as_host/start_as_guest
# below) once both sides have confirmed a working message channel, and on
# failure/disconnect respectively. Replaces Godot's peer_connected/
# connected_to_server/peer_disconnected - there's no MultiplayerPeer here to
# provide those.
signal connection_established
signal connection_failed

const CHANNEL := 0
const MAX_MESSAGES_PER_POLL := 16
const MAX_CHAT_LENGTH := 200
const MAX_CHAT_HISTORY := 100

var _opponent_id: int = 0
var _connected: bool = false
var chat_history: Array = []  # [{"name": String, "text": String}]


func _ready() -> void:
	Steam.network_messages_session_request.connect(_on_session_request)
	Steam.network_messages_session_failed.connect(_on_session_failed)
	# dummy_opponent.gd (debug stand-in for a real opponent, no network
	# involved) emits this directly to simulate the dummy winning - route it
	# through the same handler real "match_over" messages use below.
	opponent_match_over.connect(_on_opponent_match_over)


func _process(_delta: float) -> void:
	var messages: Array = Steam.receiveMessagesOnChannel(CHANNEL, MAX_MESSAGES_PER_POLL)
	for message in messages:
		if message == null or message.is_empty():
			continue
		var parsed = bytes_to_var(message.payload)
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("type"):
			continue
		_handle_message(parsed)


# Steam requires the receiving side to explicitly accept an incoming message
# session before any of the sender's messages become readable.
func _on_session_request(remote_id: int) -> void:
	if remote_id == _opponent_id or _opponent_id == 0:
		Steam.acceptSessionWithUser(remote_id)


func _on_session_failed(remote_id: int, session_error: int, state: int, debug_msg: String) -> void:
	if remote_id != _opponent_id:
		return
	print("[MPDEBUG] network_messages_session_failed remote_id=%d error=%d state=%d msg=%s" % [remote_id, session_error, state, debug_msg])
	if not _connected:
		connection_failed.emit()
		return
	_on_opponent_left()


func _handle_message(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"hello":
			if not _connected:
				_send_raw({"type": "hello_ack"})
				_connected = true
				connection_established.emit()
		"hello_ack":
			if not _connected:
				_connected = true
				connection_established.emit()
		"vitals":
			Global.last_known_opponent_hp = msg.hp
			Global.last_known_opponent_max_hp = msg.max_hp
			Global.last_known_opponent_mana = msg.mana
			Global.last_known_opponent_max_mana = msg.max_mana
			opponent_vitals_updated.emit(msg.hp, msg.max_hp, msg.mana, msg.max_mana)
		"guess_result":
			opponent_guess_result.emit(msg.correct, msg.damage)
		"match_over":
			opponent_match_over.emit(msg.outcome)
		"freeze":
			you_were_frozen.emit(msg.duration)
		"scramble":
			chunks_scrambled.emit(msg.duration)
		"card_reward":
			card_reward_received.emit(msg.winner_action, msg.loser_action)
		"reward_picker_started":
			reward_picker_started.emit(msg.key_a, msg.key_b)
		"reward_none":
			reward_none.emit()
		"chat":
			_add_chat(Global.multiplayer_opponent_name, str(msg.get("text", "")))
		"player_left":
			_on_opponent_left()


func _send_raw(payload: Dictionary) -> void:
	if _opponent_id == 0:
		return
	var data := PackedByteArray()
	data.append_array(var_to_bytes(payload))
	Steam.sendMessageToUser(_opponent_id, data, Steam.NETWORKING_SEND_RELIABLE_NO_NAGLE, CHANNEL)


# Called by MultiplayerLobby once the host knows the guest's Steam ID (from
# lobby membership). Sends the opening handshake message - Steam's reliable
# delivery retries this on its own, no manual retry loop needed on our end.
func start_as_host(opponent_steam_id: int) -> void:
	_connected = false
	_opponent_id = opponent_steam_id
	chat_history.clear()
	_send_raw({"type": "hello"})


# Called by MultiplayerLobby once the guest knows the host's Steam ID. Doesn't
# send anything proactively - just waits for the host's "hello" (handled in
# _handle_message above), which doubles as proof the channel works both ways
# once the guest's reply reaches the host.
func start_as_guest(opponent_steam_id: int) -> void:
	_connected = false
	_opponent_id = opponent_steam_id
	chat_history.clear()


func reset_connection() -> void:
	if _opponent_id != 0:
		Steam.closeSessionWithUser(_opponent_id)
	_opponent_id = 0
	_connected = false
	chat_history.clear()


func _is_connected() -> bool:
	return _connected


func send_vitals(hp: int, max_hp: int, mana: int, max_mana: int) -> void:
	if not _is_connected():
		return
	_send_raw({"type": "vitals", "hp": hp, "max_hp": max_hp, "mana": mana, "max_mana": max_mana})


func send_guess_result(correct: bool, damage: int = 0) -> void:
	if Global.is_dummy_opponent:
		# There's no real peer to message in dummy mode - a correct guess
		# there deals damage straight to the dummy so the new reveal/damage
		# loop can be tested end-to-end without a real second player.
		if correct:
			dummy_damage_taken.emit(damage)
		return
	if not _is_connected():
		return
	_send_raw({"type": "guess_result", "correct": correct, "damage": damage})


func send_freeze_opponent(duration: float = 2.0) -> void:
	if Global.is_dummy_opponent:
		return  # no real opponent board to freeze in dummy mode
	if not _is_connected():
		return
	_send_raw({"type": "freeze", "duration": duration})


func send_scramble_opponent(duration: float = 5.0) -> void:
	if Global.is_dummy_opponent:
		return  # no real opponent board to scramble in dummy mode
	if not _is_connected():
		return
	_send_raw({"type": "scramble", "duration": duration})


func send_card_reward(winner_action: int, loser_action: int) -> void:
	if Global.is_dummy_opponent:
		return  # no real opponent to hand the leftover reward card to
	if not _is_connected():
		return
	_send_raw({"type": "card_reward", "winner_action": winner_action, "loser_action": loser_action})


func send_reward_picker_started(key_a: String, key_b: String) -> void:
	if Global.is_dummy_opponent:
		return  # no real opponent to watch the picker in dummy mode
	if not _is_connected():
		return
	_send_raw({"type": "reward_picker_started", "key_a": key_a, "key_b": key_b})


func send_reward_none() -> void:
	if Global.is_dummy_opponent:
		return
	if not _is_connected():
		return
	_send_raw({"type": "reward_none"})


func send_match_over(opponent_outcome: String) -> void:
	if not _is_connected():
		return
	_send_raw({"type": "match_over", "outcome": opponent_outcome})


# Our own message goes straight into the history - unlike lobby chat, Steam
# doesn't echo P2P messages back to the sender. In dummy mode it just stays
# local.
func send_chat(text: String) -> void:
	text = text.strip_edges().left(MAX_CHAT_LENGTH)
	if text.is_empty():
		return
	_add_chat(Global.get_own_name(), text)
	if Global.is_dummy_opponent or not _is_connected():
		return
	_send_raw({"type": "chat", "text": text})


# DummyOpponent's stand-in for a real opponent's "chat" message.
func receive_dummy_chat(text: String) -> void:
	_add_chat(Global.multiplayer_opponent_name, text)


func _add_chat(sender_name: String, text: String) -> void:
	text = text.strip_edges().left(MAX_CHAT_LENGTH)
	if text.is_empty():
		return
	chat_history.append({"name": sender_name, "text": text})
	if chat_history.size() > MAX_CHAT_HISTORY:
		chat_history.pop_front()
	chat_message_added.emit(sender_name, text)


# Explicit "I'm quitting" notice, sent when the game window is closed mid-
# match (see Global._notification). This exists because the only other way
# the opponent finds out is Steam's own connection-timeout detection
# (network_messages_session_failed), which can take a while to fire for a
# clean process exit - this gets them to the end screen immediately instead.
func send_player_left() -> void:
	if not _is_connected():
		return
	_send_raw({"type": "player_left"})


func _on_opponent_match_over(outcome: String) -> void:
	Global.multiplayer_match_over = true
	Global.multiplayer_match_outcome = outcome
	Global.leave_multiplayer_lobby()
	reset_connection()
	get_tree().change_scene_to_file("res://scenes/EndScreen.tscn")


func _on_opponent_left() -> void:
	if not Global.is_multiplayer_match or Global.multiplayer_match_over:
		return
	Global.multiplayer_match_over = true
	Global.multiplayer_match_outcome = "won"
	Global.leave_multiplayer_lobby()
	reset_connection()
	get_tree().change_scene_to_file("res://scenes/EndScreen.tscn")
