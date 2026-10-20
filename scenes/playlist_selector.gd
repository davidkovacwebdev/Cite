class_name PlaylistSelector
extends VBoxContainer

# Single-choice playlist list used by MultiplayerLobby (host form and room).
# Two sections - "Official" (built-in, Global.MULTIPLAYER_PLAYLIST_FOLDER)
# and "Community" (approved Workshop playlists) - each sorted
# alphabetically, with a search box that hides rows whose name doesn't
# match. Rows show an icon on the left: the Cite logo for official
# playlists, the Workshop preview image for community ones.

signal playlist_selected(playlist_id: String)

const OFFICIAL_ICON := preload("res://assets/sprites/cite_exee_logo.png")
const COMMUNITY_FALLBACK_ICON := preload("res://assets/sprites/cite-logoonly-small.png")
const ICON_SIZE := Vector2(44, 44)
const ROW_HEIGHT := 56
const SELECTED_BORDER_COLOR := Color("#3b4fd8")

var interactive: bool = true
var selected_id: String = ""
var rows: Dictionary = {}  # playlist_id -> Button
var row_names: Dictionary = {}  # playlist_id -> display name
var button_group := ButtonGroup.new()
var selected_style: StyleBoxFlat

var search: LineEdit
var scroll: ScrollContainer
var list: VBoxContainer
var official_header: Label
var community_header: Label
var community_empty_label: Label
var no_match_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	# The theme's pressed look is barely different from normal - outline the
	# selected row instead so the current choice is obvious.
	selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(0.16, 0.2, 0.42, 0.85)
	selected_style.border_color = SELECTED_BORDER_COLOR
	selected_style.set_border_width_all(3)
	selected_style.set_corner_radius_all(4)

	search = LineEdit.new()
	search.placeholder_text = "Search playlists..."
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text): _apply_filter())
	add_child(search)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	official_header = _make_header("Official")
	community_header = _make_header("Community")
	community_empty_label = _make_note("No community playlists yet.")
	no_match_label = _make_note("No playlists match your search.")

	# Scrolling while hidden uses stale sizes - redo it once shown.
	visibility_changed.connect(func():
		if is_visible_in_tree() and rows.has(selected_id):
			_scroll_to(rows[selected_id]))


# Rebuilds the list. extra_names gives display names for IDs this player
# can't name itself (e.g. the host's community playlist before it has
# downloaded).
func set_playlists(playlist_ids: Array, extra_names: Dictionary = {}) -> void:
	for child in list.get_children():
		list.remove_child(child)
		if child not in [official_header, community_header, community_empty_label, no_match_label]:
			child.queue_free()
	rows.clear()
	row_names.clear()

	var official: Array = []
	var community: Array = []
	for id in playlist_ids:
		row_names[id] = extra_names.get(id, Global.get_playlist_display_name(id).trim_suffix(" (Community)"))
		(community if Workshop.is_community_id(id) else official).append(id)
	for id in extra_names:
		if not row_names.has(id):
			row_names[id] = extra_names[id]
			(community if Workshop.is_community_id(id) else official).append(id)
	var by_name = func(a, b): return row_names[a].naturalnocasecmp_to(row_names[b]) < 0
	official.sort_custom(by_name)
	community.sort_custom(by_name)

	list.add_child(official_header)
	for id in official:
		list.add_child(_make_row(id, OFFICIAL_ICON))
	list.add_child(community_header)
	for id in community:
		list.add_child(_make_row(id, _community_icon(id)))
	list.add_child(community_empty_label)
	list.add_child(no_match_label)

	select(selected_id)
	_apply_filter()


func select(playlist_id: String) -> void:
	selected_id = playlist_id
	var pressed = button_group.get_pressed_button()
	if pressed and (not rows.has(playlist_id) or pressed != rows[playlist_id]):
		pressed.set_pressed_no_signal(false)
	if rows.has(playlist_id):
		rows[playlist_id].set_pressed_no_signal(true)
		_scroll_to.call_deferred(rows[playlist_id])


func get_selected_id() -> String:
	return selected_id if rows.has(selected_id) else ""


func has_playlist(playlist_id: String) -> bool:
	return rows.has(playlist_id)


# Read-only mode (the guest sees the host's choice but can't change it).
func set_interactive(value: bool) -> void:
	interactive = value
	for row in rows.values():
		row.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		row.focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE


func _make_row(playlist_id: String, icon_texture: Texture2D) -> Button:
	var row = Button.new()
	row.toggle_mode = true
	row.button_group = button_group
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	row.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	row.tooltip_text = row_names[playlist_id]
	row.pressed.connect(_on_row_pressed.bind(playlist_id))
	for style_name in ["pressed", "hover_pressed"]:
		row.add_theme_stylebox_override(style_name, selected_style)

	var content = HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8
	content.offset_right = -8
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)

	var icon = TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)

	var label = Label.new()
	label.text = row_names[playlist_id]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)

	rows[playlist_id] = row
	return row


func _community_icon(playlist_id: String) -> Texture2D:
	var preview = Workshop.get_preview_texture(Workshop.file_id_of(playlist_id))
	return preview if preview else COMMUNITY_FALLBACK_ICON


func _make_header(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	_add_outline(label)
	return label


func _make_note(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_outline(label)
	return label


# Headers and notes sit straight on the lobby's light background.
func _add_outline(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.067, 0.071, 0.086))
	label.add_theme_constant_override("outline_size", 6)


func _on_row_pressed(playlist_id: String) -> void:
	if not interactive:
		return
	selected_id = playlist_id
	playlist_selected.emit(playlist_id)


func _apply_filter() -> void:
	var query = search.text.strip_edges()
	var official_visible = 0
	var community_visible = 0
	var community_total = 0
	for id in rows:
		var matches = query.is_empty() or row_names[id].findn(query) != -1
		rows[id].visible = matches
		if Workshop.is_community_id(id):
			community_total += 1
			community_visible += int(matches)
		else:
			official_visible += int(matches)

	official_header.visible = official_visible > 0
	community_header.visible = community_visible > 0 or (query.is_empty() and community_total == 0)
	community_empty_label.visible = query.is_empty() and community_total == 0
	no_match_label.visible = not query.is_empty() and official_visible + community_visible == 0


func _scroll_to(row: Control) -> void:
	# Rows only get their final positions once the containers have sorted.
	await get_tree().process_frame
	if not is_instance_valid(row) or not row.is_visible_in_tree():
		return
	# Keep the section header in view when its first row is the selected one.
	var top = row.position.y
	var before = list.get_child(row.get_index() - 1) if row.get_index() > 0 else null
	if before is Label and before.visible:
		top = before.position.y
	var bottom = row.position.y + row.size.y
	if scroll.scroll_vertical > top:
		scroll.scroll_vertical = int(top)
	elif scroll.scroll_vertical + scroll.size.y < bottom:
		scroll.scroll_vertical = int(bottom - scroll.size.y)
