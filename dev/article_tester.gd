extends Control

# Every article the game can serve: data.json (Legacy) plus every official
# and Workshop playlist (Normal / Ranked / multiplayer), merged by page id.
var all_articles: Array = []  # [{ "id": int, "title": String, "search": String, "sources": Array }]

const MAX_RESULTS := 50


func _ready() -> void:
	%SearchInput.text_changed.connect(_on_search_text_changed)
	%ResultsList.item_activated.connect(_on_result_activated)
	%BackButton.pressed.connect(_on_back_pressed)
	_load_articles()
	%SearchInput.grab_focus()


func _load_articles() -> void:
	var by_id := {}  # page id -> entry

	# Playlists first so their titles win (data.json calls both the country
	# and the city "Djibouti"; the Geography playlist says "Djibouti City").
	for playlist_id in Global.get_available_playlist_ids():
		var pfile = FileAccess.open(Global.get_playlist_path(playlist_id), FileAccess.READ)
		if not pfile:
			continue
		var playlist = JSON.parse_string(pfile.get_as_text())
		pfile.close()
		if not playlist is Dictionary:
			continue
		var source_name := Global.get_playlist_display_name(playlist_id)
		for title in playlist:
			_add_article(by_id, int(playlist[title]), str(title), source_name)

	var file = FileAccess.open("res://assets/data/data.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data is Array:
			for entry in data:
				_add_article(by_id, int(entry.id), str(entry.title), "Legacy")

	all_articles = by_id.values()
	all_articles.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)
	if all_articles.is_empty():
		%StatusLabel.text = "Failed to load any articles."
		return
	%StatusLabel.text = _idle_status()


func _add_article(by_id: Dictionary, id: int, title: String, source_name: String) -> void:
	if id == 0:
		return
	if not by_id.has(id):
		by_id[id] = {"id": id, "title": title, "search": _simplify(title), "sources": []}
	if not source_name in by_id[id].sources:
		by_id[id].sources.append(source_name)


func _simplify(text: String) -> String:
	return Global.strip_accents(text.strip_edges().to_lower())


func _idle_status() -> String:
	return "%d articles loaded (data.json + playlists). Start typing to search." % all_articles.size()


func _on_search_text_changed(text: String) -> void:
	%ResultsList.clear()
	var query = _simplify(text)
	if query == "":
		%StatusLabel.text = _idle_status()
		return

	var matches = 0
	for article in all_articles:
		if query in article["search"] or query == str(article["id"]):
			%ResultsList.add_item("%s   -   %s  [%d]" % [article["title"], ", ".join(article["sources"]), article["id"]])
			%ResultsList.set_item_metadata(%ResultsList.item_count - 1, article["id"])
			matches += 1
			if matches >= MAX_RESULTS:
				break

	if matches == 0:
		%StatusLabel.text = "No matches."
	elif matches >= MAX_RESULTS:
		%StatusLabel.text = "Showing first %d matches - narrow your search for more." % MAX_RESULTS
	else:
		%StatusLabel.text = "%d match(es). Double-click one to load it." % matches


func _on_result_activated(index: int) -> void:
	var article_id = %ResultsList.get_item_metadata(index)
	Global.start_new_run()
	Global.debug_forced_article_id = article_id
	get_tree().change_scene_to_file("res://scenes/Round.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(Global.MENU_SCENE)
