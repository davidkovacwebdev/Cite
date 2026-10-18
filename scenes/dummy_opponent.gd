extends Node

# Debug-only stand-in for a real networked opponent. Drives the exact same
# MultiplayerSync signals a real peer's RPCs would emit, so OpponentPanel and
# board.gd's multiplayer branches can be tested without a second Steam account.
class_name DummyOpponent

const BOT_NAME := "Dummy Bot"
# The bot also chats - in the dummy lobby (MultiplayerLobby) and in-match
# (here) - so the chat UI can be tested solo.
const CHAT_INTERVAL_SECONDS := 5.0
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

var mana: int = 100
var max_mana: int = 100


func _ready() -> void:
	MultiplayerSync.dummy_damage_taken.connect(_on_damage_taken)
	_broadcast_vitals()

	var chat_timer = Timer.new()
	chat_timer.wait_time = CHAT_INTERVAL_SECONDS
	chat_timer.timeout.connect(func(): MultiplayerSync.receive_dummy_chat(random_chat_line()))
	add_child(chat_timer)
	chat_timer.start()


static func random_chat_line() -> String:
	return CHAT_LINES.pick_random()


# The dummy doesn't act on its own for now - it just sits there with full
# vitals and reacts when your own correct guesses deal it damage, so the
# reveal/damage loop can still be tested without a real second player. HP
# lives on Global (not here) so it survives this node being recreated fresh
# every round.
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
