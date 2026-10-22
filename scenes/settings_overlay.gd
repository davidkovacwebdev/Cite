extends CanvasLayer

class_name SettingsOverlay

# In-match settings: the main menu's volume settings plus a few game options
# and Leave match (Quit run in single player), shown as a transparent overlay
# over the match. Toggled with Esc or the small button in the bottom-left
# corner. The game keeps running underneath - there's no pausing.

const SETTINGS_PATH := "user://scene_data.tres"
const PANEL_WIDTH := 380
const LEAVE_WARNING_COLOR := Color(1.0, 0.45, 0.45)

var settings: SaveData
var panel_root: Control
var text_size_label: Label
var leave_button: Button
var leave_warning: Label


func _ready() -> void:
	layer = 50  # above the board, banners and the reward picker
	settings = ResourceLoader.load(SETTINGS_PATH) as SaveData
	if not settings:
		settings = SaveData.new()

	# Placeholder for a cog icon later.
	var open_button = Button.new()
	open_button.text = "Settings"
	open_button.add_theme_font_size_override("font_size", 13)
	open_button.position = Vector2(12, 608)
	open_button.focus_mode = Control.FOCUS_NONE
	open_button.pressed.connect(toggle)
	add_child(open_button)

	_build_panel()
	panel_root.visible = false


func _exit_tree() -> void:
	Global.settings_overlay_open = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE:
		# Esc closes an open guess field first (MultiplayerBoard handles it).
		var board = Global.run.current_round.current_board
		if not panel_root.visible and is_instance_valid(board) and board.get("guess_open"):
			return
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	panel_root.visible = not panel_root.visible
	Global.settings_overlay_open = panel_root.visible
	if panel_root.visible:
		# Otherwise Enter would still submit a guess or chat line behind it.
		get_viewport().gui_release_focus()
	else:
		_reset_leave_confirm()
	SoundManagerScript.play_random_click("SFX")


func _build_panel() -> void:
	panel_root = ColorRect.new()
	panel_root.color = Color(0, 0, 0, 0.55)
	panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_root.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks cards/chat underneath
	add_child(panel_root)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_root.add_child(center)

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.067, 0.071, 0.086, 0.9)
	style.border_color = Color(0.247, 0.259, 0.286, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column = VBoxContainer.new()
	column.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	column.add_child(_heading("Settings", 28))

	column.add_child(_volume_slider("Master Volume", SoundManagerScript.master_volume, _on_master_volume_changed))
	column.add_child(_volume_slider("SFX Volume", SoundManagerScript.sfx_volume, _on_sfx_volume_changed))
	column.add_child(_volume_slider("Music Volume", SoundManagerScript.music_volume, _on_music_volume_changed))

	column.add_child(HSeparator.new())
	column.add_child(_heading("Game options", 18))

	var auto_scroll = _checkbox("Scroll to revealed chunks")
	auto_scroll.set_pressed_no_signal(Global.auto_scroll_to_reveal)
	auto_scroll.toggled.connect(_on_auto_scroll_toggled)
	column.add_child(auto_scroll)

	var size_row = HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	var size_caption = Label.new()
	size_caption.text = "Article text size"
	size_caption.add_theme_font_size_override("font_size", 14)
	size_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_caption)
	size_row.add_child(_small_button("-", _on_text_size_step.bind(-1)))
	text_size_label = Label.new()
	text_size_label.custom_minimum_size = Vector2(32, 0)
	text_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_size_label.add_theme_font_size_override("font_size", 14)
	size_row.add_child(text_size_label)
	size_row.add_child(_small_button("+", _on_text_size_step.bind(1)))
	column.add_child(size_row)
	_update_text_size_label()

	column.add_child(HSeparator.new())
	# Leaving forfeits, so it takes a second click to confirm.
	leave_button = Button.new()
	leave_button.text = _leave_text()
	leave_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_button.custom_minimum_size = Vector2(140, 0)
	leave_button.pressed.connect(_on_leave_pressed)
	column.add_child(leave_button)
	leave_warning = Label.new()
	if Global.is_multiplayer_match:
		leave_warning.text = "%s will win the match. Click again to leave." % Global.multiplayer_opponent_name
	else:
		leave_warning.text = "Your run will end here. Click again to quit."
	leave_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leave_warning.add_theme_font_size_override("font_size", 14)
	leave_warning.add_theme_color_override("font_color", LEAVE_WARNING_COLOR)
	leave_warning.visible = false
	column.add_child(leave_warning)

	var close_button = Button.new()
	close_button.text = "Close"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.custom_minimum_size = Vector2(140, 0)
	close_button.pressed.connect(toggle)
	column.add_child(close_button)


func _heading(text: String, font_size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


# The default empty-box icon is dark and disappears on this panel, so
# unchecked boxes get a light outlined square instead.
func _checkbox(text: String) -> CheckBox:
	var check = CheckBox.new()
	check.text = text
	check.add_theme_font_size_override("font_size", 14)
	check.add_theme_icon_override("unchecked", _unchecked_icon())
	return check


func _unchecked_icon() -> Texture2D:
	var icon_size = 16
	var image = Image.create(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	var outline = Color(0.8, 0.8, 0.85)
	for i in icon_size:
		for edge in [0, 1, icon_size - 2, icon_size - 1]:
			image.set_pixel(i, edge, outline)
			image.set_pixel(edge, i, outline)
	return ImageTexture.create_from_image(image)


func _small_button(text: String, on_pressed: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(32, 0)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	return button


func _volume_slider(caption: String, value: float, on_changed: Callable) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label = Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 14)
	box.add_child(label)
	var slider = HSlider.new()
	slider.max_value = 100
	slider.set_value_no_signal(value * 100)
	slider.value_changed.connect(on_changed)
	box.add_child(slider)
	return box


func _save() -> void:
	ResourceSaver.save(settings, SETTINGS_PATH)


func _on_leave_pressed() -> void:
	SoundManagerScript.play_random_click("SFX")
	if not leave_warning.visible:
		leave_warning.visible = true
		leave_button.text = "Leave anyway"
		return
	# Same as losing on HP: the opponent is told they won (no-op in single
	# player, where it's the end of the run).
	Global.end_multiplayer_match("lost")
	get_tree().change_scene_to_file("res://scenes/EndScreen.tscn")


func _reset_leave_confirm() -> void:
	leave_warning.visible = false
	leave_button.text = _leave_text()


func _leave_text() -> String:
	return "Leave match" if Global.is_multiplayer_match else "Quit run"


func _on_master_volume_changed(value: float) -> void:
	SoundManagerScript.play_sound_with_pitch("res://assets/sounds/sfx/click/click5.wav", "SFX")
	SoundManagerScript.set_master_volume(value / 100.0)
	settings.master_volume = value / 100.0
	_save()


func _on_sfx_volume_changed(value: float) -> void:
	SoundManagerScript.play_sound_with_pitch("res://assets/sounds/sfx/click/click5.wav", "SFX")
	SoundManagerScript.set_sfx_volume(value / 100.0)
	settings.sfx_volume = value / 100.0
	_save()


func _on_music_volume_changed(value: float) -> void:
	SoundManagerScript.set_music_volume(value / 100.0)
	settings.music_volume = value / 100.0
	_save()


func _on_auto_scroll_toggled(toggled_on: bool) -> void:
	Global.auto_scroll_to_reveal = toggled_on
	settings.auto_scroll_to_reveal = toggled_on
	_save()
	Global.match_display_settings_changed.emit()
	SoundManagerScript.play_random_click("SFX")


func _on_text_size_step(step: int) -> void:
	Global.article_text_size_offset = clampi(Global.article_text_size_offset + step,
		Global.ARTICLE_TEXT_SIZE_OFFSET_MIN, Global.ARTICLE_TEXT_SIZE_OFFSET_MAX)
	settings.article_text_size_offset = Global.article_text_size_offset
	_save()
	_update_text_size_label()
	Global.match_display_settings_changed.emit()
	SoundManagerScript.play_random_click("SFX")


func _update_text_size_label() -> void:
	var offset = Global.article_text_size_offset
	text_size_label.text = ("+%d" % offset) if offset > 0 else str(offset)
