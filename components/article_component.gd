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
	var path = Global.get_playlist_path(Global.multiplayer_playlist_id)
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("Failed to open multiplayer playlist: ", path)
		return

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		print("Failed to parse multiplayer playlist: ", path)
		return

	Global.run.wikipedia_ids.clear()
	for id in json.data.values():
		Global.run.wikipedia_ids.append(int(id))

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
	$HTTPRequest.request(url)
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
	var error = $HTTPRequestHC.request(url)
	
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
		"id": page_id
	}

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
		Global.run.current_round.censor_title()

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



func format_text(article_title: String, article_alt_title: String, article_extract: String) -> String:
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
	
	# Process each word in the extract
	var words = article_extract.split(" ")

	censor_pronunciation_and_alias_parens(words)

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
