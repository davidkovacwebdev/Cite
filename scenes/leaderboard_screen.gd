extends "res://ui/hub/hub_screen.gd"

# Leaderboards tab of the hub (same top bar and "Redacted paper" theme as the
# hub - see ui/hub/hub_screen.gd). Single Player has Normal (one board per
# playlist) and Hardcore; Multiplayer is the Ranked Duels rating ladder
# (Ratings.gd, board Leaderboards.RATING_NAME). Rows show the
# player's Steam avatar, name and score, top Leaderboards.TOP_ENTRIES plus
# the player's own entry pinned below if they're further down. The right
# column shows the player's own standing and how the board is scored.

const AVATAR_SIZE := 28
const RANK_WIDTH := 44
const NUMBER_WIDTH := 90
const MEDALS := ["MedalGold", "MedalSilver", "MedalBronze"]

var hardcore := false
var ranked_board := false
var sp_filters: HBoxContainer
var playlist_picker: OptionButton
var header_row: HBoxContainer
var rows_box: VBoxContainer
var own_row_box: VBoxContainer
var status_label: Label
var board_title: Label
var you_box: VBoxContainer
var rules_box: VBoxContainer

# steam_id -> name Label, for names that arrive after the rows are built
# (avatars are handled by hub_screen.gd's _avatar).
var identity_widgets := {}
# Bumped on every load, so a slow download for a board the player already
# left doesn't overwrite the one they're looking at.
var load_serial := 0
# Design preview only: when set, used instead of downloading from Steam
# (same shape as Leaderboards.download's result, entries may carry "name").
var preview_result := {}


func _ready() -> void:
	if Global.all_playsets.is_empty():
		Global.load_and_extract_card_data()
	Steam.persona_state_change.connect(_on_persona_state_change)
	var column := _setup_screen("Leaderboards")

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	body.add_child(_build_table())
	body.add_child(_build_side())
	_load_board()


# --- Layout -------------------------------------------------------------------

func _build_table() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TablePanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# Title + Single Player / Multiplayer switch.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_label("LEADERBOARDS", "Eyebrow"))
	board_title = _label("", "HeaderLarge")
	titles.add_child(board_title)
	head.add_child(titles)
	head.add_child(_segmented(["Single Player", "Multiplayer"], 0, func(i):
		ranked_board = i == 1
		_load_board()))
	box.add_child(head)

	# Normal / Hardcore + playlist.
	var filters := HBoxContainer.new()
	sp_filters = filters
	filters.add_theme_constant_override("separation", 10)
	filters.add_child(_segmented(["Normal", "Hardcore"], 0, func(i):
		hardcore = i == 1
		_load_board()))
	playlist_picker = OptionButton.new()
	playlist_picker.focus_mode = Control.FOCUS_NONE
	playlist_picker.custom_minimum_size.x = 240
	playlist_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for playlist in Global.get_official_playlist_ids():
		playlist_picker.add_item(Global.get_playlist_display_name(playlist))
		playlist_picker.set_item_metadata(playlist_picker.item_count - 1, playlist)
	playlist_picker.item_selected.connect(func(_index):
		SoundManagerScript.play_random_click("SFX")
		_load_board())
	filters.add_child(playlist_picker)
	box.add_child(filters)

	box.add_child(HSeparator.new())
	header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	var header_pad := MarginContainer.new()
	header_pad.add_theme_constant_override("margin_left", 13)
	header_pad.add_theme_constant_override("margin_right", 10)
	header_pad.add_child(header_row)
	box.add_child(header_pad)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	status_label = _label("", "MutedLabel")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size.y = 80
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	list.add_child(status_label)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 2)
	list.add_child(rows_box)

	own_row_box = VBoxContainer.new()
	box.add_child(own_row_box)
	return panel


func _build_side() -> Control:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = RIGHT_COLUMN_WIDTH
	right.add_theme_constant_override("separation", 14)

	you_box = _side_panel("Your standing")
	right.add_child(you_box.get_parent())

	rules_box = _side_panel("How it counts")
	rules_box.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(rules_box.get_parent())

	var back := _button("Back to Play", "GhostButton", _on_nav_play)
	back.add_to_group("back_button")
	right.add_child(back)
	return right


# --- Loading ------------------------------------------------------------------

func _board_name() -> String:
	if ranked_board:
		return Leaderboards.RATING_NAME
	if hardcore:
		return Leaderboards.HARDCORE_NAME
	if playlist_picker.selected < 0:
		return ""
	return Leaderboards.normal_board_name(playlist_picker.get_selected_metadata())


func _load_board() -> void:
	load_serial += 1
	var serial := load_serial
	sp_filters.visible = not ranked_board
	playlist_picker.visible = not hardcore
	board_title.text = "Ranked Duels" if ranked_board else ("Hardcore" if hardcore else "Normal")
	_fill_rules()
	_fill_header()
	_clear_rows()
	_fill_you({})

	var board_name := _board_name()
	var result: Dictionary
	if not preview_result.is_empty():
		result = preview_result
	else:
		if board_name.is_empty():
			status_label.text = "No playlists found."
			return
		if not Steam.loggedOn():
			status_label.text = "Leaderboards need Steam running."
			return
		status_label.text = "Loading..."
		result = await Leaderboards.download(board_name)
		if serial != load_serial or not is_inside_tree():
			return
	if not result["ok"]:
		status_label.text = "Couldn't load the leaderboard."
		return
	var entries: Array = result["entries"]
	status_label.text = "No scores yet - be the first." if entries.is_empty() else ""
	status_label.visible = not status_label.text.is_empty()

	var own_id := Steam.getSteamID()
	var own_entry: Dictionary = result["own"]
	var own_listed := false
	for entry in entries:
		var is_own := int(entry.get("steam_id", 0)) == own_id
		if is_own:
			own_listed = true
			own_entry = entry
		rows_box.add_child(_make_row(entry, is_own))
	if not own_listed and not own_entry.is_empty():
		own_row_box.add_child(HSeparator.new())
		own_row_box.add_child(_make_row(own_entry, true))
	_fill_you(own_entry)


func _clear_rows() -> void:
	status_label.visible = true
	identity_widgets.clear()
	for child in rows_box.get_children() + own_row_box.get_children():
		child.queue_free()


func _fill_header() -> void:
	for child in header_row.get_children():
		child.queue_free()
	header_row.add_child(_cell("#", RANK_WIDTH, "ColumnHeader"))
	header_row.add_child(_cell("PLAYER", 0, "ColumnHeader", true))
	if ranked_board:
		header_row.add_child(_cell("W - L", NUMBER_WIDTH, "ColumnHeader", false, HORIZONTAL_ALIGNMENT_RIGHT))
		header_row.add_child(_cell("RATING", NUMBER_WIDTH, "ColumnHeader", false, HORIZONTAL_ALIGNMENT_RIGHT))
		return
	header_row.add_child(_cell("ARTICLES", NUMBER_WIDTH, "ColumnHeader", false, HORIZONTAL_ALIGNMENT_RIGHT))
	if hardcore:
		header_row.add_child(_cell("POINTS", NUMBER_WIDTH, "ColumnHeader", false, HORIZONTAL_ALIGNMENT_RIGHT))


func _fill_you(entry: Dictionary) -> void:
	for child in you_box.get_children().slice(2):
		child.queue_free()
	if ranked_board:
		_fill_you_rating(entry)
		return
	if entry.is_empty():
		var none := _label("No run on this board yet. Finish a run to get on it.", "MutedLabel")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		you_box.add_child(none)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_label("#%d" % int(entry.get("global_rank", 0)), "BigNumber"))
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 0)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	var score := int(entry.get("score", 0))
	stats.add_child(_label("%d articles" % _articles(entry), "StrongLabel"))
	if hardcore:
		stats.add_child(_label("%d points" % score, "MutedLabel"))
	row.add_child(stats)
	you_box.add_child(row)


# The local copy (Ratings) is shown even before the first upload lands.
func _fill_you_rating(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	if not entry.is_empty():
		row.add_child(_label("#%d" % int(entry.get("global_rank", 0)), "BigNumber"))
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 0)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_child(_label("Rating %s" % _thousands(Ratings.rating), "StrongLabel"))
	stats.add_child(_label(Ratings.status_text(), "MutedLabel"))
	row.add_child(stats)
	you_box.add_child(row)
	if Ratings.games() == 0:
		var none := _label("No ranked matches yet. Play Find Match on the Play tab to get on the ladder.", "MutedLabel")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		you_box.add_child(none)


func _fill_rules() -> void:
	for child in rules_box.get_children().slice(2):
		child.queue_free()
	if ranked_board:
		for line in ["Everyone starts at %d." % Ratings.START_RATING,
				"Only Ranked matches (Find Match) count - Quick Play and rooms don't.",
				"Beating a higher-rated player gains more, losing to a lower-rated one costs more.",
				"Your first %d matches move your rating faster while it settles." % Ratings.PLACEMENT_MATCHES,
				"Leaving or disconnecting counts as a loss."]:
			var l := _label(line, "MutedLabel")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rules_box.add_child(l)
		return
	if hardcore:
		var intro := _label("Points per correct guess, by how many people read the article on Wikipedia (daily views, last 30 days).", "MutedLabel")
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules_box.add_child(intro)
		rules_box.add_child(_spacer(false, 0))
		for tier in Leaderboards.HARDCORE_TIERS:
			var row := HBoxContainer.new()
			row.custom_minimum_size.y = 28
			var name_label := _label(tier["label"], "BodyLabel")
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			var pts: int = tier["points"]
			row.add_child(_label("+%d pt%s" % [pts, "" if pts == 1 else "s"], "AccentSmall"))
			rules_box.add_child(row)
	else:
		for line in ["Score = articles guessed correctly in one run.",
				"A run counts for a playlist when you start Normal with that playlist picked.",
				"Only your best run is kept."]:
			var l := _label(line, "MutedLabel")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rules_box.add_child(l)


# Hardcore's score is points; the guess count rides along in details.
func _articles(entry: Dictionary) -> int:
	var details = entry.get("details", [])
	if hardcore and details.size() > 0:
		return int(details[0])
	return int(entry.get("score", 0))


func _make_row(entry: Dictionary, is_own: bool) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "OwnRow" if is_own else "TableRow"
	panel.custom_minimum_size.y = 40
	if not is_own:
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.mouse_entered.connect(func(): panel.theme_type_variation = "TableRowHover")
		panel.mouse_exited.connect(func(): panel.theme_type_variation = "TableRow")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var steam_id := int(entry.get("steam_id", 0))
	var rank := int(entry.get("global_rank", 0))
	row.add_child(_rank_cell(rank, is_own))

	var fallback_name: String = entry.get("name", "?")
	row.add_child(_avatar(fallback_name, AVATAR_SIZE, steam_id if preview_result.is_empty() else 0))

	var name_label := _cell(fallback_name, 0, "AccentSmall" if is_own else "NameLabel", true)
	if is_own:
		name_label.add_theme_font_size_override("font_size", 14)
	row.add_child(name_label)
	if ranked_board:
		var details = entry.get("details", [])
		var record := "%d - %d" % [int(details[0]) if details.size() > 0 else 0, int(details[1]) if details.size() > 1 else 0]
		row.add_child(_cell(record, NUMBER_WIDTH, "TableNumber", false, HORIZONTAL_ALIGNMENT_RIGHT))
		row.add_child(_cell(_thousands(int(entry.get("score", 0))), NUMBER_WIDTH, "TableNumber", false, HORIZONTAL_ALIGNMENT_RIGHT))
	else:
		row.add_child(_cell("%d" % _articles(entry), NUMBER_WIDTH, "TableNumber", false, HORIZONTAL_ALIGNMENT_RIGHT))
	if hardcore and not ranked_board:
		row.add_child(_cell("%d" % int(entry.get("score", 0)), NUMBER_WIDTH, "TableNumber", false, HORIZONTAL_ALIGNMENT_RIGHT))

	if preview_result.is_empty():
		identity_widgets[steam_id] = name_label
		# false = Steam already has their name and avatar, no callback coming.
		Steam.requestUserInformation(steam_id, false)
		_refresh_identity(steam_id)
	return panel


# Top three get a gold/silver/bronze chip, everyone else a plain number.
func _rank_cell(rank: int, is_own: bool) -> Control:
	var holder := HBoxContainer.new()
	holder.custom_minimum_size.x = RANK_WIDTH
	if rank >= 1 and rank <= MEDALS.size():
		var medal := PanelContainer.new()
		medal.theme_type_variation = MEDALS[rank - 1]
		medal.custom_minimum_size = Vector2(24, 24)
		medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var l := _label(str(rank), "MedalLabel")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		medal.add_child(l)
		holder.add_child(medal)
	else:
		var l := _cell(str(rank), RANK_WIDTH, "AccentSmall" if is_own else "SmallMuted")
		l.add_theme_font_size_override("font_size", 14)
		holder.add_child(l)
	return holder


func _cell(text: String, width: int, variation: String, expand := false, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := _label(text, variation)
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


# --- Steam names / avatars ----------------------------------------------------------

func _refresh_identity(steam_id: int) -> void:
	if not identity_widgets.has(steam_id):
		return
	var persona_name := Steam.getFriendPersonaName(steam_id)
	identity_widgets[steam_id].text = persona_name if not persona_name.is_empty() else "..."
	_refresh_avatar(steam_id)


func _on_persona_state_change(steam_id: int, _flags: int) -> void:
	_refresh_identity(steam_id)
