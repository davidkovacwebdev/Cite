extends Node

signal opponent_vitals_updated(hp: int, max_hp: int, mana: int, max_mana: int)
signal opponent_guess_result(correct: bool, damage: int, guess: String)
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

# "Skip article" vote (MultiplayerBoard): the round is skipped as a draw once
# both players vote. The opponent's vote is kept here with its round number,
# since it can arrive before this client's board for that round exists.
signal opponent_skip_voted(round_number: int)

# In-match chat (MultiplayerBoard's ChatPanel). The board is rebuilt every
# round, so the history lives here instead and the board replays it on load.
signal chat_message_added(sender_name: String, text: String, is_own: bool)

# Fired by MultiplayerLobby's own handshake (see start_as_host/start_as_guest
# below) once both sides have confirmed a working message channel, and on
# failure/disconnect respectively. Replaces Godot's peer_connected/
# connected_to_server/peer_disconnected - there's no MultiplayerPeer here to
# provide those.
signal connection_established
signal connection_failed

# Mid-match connection drop (see "Reconnecting" below): the match pauses on
# both sides until messages flow again or RECONNECT_GRACE_SECONDS pass.
signal match_connection_lost
signal match_connection_restored

const CHANNEL := 0
const MAX_MESSAGES_PER_POLL := 16
const MAX_CHAT_LENGTH := 200
const MAX_CHAT_HISTORY := 100

var _opponent_id: int = 0
var _connected: bool = false
var chat_history: Array = []  # [{"name": String, "text": String, "own": bool}]
var opponent_skip_round: int = -1
# The opponent's Ranked rating, -1 until their "rating" message arrives (it
# can beat this client's own match setup, so it's kept here - see Ratings).
var opponent_rating: int = -1

# --- Reconnecting -----------------------------------------------------------------
# During a match both sides send a "ping" every HEARTBEAT_SECONDS. Nothing
# heard for LOST_AFTER_SECONDS (or Steam reports the session failed) = the
# connection dropped: the whole match pauses (get_tree().paused - every match
# timer is pausable) behind an overlay, and pings keep going out, which
# re-opens the Steam session once the network is back.
#
# So nothing sent around the drop gets lost, game messages carry a sequence
# number; pings carry "ack" = the last one received. Anything not acked
# within RESEND_SECONDS is sent again, and the receiver drops numbers it has
# already handled, so every message is handled exactly once, in order.
#
# If the grace period runs out, the client still connected to Steam takes the
# win (its opponent is the one who went offline); a client that lost Steam
# itself takes the loss. Both online but unable to reach each other would
# give both a win - rare enough to accept without a server to arbitrate.
const HEARTBEAT_SECONDS := 1.0
const LOST_AFTER_SECONDS := 6.0
const RECONNECT_GRACE_SECONDS := 30.0
const RESEND_SECONDS := 3.0
const UNSEQUENCED := ["hello", "hello_ack", "ping"]

var connection_lost := false
var _out_seq := 0
var _in_seq := 0
var _unacked := {}  # seq -> {"payload": Dictionary, "sent": msec}, in send order
var _last_heard_ms := 0
var _last_ping_ms := 0
var _lost_since_ms := 0
var _was_live := false
var _overlay: CanvasLayer
var _overlay_status: Label


func _ready() -> void:
	# Keeps receiving (and pinging) while a dropped connection pauses the match.
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_update_connection_watch()


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
	if _match_live():
		_on_connection_lost()  # wait for them to come back instead of ending right away
		return
	_on_opponent_left()


func _handle_message(msg: Dictionary) -> void:
	_last_heard_ms = Time.get_ticks_msec()
	if connection_lost:
		_on_connection_restored()
	if msg.has("ack"):
		_drop_acked(int(msg.ack))
	if msg.has("seq"):
		var seq := int(msg.seq)
		if seq != _in_seq + 1:
			return  # already handled (a resend), or one before it is still missing - it's coming
		_in_seq = seq
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
			opponent_guess_result.emit(msg.correct, msg.damage, str(msg.get("guess", "")))
		"match_over":
			opponent_match_over.emit(msg.outcome)
		"freeze":
			you_were_frozen.emit(msg.duration)
		"scramble":
			chunks_scrambled.emit(msg.duration)
		"double_down":
			Global.opponent_double_down_armed = bool(msg.get("armed", false))
		"card_reward":
			card_reward_received.emit(msg.winner_action, msg.loser_action)
		"reward_picker_started":
			reward_picker_started.emit(msg.key_a, msg.key_b)
		"reward_none":
			reward_none.emit()
		"skip_vote":
			_on_opponent_skip_vote(int(msg.get("round", -1)))
		"chat":
			_add_chat(Global.multiplayer_opponent_name, str(msg.get("text", "")), false)
		"player_left":
			_on_opponent_left()
		"ping":
			pass  # only here for "ack" and to show we're alive
		"rating":
			opponent_rating = int(msg.get("rating", -1))
			Ratings.set_opponent_rating(opponent_rating)


func _send_raw(payload: Dictionary) -> void:
	if _opponent_id == 0:
		return
	if not payload.get("type", "") in UNSEQUENCED:
		_out_seq += 1
		payload["seq"] = _out_seq
		_unacked[_out_seq] = {"payload": payload, "sent": Time.get_ticks_msec()}
	_send_bytes(payload)


func _send_bytes(payload: Dictionary) -> void:
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
	opponent_skip_round = -1
	opponent_rating = -1
	_reset_reliability()
	_send_raw({"type": "hello"})


# Called by MultiplayerLobby once the guest knows the host's Steam ID. Doesn't
# send anything proactively - just waits for the host's "hello" (handled in
# _handle_message above), which doubles as proof the channel works both ways
# once the guest's reply reaches the host.
func start_as_guest(opponent_steam_id: int) -> void:
	_connected = false
	_opponent_id = opponent_steam_id
	chat_history.clear()
	opponent_skip_round = -1
	opponent_rating = -1
	_reset_reliability()


func reset_connection() -> void:
	if _opponent_id != 0:
		Steam.closeSessionWithUser(_opponent_id)
	_opponent_id = 0
	_connected = false
	chat_history.clear()
	opponent_skip_round = -1
	_reset_reliability()


func _is_connected() -> bool:
	return _connected


func send_vitals(hp: int, max_hp: int, mana: int, max_mana: int) -> void:
	if not _is_connected():
		return
	_send_raw({"type": "vitals", "hp": hp, "max_hp": max_hp, "mana": mana, "max_mana": max_mana})


# guess is the text the player typed (only sent for a correct guess) - the
# loser's board shows it in the answer box.
func send_guess_result(correct: bool, damage: int = 0, guess: String = "") -> void:
	if Global.is_dummy_opponent:
		# There's no real peer to message in dummy mode - a correct guess
		# there deals damage straight to the dummy so the new reveal/damage
		# loop can be tested end-to-end without a real second player.
		if correct:
			dummy_damage_taken.emit(damage)
		return
	if not _is_connected():
		return
	_send_raw({"type": "guess_result", "correct": correct, "damage": damage, "guess": guess.left(MAX_CHAT_LENGTH)})


func send_double_down_state(armed: bool) -> void:
	if Global.is_dummy_opponent or not _is_connected():
		return
	_send_raw({"type": "double_down", "armed": armed})


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


# Votes can't be taken back: with a retractable vote, a "withdraw" crossing
# the other player's "vote" on the wire would skip the round on one client
# only.
func send_skip_vote(round_number: int) -> void:
	if Global.is_dummy_opponent:
		# The bot always agrees, after a moment.
		get_tree().create_timer(1.5).timeout.connect(func(): _on_opponent_skip_vote(round_number))
		return
	if not _is_connected():
		return
	_send_raw({"type": "skip_vote", "round": round_number})


func _on_opponent_skip_vote(round_number: int) -> void:
	opponent_skip_round = round_number
	opponent_skip_voted.emit(round_number)


func send_reward_none() -> void:
	if Global.is_dummy_opponent:
		return
	if not _is_connected():
		return
	_send_raw({"type": "reward_none"})


# Ranked only: tells the opponent our rating, for their Elo calculation.
func send_rating(rating: int) -> void:
	if not _is_connected():
		return
	_send_raw({"type": "rating", "rating": rating})


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
	_add_chat(Global.get_own_name(), text, true)
	if Global.is_dummy_opponent or not _is_connected():
		return
	_send_raw({"type": "chat", "text": text})


# DummyOpponent's stand-in for a real opponent's "chat" message.
func receive_dummy_chat(text: String) -> void:
	_add_chat(Global.multiplayer_opponent_name, text, false)


func _add_chat(sender_name: String, text: String, is_own: bool) -> void:
	text = text.strip_edges().left(MAX_CHAT_LENGTH)
	if text.is_empty():
		return
	chat_history.append({"name": sender_name, "text": text, "own": is_own})
	if chat_history.size() > MAX_CHAT_HISTORY:
		chat_history.pop_front()
	chat_message_added.emit(sender_name, text, is_own)


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
	Ratings.finish_match(outcome)
	Global.leave_multiplayer_lobby()
	reset_connection()
	Global.show_match_end()


func _on_opponent_left() -> void:
	if not Global.is_multiplayer_match or Global.multiplayer_match_over:
		return
	Global.multiplayer_match_over = true
	Global.multiplayer_match_outcome = "won"
	Ratings.finish_match("won")
	Global.leave_multiplayer_lobby()
	reset_connection()
	Global.show_match_end("Opponent left")


# --- Reconnecting (see the constants at the top) ------------------------------------

func _match_live() -> bool:
	return _connected and Global.is_multiplayer_match and not Global.multiplayer_match_over \
		and not Global.is_dummy_opponent


func _update_connection_watch() -> void:
	if not _match_live():
		_was_live = false
		return
	var now := Time.get_ticks_msec()
	if not _was_live:
		# Match just started - don't count the time before it.
		_was_live = true
		_last_heard_ms = now
	if now - _last_ping_ms >= HEARTBEAT_SECONDS * 1000.0:
		_last_ping_ms = now
		_send_raw({"type": "ping", "ack": _in_seq})
		for seq in _unacked:
			if now - int(_unacked[seq]["sent"]) >= RESEND_SECONDS * 1000.0:
				_unacked[seq]["sent"] = now
				_send_bytes(_unacked[seq]["payload"])
	if not connection_lost and now - _last_heard_ms >= LOST_AFTER_SECONDS * 1000.0:
		_on_connection_lost()
	if connection_lost:
		var left := RECONNECT_GRACE_SECONDS - (now - _lost_since_ms) / 1000.0
		if left <= 0.0:
			_give_up_reconnecting()
		else:
			_update_overlay(ceili(left))


func _drop_acked(ack: int) -> void:
	for seq in _unacked.keys():
		if seq <= ack:
			_unacked.erase(seq)


func _reset_reliability() -> void:
	_out_seq = 0
	_in_seq = 0
	_unacked.clear()
	_was_live = false
	if connection_lost:
		connection_lost = false
		_set_paused(false)


func _on_connection_lost() -> void:
	if connection_lost:
		return
	print("[MPDEBUG] connection lost - pausing for up to %ds" % RECONNECT_GRACE_SECONDS)
	connection_lost = true
	_lost_since_ms = Time.get_ticks_msec()
	_set_paused(true)
	_update_overlay(ceili(RECONNECT_GRACE_SECONDS))
	match_connection_lost.emit()


func _on_connection_restored() -> void:
	print("[MPDEBUG] connection restored")
	connection_lost = false
	_set_paused(false)
	# Don't wait for the resend timer - send everything they may have missed now.
	var now := Time.get_ticks_msec()
	for seq in _unacked:
		_unacked[seq]["sent"] = now
		_send_bytes(_unacked[seq]["payload"])
	match_connection_restored.emit()


func _give_up_reconnecting() -> void:
	if Steam.loggedOn():
		_on_opponent_left()  # we're online, they never came back
	else:
		_leave_match_as_loss()


func _leave_match_as_loss() -> void:
	Global.end_multiplayer_match("lost")  # also resets the connection (unpauses)
	_set_paused(false)
	Global.show_match_end("Connection lost")


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if paused:
		_show_overlay()
	elif _overlay:
		_overlay.visible = false


func _show_overlay() -> void:
	if _overlay == null:
		_overlay = _build_overlay()
		add_child(_overlay)
	_overlay.visible = true


func _update_overlay(seconds_left: int) -> void:
	if _overlay_status == null:
		return
	var who := Global.multiplayer_opponent_name if not Global.multiplayer_opponent_name.is_empty() else "your opponent"
	var waiting := "You're offline - reconnecting" if not Steam.loggedOn() else "Reconnecting to " + who
	_overlay_status.text = "%s...\nThe match ends in %ds if the connection doesn't come back." % [waiting, seconds_left]


func _build_overlay() -> CanvasLayer:
	var style := preload("res://ui/match/match_style.gd")
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = style.HUB_THEME
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = style.color("overlay_dim")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)  # also swallows clicks meant for the paused match
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TablePanel"
	panel.custom_minimum_size.x = 420
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Connection lost"
	title.theme_type_variation = "HeaderMedium"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_overlay_status = Label.new()
	_overlay_status.theme_type_variation = "MutedLabel"
	_overlay_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_overlay_status)
	var paused_note := Label.new()
	paused_note.text = "The match is paused for both of you."
	paused_note.theme_type_variation = "SmallMuted"
	paused_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(paused_note)
	var leave := Button.new()
	leave.text = "Leave match (counts as a loss)"
	leave.theme_type_variation = "GhostButton"
	leave.focus_mode = Control.FOCUS_NONE
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(func():
		if connection_lost:
			_leave_match_as_loss())
	box.add_child(leave)
	return layer
