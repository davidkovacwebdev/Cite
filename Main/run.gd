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

var double_down_armed: bool = false
var letter_reveal_armed: bool = false

# Multiplayer hand, as Card.Action_sub_type values, carried across rounds
# (persists through round reloads since this whole Run object does). Dealt
# once at match start - the same 3 random specials for both players (see
# Deck.generate_multiplayer_hand) - then each round adds the reward card the
# player picked or was handed (MultiplayerBoard). A card leaves only when
# it's played.
var mp_hand: Array = []
var mp_hand_dealt: bool = false




# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
