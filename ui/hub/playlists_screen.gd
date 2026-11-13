extends "res://ui/hub/hub_screen.gd"

# Playlists tab of the hub (also the hub's Playlists card "Browse"). Left:
# every playlist - Official and Community sections, with search (the same
# PlaylistSelector the lobby uses). Right: the selected playlist's name,
# author, size and description, with Play Single Player and Create Room
# (opens the lobby's host form with this playlist already picked).

const DETAILS_WIDTH := 340
const PREVIEW_SIZE := 64
# Compact action buttons so the description gets the panel's height.
const ACTION_FONT_SIZE := 14
const OFFICIAL_AUTHOR := "Cite team"

var selector: PlaylistSelector
var selected_id := ""

var preview: TextureRect
var name_label: Label
var author_label: Label
var kind_tag: Label
var count_label: Label
var description_label: Label
var workshop_button: Button
var details_box: VBoxContainer
var empty_label: Label


func _ready() -> void:
	Steam.persona_state_change.connect(_on_persona_state_change)
	Workshop.community_playlists_changed.connect(_reload_playlists)
	var column := _setup_screen("Playlists")

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	body.add_child(_build_list())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	body.add_child(right)
	right.add_child(_build_details())
	right.add_child(_build_own_uploads())
	var back := _button("Back to Play", "GhostButton", _on_nav_play)
	right.add_child(back)

	_reload_playlists()
	var ids := Global.get_available_playlist_ids()
	if not ids.is_empty():
		_select(Global.multiplayer_playlist_id if Global.multiplayer_playlist_id in ids else ids[0])
	# Pick up newly approved / updated community playlists.
	Workshop.refresh_community_playlists()


# --- Layout -------------------------------------------------------------------

func _build_list() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TablePanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_label("PLAYLISTS", "Eyebrow"))
	titles.add_child(_label("Browse playlists", "HeaderLarge"))
	head.add_child(titles)
	# Workshop submit flow: build one in-game or upload a .json file.
	var create := _button("Submit a community playlist", "", func(): _open_lobby("submit"))
	create.tooltip_text = "Build a playlist or upload a file to the Steam Workshop"
	create.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(create)
	box.add_child(head)

	selector = PlaylistSelector.new()
	selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selector.playlist_selected.connect(_select)
	box.add_child(selector)
	return panel


func _build_details() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "SidePanel"
	panel.custom_minimum_size.x = DETAILS_WIDTH
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var outer := VBoxContainer.new()
	panel.add_child(outer)

	empty_label = _label("Pick a playlist to see its details.", "MutedLabel")
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(empty_label)

	details_box = VBoxContainer.new()
	details_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_box.add_theme_constant_override("separation", 10)
	outer.add_child(details_box)

	# Preview beside the name/author, not above them.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	details_box.add_child(head)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(preview)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 2)
	head.add_child(names)

	name_label = _label("", "HeaderMedium")
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(name_label)

	author_label = _label("", "BodyLabel")
	author_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(author_label)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 10)
	kind_tag = _label("", "TagLabel")
	kind_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(kind_tag)
	count_label = _label("", "SmallMuted")
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(count_label)
	details_box.add_child(meta)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	description_label = _label("", "MutedLabel")
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(description_label)
	details_box.add_child(scroll)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	details_box.add_child(actions)
	var play := _button("Single Player", "CtaButton", func():
		if _still_available():
			_start_single_player(false, selected_id))
	var room := _button("Create Room", "", func():
		if _still_available():
			_create_room_with(selected_id))
	for b in [play, room]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
		actions.add_child(b)
		_compact.call_deferred(b)  # once in the tree, so it copies the hub theme's boxes
	workshop_button = _button("View on Steam Workshop", "SmallButton", func():
		Workshop.open_item_page(Workshop.file_id_of(selected_id)))
	workshop_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	details_box.add_child(workshop_button)

	_show_details(false)
	return panel


# Shorter padding than the theme's 18x8 for these buttons.
func _compact(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := b.get_theme_stylebox(state).duplicate() as StyleBox
		if box:
			box.content_margin_left = 10
			box.content_margin_right = 10
			box.content_margin_top = 5
			box.content_margin_bottom = 5
			b.add_theme_stylebox_override(state, box)


# --- Data ---------------------------------------------------------------------

func _reload_playlists() -> void:
	selector.set_playlists(Global.get_available_playlist_ids())
	if selector.has_playlist(selected_id):
		selector.select(selected_id)
		_fill_details()
	else:
		selected_id = ""
		_show_details(false)


func _select(playlist_id: String) -> void:
	selected_id = playlist_id
	selector.select(playlist_id)
	_fill_details()


func _fill_details() -> void:
	if selected_id.is_empty():
		_show_details(false)
		return
	_show_details(true)
	var community := Workshop.is_community_id(selected_id)
	name_label.text = Global.get_playlist_display_name(selected_id).trim_suffix(" (Community)")
	kind_tag.text = "Community" if community else "Official"
	var count := Global.get_playlist_article_ids(selected_id).size()
	count_label.text = "%d articles" % count
	workshop_button.visible = community
	if community:
		var file_id := Workshop.file_id_of(selected_id)
		var texture := Workshop.get_preview_texture(file_id)
		preview.texture = texture if texture else PlaylistSelector.COMMUNITY_FALLBACK_ICON
		description_label.text = Workshop.get_description(file_id).strip_edges()
		_fill_author(Workshop.get_author_id(file_id))
	else:
		preview.texture = PlaylistSelector.OFFICIAL_ICON
		description_label.text = "A built-in playlist. Ranked Duels and the Daily Challenge draw from every official playlist."
		author_label.text = "by " + OFFICIAL_AUTHOR


func _fill_author(author_id: int) -> void:
	if author_id == 0:
		author_label.text = "by a community author"
		return
	# Steam may not know the name yet; persona_state_change fills it in.
	if Steam.requestUserInformation(author_id, true):
		author_label.text = "by ..."
	else:
		author_label.text = "by " + Steam.getFriendPersonaName(author_id)


func _on_persona_state_change(steam_id: int, _flags: int) -> void:
	if Workshop.is_community_id(selected_id) and steam_id == Workshop.get_author_id(Workshop.file_id_of(selected_id)):
		author_label.text = "by " + Steam.getFriendPersonaName(steam_id)


func _show_details(on: bool) -> void:
	details_box.visible = on
	empty_label.visible = not on


# Already on the Playlists screen: just select it.
func _open_playlist(file_id: int) -> void:
	var id := Workshop.playlist_id_of(file_id)
	if selector.has_playlist(id):
		_select(id)


# A community playlist can be withdrawn by a refresh while it's shown.
func _still_available() -> bool:
	if selected_id in Global.get_available_playlist_ids():
		return true
	_show_toast("That playlist isn't available any more")
	return false
