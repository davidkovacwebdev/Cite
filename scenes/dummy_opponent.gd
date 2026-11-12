extends Node

# Debug-only stand-in for a real networked opponent. Drives the exact same
# MultiplayerSync signals a real peer's RPCs would emit, so OpponentPanel and
# board.gd's multiplayer branches can be tested without a second Steam account.
class_name DummyOpponent

const BOT_NAME := "Dummy Bot"
# The bot also chats - in the dummy lobby (MultiplayerLobby) and in-match
# (here) - so the chat UI can be tested solo.
const CHAT_INTERVAL_SECONDS := 5.0
# A real winner's picker opens after their own answer banner; the board keeps
# an early message until it starts watching, so the exact timing is loose.
const ANSWER_WAIT := 2.0
const CHAT_LINES := [
	"gl hf",
	"hmm...",
	"I know this one!",
	"wait what",
	"this article is so random",
	"no way",
	"lol",
	"is it a city?",
	"too easy",
	"I'm only a bot, go easy on me",
	"ugh, so close",
	"who even writes these",
	"nice one",
	"I swear I've read this before",
	"brb",
]

# How the bot plays each round (Global.dummy_bot_level): it guesses once the
# board has revealed a random number of chunks in [min, max] (fractions of
# the article), after a short "typing" pause. PASSIVE never guesses.
const GUESS_AT := {
	Global.DummyBotLevel.NORMAL: [0.35, 0.85],
	Global.DummyBotLevel.FAST: [0.1, 0.4],
}
const TYPING_SECONDS := [1.0, 4.0]
# Now and then it guesses wrong (same 50 HP a real wrong guess costs).
const WRONG_GUESS_EVERY_SECONDS := [12.0, 30.0]
const WRONG_GUESS_CHANCE := 0.35
const WRONG_GUESS_DAMAGE := 50
# Reward picker timing, as seen from the loser's side (MultiplayerBoard's
# mirrored picker): it opens after the answer banner, then the bot picks.
const PICK_SECONDS := [1.5, 3.0]

var mana: int = 100
var max_mana: int = 100
var guess_at_fraction := -1.0
var guessing := false
var wrong_timer: Timer


func _ready() -> void:
	MultiplayerSync.dummy_damage_taken.connect(_on_damage_taken)
	_broadcast_vitals()

	var chat_timer = Timer.new()
	chat_timer.wait_time = CHAT_INTERVAL_SECONDS
	chat_timer.timeout.connect(func(): MultiplayerSync.receive_dummy_chat(random_chat_line()))
	add_child(chat_timer)
	chat_timer.start()

	if GUESS_AT.has(Global.dummy_bot_level):
		var span: Array = GUESS_AT[Global.dummy_bot_level]
		guess_at_fraction = randf_range(span[0], span[1])
		wrong_timer = Timer.new()
		wrong_timer.one_shot = true
		wrong_timer.timeout.connect(_maybe_wrong_guess)
		add_child(wrong_timer)
		_restart_wrong_timer()


static func random_chat_line() -> String:
	return CHAT_LINES.pick_random()


# The round's board (rebuilt every round, like this node), once it's live.
func _board() -> Node:
	var round_node = Global.run.current_round
	if round_node == null or not is_instance_valid(round_node.current_board):
		return null
	var board = round_node.current_board
	if not board.is_inside_tree() or not "round_started" in board or not board.round_started:
		return null
	return board


func _process(_delta: float) -> void:
	if guessing or guess_at_fraction < 0.0 or Global.multiplayer_match_over:
		return
	var board = _board()
	if board == null or board.round_advancing or not board.chunks:
		return
	var target := maxi(1, ceili(board.chunks.size() * guess_at_fraction))
	if board.reveal_index >= target:
		guessing = true
		_guess_after_typing()


func _guess_after_typing() -> void:
	await get_tree().create_timer(randf_range(TYPING_SECONDS[0], TYPING_SECONDS[1]), false).timeout
	var board = _board()
	if board == null or board.round_advancing or Global.multiplayer_match_over:
		return  # the player got there first (or the match ended)
	var damage: int = board._current_guess_damage()
	var title: String = Global.run.current_round.article_title
	MultiplayerSync.opponent_guess_result.emit(true, damage, title)
	if Global.multiplayer_match_over or Global.run.last_article:
		return  # no reward on the final article (same as a real winner)
	# Play the winner's side of the reward pick so the mirrored picker shows.
	var keys: Array = MultiplayerBoard.REWARD_SPECIALS.keys()
	keys.shuffle()
	await get_tree().create_timer(ANSWER_WAIT, false).timeout
	if not is_inside_tree() or Global.multiplayer_match_over:
		return
	MultiplayerSync.reward_picker_started.emit(keys[0], keys[1])
	await get_tree().create_timer(randf_range(PICK_SECONDS[0], PICK_SECONDS[1]), false).timeout
	if not is_inside_tree() or Global.multiplayer_match_over:
		return
	var picked := randi() % 2
	MultiplayerSync.card_reward_received.emit(
		MultiplayerBoard.REWARD_SPECIALS[keys[picked]], MultiplayerBoard.REWARD_SPECIALS[keys[1 - picked]])


func _restart_wrong_timer() -> void:
	wrong_timer.start(randf_range(WRONG_GUESS_EVERY_SECONDS[0], WRONG_GUESS_EVERY_SECONDS[1]))


func _maybe_wrong_guess() -> void:
	var board = _board()
	if board != null and not board.round_advancing and not guessing and randf() < WRONG_GUESS_CHANCE:
		_on_damage_taken(WRONG_GUESS_DAMAGE)
	if is_inside_tree() and not Global.multiplayer_match_over:
		_restart_wrong_timer()


# Damage from your correct guesses (and its own wrong ones). HP lives on
# Global (not here) so it survives this node being recreated every round.
func _on_damage_taken(amount: int) -> void:
	Global.dummy_opponent_hp = max(0, Global.dummy_opponent_hp - amount)
	_broadcast_vitals()
	if Global.dummy_opponent_hp <= 0:
		MultiplayerSync.opponent_match_over.emit("won")


func _broadcast_vitals() -> void:
	# Real opponents' vitals land in last_known_* via MultiplayerSync's
	# message handler - the dummy bypasses that, so keep it in sync here or
	# OpponentPanel shows stale HP at the start of each round.
	Global.last_known_opponent_hp = Global.dummy_opponent_hp
	Global.last_known_opponent_max_hp = Global.dummy_opponent_max_hp
	MultiplayerSync.opponent_vitals_updated.emit(Global.dummy_opponent_hp, Global.dummy_opponent_max_hp, mana, max_mana)
