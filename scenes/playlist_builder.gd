class_name PlaylistBuilder
extends VBoxContainer

# In-game playlist explorer used by MultiplayerLobby's Submit Playlist flow:
# search Wikipedia, open an article to read its intro (what players will
# see), add it, and hand the finished {"Article Title": page_id} playlist
# to the regular Workshop submit form. The playlist in progress is saved to
# DRAFT_PATH after every change so leaving the screen never loses it.

signal back_pressed
signal continue_pressed(playlist: Dictionary)

const API_URL := "https://en.wikipedia.org/w/api.php?format=json&formatversion=2&"
const PAGE_URL := "https://en.wikipedia.org/?curid=%d"
const DRAFT_PATH := "user://playlist_draft.json"
const SEARCH_LIMIT := 20  # TextExtracts gives at most 20 intros per request
const MIN_ARTICLE_WORDS := 150  # intro length - shorter articles are hidden and can't be added
const SEARCH_DELAY_SECONDS := 0.4  # typing pause before searching
const IMAGE_SIZE := Vector2(150, 110)  # article thumbnail box, top right of the preview
const IMAGE_FETCH_WIDTH := 300  # px - 2x the box so it stays sharp when scaled
# Colours/fonts come from the hub theme the lobby uses (ui/hub/hub_theme.tres):
# type variations for widgets, "Hub" colours ("added", "warning") for states.

var playlist: Dictionary = {}  # title -> page_id, in the order added
var preview_page_id: int = 0
var preview_title: String = ""
var preview_disambiguation: bool = false
var preview_playable: bool = false
var search_query: String = ""
var search_offset: int = 0  # gsroffset for the next "More results" page, -1 = none
var hidden_count: int = 0  # results dropped this search (too short / disambiguation)
var word_regex := RegEx.create_from_string("\\S+")

var search_request: HTTPRequest
var preview_request: HTTPRequest
var image_request: HTTPRequest
var search_timer: Timer
var result_buttons: Dictionary = {}  # page_id -> Button

var search_input: LineEdit
var results_list: VBoxContainer
var results_note: Label
var more_button: Button
var preview_title_label: Label
var preview_info_label: Label
var preview_text: RichTextLabel
var preview_image: TextureRect
var add_button: Button
var open_button: Button
var playlist_header: Label
var playlist_list: VBoxContainer
var save_button: Button
var clear_button: Button
var status_label: Label
var continue_button: Button
var save_dialog: FileDialog
var clear_armed: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 12)

	search_request = HTTPRequest.new()
	search_request.request_completed.connect(_on_search_completed)
	add_child(search_request)
	preview_request = HTTPRequest.new()
	preview_request.request_completed.connect(_on_preview_completed)
	add_child(preview_request)
	image_request = HTTPRequest.new()
	image_request.request_completed.connect(_on_image_completed)
	add_child(image_request)
	search_timer = Timer.new()
	search_timer.one_shot = true
	search_timer.wait_time = SEARCH_DELAY_SECONDS
	search_timer.timeout.connect(_search)
	add_child(search_timer)

	var title = Label.new()
	title.text = "Build a Playlist"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = "PageTitle"
	add_child(title)

	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	add_child(columns)

	# Left: search + results
	var left = _make_column(columns, 280)
	search_input = LineEdit.new()
	search_input.placeholder_text = "Search Wikipedia..."
	search_input.clear_button_enabled = true
	search_input.text_changed.connect(func(_text): search_timer.start())
	search_input.text_submitted.connect(func(_text): _search())
	left.add_child(search_input)
	results_note = _make_note("Search for an article to add.")
	left.add_child(results_note)
	results_list = _make_scroll_list(left)
	more_button = Button.new()
	more_button.theme_type_variation = "SmallButton"
	more_button.text = "More results"
	more_button.visible = false
	more_button.pressed.connect(func(): _request_search_page())
	left.add_child(more_button)

	# Middle: article preview
	var middle = _make_column(columns, 0)
	middle.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	middle.add_child(header)
	var heading = VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	preview_title_label = Label.new()
	preview_title_label.theme_type_variation = "HeaderMedium"
	preview_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(preview_title_label)
	preview_info_label = _make_note("")
	heading.add_child(preview_info_label)
	preview_image = TextureRect.new()
	preview_image.custom_minimum_size = IMAGE_SIZE
	preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview_image.visible = false
	header.add_child(preview_image)
	preview_text = RichTextLabel.new()
	preview_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_text.scroll_active = true
	preview_text.selection_enabled = true
	middle.add_child(preview_text)
	var preview_buttons = HBoxContainer.new()
	preview_buttons.add_theme_constant_override("separation", 10)
	middle.add_child(preview_buttons)
	add_button = Button.new()
	add_button.theme_type_variation = "CtaButton"
	add_button.add_theme_font_size_override("font_size", 16)
	add_button.text = "Add to Playlist"
	add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_button.pressed.connect(_on_add_pressed)
	preview_buttons.add_child(add_button)
	open_button = Button.new()
	open_button.theme_type_variation = "SmallButton"
	open_button.text = "Open on Wikipedia"
	open_button.pressed.connect(func(): OS.shell_open(PAGE_URL % preview_page_id))
	preview_buttons.add_child(open_button)

	# Right: the playlist so far
	var right = _make_column(columns, 260)
	playlist_header = Label.new()
	playlist_header.theme_type_variation = "HeaderSmall"
	right.add_child(playlist_header)
	playlist_list = _make_scroll_list(right)
	var list_buttons = HBoxContainer.new()
	list_buttons.add_theme_constant_override("separation", 8)
	right.add_child(list_buttons)
	save_button = Button.new()
	save_button.theme_type_variation = "SmallButton"
	save_button.text = "Save as File..."
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(func(): save_dialog.popup_centered_ratio(0.6))
	list_buttons.add_child(save_button)
	clear_button = Button.new()
	clear_button.theme_type_variation = "SmallButton"
	clear_button.text = "Clear"
	clear_button.pressed.connect(_on_clear_pressed)
	list_buttons.add_child(clear_button)

	# Bottom: Back / status / Continue
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	add_child(bottom)
	var back = Button.new()
	back.theme_type_variation = "GhostButton"
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 0)
	back.add_to_group("back_button")
	back.pressed.connect(func(): back_pressed.emit())
	bottom.add_child(back)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.theme_type_variation = "MutedLabel"
	bottom.add_child(status_label)
	continue_button = Button.new()
	continue_button.theme_type_variation = "CtaButton"
	continue_button.add_theme_font_size_override("font_size", 16)
	continue_button.text = "Continue to Submit"
	continue_button.custom_minimum_size = Vector2(220, 0)
	continue_button.pressed.connect(func(): continue_pressed.emit(playlist.duplicate()))
	bottom.add_child(continue_button)

	save_dialog = FileDialog.new()
	save_dialog.title = "Save playlist"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.json ; Playlist JSON"])
	save_dialog.current_file = "playlist.json"
	save_dialog.use_native_dialog = true
	save_dialog.file_selected.connect(_on_save_file_selected)
	add_child(save_dialog)

	_load_draft()
	_show_preview_placeholder()
	_refresh_playlist()


# Called by the lobby each time the screen is shown.
func open() -> void:
	clear_armed = false
	clear_button.text = "Clear"
	status_label.text = "Click a result to read it, then add it. Playlists need at least %d articles." \
		% Workshop.MIN_PLAYLIST_ARTICLES
	search_input.grab_focus()


# --- Search ----------------------------------------------------------------

# Searches titles and article text. Each page of results comes with its
# intro, so short articles and disambiguation pages are dropped before
# they're listed.
func _search() -> void:
	search_timer.stop()
	search_request.cancel_request()
	_clear_results()
	search_query = search_input.text.strip_edges()
	hidden_count = 0
	if search_query.is_empty():
		_set_results_note("Search for an article to add.")
		return
	search_offset = 0
	_request_search_page()


func _request_search_page() -> void:
	more_button.visible = false
	_set_results_note("Searching...")
	var url = API_URL + "action=query&generator=search&gsrnamespace=0&gsrlimit=%d&gsroffset=%d&gsrsearch=%s" \
		% [SEARCH_LIMIT, search_offset, search_query.uri_encode()] \
		+ "&prop=extracts%7Cpageprops&ppprop=disambiguation&exintro=true&explaintext=true&exlimit=max"
	if search_request.request(url) != OK:
		_set_results_note("Couldn't reach Wikipedia.")


func _on_search_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = _parse_response(result, response_code, body)
	if data == null:
		_set_results_note("Couldn't reach Wikipedia.")
		more_button.visible = search_offset > 0
		return
	var pages: Array = data.get("query", {}).get("pages", [])
	pages.sort_custom(func(a, b): return a.get("index", 0) < b.get("index", 0))
	for page in pages:
		var page_id = int(page.get("pageid", 0))
		var title = String(page.get("title", ""))
		if page_id <= 0 or title.is_empty() or result_buttons.has(page_id):
			continue
		var extract = String(page.get("extract", "")).strip_edges()
		if page.get("pageprops", {}).has("disambiguation") or _word_count(extract) < MIN_ARTICLE_WORDS:
			hidden_count += 1
			continue
		var row = _make_row_button(title)
		row.tooltip_text = extract.left(300) + ("..." if extract.length() > 300 else "")
		row.pressed.connect(_show_preview.bind(page_id, title))
		results_list.add_child(row)
		result_buttons[page_id] = row
	_mark_added_results()

	search_offset = int(data.get("continue", {}).get("gsroffset", -1))
	more_button.visible = search_offset > 0
	var note = ""
	if result_buttons.is_empty():
		note = "No articles found." if hidden_count == 0 else "No playable articles found."
	if hidden_count > 0:
		note += ("\n" if not note.is_empty() else "") \
			+ "%d hidden (under %d words, or disambiguation)." % [hidden_count, MIN_ARTICLE_WORDS]
	_set_results_note(note)


func _clear_results() -> void:
	for child in results_list.get_children():
		child.queue_free()
	result_buttons.clear()
	more_button.visible = false


func _set_results_note(note: String) -> void:
	results_note.text = note
	results_note.visible = not note.is_empty()


# --- Preview ---------------------------------------------------------------

func _show_preview_placeholder() -> void:
	preview_page_id = 0
	preview_title = ""
	preview_title_label.text = "No article open"
	preview_info_label.text = ""
	preview_playable = false
	preview_text.text = "Search on the left and click a result to see its intro - the text players reveal during a match."
	_update_preview_buttons()


func _show_preview(page_id: int, title: String) -> void:
	preview_request.cancel_request()
	image_request.cancel_request()
	preview_image.visible = false
	preview_image.texture = null
	preview_page_id = page_id
	preview_title = title
	preview_disambiguation = false
	preview_playable = false
	preview_title_label.text = title
	preview_info_label.text = "Loading..."
	preview_info_label.remove_theme_color_override("font_color")
	preview_text.text = ""
	_update_preview_buttons()
	var url = API_URL + "action=query&prop=extracts%%7Cpageprops%%7Cpageviews%%7Cpageimages&ppprop=disambiguation&pvipdays=30&piprop=thumbnail&pithumbsize=%d&exintro=true&explaintext=true&redirects=true&pageids=%d" \
		% [IMAGE_FETCH_WIDTH, page_id]
	if preview_request.request(url) != OK:
		preview_info_label.text = "Couldn't reach Wikipedia."


func _on_preview_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = _parse_response(result, response_code, body)
	var pages = data.get("query", {}).get("pages", []) if data != null else []
	if pages.is_empty() or pages[0].has("missing"):
		preview_info_label.text = "Couldn't load this article."
		return
	var page = pages[0]
	preview_page_id = int(page.get("pageid", preview_page_id))
	preview_title = String(page.get("title", preview_title))
	preview_title_label.text = preview_title
	preview_disambiguation = page.get("pageprops", {}).has("disambiguation")
	var extract = String(page.get("extract", "")).strip_edges()
	var words = _word_count(extract)
	preview_text.text = extract if not extract.is_empty() else "(This article has no intro text.)"
	preview_text.scroll_to_line(0)
	var thumbnail_url = String(page.get("thumbnail", {}).get("source", ""))
	if not thumbnail_url.is_empty():
		image_request.request(thumbnail_url)

	if preview_disambiguation:
		preview_info_label.text = "Disambiguation page - pick one of the specific articles instead."
		preview_info_label.add_theme_color_override("font_color", get_theme_color("warning", "Hub"))
	elif words < MIN_ARTICLE_WORDS:
		preview_info_label.text = "Only %d words - articles need at least %d." % [words, MIN_ARTICLE_WORDS]
		preview_info_label.add_theme_color_override("font_color", get_theme_color("warning", "Hub"))
	else:
		preview_playable = true
		var views = _average_daily_views(page.get("pageviews"))
		var popularity = "views unknown" if views < 0 \
			else "%s, ~%d views/day" % [_popularity_label(views), roundi(views)]
		preview_info_label.text = "%d words  ·  %s" % [words, popularity]
		preview_info_label.remove_theme_color_override("font_color")
	_update_preview_buttons()


# Articles without a lead image (or one Godot can't decode, e.g. GIF) just
# keep the thumbnail hidden.
func _on_image_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var image = Workshop.image_from_bytes(body)
	if image == null:
		return
	preview_image.texture = ImageTexture.create_from_image(image)
	preview_image.visible = true


func _update_preview_buttons() -> void:
	open_button.disabled = preview_page_id <= 0
	if _has_page(preview_page_id):
		add_button.text = "Remove from Playlist"
		add_button.disabled = false
	else:
		add_button.text = "Add to Playlist"
		add_button.disabled = not preview_playable or playlist.size() >= Workshop.MAX_PLAYLIST_ARTICLES


func _on_add_pressed() -> void:
	if _has_page(preview_page_id):
		_remove_page(preview_page_id)
		return
	if playlist.has(preview_title):
		status_label.text = "\"%s\" is already in the playlist." % preview_title
		return
	playlist[preview_title] = preview_page_id
	status_label.text = "Added \"%s\"." % preview_title
	_refresh_playlist()
	search_input.grab_focus()


# --- Playlist --------------------------------------------------------------

func _has_page(page_id: int) -> bool:
	return page_id > 0 and playlist.values().has(page_id)


func _remove_page(page_id: int) -> void:
	for title in playlist.keys():
		if playlist[title] == page_id:
			playlist.erase(title)
			status_label.text = "Removed \"%s\"." % title
	_refresh_playlist()


func _refresh_playlist() -> void:
	for child in playlist_list.get_children():
		child.queue_free()
	# Newest first, so what was just added is always in view.
	var titles = playlist.keys()
	titles.reverse()
	for title in titles:
		var page_id: int = playlist[title]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var open = _make_row_button(title)
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.pressed.connect(_show_preview.bind(page_id, title))
		row.add_child(open)
		var remove = Button.new()
		remove.theme_type_variation = "RowButton"
		remove.text = "x"
		remove.tooltip_text = "Remove"
		remove.custom_minimum_size = Vector2(30, 0)
		remove.pressed.connect(_remove_page.bind(page_id))
		row.add_child(remove)
		playlist_list.add_child(row)

	var count = playlist.size()
	var enough = count >= Workshop.MIN_PLAYLIST_ARTICLES
	playlist_header.text = "Your playlist: %d" % count if enough \
		else "Your playlist: %d (min. %d)" % [count, Workshop.MIN_PLAYLIST_ARTICLES]
	playlist_header.add_theme_color_override("font_color", get_theme_color("added" if enough else "text", "Hub"))
	continue_button.disabled = not enough
	continue_button.tooltip_text = "" if enough \
		else "Add %d more article(s) first." % (Workshop.MIN_PLAYLIST_ARTICLES - count)
	save_button.disabled = playlist.is_empty()
	clear_button.disabled = playlist.is_empty()
	_mark_added_results()
	_update_preview_buttons()
	_save_draft()


func _mark_added_results() -> void:
	for page_id in result_buttons:
		var button: Button = result_buttons[page_id]
		if _has_page(page_id):
			button.add_theme_color_override("font_color", get_theme_color("added", "Hub"))
		else:
			button.remove_theme_color_override("font_color")


# Two clicks, so one stray press can't wipe a long playlist.
func _on_clear_pressed() -> void:
	if not clear_armed:
		clear_armed = true
		clear_button.text = "Sure?"
		return
	clear_armed = false
	clear_button.text = "Clear"
	playlist.clear()
	status_label.text = "Playlist cleared."
	_refresh_playlist()


func _on_save_file_selected(path: String) -> void:
	if path.get_extension().to_lower() != "json":
		path += ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		status_label.text = "Couldn't save to %s." % path.get_file()
		return
	file.store_string(JSON.stringify(playlist, "  ", false))
	file.close()
	status_label.text = "Saved %d articles to %s." % [playlist.size(), path.get_file()]


func _save_draft() -> void:
	var file = FileAccess.open(DRAFT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(playlist, "", false))
		file.close()


func _load_draft() -> void:
	if not FileAccess.file_exists(DRAFT_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(DRAFT_PATH))
	if not data is Dictionary:
		return
	for title in data:
		if typeof(data[title]) in [TYPE_INT, TYPE_FLOAT] and int(data[title]) > 0:
			playlist[String(title)] = int(data[title])


# --- Helpers ---------------------------------------------------------------

func _parse_response(result: int, response_code: int, body: PackedByteArray) -> Variant:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return null
	var data = JSON.parse_string(body.get_string_from_utf8())
	return data if data is Dictionary else null


# prop=pageviews gives {"2026-10-01": 123, ...} with null for days that
# aren't counted yet - same averaging as Article.average_daily_views().
func _average_daily_views(pageviews) -> float:
	if not pageviews is Dictionary:
		return -1.0
	var total := 0.0
	var days := 0
	for views in pageviews.values():
		if views != null:
			total += float(views)
			days += 1
	return total / days if days > 0 else -1.0


func _popularity_label(daily_views: float) -> String:
	for tier in Leaderboards.HARDCORE_TIERS:
		if daily_views >= tier["min_views"]:
			return tier["label"]
	return Leaderboards.HARDCORE_TIERS[0]["label"]


func _word_count(text: String) -> int:
	return word_regex.search_all(text).size()


func _make_column(parent: Control, width: int) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.theme_type_variation = "SidePanel"
	parent.add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	return column


func _make_scroll_list(parent: Control) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	return list


func _make_row_button(text: String) -> Button:
	var button = Button.new()
	button.text = text
	button.theme_type_variation = "RowButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _make_note(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = "MutedLabel"
	return label
