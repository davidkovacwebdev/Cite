extends Control

var points:int
var number_of_rounds:int
var number_of_played_cards:int
var number_of_total_cards:int
var number_of_wrong_guesses:int
var number_of_combos: int
var min_blink_time: int
var max_blink_time: int


var quote:String
var quote_author:String


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_random_menu_quote()
	if Global.uses_modern_ui():
		_apply_paper_style()

	if Global.is_multiplayer_match:
		if Global.multiplayer_match_outcome == "won":
			%Title.text = "You Won!"
		else:
			%Title.text = "You Lost!"
		if Global.uses_modern_ui():
			_build_match_summary()

	%Quote.text = "\"" + quote + "\"\n-" + quote_author
	number_of_rounds = Global.run.round_number
	min_blink_time = number_of_rounds * 15
	max_blink_time = number_of_rounds * 20
	var blink_time = randi_range(min_blink_time, max_blink_time)
	
	number_of_played_cards = Global.run.number_of_played_cards
	number_of_total_cards = Global.run.number_of_total_cards
	number_of_wrong_guesses = Global.run.number_of_wrong_guesses
	number_of_combos = Global.run.number_of_combos
	#points =  calculate_points()
	if not %Button.pressed.is_connected(_on_button_pressed):
		%Button.connect("pressed", _on_button_pressed)
	
	SoundManagerScript.stop_music()
	
	#%Points.text = "Total Points: " + str(calculate_points()) + " in " + str(number_of_rounds) + " rounds"
	%CardStats.text = "You played " + str(number_of_played_cards)+ " out of "+ str(number_of_total_cards) +" cards"
	%ComboNumber.text = "You had " + str(number_of_combos) + " Tripple x Combos"
	%WrongGuesses.text = "You had " + str(number_of_wrong_guesses) + " wrong guesses"
	$%BlinkTime.text = "You blinked " + str(blink_time) + " times, you should check that"
	%LastArticle.text = "Your demise was sealed when you failed miserably at guessing the "+ Global.run.current_round.article_title +" article"
	# Before the playlist selection is cleared - it picks the leaderboard.
	Leaderboards.submit_run()
	if Global.is_multiplayer_match:
		PlayerStats.record_match()
	elif not Global.legacy_mode:
		PlayerStats.record_run()
	Global.selected_categories = []
	Global.selected_playsets = []
	Global.run.wikipedia_ids = []

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


# Single player (Normal/Hardcore) and multiplayer: the hub's paper look.
# Legacy runs keep the original gradient screen.
func _apply_paper_style() -> void:
	var style := preload("res://ui/match/match_style.gd")
	theme = style.HUB_THEME
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	$TextureRect.visible = false
	var bg := ColorRect.new()
	bg.color = style.color("bg")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	%Title.add_theme_font_override("normal_font", preload("res://ui/fonts/fraunces_600.tres"))
	%Title.add_theme_font_size_override("normal_font_size", 44)
	%Quote.add_theme_font_override("normal_font", preload("res://ui/fonts/plex_400.tres"))
	%Quote.add_theme_font_size_override("normal_font_size", 18)
	%Quote.add_theme_color_override("default_color", style.color("muted"))
	for label in [%Points, %CardStats, %ComboNumber, %WrongGuesses, %BlinkTime, %LastArticle]:
		label.add_theme_font_override("normal_font", preload("res://ui/fonts/plex_500.tres"))
		label.add_theme_font_size_override("normal_font_size", 18)
		label.add_theme_color_override("default_color", style.color("text"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The stats sit in a plain Container, which doesn't size its children -
	# wrapping labels need a width or they collapse into a 1-letter column.
	$Container/VBoxContainer.custom_minimum_size.x = $Container.offset_right - $Container.offset_left
	%Button.theme_type_variation = "CtaButton"
	%Button.text = "Back to Play"
	%Button.add_theme_font_size_override("font_size", 18)
	%Button.offset_left = -110
	%Button.offset_right = 110
	%Button.offset_top = -84
	%Button.offset_bottom = -36


# --- Multiplayer summary ------------------------------------------------------
# Replaces the single player stats: the rating change (Ranked) and every
# article of the match - who guessed it and the damage it dealt.

const SUMMARY_WIDTH := 680
const OUTCOME_WIDTH := 170
const DAMAGE_WIDTH := 130


func _build_match_summary() -> void:
	var style := preload("res://ui/match/match_style.gd")
	$Container.visible = false
	$CenterContainer.visible = false

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 100)  # above the Back button
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = SUMMARY_WIDTH
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var won := Global.multiplayer_match_outcome == "won"
	var title := _summary_label("You won" if won else "You lost", "HeaderLarge")
	title.add_theme_color_override("font_color", style.color("added") if won else style.color("accent"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var opponent := Global.multiplayer_opponent_name if not Global.multiplayer_opponent_name.is_empty() else "your opponent"
	var versus := _summary_label("vs " + opponent, "MutedLabel")
	versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(versus)
	column.add_child(_rating_line(style))

	var panel := PanelContainer.new()
	panel.theme_type_variation = "TablePanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_summary_row(["#", "ARTICLE", "RESULT", "DAMAGE"], "ColumnHeader"))
	box.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	scroll.add_child(rows)

	var articles: Array = Global.run.mp_log.duplicate()
	# The match can end mid-article (wrong guesses, or someone leaving).
	var current: String = Global.run.current_round.article_title
	if not current.is_empty() and (articles.is_empty() or articles[-1]["title"] != current):
		articles.append({"title": current, "result": "unfinished", "damage": 0, "round": Global.run.round_number})
	if articles.is_empty():
		rows.add_child(_summary_label("No articles were finished.", "MutedLabel"))
	for i in articles.size():
		rows.add_child(_article_row(i + 1, articles[i], style))


func _rating_line(style) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var result: Dictionary = Ratings.last_result
	if not Global.multiplayer_ranked or result.is_empty():
		row.add_child(_summary_label("Unranked match - rating unchanged", "SmallMuted"))
		return row
	row.add_child(_summary_label("Rating %d" % int(result["new"]), "StrongLabel"))
	var delta := int(result["delta"])
	var change := _summary_label("%+d" % delta, "StrongLabel")
	change.add_theme_color_override("font_color", style.color("added") if delta >= 0 else style.color("accent"))
	row.add_child(change)
	if result.get("practice", false):
		row.add_child(_summary_label("Practice vs bot - not saved", "SmallMuted"))
	elif Ratings.is_provisional():
		row.add_child(_summary_label("Provisional · %d/%d placement matches" % [Ratings.games(), Ratings.PLACEMENT_MATCHES], "SmallMuted"))
	return row


func _article_row(number: int, entry: Dictionary, style) -> Control:
	var damage := int(entry.get("damage", 0))
	var outcome := ""
	var damage_text := ""
	var color: Color = style.color("muted")
	match entry.get("result", ""):
		"you":
			outcome = "You guessed it"
			damage_text = "-%d to them" % damage
			color = style.color("added")
		"opponent":
			outcome = "They guessed it"
			damage_text = "-%d to you" % damage
			color = style.color("accent")
		"skipped":
			outcome = "Both skipped"
			damage_text = "-%d each" % damage
		"timeout":
			outcome = "Nobody got it"
			damage_text = "-%d each" % damage
		_:
			outcome = "Match ended"
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TableRow"
	panel.custom_minimum_size.y = 36
	var row := _summary_row([str(number), String(entry.get("title", "?")), outcome, damage_text], "TableNumber")
	var outcome_label: Label = row.get_child(2)
	outcome_label.add_theme_color_override("font_color", color)
	panel.add_child(row)
	# Hover: both players' guesses on this article.
	if entry.has("round"):
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.mouse_entered.connect(func():
			panel.theme_type_variation = "TableRowHover"
			_show_guesses_popup(panel, entry))
		panel.mouse_exited.connect(func():
			panel.theme_type_variation = "TableRow"
			_hide_guesses_popup())
		panel.tree_exiting.connect(_hide_guesses_popup)
	return panel


# --- Per-article guesses popup ----------------------------------------------

const GUESSES_POPUP_WIDTH := 210  # fits in the margin beside the 680px table at 1152 wide
const MAX_GUESSES_SHOWN := 5
var guesses_popup: CanvasLayer


func _show_guesses_popup(row: Control, entry: Dictionary) -> void:
	_hide_guesses_popup()
	var style := preload("res://ui/match/match_style.gd")
	var guesses: Array = Global.run.guesses_for_round(int(entry["round"]))
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	guesses_popup = layer
	var panel := PanelContainer.new()
	panel.theme = style.HUB_THEME
	panel.theme_type_variation = "DropdownPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size.x = GUESSES_POPUP_WIDTH
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := _summary_label(String(entry.get("title", "?")), "NameLabel")
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 10
	box.add_child(title)
	var opponent := Global.multiplayer_opponent_name if not Global.multiplayer_opponent_name.is_empty() else "Opponent"
	box.add_child(_guess_column("You", guesses.filter(func(g): return g["who"] == "you"), style, false))
	box.add_child(_guess_column(opponent, guesses.filter(func(g): return g["who"] == "opponent"), style,
		Global.is_player_muted(Global.multiplayer_opponent_id)))
	for c in [box] + box.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Beside the summary table, level with the row, kept on screen - placed
	# once it has laid out, so its real height is known.
	panel.visible = false
	await get_tree().process_frame
	if not is_instance_valid(panel) or not is_instance_valid(row):
		return
	panel.reset_size()
	panel.visible = true
	var r := row.get_global_rect()
	var screen := get_viewport_rect().size
	var pos := Vector2(r.end.x + 12, r.get_center().y - panel.size.y / 2.0)
	if pos.x + panel.size.x > screen.x - 8:
		pos.x = r.position.x - panel.size.x - 12
	pos.x = clampf(pos.x, 8, maxf(8.0, screen.x - panel.size.x - 8))
	pos.y = clampf(pos.y, 8, maxf(8.0, screen.y - panel.size.y - 8))
	panel.position = pos


# "You" / opponent name, then each guess in order: wrong ones muted and
# struck through, the correct one green. Muted players' texts stay hidden.
func _guess_column(who: String, guesses: Array, style, hide_text: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var name_label := _summary_label(who.to_upper(), "Eyebrow")
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	if guesses.is_empty():
		column.add_child(_summary_label("No guesses", "SmallMuted"))
		return column
	var shown := guesses.slice(-MAX_GUESSES_SHOWN) if guesses.size() > MAX_GUESSES_SHOWN else guesses
	if shown.size() < guesses.size():
		column.add_child(_summary_label("... %d earlier" % (guesses.size() - shown.size()), "SmallMuted"))
	for g in shown:
		var text := String(g["text"])
		var correct: bool = g["correct"]
		var label := _summary_label("", "SmallLabel")
		label.custom_minimum_size.x = 10
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if correct and text.is_empty():
			label.text = "✓ Completed with Letter Reveal"
		elif text.is_empty():
			label.text = "× (wrong guess)"
		elif hide_text:
			label.text = ("✓ " if correct else "× ") + "(hidden - muted)"
		else:
			label.text = ("✓ " if correct else "× ") + text
		label.add_theme_color_override("font_color", style.color("added") if correct else style.color("muted"))
		column.add_child(label)
	return column


func _hide_guesses_popup() -> void:
	if is_instance_valid(guesses_popup):
		guesses_popup.queue_free()
	guesses_popup = null


func _summary_row(cells: Array, variation: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var widths := [36, 0, OUTCOME_WIDTH, DAMAGE_WIDTH]
	for i in cells.size():
		var label := _summary_label(cells[i], variation)
		label.custom_minimum_size.x = widths[i]
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if i == 1:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 3:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
	return row


func _summary_label(text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


#func calculate_points() -> int:
	## Base points
	#var round_points = number_of_rounds * 100
	#for i in range(1, number_of_rounds + 1):
		#round_points += (i * 150)
	#var combo_points = number_of_combos * 1000
	#var wrong_guess_penalty = number_of_wrong_guesses * 10
	#
	## Efficiency multiplier (avoid division by zero)
	#if number_of_played_cards == 0:
		#number_of_played_cards = 1
	#
	#var efficiency_multiplier = 1.0 + (float(number_of_total_cards - number_of_played_cards) / number_of_total_cards)
	#
	## Calculate total
	#var base_score = round_points + combo_points - wrong_guess_penalty
	#points = int(base_score * efficiency_multiplier)
	#
	#return max(points, 0)
	
	
func _on_button_pressed():
	# Legacy runs go back to the old menu they were started from.
	var legacy: bool = Global.legacy_mode and not Global.is_multiplayer_match
	Global.open_legacy_menu = legacy
	get_tree().change_scene_to_file("res://Main/Main.tscn" if legacy else Global.MENU_SCENE)
	
func get_random_menu_quote():
	var file_path = "res://assets/data/end_quotes.json"
	if FileAccess.file_exists(file_path):
		var content = FileAccess.get_file_as_string(file_path)
		var json_data = JSON.parse_string(content)
		
		if json_data is Array and json_data.size() > 0:
			var entry = json_data.pick_random() # Pick the whole object once
			quote = entry.get("text", "")
			quote_author = entry.get("author", "Unknown")
