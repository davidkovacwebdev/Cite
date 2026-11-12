
extends Node


var run: Run

var selected_categories = []
var selected_playsets = []

var all_playsets = []
var all_categories = []
var achievement_data = []

var is_multiplayer_match: bool = false
# Single player started from the Legacy menu: the original look (gradient
# background, classic bars and cards). Set by Main after start_new_run().
var legacy_mode: bool = false
var is_dummy_opponent: bool = false
# DummyOpponent is a plain Node recreated fresh every round (the whole scene
# reloads each round), so its accumulated damage has to live here instead of
# on the node itself, or it'd silently reset to full HP every round.
var dummy_opponent_hp: int = MULTIPLAYER_START_HP
var dummy_opponent_max_hp: int = MULTIPLAYER_START_HP
# Dev: how the bot plays (DummyOpponent) - picked in the hub's settings.
enum DummyBotLevel { PASSIVE, NORMAL, FAST }
var dummy_bot_level: int = DummyBotLevel.NORMAL
# Dev: "Ranked" / "Quick Play" - the hub starts a fake matchmaking search
# against the bot when it loads (hub_screen._dev_dummy_matchmaking).
var pending_dummy_matchmaking: String = ""
var multiplayer_opponent_id: int = 0
var multiplayer_opponent_name: String = ""
var multiplayer_article_seed: int = 0

# Multiplayer article pools - each .json file in this folder is a playlist
# ({"Article Title": wikipedia_page_id, ...}), picked by the host in the
# lobby (MultiplayerLobby) and synced to the guest via lobby data. The
# filename (minus extension) doubles as its ID - drop a new file in here to
# add a playlist, no code changes needed.
const MULTIPLAYER_PLAYLIST_FOLDER := "res://assets/data/multiplayer_playlists/"
var multiplayer_playlist_id: String = "geography"


# Shared by MultiplayerLobby (real matches) and Main's dummy-lobby debug
# shortcut (solo testing) so both list playlists the same way - drop a new
# .json in MULTIPLAYER_PLAYLIST_FOLDER and it shows up in both places with
# no code changes needed.
func get_available_playlist_ids() -> Array:
	var ids := get_official_playlist_ids()
	# Approved Steam Workshop playlists ("ws_<file_id>") come after the
	# built-in ones - see Workshop.gd.
	ids.append_array(Workshop.get_playlist_ids())
	return ids


# The built-in (official) playlists, sorted - the .json files in
# MULTIPLAYER_PLAYLIST_FOLDER.
func get_official_playlist_ids() -> Array:
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
	return ids


# Virtual playlist: every official playlist merged. Find Match / Quick Play
# and the Daily Challenge draw from it (community playlists stay opt-in via
# private rooms).
const OFFICIAL_POOL := "official"


# Wikipedia page ids in a playlist, in a fixed order both players agree on
# (file order for one playlist; sorted and de-duplicated for OFFICIAL_POOL).
func get_playlist_article_ids(playlist_id: String) -> Array:
	if playlist_id == OFFICIAL_POOL:
		var merged := {}
		for id in get_official_playlist_ids():
			for article_id in _read_playlist_ids(get_playlist_path(id)):
				merged[article_id] = true
		var ids: Array = merged.keys()
		ids.sort()
		return ids
	return _read_playlist_ids(get_playlist_path(playlist_id))


# Display name of the first official playlist holding this article ("" if none).
func get_official_playlist_name_of(article_id: int) -> String:
	for id in get_official_playlist_ids():
		if article_id in _read_playlist_ids(get_playlist_path(id)):
			return get_playlist_display_name(id)
	return ""


func _read_playlist_ids(path: String) -> Array:
	var ids: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open playlist: " + path)
		return ids
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("Failed to parse playlist: " + path)
		return ids
	for id in data.values():
		ids.append(int(id))
	return ids


func get_playlist_path(playlist_id: String) -> String:
	if Workshop.is_community_id(playlist_id):
		return Workshop.cache_path(Workshop.file_id_of(playlist_id))
	return MULTIPLAYER_PLAYLIST_FOLDER + playlist_id + ".json"


# Built-ins are named after their file (world_history -> "World
# History"), community ones by their Workshop title.
# Official playlists whose name from the filename ("tv_celebrities" ->
# "Tv Celebrities") comes out wrong.
const OFFICIAL_DISPLAY_NAMES := {"tv_celebrities": "TV Celebrities"}


func get_playlist_display_name(playlist_id: String) -> String:
	if playlist_id == OFFICIAL_POOL:
		return "All official playlists (Ranked selection)"
	if Workshop.is_community_id(playlist_id):
		var title = Workshop.get_title(Workshop.file_id_of(playlist_id))
		return (title if not title.is_empty() else "Community playlist") + " (Community)"
	if OFFICIAL_DISPLAY_NAMES.has(playlist_id):
		return OFFICIAL_DISPLAY_NAMES[playlist_id]
	return playlist_id.replace("_", " ").capitalize()


# Fingerprint of the playlist file's exact contents. Host and guest compare
# these before a match, since the article order (and so the whole match)
# comes from the file - "" if this player doesn't have it.
func get_playlist_hash(playlist_id: String) -> String:
	if playlist_id == OFFICIAL_POOL:
		var parts := PackedStringArray()
		for id in get_official_playlist_ids():
			parts.append(id + ":" + get_playlist_hash(id))
		return ",".join(parts).md5_text()
	var path = get_playlist_path(playlist_id)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_md5(path)
var multiplayer_match_outcome: String = ""  # "won" or "lost", set once the match ends
var multiplayer_match_over: bool = false
# Matchmaking's Ranked mode - the only matches that change the rating (Ratings.gd).
var multiplayer_ranked: bool = false

# Last vitals we actually heard from the opponent, kept for OpponentPanel to
# apply immediately on a fresh round (its HealthComponent/ManaComponent
# otherwise reset to full in _ready() every round reload, flashing the wrong
# value until the next real broadcast arrived).
var last_known_opponent_hp: int = MULTIPLAYER_START_HP
var last_known_opponent_max_hp: int = MULTIPLAYER_START_HP
var last_known_opponent_mana: int = 100
var last_known_opponent_max_mana: int = 100

# Stashed by MultiplayerLobby once the match connects, and left for real via
# leave_multiplayer_lobby() below once the match actually ends - the lobby
# is only needed to exchange Steam IDs for matchmaking, not for the
# ISteamNetworkingMessages channel itself, but there's no reason to leave it
# mid-match either.
var multiplayer_lobby_id: int = 0

# Which MultiplayerLobby screen to open on: "browse" (Find / Host a Game - public
# game list, plus Host a Game / Join Privately), "submit" (Submit Playlist to
# Workshop) or "dummy" (local bot game). Set by Main's multiplayer submenu
# right before switching scenes.
var multiplayer_lobby_entry: String = "browse"
# Set when leaving MultiplayerLobby with Back, so Main reopens on its
# Multiplayer submenu instead of the top-level menu.
var return_to_multiplayer_menu: bool = false
# Hub-style screen that opened the lobby (e.g. Playlists) - the lobby's Back
# returns there instead of the hub. "" = the hub.
var lobby_return_scene: String = ""
# Same for the Leaderboards screen and the Game submenu.
var return_to_game_menu: bool = false
# Hub's "Legacy" link / the end of a Legacy run: Main.tscn opens straight on
# the old Normal/Hardcore screen, in its original blue look.
var open_legacy_menu: bool = false
# Hub: Single Player takes the top spot while fewer than
# HUB_SP_FIRST_BELOW people are playing (matchmaking would mostly wait).
# Last count Steam reported (-1 = unknown) so the hub opens straight on the
# right layout, and a dev override from the hub settings (session only).
const HUB_SP_FIRST_BELOW := 100
enum HubLayout { AUTO, SINGLE_PLAYER, MULTIPLAYER }
var last_player_count: int = -1
var hub_layout_override: int = HubLayout.AUTO

# Starting (and max) HP. Multiplayer matches start higher so a duel lasts
# more articles; both players must run the same build (LOBBY_VERSION).
const SINGLE_PLAYER_START_HP := 2000
const MULTIPLAYER_START_HP := 4000

# Sent with every Wikipedia / Wikimedia request. Wikimedia's API policy asks
# apps to identify themselves with a name and a way to reach the maintainer;
# generic clients can get rate-limited or blocked.
const WIKIPEDIA_HEADERS := ["User-Agent: Cite/1.0 (https://github.com/davidkovacwebdev/Cite; Steam app 4339350)"]

# Developer tools (F12 on the hub, Legacy's test buttons). res://dev/ is left
# out of every export preset, so shipped builds don't have it at all; the
# debug-build check keeps it off even in an export that forgot the filter.
const DEV_TOOLS := "res://dev/dev_tools.gd"


func dev_tools_available() -> bool:
	return OS.is_debug_build() and ResourceLoader.exists(DEV_TOOLS)
# Room code typed into the hub's Private Match card (lobby entry "join").
var pending_lobby_code: String = ""
# Where "back to the menu" goes: the new hub (Main.tscn is kept, unused).
const MENU_SCENE := "res://ui/hub/hub.tscn"

var debug_forced_article_id: int = 0

# In-match display options, changed from the settings overlay (Esc) and saved
# in SaveData. MultiplayerBoard listens for the signal to re-apply them live.
signal match_display_settings_changed
const ARTICLE_TEXT_SIZE_OFFSET_MIN := -5
const ARTICLE_TEXT_SIZE_OFFSET_MAX := 5
var auto_scroll_to_reveal: bool = true
var article_text_size_offset: int = 0
var settings_overlay_open: bool = false

# Double Down: armed by the card until the player's next guess or the round
# ends. While armed, the opponent's correct guess deals 2x to this player.
# The opponent's armed state is mirrored here only so the winner's damage
# number shows the doubled amount - the loser applies the doubling itself.
var opponent_double_down_armed: bool = false

func set_double_down_armed(armed: bool) -> void:
	if run.double_down_armed == armed:
		return
	run.double_down_armed = armed
	MultiplayerSync.send_double_down_state(armed)

func broadcast_vitals() -> void:
	if not is_multiplayer_match or run == null or run.Health == null or run.Mana == null:
		return
	MultiplayerSync.send_vitals(run.Health.current_hp, run.Health.max_hp, run.Mana.current_mana, run.Mana.max_mana)

func end_multiplayer_match(my_outcome: String) -> void:
	if not is_multiplayer_match or multiplayer_match_over:
		return
	multiplayer_match_over = true
	multiplayer_match_outcome = my_outcome
	Ratings.finish_match(my_outcome)
	var opponent_outcome = "won" if my_outcome == "lost" else "lost"
	MultiplayerSync.send_match_over(opponent_outcome)
	leave_multiplayer_lobby()
	MultiplayerSync.reset_connection()

func leave_multiplayer_lobby() -> void:
	if multiplayer_lobby_id != 0:
		Steam.leaveLobby(multiplayer_lobby_id)
		multiplayer_lobby_id = 0

func _ready():
	# Steam callbacks (run in _process) must keep coming while a dropped
	# multiplayer connection pauses the tree - see MultiplayerSync.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Default behavior quits immediately on the window's close button, before
	# _notification below gets a chance to tell the opponent we're leaving.
	get_tree().set_auto_accept_quit(false)

	run = Run.new()
	var settings = ResourceLoader.load("user://scene_data.tres") as SaveData
	if settings:
		auto_scroll_to_reveal = settings.auto_scroll_to_reveal
		article_text_size_offset = settings.article_text_size_offset
	var file =FileAccess.open("res://assets/data/achievements.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		achievement_data = JSON.parse_string(json_string)
		print("Loaded Achievements: ", achievement_data) # ADD THIS
	else:
		print("Could not find JSON file!")


# Esc presses whichever Back/Return button is showing. Buttons opt in via the
# "back_button" group in their scene; each screen shows at most one at a time.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE):
		return
	if get_tree().paused:
		return  # a dropped multiplayer connection is pausing the match (MultiplayerSync)
	for button in get_tree().get_nodes_in_group("back_button"):
		if button is BaseButton and button.is_visible_in_tree() and not button.disabled:
			get_viewport().set_input_as_handled()
			button.pressed.emit()
			return


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
		Ratings.finish_match("lost")  # leaving a ranked match is a loss
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


# Maps accented Latin characters to their unaccented equivalent - used
# for guess matching and for the
# title-censoring word comparison in article_component.gd, so "Sánchez" and
# "Sanchez" are treated as the same word regardless of which form Wikipedia's
# API happens to return.
# Covers Central/Eastern European letters too (č, ć, š, ž, đ, ł, ő...), so
# e.g. "Luka Dončić" matches a typed "luka doncic". Uppercase forms map to
# uppercase so callers that haven't lowercased yet still work.
const _ACCENT_MAP := {
		"á": "a", "Á": "A", "à": "a", "À": "A", "â": "a", "Â": "A", "ä": "a",
		"Ä": "A", "ã": "a", "Ã": "A", "å": "a", "Å": "A", "ā": "a", "Ā": "A",
		"ă": "a", "Ă": "A", "ą": "a", "Ą": "A", "ǎ": "a", "Ǎ": "A", "ç": "c",
		"Ç": "C", "ć": "c", "Ć": "C", "ĉ": "c", "Ĉ": "C", "ċ": "c", "Ċ": "C",
		"č": "c", "Č": "C", "ď": "d", "Ď": "D", "đ": "d", "Đ": "D", "é": "e",
		"É": "E", "è": "e", "È": "E", "ê": "e", "Ê": "E", "ë": "e", "Ë": "E",
		"ē": "e", "Ē": "E", "ĕ": "e", "Ĕ": "E", "ė": "e", "Ė": "E", "ę": "e",
		"Ę": "E", "ě": "e", "Ě": "E", "ĝ": "g", "Ĝ": "G", "ğ": "g", "Ğ": "G",
		"ġ": "g", "Ġ": "G", "ģ": "g", "Ģ": "G", "ĥ": "h", "Ĥ": "H", "ħ": "h",
		"Ħ": "H", "í": "i", "Í": "I", "ì": "i", "Ì": "I", "î": "i", "Î": "I",
		"ï": "i", "Ï": "I", "ĩ": "i", "Ĩ": "I", "ī": "i", "Ī": "I", "ĭ": "i",
		"Ĭ": "I", "į": "i", "Į": "I", "ı": "i", "ǐ": "i", "Ǐ": "I",
		"ĵ": "j", "Ĵ": "J", "ķ": "k", "Ķ": "K", "ĺ": "l", "Ĺ": "L", "ļ": "l",
		"Ļ": "L", "ľ": "l", "Ľ": "L", "ŀ": "l", "Ŀ": "L", "ł": "l", "Ł": "L",
		"ñ": "n", "Ñ": "N", "ń": "n", "Ń": "N", "ņ": "n", "Ņ": "N", "ň": "n",
		"Ň": "N", "ŉ": "n", "ó": "o", "Ó": "O", "ò": "o", "Ò": "O", "ô": "o",
		"Ô": "O", "ö": "o", "Ö": "O", "õ": "o", "Õ": "O", "ø": "o", "Ø": "O",
		"ō": "o", "Ō": "O", "ŏ": "o", "Ŏ": "O", "ő": "o", "Ő": "O", "ǒ": "o",
		"Ǒ": "O", "ŕ": "r", "Ŕ": "R", "ŗ": "r", "Ŗ": "R", "ř": "r", "Ř": "R",
		"ś": "s", "Ś": "S", "ŝ": "s", "Ŝ": "S", "ş": "s", "Ş": "S", "š": "s",
		"Š": "S", "ș": "s", "Ș": "S", "ţ": "t", "Ţ": "T", "ť": "t", "Ť": "T",
		"ŧ": "t", "Ŧ": "T", "ț": "t", "Ț": "T", "ú": "u", "Ú": "U", "ù": "u",
		"Ù": "U", "û": "u", "Û": "U", "ü": "u", "Ü": "U", "ũ": "u", "Ũ": "U",
		"ū": "u", "Ū": "U", "ŭ": "u", "Ŭ": "U", "ů": "u", "Ů": "U", "ű": "u",
		"Ű": "U", "ų": "u", "Ų": "U", "ǔ": "u", "Ǔ": "U", "ŵ": "w", "Ŵ": "W",
		"ý": "y", "Ý": "Y", "ÿ": "y", "Ÿ": "Y", "ŷ": "y", "Ŷ": "Y", "ź": "z",
		"Ź": "Z", "ż": "z", "Ż": "Z", "ž": "z", "Ž": "Z",
		"ß": "ss", "æ": "ae", "Æ": "AE", "œ": "oe", "Œ": "OE", "þ": "th", "ð": "d", "Ð": "D",
}


func strip_accents(text: String) -> String:
	var result := ""
	for c in text:
		result += _ACCENT_MAP.get(c, c)
	return result


# A title character that gets blanked (and must be guessed): a-z, A-Z, 0-9,
# plus any accented Latin letter that strip_accents() folds to one of those.
func is_guessable_char(c: String) -> bool:
	var s := strip_accents(c)
	if s.is_empty():
		return false
	var f := s[0]
	return (f >= "a" and f <= "z") or (f >= "A" and f <= "Z") or (f >= "0" and f <= "9")


# Used to accept/reject a player's title guess: a flat 85% similarity ratio
# for any length, so small typos are forgiven.
# The match-style look (dark background, minimal bars, dark cards) - used by
# multiplayer and by single player outside Legacy.
func uses_modern_ui() -> bool:
	return is_multiplayer_match or not legacy_mode


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
	dummy_opponent_hp = MULTIPLAYER_START_HP
	dummy_opponent_max_hp = MULTIPLAYER_START_HP
	multiplayer_opponent_id = 0
	multiplayer_opponent_name = ""
	multiplayer_match_outcome = ""
	multiplayer_match_over = false
	multiplayer_ranked = false
	MultiplayerSync.opponent_skip_round = -1
	last_known_opponent_hp = MULTIPLAYER_START_HP
	last_known_opponent_max_hp = MULTIPLAYER_START_HP
	last_known_opponent_mana = 100
	last_known_opponent_max_mana = 100
	debug_forced_article_id = 0







#Steam handling

# Your own Steam name - "You" when Steam isn't running/logged in (then
# getPersonaName() returns an empty string), so chat never shows a blank name.
func get_own_name() -> String:
	var own_name = Steam.getPersonaName()
	return own_name if not own_name.is_empty() else "You"

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
