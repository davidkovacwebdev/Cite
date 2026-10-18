
extends Node


var run: Run

var selected_categories = []
var selected_playsets = []

var all_playsets = []
var all_categories = []
var achievement_data = []

var is_multiplayer_match: bool = false
var is_dummy_opponent: bool = false
# DummyOpponent is a plain Node recreated fresh every round (the whole scene
# reloads each round), so its accumulated damage has to live here instead of
# on the node itself, or it'd silently reset to full HP every round.
var dummy_opponent_hp: int = 2000
# Starting HP for BOTH sides in Lobby Dummy matches only (testing), so a
# match doesn't end before whatever's being tested gets a chance to happen.
const DUMMY_TEST_HP := 1000000
var dummy_opponent_max_hp: int = 2000
var multiplayer_opponent_id: int = 0
var multiplayer_opponent_name: String = ""
var multiplayer_article_seed: int = 0

# Multiplayer article pools - each .json file in this folder is a playlist
# ({"Article Title": wikipedia_page_id, ...}), picked by the host in the
# lobby (MultiplayerLobby) and synced to the guest via lobby data. The
# filename (minus extension) doubles as its ID - drop a new file in here to
# add a playlist, no code changes needed.
const MULTIPLAYER_PLAYLIST_FOLDER := "res://assets/data/multiplayer_playlists/"
var multiplayer_playlist_id: String = "common_knowledge"


# Shared by MultiplayerLobby (real matches) and Main's dummy-lobby debug
# shortcut (solo testing) so both list playlists the same way - drop a new
# .json in MULTIPLAYER_PLAYLIST_FOLDER and it shows up in both places with
# no code changes needed.
func get_available_playlist_ids() -> Array:
	var ids: Array = []
	var dir = DirAccess.open(MULTIPLAYER_PLAYLIST_FOLDER)
	if not dir:
		push_error("Couldn't open multiplayer playlist folder: " + MULTIPLAYER_PLAYLIST_FOLDER)
		return ids

	dir.list_dir_begin()
	var filename = dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.get_extension() == "json":
			ids.append(filename.get_basename())
		filename = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	# Approved Steam Workshop playlists ("ws_<file_id>") come after the
	# built-in ones - see Workshop.gd.
	ids.append_array(Workshop.get_playlist_ids())
	return ids


func get_playlist_path(playlist_id: String) -> String:
	if Workshop.is_community_id(playlist_id):
		return Workshop.cache_path(Workshop.file_id_of(playlist_id))
	return MULTIPLAYER_PLAYLIST_FOLDER + playlist_id + ".json"


# Built-ins are named after their file (common_knowledge -> "Common
# Knowledge"), community ones by their Workshop title.
func get_playlist_display_name(playlist_id: String) -> String:
	if Workshop.is_community_id(playlist_id):
		var title = Workshop.get_title(Workshop.file_id_of(playlist_id))
		return (title if not title.is_empty() else "Community playlist") + " (Community)"
	return playlist_id.replace("_", " ").capitalize()


# Fingerprint of the playlist file's exact contents. Host and guest compare
# these before a match, since the article order (and so the whole match)
# comes from the file - "" if this player doesn't have it.
func get_playlist_hash(playlist_id: String) -> String:
	var path = get_playlist_path(playlist_id)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_md5(path)
var multiplayer_match_outcome: String = ""  # "won" or "lost", set once the match ends
var multiplayer_match_over: bool = false

# Last vitals we actually heard from the opponent, kept for OpponentPanel to
# apply immediately on a fresh round (its HealthComponent/ManaComponent
# otherwise reset to full in _ready() every round reload, flashing the wrong
# value until the next real broadcast arrived).
var last_known_opponent_hp: int = 2000
var last_known_opponent_max_hp: int = 2000
var last_known_opponent_mana: int = 100
var last_known_opponent_max_mana: int = 100

# Stashed by MultiplayerLobby once the match connects, and left for real via
# leave_multiplayer_lobby() below once the match actually ends - the lobby
# is only needed to exchange Steam IDs for matchmaking, not for the
# ISteamNetworkingMessages channel itself, but there's no reason to leave it
# mid-match either.
var multiplayer_lobby_id: int = 0

# Which MultiplayerLobby screen to open on: "browse" (public game list) or
# "host_join" (host a game / connect privately with a code). Set by Main's
# multiplayer submenu right before switching scenes.
var multiplayer_lobby_entry: String = "host_join"

var debug_forced_article_id: int = 0

func broadcast_vitals() -> void:
	if not is_multiplayer_match or run == null or run.Health == null or run.Mana == null:
		return
	MultiplayerSync.send_vitals(run.Health.current_hp, run.Health.max_hp, run.Mana.current_mana, run.Mana.max_mana)

func end_multiplayer_match(my_outcome: String) -> void:
	if not is_multiplayer_match or multiplayer_match_over:
		return
	multiplayer_match_over = true
	multiplayer_match_outcome = my_outcome
	var opponent_outcome = "won" if my_outcome == "lost" else "lost"
	MultiplayerSync.send_match_over(opponent_outcome)
	leave_multiplayer_lobby()
	MultiplayerSync.reset_connection()

func leave_multiplayer_lobby() -> void:
	if multiplayer_lobby_id != 0:
		Steam.leaveLobby(multiplayer_lobby_id)
		multiplayer_lobby_id = 0

func _ready():
	# Default behavior quits immediately on the window's close button, before
	# _notification below gets a chance to tell the opponent we're leaving.
	get_tree().set_auto_accept_quit(false)

	run = Run.new()
	var file = FileAccess.open("res://assets/data/achievements.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		achievement_data = JSON.parse_string(json_string)
		print("Loaded Achievements: ", achievement_data) # ADD THIS
	else:
		print("Could not find JSON file!")


func _process(_delta: float) -> void:
	# Steam's async calls (lobby creation/joining, P2P events, etc.) only
	# deliver their results as signals if this is pumped every frame - it's
	# never been needed before since achievements are synchronous calls.
	Steam.run_callbacks()


# Closing the game window mid-match otherwise leaves the opponent waiting on
# Steam's own connection-timeout detection to notice - this tells them
# immediately instead, then gives the message a moment to actually reach
# Steam's network layer before the process exits (queuing it and quitting in
# the same instant risks it never being sent at all).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if is_multiplayer_match and not multiplayer_match_over:
		MultiplayerSync.send_player_left()
		await get_tree().create_timer(0.3).timeout
	get_tree().quit()


func load_and_extract_card_data() -> bool:
	# Load JSON file
	var file_path = "res://assets/data/data.json"
	
	if not FileAccess.file_exists(file_path):
		push_error("Card data file not found: " + file_path)
		return false
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open card data file: " + file_path)
		return false
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("JSON Parse Error: " + json.get_error_message())
		return false
	
	var card_data = json.get_data()
	
	# Extract unique playsets and categories in one pass
	var playset_set = {}
	var category_count = {}  # Dictionary to count category occurrences
	var category_set = {}    # Dictionary to store qualifying categories
	
	for card in card_data:
		# Extract playsets (arrays)
		if card.has("playset") and card["playset"] is Array:
			for playset in card["playset"]:
				if playset and typeof(playset) == TYPE_STRING and playset.strip_edges() != "":
					playset_set[playset] = true
		
		# Extract main category
		if card.has("main_category") and card["main_category"]:
			var main_cat = card["main_category"]
			if typeof(main_cat) == TYPE_STRING and main_cat.strip_edges() != "":
				if category_count.has(main_cat):
					category_count[main_cat] += 1
				else:
					category_count[main_cat] = 1
		
		# Extract related categories
		if card.has("related_categories") and card["related_categories"] is Array:
			for category in card["related_categories"]:
				if category and typeof(category) == TYPE_STRING and category.strip_edges() != "":
					if category_count.has(category):
						category_count[category] += 1
					else:
						category_count[category] = 1
	
	# Only add categories with 10 or more articles
	for category in category_count:
		if category_count[category] >= 10:
			category_set[category] = true
	
	# Convert to arrays and sort alphabetically
	all_playsets = playset_set.keys()
	all_playsets.sort()
	
	all_categories = category_set.keys()
	all_categories.sort()
	
	
	
	return true

# Calculates Levenshtein distance between two strings
func levenshtein_distance(a: String, b: String) -> int:
	a = a.to_lower()
	b = b.to_lower()
	
	var len_a = a.length()
	var len_b = b.length()
	
	# Initialize distance matrix
	var matrix = []
	for i in range(len_a + 1):
		matrix.append([])
		for j in range(len_b + 1):
			if i == 0:
				matrix[i].append(j)
			elif j == 0:
				matrix[i].append(i)
			else:
				matrix[i].append(0)
				
	# Compute distances
	for i in range(1, len_a + 1):
		for j in range(1, len_b + 1):
			var cost = 0 if a[i - 1] == b[j - 1] else 1
			matrix[i][j] = min(
				matrix[i - 1][j] + 1,      # deletion
				matrix[i][j - 1] + 1,      # insertion
				matrix[i - 1][j - 1] + cost # substitution
			)
	
	return matrix[len_a][len_b]


func similarity_ratio(a: String, b: String) -> float:
	var distance = levenshtein_distance(a, b)
	var max_len = max(a.length(), b.length())
	if max_len == 0:
		return 1.0
	return 1.0 - float(distance) / float(max_len)


# Maps accented Latin characters to their unaccented equivalent (expects
# already-lowercased input) - used both for guess matching and for the
# title-censoring word comparison in article_component.gd, so "Sánchez" and
# "Sanchez" are treated as the same word regardless of which form Wikipedia's
# API happens to return.
func strip_accents(text: String) -> String:
	var replacements = {
		"á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a", "å": "a",
		"é": "e", "è": "e", "ê": "e", "ë": "e",
		"í": "i", "ì": "i", "î": "i", "ï": "i",
		"ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o",
		"ú": "u", "ù": "u", "û": "u", "ü": "u",
		"ñ": "n", "ç": "c",
		"ý": "y", "ÿ": "y"
	}
	var result = text
	for accented in replacements:
		result = result.replace(accented, replacements[accented])
	return result


# Used to accept/reject a player's title guess: a flat 85% similarity ratio
# for any length, so small typos are forgiven.
func is_guess_match(guess: String, solution: String) -> bool:
	var distance = levenshtein_distance(guess, solution)
	var max_len = max(guess.length(), solution.length())
	if max_len == 0:
		return true
	return (1.0 - float(distance) / float(max_len)) >= 0.85


func start_new_run():
	run = Run.new()  # Just create a fresh Run instance
	is_multiplayer_match = false
	is_dummy_opponent = false
	dummy_opponent_hp = 2000
	dummy_opponent_max_hp = 2000
	multiplayer_opponent_id = 0
	multiplayer_opponent_name = ""
	multiplayer_match_outcome = ""
	multiplayer_match_over = false
	last_known_opponent_hp = 2000
	last_known_opponent_max_hp = 2000
	last_known_opponent_mana = 100
	last_known_opponent_max_mana = 100
	debug_forced_article_id = 0







#Steam handling

func _init ():
	var response : Dictionary = Steam.steamInitEx(4339350, true)
	print(response)





#Handling achievements

func getArticleAch(id):
	if achievement_data == null or achievement_data.is_empty():
		print("CRITICAL: achievement_data is empty or null!")
		return ""

	var target_id = id
	for entry in achievement_data:
		# Cast the JSON side to int too, just in case
		if int(entry["id"]) == target_id:
			print("SUCCESS: ", entry["achievement"])
			return entry["achievement"]
			
	
	print("No match found for ID: ", target_id)
	return ""

func getArticleAchSound(id):
	if achievement_data == null or achievement_data.is_empty():
		print("CRITICAL: achievement_data is empty or null!")
		return ""

	var target_id = id
	for entry in achievement_data:
		# Cast the JSON side to int too, just in case
		if int(entry["id"]) == target_id:
			print("SUCCESS: ", entry["sound"])
			return entry["sound"]
			
	
	print("No match found for ID: ", target_id)
	return ""


func setAchievement(ach):
	# 1. Get the achievement status (Returns a Dictionary)
	var status = Steam.getAchievement(ach)
	# 2. Check if the call was successful ('ret') and if not already earned
	if not status.is_empty():
		if status['ret'] and not status['achieved']:
			Steam.setAchievement(ach)
			Steam.storeStats()
