extends "res://ui/hub/hub_screen.gd"

# Profile tab of the hub. Left: who you are (avatar, name, rating, streaks),
# recent multiplayer matches and your article collection (per-playlist
# progress + a searchable grid). Right: rating over time, bests from the Steam
# leaderboards, lifetime stats, Daily Challenge streak + calendar, and your
# Workshop playlists. Data: Ratings (rating), PlayerStats (everything kept
# locally), Leaderboards (bests), DailyState's save (via PlayerStats).

const RatingChart := preload("res://ui/hub/rating_chart.gd")
const DailyState := preload("res://ui/daily/daily_state.gd")

const AVATAR_SIZE := 64
const MAX_CHIPS := 80
const CALENDAR_DAYS := 28
const CALENDAR_CELL := 18

var chips_box: HFlowContainer
var chips_note: Label
var bests_box: VBoxContainer
var rating_number: Label
var rating_status: Label


func _ready() -> void:
	if Global.all_playsets.is_empty():
		Global.load_and_extract_card_data()
	var column := _setup_screen("Profile")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	scroll.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 16)
	body.add_child(left)
	left.add_child(_build_header())
	left.add_child(_build_matches())
	left.add_child(_build_collection())

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = RIGHT_COLUMN_WIDTH
	right.add_theme_constant_override("separation", 14)
	body.add_child(right)
	right.add_child(_build_rating_panel())
	right.add_child(_build_bests())
	right.add_child(_build_lifetime())
	right.add_child(_build_daily())
	right.add_child(_build_playlists())
	var back := _button("Back to Play", "GhostButton", _on_nav_play)
	right.add_child(back)

	Ratings.changed.connect(_refresh_rating)
	_refresh_rating()
	_load_bests()


# --- Header -------------------------------------------------------------------

func _build_header() -> Control:
	var panel := _panel("TablePanel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var own_name := Global.get_own_name()
	var avatar := _avatar(own_name, AVATAR_SIZE, Steam.getSteamID() if Steam.loggedOn() else 0)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)

	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 2)
	who.add_child(_label("PROFILE", "Eyebrow"))
	var name_label := _label(own_name, "HeaderLarge")
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(name_label)
	row.add_child(who)

	var rating := _stat_tile("", "Rating", "")
	rating_number = rating[1]
	rating_status = rating[2]
	row.add_child(rating[0])
	var streak := int(PlayerStats.totals["streak"])
	row.add_child(_stat_tile(str(streak), "Win streak", "Best %d · Ranked" % int(PlayerStats.totals["best_streak"]))[0])
	var daily: Array = PlayerStats.daily_streaks()
	row.add_child(_stat_tile(str(daily[0]), "Daily streak", "Best %d days" % daily[1])[0])
	return panel


# [tile, number label, note label]
func _stat_tile(number: String, caption: String, note: String) -> Array:
	var tile := VBoxContainer.new()
	tile.custom_minimum_size.x = 120
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 0)
	var n := _label(number, "BigNumber")
	tile.add_child(n)
	tile.add_child(_label(caption, "StrongLabel"))
	var note_label := _label(note, "SmallMuted")
	tile.add_child(note_label)
	return [tile, n, note_label]


func _refresh_rating() -> void:
	rating_number.text = _thousands(Ratings.rating)
	rating_status.text = "Provisional %d/%d" % [Ratings.games(), Ratings.PLACEMENT_MATCHES] \
		if Ratings.is_provisional() else "%d W · %d L" % [Ratings.wins, Ratings.losses]


# --- Collection ---------------------------------------------------------------

func _build_collection() -> Control:
	var panel := _panel("TablePanel")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("COLLECTION", "Eyebrow"))
	var count := PlayerStats.collection.size()
	box.add_child(_label("%s article%s guessed" % [_thousands(count), "" if count == 1 else "s"], "HeaderMedium"))
	var intro := _label("Every article you've guessed right, in any mode. Starred ones unlock a Steam achievement.", "MutedLabel")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	# Progress per official playlist.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	for playlist in Global.get_official_playlist_ids():
		var progress: Array = PlayerStats.playlist_progress(playlist)
		var name_label := _label(Global.get_playlist_display_name(playlist), "BodyLabel")
		name_label.custom_minimum_size.x = 150
		grid.add_child(name_label)
		var bar := ProgressBar.new()
		bar.theme_type_variation = "HubProgress"
		bar.show_percentage = false
		bar.max_value = maxi(int(progress[1]), 1)
		bar.value = int(progress[0])
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		var numbers := _label("%d / %d" % progress, "SmallMuted")
		numbers.custom_minimum_size.x = 80
		numbers.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(numbers)
	box.add_child(grid)

	var search := LineEdit.new()
	search.placeholder_text = "Search your collection"
	search.clear_button_enabled = true
	search.text_changed.connect(_fill_chips)
	box.add_child(search)
	chips_box = HFlowContainer.new()
	chips_box.add_theme_constant_override("h_separation", 6)
	chips_box.add_theme_constant_override("v_separation", 6)
	box.add_child(chips_box)
	chips_note = _label("", "SmallMuted")
	box.add_child(chips_note)
	_fill_chips("")
	return panel


func _fill_chips(query: String) -> void:
	for child in chips_box.get_children():
		child.queue_free()
	query = Global.strip_accents(query.strip_edges().to_lower())
	# Newest first.
	var keys := PlayerStats.collection.keys()
	keys.sort_custom(func(a, b): return int(PlayerStats.collection[a]["d"]) > int(PlayerStats.collection[b]["d"]))
	var shown := 0
	var matching := 0
	for key in keys:
		var entry: Dictionary = PlayerStats.collection[key]
		var title := String(entry["t"])
		if not query.is_empty() and not Global.strip_accents(title.to_lower()).contains(query):
			continue
		matching += 1
		if shown >= MAX_CHIPS:
			continue
		shown += 1
		chips_box.add_child(_chip(int(key), title, int(entry["n"])))
	if PlayerStats.collection.is_empty():
		chips_note.text = "Nothing yet - guess an article in any mode to start your collection."
	elif matching == 0:
		chips_note.text = "No guessed article matches that."
	elif matching > shown:
		chips_note.text = "Showing %d of %d - search to find the rest." % [shown, matching]
	else:
		chips_note.text = ""


func _chip(page_id: int, title: String, times: int) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = get_theme_color("surface", "Hub")
	sb.border_color = Color(get_theme_color("muted", "Hub"), 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	var label := _label(("★ " if PlayerStats.is_achievement_article(page_id) else "") + title, "BodyLabel")
	chip.add_child(label)
	chip.tooltip_text = "%s\nGuessed %d time%s" % [title, times, "" if times == 1 else "s"]
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	return chip


# --- Recent matches -----------------------------------------------------------

func _build_matches() -> Control:
	var panel := _panel("TablePanel")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_label("MULTIPLAYER", "Eyebrow"))
	box.add_child(_label("Recent matches", "HeaderMedium"))
	if PlayerStats.matches.is_empty():
		box.add_child(_label("No matches yet. Find Match on the Play tab starts one.", "MutedLabel"))
		return panel
	for m in PlayerStats.matches:
		box.add_child(_match_row(m))
	return panel


func _match_row(m: Dictionary) -> Control:
	var won: bool = m.get("outcome", "") == "won"
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TableRow"
	panel.custom_minimum_size.y = 38
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var result := _label("WIN" if won else "LOSS", "StrongLabel")
	result.custom_minimum_size.x = 44
	result.add_theme_color_override("font_color", get_theme_color("added" if won else "accent", "Hub"))
	row.add_child(result)
	var opponent := String(m.get("opponent", ""))
	var who := _label("vs " + (opponent if not opponent.is_empty() else "?"), "NameLabel")
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(who)
	row.add_child(_fixed(_label("%d - %d articles" % [int(m.get("mine", 0)), int(m.get("theirs", 0))], "SmallMuted"), 100))
	var kind: String
	if m.get("ranked", false):
		kind = "Ranked %+d → %s" % [int(m.get("delta", 0)), _thousands(int(m.get("rating", 0)))]
	else:
		kind = "Unranked"
	row.add_child(_fixed(_label(kind, "SmallMuted"), 130))
	var when := _fixed(_label(_ago(int(m.get("time", 0))), "SmallMuted"), 70)
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(when)
	return panel


# --- Right column -------------------------------------------------------------

func _build_rating_panel() -> Control:
	var box := _side_panel("Rating", "Ranked Duels")
	var chart := RatingChart.new()
	chart.custom_minimum_size.y = 110
	chart.points = PlayerStats.rating_history
	box.add_child(chart)
	return box.get_parent()


func _build_bests() -> Control:
	bests_box = _side_panel("Bests", "Steam leaderboards")
	return bests_box.get_parent()


# Hardcore, every official playlist's Normal board, and today's Daily - one
# Steam request each, so rows appear as they load.
func _load_bests() -> void:
	if not Steam.loggedOn():
		bests_box.add_child(_wrapped("Bests need Steam running.", "MutedLabel"))
		return
	var loading := _label("Loading...", "MutedLabel")
	bests_box.add_child(loading)
	var boards := [[Leaderboards.HARDCORE_NAME, "Hardcore", true]]
	for playlist in Global.get_official_playlist_ids():
		boards.append([Leaderboards.normal_board_name(playlist), Global.get_playlist_display_name(playlist), false])
	var any := false
	for board in boards:
		var result: Dictionary = await Leaderboards.own_entry(board[0])
		if not is_inside_tree():
			return
		var entry: Dictionary = result["entry"]
		if entry.is_empty():
			continue
		any = true
		var details = entry.get("details", [])
		var score := int(entry.get("score", 0))
		var text := "%d pts · %d articles" % [score, int(details[0]) if details.size() > 0 else 0] if board[2] else "%d articles" % score
		bests_box.add_child(_kv(board[1], "%s  #%s" % [text, _thousands(int(entry.get("global_rank", 0)))]))
	loading.queue_free()
	if not any:
		bests_box.add_child(_wrapped("No runs on the leaderboards yet. Finish a Normal or Hardcore run to get on them.", "MutedLabel"))


func _build_lifetime() -> Control:
	var box := _side_panel("Lifetime")
	var t: Dictionary = PlayerStats.totals
	box.add_child(_kv("Matches", "%d  (%d W · %d L)" % [int(t["matches"]), int(t["wins"]), int(t["losses"])]))
	box.add_child(_kv("Single player runs", str(int(t["runs"]))))
	box.add_child(_kv("Articles guessed", _thousands(int(t["correct"]))))
	var attempts := int(t["correct"]) + int(t["wrong"])
	box.add_child(_kv("Guess accuracy", "%d%%" % roundi(PlayerStats.accuracy() * 100.0) if attempts > 0 else "-"))
	box.add_child(_kv("Damage dealt", _thousands(int(t["damage"]))))
	if not PlayerStats.fastest.is_empty():
		_add_record(box, "Fastest guess", PlayerStats.fastest["t"], "%d%% of the article shown" % roundi(float(PlayerStats.fastest["pct"]) * 100.0))
	if not PlayerStats.rarest.is_empty():
		_add_record(box, "Rarest article", PlayerStats.rarest["t"], "%s views a day on Wikipedia" % _thousands(roundi(float(PlayerStats.rarest["views"]))))
	return box.get_parent()


func _build_daily() -> Control:
	var streaks: Array = PlayerStats.daily_streaks()
	var box := _side_panel("Daily Challenge", "last %d days" % CALENDAR_DAYS)
	box.add_child(_kv("Streak", "%d day%s  (best %d)" % [streaks[0], "" if streaks[0] == 1 else "s", streaks[1]]))
	var days := PlayerStats.daily_days()
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var today := DailyState.today_number()
	for i in range(CALENDAR_DAYS - 1, -1, -1):
		var day := today - i
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(CALENDAR_CELL, CALENDAR_CELL)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		var tip: String
		if days.has(day):
			var solved: int = days[day]
			var color := "added" if solved >= 4 else ("warning" if solved >= 1 else "accent")
			sb.bg_color = get_theme_color(color, "Hub")
			tip = "Daily #%d: %d of %d solved" % [day, solved, DailyState.ARTICLES_PER_DAY]
		else:
			sb.bg_color = Color(get_theme_color("muted", "Hub"), 0.18)
			tip = "Daily #%d: not played" % day if day >= 1 else "Before the Daily started"
		if day == today:
			sb.set_border_width_all(2)
			sb.border_color = get_theme_color("text", "Hub")
		cell.add_theme_stylebox_override("panel", sb)
		cell.tooltip_text = tip
		grid.add_child(cell)
	box.add_child(grid)
	var key := _wrapped("Green 4+ solved · yellow 1-3 · red none · outlined = today", "SmallMuted")
	box.add_child(key)
	return box.get_parent()


# Community playlists (approved, so they're in the browser) uploaded by this
# player. Pending ones only show on the Workshop itself.
func _build_playlists() -> Control:
	var box := _side_panel("Your playlists")
	var own_id := Steam.getSteamID() if Steam.loggedOn() else 0
	var count := 0
	for playlist_id in Workshop.get_playlist_ids():
		var file_id := Workshop.file_id_of(playlist_id)
		if own_id != 0 and Workshop.get_author_id(file_id) == own_id:
			count += 1
			var row := _button(Workshop.get_title(file_id), "TextLink", func(): _open_playlist(file_id))
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			box.add_child(row)
	if count == 0:
		box.add_child(_wrapped("None approved yet. Uploads waiting for approval show on the Workshop.", "MutedLabel"))
	box.add_child(_button("Upload a playlist", "GhostButton", func(): _open_lobby("submit")))
	return box.get_parent()


func _open_playlist(file_id: int) -> void:
	Global.multiplayer_playlist_id = Workshop.playlist_id_of(file_id)  # the Playlists screen opens on it
	get_tree().change_scene_to_file(PLAYLISTS_SCENE)


# --- Helpers ------------------------------------------------------------------

func _panel(variation: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	return panel


func _kv(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := _label(key, "MutedLabel")
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var v := _label(value, "BodyLabel")
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.clip_text = true
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.custom_minimum_size.x = 130
	v.tooltip_text = value
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(v)
	return row


# A record with an article title: too long for one key/value row.
func _add_record(box: VBoxContainer, key: String, title: String, detail: String) -> void:
	box.add_child(_spacer(false, 4))
	box.add_child(_label(key, "MutedLabel"))
	box.add_child(_wrapped(title, "StrongLabel"))
	box.add_child(_label(detail, "SmallMuted"))


func _wrapped(text: String, variation: String) -> Label:
	var label := _label(text, variation)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _fixed(label: Label, width: int) -> Label:
	label.custom_minimum_size.x = width
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


static func _ago(unix: int) -> String:
	var secs := int(Time.get_unix_time_from_system()) - unix
	if secs < 3600:
		return "%dm ago" % maxi(secs / 60, 1)
	if secs < 86400:
		return "%dh ago" % (secs / 3600)
	return "%dd ago" % (secs / 86400)
