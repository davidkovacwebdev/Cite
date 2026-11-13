extends Node2D

class_name Article

var article_id: int
var article_title: String = ""
var article_alternative_title: String = ""
var article_category: String = ""
var article_related_categories: String = ""
var article_difficulty: int = 0
var article_extract: String = ""
var current_deck
var DeckScene = preload("res://scenes/Deck.tscn")
var BoardScene = preload("res://scenes/Board.tscn")
var MultiplayerBoardScene = preload("res://scenes/MultiplayerBoard.tscn")
var SingleplayerBoardScene = preload("res://scenes/SingleplayerBoard.tscn")

# Multiplayer's first-round hand - both players get the same cards (see
# Deck.generate_multiplayer_hand).
const MP_STARTING_HAND_SIZE := 3

const ArticleImage := preload("res://components/article_image.gd")

var hc_article_id: int
var hc_article_title

#@onready var round_ids = Global.run.wikipedia_ids

func _ready() -> void:
	$HTTPRequest.request_completed.connect(_on_request_completed)
	$HTTPRequestHC.request_completed.connect(_on_request_completed_hc)

	if Global.debug_forced_article_id != 0:
		Global.run.last_article = true
		request_article(Global.debug_forced_article_id)
		return

	# Wait for the titles to be updated before loading data
	#await update_article_titles()
	if Global.run.current_game_mode == 0:
		if Global.run.wikipedia_ids.is_empty() and Global.run.first_run == true:
			if Global.is_multiplayer_match:
				load_multiplayer_article_data()  # Load once
			else:
				load_article_data()  # Load once
		elif Global.run.wikipedia_ids.is_empty():
			Global.run.last_article = true

		if Global.run.last_article == false:
			request_random_article()
	elif Global.run.current_game_mode == 1:
		request_article_hc()
		Global.run.last_article = false


# Multiplayer draws from the host-selected playlist (see MultiplayerLobby)
# instead of data.json - each playlist is just {"Title": wikipedia_id, ...},
# no category/playset metadata needed since CategoryReveal/DifficultyReveal
# are hidden in multiplayer anyway. Titles exist for whoever's curating the
# playlist file to read, not used here.
func load_multiplayer_article_data():
	Global.run.first_run = false
	Global.run.wikipedia_ids.clear()
	Global.run.wikipedia_ids.append_array(Global.get_playlist_article_ids(Global.multiplayer_playlist_id))
	if Global.run.wikipedia_ids.is_empty():
		print("Multiplayer playlist is empty or missing: ", Global.multiplayer_playlist_id)
		return

	# Both players load the same playlist into the same starting order, so
	# seeding with a seed shared at match start makes this shuffle - and
	# therefore the whole article sequence - identical on both ends. Cards
	# get drawn/erased from this same list as rounds progress, so no ID can
	# come up twice in one match.
	seed(Global.multiplayer_article_seed)
	Global.run.wikipedia_ids.shuffle()


func load_article_data():
	Global.run.first_run = false
	var file = FileAccess.open("res://assets/data/data.json", FileAccess.READ)
	if not file:
		print("Failed to open data.json")
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		print("Failed to parse JSON")
		return
	
	Global.run.cached_data = json.data
	
	Global.run.wikipedia_ids.clear()  # Clear previous IDs

	# Single player Normal draws from one playlist picked in the hub (official
	# or community), or all official ones; data.json above is still read for the hints'
	# category/difficulty where it has the article. Legacy keeps data.json's
	# playsets/categories.
	if not Global.legacy_mode:
		var playlist: String = Global.OFFICIAL_POOL
		if Global.selected_playsets.size() == 1 and str(Global.selected_playsets[0]) in Global.get_available_playlist_ids():
			playlist = str(Global.selected_playsets[0])
		Global.run.wikipedia_ids.append_array(Global.get_playlist_article_ids(playlist))
		Global.run.wikipedia_ids.shuffle()
		return
	
	for article_obj in json.data:
		var matches = false
		
		# Check categories (main or related)
		if not Global.selected_categories.is_empty():
			if article_obj.main_category in Global.selected_categories:
				matches = true
			else:
				for rel_cat in article_obj.related_categories:
					if rel_cat in Global.selected_categories:
						matches = true
						break
		# Check playset
		# Check playset (array or missing)
		# Check playset (array or missing)
		# Check if we still need a match and if the user actually selected any playsets
		if not matches and not Global.selected_playsets.is_empty():
			# Ensure the key exists and is actually an Array before trying to loop
			if article_obj.has("playset") and typeof(article_obj.playset) == TYPE_ARRAY:
				for p in article_obj.playset:
					# Safety check: ensure 'p' is a String before calling to_lower()
					if typeof(p) == TYPE_STRING:
						if p.to_lower() in Global.selected_playsets:
							matches = true
							break # Exit the loop as soon as one playset matches
		
		# If no filters selected, include all
		if Global.selected_categories.is_empty() and Global.selected_playsets.is_empty():
			matches = true
		
		if matches:
			Global.run.wikipedia_ids.append(int(article_obj.id))

	if Global.is_multiplayer_match:
		# Both players filter the same data.json into the same starting order,
		# so seeding with a seed shared at match start makes this shuffle -
		# and therefore the whole article sequence - identical on both ends.
		seed(Global.multiplayer_article_seed)
	Global.run.wikipedia_ids.shuffle()

func get_random_article_id() -> int:
	return Global.run.wikipedia_ids[0]

func request_random_article():
	var random_id = get_random_article_id()
	
	if random_id not in Global.run.wikipedia_ids:
		request_random_article()
	else:
		request_article(random_id)
		Global.run.wikipedia_ids.erase(random_id)

func request_article(page_id: int):
	var url = "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&pageids=" + str(page_id) + "&explaintext=true&exintro=true&format=json&origin=*"
	if Global.run.current_game_mode == 1:
		# Hardcore scores each guess by how obscure the article is.
		url = url.replace("prop=extracts", "prop=extracts%7Cpageviews") + "&pvipdays=30"
	elif Global.is_multiplayer_match or not Global.legacy_mode:
		# Hints in Normal single player and multiplayer: the short description
		# ("Slovenian basketball player (born 1999)") and pageviews for the
		# difficulty.
		url = url.replace("prop=extracts", "prop=extracts%7Cdescription%7Cpageviews") + "&pvipdays=30"
	$HTTPRequest.request(url, Global.WIKIPEDIA_HEADERS)
	article_id = page_id

func _on_request_completed(result, response_code, headers, body):
	var article_data = parse_article_data(body)
	if not article_data or article_data.get("extract") == null:
		print("Article not found: ", article_data.get("title", "") if article_data else "(unparseable response)")
		return

	if Global.run.current_game_mode == 1: # Only for Hardcore
		if article_data["extract"].length() < 400:
			print("Article too short (", article_data["extract"].length(), " chars). Retrying...")
			request_article_hc() # Call for a new random ID
			return # Stop this round from starting
	
	setup_article_round(article_data)
	initialize_game_components(article_data)
	
	if Global.run.wikipedia_ids.is_empty() and Global.run.current_game_mode == 0:
		Global.run.last_article = true
	else:
		Global.run.last_article = false
	
		
		
func request_article_hc():
	# Step 1: Request a random ID from Wikipedia
	var url = "https://en.wikipedia.org/w/api.php?action=query&list=random&rnnamespace=0&rnlimit=1&format=json&origin=*"
	var error = $HTTPRequestHC.request(url, Global.WIKIPEDIA_HEADERS)
	
	if error != OK:
		print("Error starting Hardcore request")
	
func _on_request_completed_hc(result, response_code, headers, body):
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if json and json.has("query") and json["query"].has("random"):
		var random_id = json["query"]["random"][0]["id"]
		var random_title = json["query"]["random"][0]["title"]
		if not random_id in Global.run.hardcore_ids:
			
			hc_article_id = random_id
			hc_article_title = random_title
			Global.run.hardcore_ids.append(random_id)
	
		# Step 3: Pass this ID to your existing content requester
		# This uses the main $HTTPRequest node to fetch the actual text
		request_article(random_id)
	else:
		print("Failed to get a random ID from Wikipedia")

func parse_article_data(body) -> Dictionary:
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json or not "query" in json or not "pages" in json["query"]:
		print("Failed to parse article data")
		return {}
	
	var pages = json["query"]["pages"]
	var page_id = pages.keys()[0]
	var page_data = pages[page_id]

	return {
		"title": strip_disambiguation(page_data["title"]),
		"extract": page_data["extract"],
		"description": str(page_data.get("description", "")),
		"id": page_id,
		"daily_views": average_daily_views(page_data.get("pageviews"))
	}


# prop=pageviews gives {"2026-10-01": 123, ...}, with null for days Wikipedia
# has no count for yet - -1 when there's nothing to go on.
func average_daily_views(pageviews) -> float:
	if not pageviews is Dictionary:
		return -1.0
	var total := 0.0
	var days := 0
	for views in pageviews.values():
		if views != null:
			total += float(views)
			days += 1
	return total / days if days > 0 else -1.0

# Wikipedia disambiguates same-named topics with a trailing "(...)" on the
# actual page title, e.g. "Turkey (bird)" vs the country - not part of the
# real subject name, so this strips it before the title is ever displayed,
# censored, or matched against a player's guess. Every mode funnels through
# parse_article_data() for its title, so fixing it here covers all of them.
func strip_disambiguation(title: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\s*\\([^)]*\\)\\s*$")
	var stripped = regex.sub(title, "", false).strip_edges()
	return stripped if stripped != "" else title

func setup_article_round(article_data: Dictionary):
	article_id = int(article_data["id"])
	# Start fetching the answer picture now so it's ready when the round ends.
	Global.run.current_round.image_id = article_id
	ArticleImage.prefetch(article_id)
	if Global.run.current_game_mode == 0:
		article_title = article_data["title"]
		article_extract = article_data["extract"]
		Global.run.current_round.current_id = article_id
		print(article_title)
		Global.run.current_round.article_title = article_title

		if Global.is_multiplayer_match:
			# Playlists (Global.MULTIPLAYER_PLAYLIST_FOLDER) are just title->id
			# pairs - no category/playset/alternative-title metadata like
			# data.json has, and none of it is displayed in multiplayer anyway
			# (CategoryReveal/DifficultyReveal are hidden there).
			article_alternative_title = article_title
			Global.run.current_round.article_alternative_title = article_alternative_title
			Global.run.current_round.article_main_category = ""
			Global.run.current_round.article_related_categories = ""
			Global.run.current_round.article_difficulty = 0
		elif not Global.legacy_mode and not _in_cache(article_id):
			# Playlist article data.json doesn't know: no alias, the playlist
			# as its category, no difficulty (that hint hides itself).
			article_alternative_title = article_title
			Global.run.current_round.article_alternative_title = article_title
			Global.run.current_round.article_main_category = Global.get_official_playlist_name_of(article_id)
			Global.run.current_round.article_related_categories = ""
			Global.run.current_round.article_difficulty = 0
		else:
			article_category = get_category_from_cache(article_id)
			article_related_categories = get_related_category_from_cache(article_id)
			article_alternative_title = get_alternative_title_from_cache(article_id)
			article_difficulty = get_difficulty_from_cache(article_id)
			Global.run.current_round.article_alternative_title = article_alternative_title
			Global.run.current_round.article_main_category = article_category
			Global.run.current_round.article_related_categories = article_related_categories
			Global.run.current_round.article_difficulty = article_difficulty

		var censored_text = format_text(article_title, article_alternative_title, article_extract)
		Global.run.current_round.article_chunks = split_sentences(censored_text)
		var description: String = article_data.get("description", "")
		Global.run.current_round.article_description = format_text(article_title, article_alternative_title, description, false) if description != "" else ""
		Global.run.current_round.article_daily_views = article_data.get("daily_views", -1.0)

		Global.run.current_round.censor_title()
	elif Global.run.current_game_mode == 1:
		article_title = article_data["title"]
		article_extract = article_data["extract"]
		Global.run.current_round.article_alternative_title = article_data["title"]
		Global.run.current_round.article_title = article_title
		var censored_text = format_text(article_title, article_alternative_title, article_extract)
		Global.run.current_round.article_chunks = split_sentences(censored_text)
		Global.run.current_round.article_main_category = "Nope"
		Global.run.current_round.article_related_categories = "not in hardcore mode"
		Global.run.current_round.article_difficulty = ""
		Global.run.current_round.article_daily_views = article_data.get("daily_views", -1.0)
		Global.run.current_round.censor_title()

func _in_cache(target_id: int) -> bool:
	for article_obj in Global.run.cached_data:
		if int(article_obj.id) == target_id:
			return true
	return false


func get_category_from_cache(target_id: int) -> String:
	for article_obj in Global.run.cached_data:
		if article_obj.id == target_id:
			return article_obj.main_category
	return "Unknown"
func get_related_category_from_cache(target_id: int) -> String:
	for article_obj in Global.run.cached_data:
		if article_obj.id == target_id:
			# Convert array to comma-separated string
			var categories_string: String = ", ".join(article_obj.related_categories)
			return categories_string
	return "Unknown"

func get_alternative_title_from_cache(target_id: int) -> String:
	for article_obj in Global.run.cached_data:
		if article_obj.id == target_id:
			return article_obj.alternative_title
	return "Unknown"

func get_difficulty_from_cache(target_id: int) -> int:
	for article_obj in Global.run.cached_data:
		if article_obj.id == target_id:
			return article_obj.difficulty
	return 0
	
func initialize_game_components(article_data: Dictionary):
	create_deck()
	create_board()
	
	current_deck.generate_deck(Global.run.current_round.article_chunks.size(), Global.run.current_round.article_chunks)
	Global.run.current_round.current_deck_card_count = current_deck.round_deck.size()

	draw_initial_cards()
	update_board_title()

func create_deck():
	current_deck = DeckScene.instantiate()
	Global.run.current_round.current_deck = current_deck
	get_parent().add_child(current_deck)

func create_board():
	var scene = BoardScene  # Legacy single player
	if Global.is_multiplayer_match:
		scene = MultiplayerBoardScene
	elif Global.uses_modern_ui():
		scene = SingleplayerBoardScene
	var current_board = scene.instantiate()
	Global.run.current_round.current_board = current_board
	get_parent().add_child(current_board)

func draw_initial_cards():
	# Multiplayer's deck is exactly its carried-over hand (Run.mp_hand) - deal
	# all of it. Single-player still draws a random hand_size subset.
	var count = Global.run.current_round.current_deck_card_count if Global.is_multiplayer_match else Global.run.hand_size
	for i in range(count):
		current_deck.draw_card()

func update_board_title():
	if Global.run.current_round.current_board:
		Global.run.current_round.current_board.update_board_title()

# The rest of your existing functions remain the same...

#func load_random_article_data():
	## This Wikipedia API URL returns 1 random article from the Main namespace (0)
	#var url = "https://en.wikipedia.org/w/api.php?action=query&list=random&rnnamespace=0&rnlimit=1&format=json&origin=*"
	## We use a separate temporary HTTPRequest if you don't want to interfere with the main one
	## or just use your existing $HTTPRequest
	#var error = $HTTPRequest.request(url)
	#
	#if error != OK:
		#print("An error occurred in the HTTP request.")



# censor_parens: blank the opening "(pronunciation; alias)" parentheses -
# off for the short description, whose "(born 1999)" is part of the hint.
func format_text(article_title: String, article_alt_title: String, article_extract: String, censor_parens := true) -> String:
	# Common words to exclude from censoring
	var common_words = ["the", "a", "an", "in", "on", "at", "to", "for", "of", "and", "or", "but", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "can", "with", "by", "from", "as", "it", "its", "it's", "that", "this", "these", "those", "he", "she", "they", "we", "i", "you", "me", "him", "her", "us", "them", "my", "your", "his", "her", "its", "our", "their", "mine", "yours", "hers", "ours", "theirs"]
	
	# Combine main title and alternative title into one list of words to censor
	var title_pool = article_title.to_lower().split(" ")

	# Only add alt title words if it's not empty and not "Unknown"
	if article_alt_title != "" and article_alt_title != "Unknown":
		title_pool.append_array(article_alt_title.to_lower().split(" "))

	# Strip accents so "Sánchez" in the title still matches "Sanchez" (or
	# vice versa) in the extract - an accent alone is enough to drop the
	# Levenshtein similarity below the 0.9 match threshold below.
	for i in range(title_pool.size()):
		title_pool[i] = Global.strip_accents(title_pool[i])

	# Create a cleaned version of all title words (without special characters)
	var cleaned_title_words = []
	for word in title_pool:
		var clean_word = word.replace("/", "").replace("(", "").replace(")", "").replace("[", "").replace("]", "").replace(";", "").replace(",", "").replace(".", "").replace(":", "")
		# Remove numbers
		for n in range(10):
			clean_word = clean_word.replace(str(n), "")
			
		if clean_word.length() > 0 and not common_words.has(clean_word):
			cleaned_title_words.append(clean_word)
	
	# Legacy keeps its original censoring; everything else also blanks
	# pronunciations anywhere in the text and plural/singular title words.
	var thorough := Global.uses_modern_ui()

	# Process each word in the extract
	var words = article_extract.split(" ")
	# split() gives a PackedStringArray, which the Array-typed censor
	# functions below receive as a copy - their blanking was lost. Legacy
	# keeps that original behaviour.
	if thorough:
		words = Array(words)

	if censor_parens:
		censor_pronunciation_and_alias_parens(words)
	if thorough and censor_parens:
		censor_pronunciations(words)
	var title_forms := {}
	if thorough:
		for clean_title_word in cleaned_title_words:
			for form in word_forms(clean_title_word):
				title_forms[form] = true

	for i in range(words.size()):
		var original_word = words[i]
		var lowercase_word = Global.strip_accents(original_word.to_lower())

		# Create a cleaned version of the extract word
		var clean_lowercase_word = lowercase_word.replace("/", "").replace("(", "").replace(")", "").replace("[", "").replace("]", "").replace(";", "").replace(",", "").replace(".", "").replace(":", "")
		for n in range(10):
			clean_lowercase_word = clean_lowercase_word.replace(str(n), "")
		
		if common_words.has(clean_lowercase_word):
			continue
		
		var should_censor = false
		
		# Check against the combined title pool (original fragments)
		for title_word in title_pool:
			if lowercase_word.find(title_word) != -1 or Global.similarity_ratio(lowercase_word, title_word) > 0.9:
				should_censor = true
				break
		
		# Check against the cleaned title pool
		if not should_censor:
			for clean_title_word in cleaned_title_words:
				if clean_lowercase_word.find(clean_title_word) != -1 or Global.similarity_ratio(clean_lowercase_word, clean_title_word) > 0.9:
					should_censor = true
					break

		# Plural/singular of a title word: "raspberries" for "Raspberry",
		# "mice" for "Mouse" - too different as text for the checks above.
		if not should_censor and thorough:
			for form in word_forms(clean_lowercase_word):
				if title_forms.has(form):
					should_censor = true
					break

		# Pieces of a compound title word, e.g. "kilo-", "gram", "kilos" for
		# "Kilogram" - the checks above only catch words containing the title.
		if not should_censor:
			for clean_title_word in cleaned_title_words:
				if is_title_word_part(clean_lowercase_word, clean_title_word):
					should_censor = true
					break

		if should_censor:
			var censored = ""
			for j in range(original_word.length()):
				censored += "_"
			words[i] = censored
	
	return " ".join(words)


const IRREGULAR_PLURALS := {
	"mice": "mouse", "lice": "louse", "geese": "goose", "teeth": "tooth",
	"feet": "foot", "men": "man", "women": "woman", "children": "child",
	"people": "person", "oxen": "ox", "cacti": "cactus", "fungi": "fungus",
	"octopi": "octopus", "alumni": "alumnus", "nuclei": "nucleus",
	"radii": "radius", "bacteria": "bacterium", "criteria": "criterion",
	"phenomena": "phenomenon", "data": "datum", "media": "medium",
	"indices": "index", "vertices": "vertex", "matrices": "matrix",
	"dice": "die", "wolves": "wolf", "knives": "knife", "leaves": "leaf",
	"lives": "life", "wives": "wife", "halves": "half", "loaves": "loaf",
	"thieves": "thief", "shelves": "shelf", "calves": "calf",
}


# Base forms a word could be the plural/possessive of, plus the word itself:
# "raspberries" -> raspberry, "boxes" -> box, "cats'" -> cat, "mice" ->
# mouse. Two words share a form = same word, different number. Only words of
# 3+ letters, so "as"/"is" don't collapse into "a"/"i".
func word_forms(word: String) -> Array:
	var w := word.to_lower().strip_edges()
	# Trim quotes/apostrophes/punctuation off both ends, then a possessive.
	var trim := RegEx.new()
	trim.compile("^[^a-z0-9]+|[^a-z0-9]+$")
	w = trim.sub(w, "", true)
	for suffix in ["'s", "’s"]:
		if w.ends_with(suffix):
			w = w.left(-suffix.length())
	if w.length() < 3:
		return []
	var forms := [w]
	if IRREGULAR_PLURALS.has(w):
		forms.append(IRREGULAR_PLURALS[w])
	if w.ends_with("ies") and w.length() > 4:
		forms.append(w.left(-3) + "y")
	if w.ends_with("ves") and w.length() > 4:
		forms.append(w.left(-3) + "f")
		forms.append(w.left(-3) + "fe")
	# "-es" only after s/x/z/ch/sh/o (boxes, churches, potatoes) - "James"
	# isn't "jam".
	if w.ends_with("es") and w.length() > 4:
		var stem := w.left(-2)
		for ending in ["s", "x", "z", "ch", "sh", "o"]:
			if stem.ends_with(ending):
				forms.append(stem)
				break
	if w.ends_with("s") and not w.ends_with("ss") and w.length() > 3:
		forms.append(w.left(-1))
	return forms


# Characters that only show up in IPA transcriptions, never in normal
# English or in names (so no ø, œ, ç, æ, which do).
const IPA_CHARS := "ˈˌːˑəɪʊʃʒθðŋɑɒɔɛɜʌɐɚɝɹɾʔʁʀɣχβɸʎɲɳɭʂʐɕʑɤɯɵɨʉɫʍɥʏɘɞɰɮ"
const PRONUNCIATION_WORDS := ["pronounced", "pronunciation", "pronounce", "listen", "ipa"]


func _has_ipa(word: String) -> bool:
	for c in word:
		if IPA_CHARS.contains(c):
			return true
	return false


# A respelling syllable chain: "NYOK-ee", "WUUST-ər-shər", "rə-ZAY" - a
# hyphenated word with an ALL-CAPS part (stressed syllable) of 2+ letters.
func _is_respelling(word: String) -> bool:
	var bare := word.strip_edges().lstrip("(\"'“[/").rstrip(")\"'”],.;:/")
	if not bare.contains("-"):
		return false
	var has_caps := false
	var has_lower := false
	for part in bare.split("-", false):
		if part.length() >= 2 and part == part.to_upper() and part != part.to_lower():
			has_caps = true
		elif part != part.to_upper():
			has_lower = true
	return has_caps and has_lower


func _blank_word(word: String) -> String:
	var out := ""
	for c in word:
		out += c if c in ["(", ")", ",", ";", ":", " "] else "_"
	return out


# Pronunciation help anywhere in the text, not just the lead's parentheses
# (censor_pronunciation_and_alias_parens): respellings and IPA spell the
# title out phonetically. Blanks
#   - any word with IPA characters, and /slash-delimited/ transcriptions,
#   - a whole (...) aside that holds IPA, a respelling or "pronounced",
#   - the few words after "pronounced" outside parentheses.
func censor_pronunciations(words: Array) -> void:
	var n := words.size()
	var blank := []
	blank.resize(n)
	blank.fill(false)

	# Parenthetical asides.
	var i := 0
	while i < n:
		if String(words[i]).contains("("):
			var depth := 0
			var j := i
			var marked := false
			while j < n:
				var w: String = words[j]
				depth += w.count("(") - w.count(")")
				var bare := w.to_lower().lstrip("(\"'").rstrip(")\"',.;:")
				if _has_ipa(w) or _is_respelling(w) or bare in PRONUNCIATION_WORDS:
					marked = true
				if depth <= 0 or j - i > 30:
					break
				j += 1
			if marked:
				for k in range(i, mini(j, n - 1) + 1):
					blank[k] = true
			i = j + 1
		else:
			i += 1

	for k in n:
		var w: String = words[k]
		if _has_ipa(w):
			blank[k] = true
		# /ˈræz.bər.i/ - from the opening slash to the closing one.
		if w.begins_with("/") and w.length() > 1:
			for m in range(k, mini(k + 6, n)):
				var end_word: String = words[m]
				if (m > k or end_word.length() > 1) and end_word.rstrip(",.;:)").ends_with("/"):
					for b in range(k, m + 1):
						blank[b] = true
					break
		# "... is pronounced RAZ-bər-ee" / pronounced "Ray-zee" - the
		# respelled or quoted words right after it (not "a pronounced effect").
		if w.to_lower().rstrip(",.;:") in ["pronounced", "pronunciation"]:
			var quoted := false
			for m in range(k + 1, mini(k + 8, n)):
				var next_word: String = words[m]
				if next_word.to_lower() in ["as", "like", "is", "was"] and not quoted:
					continue
				var opens_quote := next_word.length() > 1 and next_word[0] in ["\"", "'", "“", "‘"]
				if not (quoted or opens_quote or _is_respelling(next_word) or _has_ipa(next_word)):
					break
				blank[m] = true
				if opens_quote:
					quoted = true
				if quoted and next_word.rstrip(",.;:)").right(1) in ["\"", "'", "”", "’"] and (m > k + 1 or next_word.length() > 2):
					quoted = false
				if not quoted and (next_word.ends_with(",") or next_word.ends_with(".") or next_word.ends_with(";")):
					break

	for k in n:
		if blank[k]:
			words[k] = _blank_word(words[k])


# True when `word` is the leading or trailing part of `title_word` (plural
# "s"/"es" allowed), at least 4 letters - "gram"/"kilos" for "kilogram". Only
# prefix/suffix so random inner fragments don't count.
func is_title_word_part(word: String, title_word: String) -> bool:
	var stem = word.replace("-", "").replace("\"", "").replace("'", "")
	var candidates = [stem]
	if stem.ends_with("es"):
		candidates.append(stem.left(-2))
	if stem.ends_with("s"):
		candidates.append(stem.left(-1))
	for candidate in candidates:
		if candidate.length() < 4 or candidate.length() >= title_word.length():
			continue
		if title_word.begins_with(candidate) or title_word.ends_with(candidate):
			return true
	return false


# Wikipedia's lead sentence pattern is roughly:
#   Title (pronunciation), also known as X, Y (native script, romanized: Z),
#   is the ...
# There can be several parenthetical asides strung together before the
# sentence's main verb - IPA, ALL-CAPS syllable respellings like
# "WUUST-ə-shər", native scripts, romanizations, abbreviations. None of that
# resembles the title as plain characters, so the word-similarity censor
# below misses it and it leaks the answer. Rather than pattern-matching every
# respelling style, blank every parenthetical up to the first standalone
# "is"/"was"/"are"/"were" - modifies `words` in place.
func censor_pronunciation_and_alias_parens(words: Array) -> void:
	var copulas = ["is", "was", "are", "were"]
	var scan_limit = min(words.size(), 40)
	var depth = 0

	for i in range(scan_limit):
		var word = words[i]

		if depth == 0:
			var bare = word.to_lower().rstrip(",.;:")
			if copulas.has(bare):
				return

		var opens = word.count("(")
		var closes = word.count(")")

		if depth > 0 or opens > 0:
			depth += opens
			depth -= closes

			var censored = ""
			for c in word:
				if c == "(" or c == ")" or c == "," or c == ";" or c == ":" or c == " ":
					censored += c
				else:
					censored += "_"
			words[i] = censored

func split_sentences(text: String) -> Array:
	var sentences: Array = []
	var temp: Array = []

	# Split text by sentence-ending punctuation: '.', '!', '?'
	var current_sentence := ""
	var in_brackets = false
	
	for c in text:
		# Handle square brackets
		if c == "[":
			in_brackets = true
			continue
		elif c == "]":
			in_brackets = false
			continue
		
		# Skip characters inside brackets
		if in_brackets:
			continue
		
		# Normal sentence building
		current_sentence += c
		if c in [".", "!", "?"]:
			temp.append(current_sentence.strip_edges())
			current_sentence = ""

	# Add any remaining text
	if current_sentence.strip_edges() != "":
		temp.append(current_sentence.strip_edges())

	# Merge sentences with 3 or fewer words into previous sentence
	for sentence in temp:
		if sentence == "":
			continue
		if sentences.size() > 0 and sentence.split(" ").size() <= 3:
			sentences[sentences.size() - 1] += " " + sentence
		else:
			sentences.append(sentence)
	return sentences
