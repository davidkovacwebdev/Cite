extends Node

class_name Run

var round_number:int = 1
var first_skipped: bool = false
var first_run: bool = true
var last_article: bool = false
var number_of_combos:int
var number_of_wrong_guesses: int
var number_of_total_cards:int
var number_of_played_cards:int

var playset: String


var number_of_skips:int = 3


var Health
var Mana

enum GameMode {
	NORMAL,
	HARDCORE,
	STORY_MODE
}
var current_game_mode: GameMode
#To be determined 
enum Difficulty {
	NOVICE,
	SLAGALICA_ENJOYER,
	POTERA_WINNER
}
var current_difficulty: Difficulty = Difficulty.NOVICE


var current_round = Round.new()


var wikipedia_ids: Array[int] = []
var hardcore_ids: Array[int] = []

var cached_data = []

var current_hp:int
var max_hp:int
var current_mana:int
var max_mana:int

#mozda nece trebati
var legacy_max_hp:int
var legacy_heal:int
#mozda nece trebati
var legacy_max_mana:int 
var legacy_mana_restore:int 

var hand_size:int = 3

# Multiplayer-only special cards: each usable once per MATCH (persists across
# round reloads since this whole Run object does), not once per round.
var mp_special_cards_used: Dictionary = {}
var double_down_armed: bool = false
var letter_reveal_armed: bool = false

# Round-win reward cards (see MultiplayerBoard._run_card_reward_choice) this
# player owns but hasn't played yet, as Card.Action_sub_type values. Every
# round they're dealt back into the deck alongside the unplayed specials, and
# one entry is removed only when that card is actually played - so a reward
# stays with the player for the rest of the match until used. Persists across
# round reloads since this whole Run object does.
var mp_reward_cards: Array = []




# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
