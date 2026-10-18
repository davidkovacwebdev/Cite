extends Control

var all_articles: Array = []  # [{ "id": int, "title": String }]

const MAX_RESULTS := 50


func _ready() -> void:
	%SearchInput.text_changed.connect(_on_search_text_changed)
	%ResultsList.item_activated.connect(_on_result_activated)
	%BackButton.pressed.connect(_on_back_pressed)
	_load_articles()
	%SearchInput.grab_focus()


func _load_articles() -> void:
	var file = FileAccess.open("res://assets/data/data.json", FileAccess.READ)
	if not file:
		%StatusLabel.text = "Failed to open article database."
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		%StatusLabel.text = "Failed to parse article database."
		return
	file.close()

	for entry in json.data:
		all_articles.append({"id": int(entry.id), "title": entry.title})

	%StatusLabel.text = "%d articles loaded. Start typing to search." % all_articles.size()


func _on_search_text_changed(text: String) -> void:
	%ResultsList.clear()
	var query = text.strip_edges().to_lower()
	if query == "":
		%StatusLabel.text = "%d articles loaded. Start typing to search." % all_articles.size()
		return

	var matches = 0
	for article in all_articles:
		if query in article["title"].to_lower():
			%ResultsList.add_item(article["title"])
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
	get_tree().change_scene_to_file("res://Main/Main.tscn")
