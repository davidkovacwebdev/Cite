extends "res://ui/hub/hub_screen.gd"

# The online hub - the new main menu / startup screen (layout from the UI
# playground mockup, "Redacted paper" look in ui/hub/hub_theme.tres). Top bar,
# settings, toasts and widget builders live in hub_screen.gd.
#
# The Ranked rating comes from globals/Ratings.gd. Daily
# card + "Today's Daily" come from ui/daily (Steam daily leaderboard). The friends list is the player's real Steam
# friends. Legacy (the original game, untouched in Main.tscn / Board.tscn) is
# only a small link in the Single Player popup.

const Matchmaker := preload("res://ui/hub/matchmaker.gd")
const HERO_HEIGHT := 226

# Steam friends list: rebuilt at most this often when statuses change.
const FRIENDS_REFRESH_SECONDS := 2.0

const DailyState := preload("res://ui/daily/daily_state.gd")
const DAILY_SCENE := "res://ui/daily/daily.tscn"
const ArticleHighlight := preload("res://ui/hub/article_highlight.gd")
const HIGHLIGHT_IMAGE_HEIGHT := 96

var reset_label: Label
var daily_meta: Label
var daily_button: Button
var daily_rows: VBoxContainer  # friends' scores inside daily_box (refilled when the set updates)
var daily_set_key := ""  # today's Daily set as of the cached schedule
var daily_box: VBoxContainer
var matchmaker: Node
# Matchmaking overlay widgets (built in _start_matchmaking).
var mm_title: Label
var mm_time: Label
var mm_sub: Label
var mm_scan: Control
var mm_scan_fill: Control
var mm_opponent: Control
var mm_started_at := 0.0
var mm_scan_t := 0.0
var code_input: LineEdit
var friends_box: VBoxContainer
var friends_note: Label
var friends_scroll: ScrollContainer
var friends_refresh_timer: Timer
var left_column: VBoxContainer
var sp_first := false
var lists_desc: Label  # Playlists card (counts update when Workshop playlists load)
var lists_spotlight: Label


func _ready() -> void:
	var column := _setup_screen("Play")
	_apply_saved_settings()
	Global.load_and_extract_card_data()

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	left_column = VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 14)
	body.add_child(left_column)
	sp_first = _wants_sp_first()
	_fill_left_column()
	body.add_child(_build_right_column())
	_tick_reset()

	matchmaker = Matchmaker.new()
	add_child(matchmaker)
	matchmaker.state_changed.connect(_on_matchmaking_state)
	matchmaker.failed.connect(func(message: String):
		_close_modal()
		_show_toast(message))
	if not Global.pending_dummy_matchmaking.is_empty():
		var dummy_mode := Global.pending_dummy_matchmaking
		Global.pending_dummy_matchmaking = ""
		_start_matchmaking.call_deferred(dummy_mode, true)


func _process(delta: float) -> void:
	_tick_reset()
	_tick_matchmaking(delta)


# Startup duties the old main menu did: apply saved fullscreen and volumes.
func _apply_saved_settings() -> void:
	if not ResourceLoader.exists(SETTINGS_PATH):
		return
	if settings.fullscreen and get_window().mode != Window.MODE_FULLSCREEN:
		get_window().mode = Window.MODE_FULLSCREEN
	SoundManagerScript.set_master_volume(settings.master_volume)
	SoundManagerScript.set_sfx_volume(settings.sfx_volume)
	SoundManagerScript.set_music_volume(settings.music_volume)


# --- Left column: hero + mode cards -------------------------------------------------

# Single Player on top while few people are online (or unknown, e.g. Steam
# offline), Ranked otherwise; the dev setting overrides it.
func _wants_sp_first() -> bool:
	match Global.hub_layout_override:
		Global.HubLayout.SINGLE_PLAYER:
			return true
		Global.HubLayout.MULTIPLAYER:
			return false
	return Global.last_player_count < Global.HUB_SP_FIRST_BELOW


func _on_player_count(success: int, players: int) -> void:
	super(success, players)
	if success != 1:
		return
	Global.last_player_count = maxi(players, 1)
	if _wants_sp_first() != sp_first:
		sp_first = not sp_first
		_fill_left_column()


func _fill_left_column() -> void:
	for c in left_column.get_children():
		left_column.remove_child(c)
		c.queue_free()
	var left := left_column
	left.add_child(_build_sp_hero() if sp_first else _build_hero())

	var modes := HBoxContainer.new()
	modes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modes.add_theme_constant_override("separation", 14)
	left.add_child(modes)

	# Daily Challenge -> ui/daily.
	var daily := _mode_card("calendar", "Daily Challenge",
		"%d official articles, same for everyone. One attempt per day." % DailyState.ARTICLES_PER_DAY)
	daily_meta = _label("", "SmallLabel")
	daily.add_child(daily_meta)
	reset_label = _label("Resets in --:--:--", "SmallLabel")
	daily.add_child(reset_label)
	daily_button = _button("Play Daily", "CtaButton", func(): get_tree().change_scene_to_file(DAILY_SCENE))
	daily.add_child(daily_button)
	modes.add_child(daily.get_parent())
	_refresh_daily_card()

	# Private Match -> the existing lobby (host form / join by code / browser).
	var private := _mode_card("link", "Private Match", "Play a friend with a room code or invite link.")
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 6)
	code_input = LineEdit.new()
	code_input.placeholder_text = "Code"
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_input.custom_minimum_size.x = 40
	code_input.text_submitted.connect(func(_t): _on_join_code())
	code_row.add_child(code_input)
	code_row.add_child(_button("Join", "SmallButton", _on_join_code))
	private.add_child(code_row)
	private.add_child(_button("Create Room", "", func(): _open_lobby("host")))
	private.add_child(_button("Browse public rooms", "OutlineButton", func(): _open_lobby("browse")))
	modes.add_child(private.get_parent())

	if sp_first:
		# Ranked moves down into the cards, as the first one.
		var duel := _mode_card("users", "Ranked Duels", "1v1, first correct guess deals the damage. All articles are random picks from every official playlist.")
		var duel_find := _button("Find Match", "", func(): _start_matchmaking("Ranked"))
		_attach_hover_notes(duel_find, true)
		duel.add_child(duel_find)
		var duel_quick := _button("Quick Play · unranked", "OutlineButton", func(): _start_matchmaking("Quick Play"))
		_attach_hover_notes(duel_quick, false)
		duel.add_child(duel_quick)
		modes.add_child(duel.get_parent())
		modes.move_child(duel.get_parent(), 0)  # first card, leftmost
	else:
		# Single Player -> the current (non-Legacy) single player.
		var single := _mode_card("user", "Single Player", "Your deck, article after article. How far can you get?")
		var best := _label("", "SmallLabel")
		best.visible = false
		single.add_child(best)
		single.add_child(_button("Start Run", "", _open_single_player))
		modes.add_child(single.get_parent())
		_load_best_run(func(run: Dictionary):
			if run.is_empty():
				return
			best.text = "Best: %d articles · #%s" % [run["score"], _thousands(run["rank"])]
			best.tooltip_text = "%s leaderboard" % Global.get_playlist_display_name(run["playlist"])
			best.mouse_filter = Control.MOUSE_FILTER_PASS
			best.visible = true)

	# Playlists -> the Playlists screen.
	var lists := _mode_card("list", "Playlists", "")
	lists_desc = lists.get_child(2)  # _mode_card's description label
	lists_spotlight = _label("", "SmallLabel")
	lists.add_child(lists_spotlight)
	lists.add_child(_button("Browse", "", _on_nav_playlists))
	modes.add_child(lists.get_parent())
	_refresh_playlists_card()
	if not Workshop.community_playlists_changed.is_connected(_refresh_playlists_card):
		Workshop.community_playlists_changed.connect(_refresh_playlists_card)


func _refresh_playlists_card() -> void:
	if is_instance_valid(lists_desc):
		lists_desc.text = _playlists_blurb()
		lists_spotlight.text = _playlist_spotlight()


# "9 official and 41 community playlists, or build your own." (real counts).
func _playlists_blurb() -> String:
	var official := Global.get_official_playlist_ids().size()
	var community: int = Workshop.community_playlists.size()
	if community == 0:
		return "%d official playlists, or build your own and share it on the Workshop." % official
	return "%d official and %s community playlists, or build your own." % [official, _thousands(community)]


# The newest community playlist, else one official playlist that changes daily.
func _playlist_spotlight() -> String:
	var newest := ""
	var newest_time := -1
	for key in Workshop.community_playlists:
		var info: Dictionary = Workshop.community_playlists[key]
		if int(info.get("time_updated", 0)) > newest_time:
			newest_time = int(info.get("time_updated", 0))
			newest = String(info.get("title", ""))
	if newest != "":
		return "Newest: %s" % newest
	var official := Global.get_official_playlist_ids()
	if official.is_empty():
		return ""
	var pick: String = official[DailyState.today_number() % official.size()]
	return "Today's pick: %s" % Global.get_playlist_display_name(pick)


# Calls on_loaded with Leaderboards.best_normal_run()'s answer, if this hub
# is still open by then.
func _load_best_run(on_loaded: Callable) -> void:
	var run: Dictionary = await Leaderboards.best_normal_run()
	if is_inside_tree():
		on_loaded.call(run)


# Hero frame (panel, corner glow, padding); returns [panel, content row].
func _hero_frame() -> Array:
	var hero := PanelContainer.new()
	hero.theme_type_variation = "HeroPanel"
	hero.custom_minimum_size.y = HERO_HEIGHT

	# Soft accent glow in the top-right corner (behind the content).
	var glow_holder := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		glow_holder.add_theme_constant_override("margin_" + side, 1)
	glow_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, get_theme_color("hero_glow", "Hub"))
	gradient.set_color(1, Color(get_theme_color("hero_glow", "Hub"), 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(1, 0)
	tex.fill_to = Vector2(0.45, 0.75)
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_holder.add_child(glow)
	hero.add_child(glow_holder)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 22)
	hero.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	pad.add_child(row)
	return [hero, row]


# Hero with a stat on the left ([big number, label, sub-label]) and a column
# of buttons on the right.
# Returns the stat's number and note labels, for callers that update them.
func _hero_info(row: HBoxContainer, eyebrow: String, title: String, pitch_text: String, stat: Array) -> Array:
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	info.add_child(_label(eyebrow, "Eyebrow"))
	info.add_child(_label(title, "HeaderLarge"))
	var pitch := _label(pitch_text, "MutedLabel")
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(pitch)
	info.add_child(_spacer(true, 8))
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 14)
	var number := _label(stat[0], "BigNumber")
	stat_row.add_child(number)
	var stat_info := VBoxContainer.new()
	stat_info.add_theme_constant_override("separation", 0)
	stat_info.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_info.add_child(_label(stat[1], "StrongLabel"))
	var note := _label(stat[2], "SmallMuted")
	stat_info.add_child(note)
	stat_row.add_child(stat_info)
	info.add_child(stat_row)
	row.add_child(info)
	return [number, note]


func _hero_cta(row: HBoxContainer) -> VBoxContainer:
	var cta := VBoxContainer.new()
	cta.custom_minimum_size.x = 270
	cta.alignment = BoxContainer.ALIGNMENT_CENTER
	cta.add_theme_constant_override("separation", 10)
	row.add_child(cta)
	return cta


# Single Player on top (few people online): runs, with Ranked as a card below.
func _build_sp_hero() -> Control:
	var frame := _hero_frame()
	var row: HBoxContainer = frame[1]
	var stat := _hero_info(row, "SINGLE PLAYER", "How far can you get?",
		"Your deck, article after article. Pick a playlist, or go Hardcore.",
		["-", "Best run", "Loading..." if Steam.loggedOn() else "Leaderboards need Steam running"])
	var number: Label = stat[0]
	var stat_note: Label = stat[1]
	if Steam.loggedOn():
		_load_best_run(func(run: Dictionary):
			if run.is_empty():
				stat_note.text = "Finish a run on one playlist to get ranked"
				return
			number.text = str(run["score"])
			stat_note.text = "articles · #%s on %s" % [_thousands(run["rank"]), Global.get_playlist_display_name(run["playlist"])])
	var cta := _hero_cta(row)
	var start := _button("Start Run", "CtaButton", _open_single_player)
	start.custom_minimum_size.y = 48
	cta.add_child(start)
	cta.add_child(_button("Leaderboards", "", _on_nav_leaderboards))
	var note := _label("Normal, Hardcore or Legacy", "SmallMuted")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cta.add_child(note)
	return frame[0]


func _build_hero() -> Control:
	var frame := _hero_frame()
	var row: HBoxContainer = frame[1]
	var stat := _hero_info(row, "RANKED DUELS", "Climb the ladder",
		"1v1 on the same article. First correct guess deals the damage.",
		["", "Rating", ""])
	_watch_rating(stat[0], "%s")
	_watch_rating(stat[1], "")  # status line, see _refresh_ratings
	var cta := _hero_cta(row)
	var find := _button("Find Match", "CtaButton", func(): _start_matchmaking("Ranked"))
	_attach_hover_notes(find, true)
	find.custom_minimum_size.y = 48
	cta.add_child(find)
	var quick := _button("Quick Play  · unranked", "", func(): _start_matchmaking("Quick Play"))
	_attach_hover_notes(quick, false)
	cta.add_child(quick)
	# Ranked and Quick Play always use every official playlist; community
	# playlists are played in private rooms.
	var wait := _label("Random articles from all official playlists", "SmallMuted")
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cta.add_child(wait)
	return frame[0]


# Hovering Find Match / Quick Play pops up the notes under the button: no
# googling (both), plus the pre-season note for Ranked.
const HOVER_NOTES_WIDTH := 300
var hover_notes: CanvasLayer  # the open popup, null when none


func _attach_hover_notes(button: Button, ranked: bool) -> void:
	button.mouse_entered.connect(func(): _show_hover_notes(button, ranked))
	button.mouse_exited.connect(_hide_hover_notes)
	button.pressed.connect(_hide_hover_notes)
	button.tree_exiting.connect(_hide_hover_notes)


func _show_hover_notes(button: Button, ranked: bool) -> void:
	_hide_hover_notes()
	if _modal_open():
		return
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	hover_notes = layer
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.theme_type_variation = "DropdownPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size.x = HOVER_NOTES_WIDTH
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	box.add_child(_notice(FAIR_PLAY_TEXT, "accent", true))
	if ranked:
		box.add_child(_notice(PRESEASON_TEXT))
	for c in [box] + box.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Under the button, centred on it, kept on screen.
	panel.reset_size()
	var r := button.get_global_rect()
	var pos := Vector2(r.get_center().x - HOVER_NOTES_WIDTH / 2.0, r.end.y + 6)
	var screen := get_viewport_rect().size
	pos.x = clampf(pos.x, 8, screen.x - HOVER_NOTES_WIDTH - 8)
	if pos.y + panel.size.y > screen.y - 8:
		pos.y = r.position.y - panel.size.y - 6  # no room below: above it
	panel.position = pos


func _hide_hover_notes() -> void:
	if is_instance_valid(hover_notes):
		hover_notes.queue_free()
	hover_notes = null


# Returns the card's content VBox (its parent is the ModeCard panel).
func _mode_card(icon: String, title: String, desc: String, tag := "") -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "ModeCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x = 10
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var head := HBoxContainer.new()
	var icon_box := PanelContainer.new()
	icon_box.theme_type_variation = "ModeIcon"
	var icon_rect := _icon(icon, 20)
	icon_rect.modulate = get_theme_color("accent", "Hub")
	icon_box.add_child(icon_rect)
	head.add_child(icon_box)
	head.add_child(_spacer())
	if not tag.is_empty():
		var tag_label := _label(tag, "TagLabel")
		tag_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		head.add_child(tag_label)
	box.add_child(head)

	box.add_child(_label(title, "HeaderMedium"))
	var desc_label := _label(desc, "MutedLabel")
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc_label)
	box.add_child(_spacer(true))
	return box


# --- Right column: article of the day, friends, today's Daily -------------------

func _build_right_column() -> Control:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = RIGHT_COLUMN_WIDTH
	right.add_theme_constant_override("separation", 14)

	right.add_child(_build_highlight())

	var friends := _side_panel("Friends", " ")
	friends.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	friends_note = friends.get_child(0).get_child(1)
	friends_scroll = ScrollContainer.new()
	friends_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	friends_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	friends.add_child(friends_scroll)
	friends_box = VBoxContainer.new()
	friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_box.add_theme_constant_override("separation", 0)
	friends_scroll.add_child(friends_box)
	right.add_child(friends.get_parent())

	friends_refresh_timer = Timer.new()
	friends_refresh_timer.one_shot = true
	friends_refresh_timer.wait_time = FRIENDS_REFRESH_SECONDS
	friends_refresh_timer.timeout.connect(_fill_friends)
	add_child(friends_refresh_timer)
	Steam.persona_state_change.connect(func(_id, _flags):
		if friends_refresh_timer.is_stopped():
			friends_refresh_timer.start())
	_fill_friends()

	daily_box = _side_panel("Today's Daily", "Friends")
	right.add_child(daily_box.get_parent())
	daily_rows = VBoxContainer.new()
	daily_box.add_child(daily_rows)
	_fill_daily_friends()
	_update_daily_schedule()
	return right


# "Article of the Day": image, title and the start of the intro; clicking
# opens it on Wikipedia. Fills in once ArticleHighlight has loaded it, and
# hides itself if it can't (offline).
func _build_highlight() -> Control:
	var box := _side_panel("Article of the Day", "Wikipedia")
	var panel := box.get_parent()
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var image := TextureRect.new()
	image.custom_minimum_size.y = HIGHLIGHT_IMAGE_HEIGHT
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.clip_contents = true
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(image)
	var title := _label("Loading...", "NameLabel")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 60
	box.add_child(title)
	var extract := _label("", "SmallMuted")
	extract.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	extract.max_lines_visible = 2
	extract.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	extract.custom_minimum_size.x = 60
	box.add_child(extract)
	_load_highlight(panel, image, title, extract)
	return panel


func _load_highlight(panel: Control, image: TextureRect, title: Label, extract: Label) -> void:
	var a := await ArticleHighlight.load_today(self)
	if not is_instance_valid(panel):
		return
	if a.is_empty():
		panel.visible = false
		return
	image.texture = a["texture"]
	title.text = a["title"]
	extract.text = a["extract"]
	panel.tooltip_text = "Read \"%s\" on Wikipedia" % a["title"]
	var id: int = a["id"]
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			SoundManagerScript.play_random_sound_from_folder_with_pitch(CLICK_FOLDER, "SFX")
			OS.shell_open(ArticleHighlight.page_url(id)))


# Real Steam friends: in Cite first, then online, in another game, away,
# offline. Friends in a Cite lobby get a Join button.
func _fill_friends() -> void:
	var scroll_pos := friends_scroll.scroll_vertical
	for c in friends_box.get_children():
		c.queue_free()
	if not Steam.loggedOn():
		friends_note.text = ""
		var off := _label("Open Steam to see your friends here.", "MutedLabel")
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		friends_box.add_child(off)
		return

	var app_id := Steam.getAppID()
	var friends := []
	var online := 0
	for i in Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE):
		var id := Steam.getFriendByIndex(i, Steam.FRIEND_FLAG_IMMEDIATE)
		var state := Steam.getFriendPersonaState(id)
		var game: Dictionary = Steam.getFriendGamePlayed(id)
		var in_cite := not game.is_empty() and int(game.get("id", 0)) == app_id
		var lobby := int(game.get("lobby", 0)) if in_cite else 0
		# Older builds made matchmaking lobbies friend-visible - never offer to
		# join someone who's searching for a match.
		if lobby != 0 and Steam.getLobbyData(lobby, Matchmaker.GAME_KEY) == Matchmaker.GAME_VALUE:
			lobby = 0
		var info := _friend_status(state, game, in_cite, lobby)
		if state != Steam.PERSONA_STATE_OFFLINE:
			online += 1
		friends.append({"id": id, "name": Steam.getFriendPersonaName(id), "lobby": lobby,
			"status": info[0], "dot": info[1], "order": info[2]})
	friends.sort_custom(func(a, b):
		if a["order"] != b["order"]:
			return a["order"] < b["order"]
		return a["name"].naturalnocasecmp_to(b["name"]) < 0)

	friends_note.text = "%d online" % online
	if friends.is_empty():
		var none := _label("No Steam friends yet.", "MutedLabel")
		friends_box.add_child(none)
	for f in friends:
		friends_box.add_child(_friend_row(f))
	friends_scroll.set_deferred("scroll_vertical", scroll_pos)


# Steam chat with a friend: in the in-game overlay when it's available
# (launched through Steam), otherwise the Steam client's own chat window.
func _open_steam_chat(steam_id: int) -> void:
	if Steam.isOverlayEnabled():
		Steam.activateGameOverlayToUser("chat", steam_id)
	else:
		OS.shell_open("steam://friends/message/%d" % steam_id)


# [status text, dot colour name, sort order]
func _friend_status(state: int, game: Dictionary, in_cite: bool, lobby: int) -> Array:
	if state == Steam.PERSONA_STATE_OFFLINE:
		return ["Offline", "offline", 4]
	if in_cite:
		return ["In a Cite lobby" if lobby != 0 else "Playing Cite", "live", 0]
	if not game.is_empty():
		return ["In another game", "online", 2]
	match state:
		Steam.PERSONA_STATE_AWAY:
			return ["Away", "offline", 3]
		Steam.PERSONA_STATE_SNOOZE:
			return ["Snoozing", "offline", 3]
		Steam.PERSONA_STATE_BUSY:
			return ["Busy", "offline", 3]
	return ["Online", "online", 1]


func _friend_row(f: Dictionary) -> Control:
	var hover := PanelContainer.new()
	hover.theme_type_variation = "RowHover"
	hover.self_modulate.a = 0.0
	hover.custom_minimum_size.y = 44
	hover.mouse_filter = Control.MOUSE_FILTER_PASS
	hover.mouse_entered.connect(func(): hover.self_modulate.a = 1.0)
	hover.mouse_exited.connect(func(): hover.self_modulate.a = 0.0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	hover.add_child(row)

	var av := Control.new()
	av.custom_minimum_size = Vector2(32, 32)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.add_child(_avatar(f["name"], 32, f["id"]))
	var dot := _status_dot(f["dot"], 10)
	dot.position = Vector2(24, 24)
	av.add_child(dot)
	row.add_child(av)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := _label(f["name"], "NameLabel")
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 60
	text.add_child(name_label)
	var st := _label(f["status"], "SmallMuted")
	st.add_theme_font_size_override("font_size", 11)
	st.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(st)
	row.add_child(text)

	var friend_id: int = f["id"]
	var friend_name: String = f["name"]
	# Clicking the row opens their profile (the chat button keeps its own click).
	_make_clickable(hover, func(): _open_profile(friend_id, friend_name), "View profile")
	var chat :=_button("", "RowIconButton", func(): _open_steam_chat(friend_id))
	chat.icon = load(ICON_DIR + "message-circle.svg")
	chat.expand_icon = true
	chat.custom_minimum_size = Vector2(30, 30)
	chat.tooltip_text = "Chat on Steam"
	chat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chat)

	var lobby: int = f["lobby"]
	if lobby != 0:
		var b := _button("Join", "SmallButton", func():
			Global.pending_lobby_code = str(lobby)
			_open_lobby("join"))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
	return hover


# Card text + button for today's set (from the cached schedule).
func _refresh_daily_card() -> void:
	var day := DailyState.today_number()
	var day_set := DailyState.todays_set(day, int(DailyState.load_day(day)["reroll"]))
	daily_set_key = day_set["key"]
	var day_state := DailyState.load_day(day, daily_set_key)
	var finished := DailyState.is_finished(day_state)
	var started: bool = not day_state["results"].is_empty() or int(day_state["started_id"]) != 0
	daily_meta.text = ""
	if finished:
		daily_meta.text = "Your score: %s" % _thousands(DailyState.total_points(day_state))
	elif started:
		daily_meta.text = "In progress: %d of %d done" % [day_state["results"].size(), DailyState.ARTICLES_PER_DAY]
	daily_button.text = "View Results" if finished else ("Continue Daily" if started else "Play Daily")
	daily_button.theme_type_variation = "" if finished else "CtaButton"


# Download the latest schedule; if today's set changed, refresh the card and
# friends' scores.
func _update_daily_schedule() -> void:
	var before := daily_set_key
	await DailyState.fetch_schedule(self)
	if not is_inside_tree():
		return
	_refresh_daily_card()
	if daily_set_key != before:
		_fill_daily_friends()


# Friends' scores on today's Daily board (Steam), plus "You" if not played.
func _fill_daily_friends() -> void:
	for c in daily_rows.get_children():
		c.queue_free()
	if not Steam.loggedOn():
		daily_rows.add_child(_label("Open Steam to see friends' scores.", "SmallMuted"))
		return
	var day := DailyState.today_number()
	var key := daily_set_key
	var result: Dictionary = await Leaderboards.download(Leaderboards.daily_board_name(day, key), true)
	if not is_inside_tree() or key != daily_set_key:
		return  # the set changed meanwhile - a newer fill is running
	var own_id := Steam.getSteamID()
	var shown := 0
	var own_listed := false
	for e in result["entries"]:
		if shown >= 4:
			break
		var sid := int(e.get("steam_id", 0))
		var is_me := sid == own_id
		own_listed = own_listed or is_me
		var who := "You" if is_me else Steam.getFriendPersonaName(sid)
		var details: Array = e.get("details", [])
		var solved := "%d/5 · " % int(details[0]) if details.size() > 0 else ""
		shown += 1
		daily_rows.add_child(_daily_row(str(shown), who, solved + _thousands(int(e.get("score", 0))), is_me))
	if not own_listed:
		daily_rows.add_child(_daily_row("–", "You", "Not played", true))
	if result["count"] > 0 and daily_meta and daily_meta.text.is_empty():
		daily_meta.text = "%s played today" % _thousands(int(result["count"]))


func _daily_row(rank: String, who: String, score: String, is_me: bool) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 30
	row.add_theme_constant_override("separation", 8)
	var r := _label(rank, "AccentSmall" if is_me else "SmallMuted")
	r.custom_minimum_size.x = 18
	row.add_child(r)
	var n := _label(who, "AccentSmall" if is_me else "SmallLabel")
	n.add_theme_font_size_override("font_size", 14)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var s := _label(score, "AccentSmall" if is_me else "SmallMuted")
	s.add_theme_font_size_override("font_size", 13)
	row.add_child(s)
	for c in row.get_children():
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row


func _tick_reset() -> void:
	if not reset_label:
		return
	var now := int(Time.get_unix_time_from_system())
	var left := 86400 - (now % 86400)  # seconds to the next UTC midnight
	reset_label.text = "Resets in %02d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]


# --- Actions ------------------------------------------------------------------

func _on_join_code() -> void:
	var code := code_input.text.strip_edges()
	if not code.is_valid_int():
		_show_toast("Enter the room code your friend shared")
		code_input.grab_focus()
		return
	Global.pending_lobby_code = code
	_open_lobby("join")


# Two separate mode cards side by side: Normal holds the playlist list
# (Official / Community sections) and its own Play button; Hardcore stands
# apart, since it always draws from every official article.
func _open_single_player() -> void:
	var box := _open_modal("Single Player", 760)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	# Normal: pick a playlist, then play it.
	var normal := _mode_card("list", "Normal", "Play through one playlist at your own pace.")
	normal.get_parent().size_flags_stretch_ratio = 1.7
	row.add_child(normal.get_parent())
	normal.remove_child(normal.get_child(normal.get_child_count() - 1))  # the card's bottom spacer
	var selector := PlaylistSelector.new()
	selector.custom_minimum_size.y = 300
	selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	normal.add_child(selector)
	var ids := [Global.OFFICIAL_POOL]
	ids.append_array(Global.get_official_playlist_ids())
	ids.append_array(Workshop.get_playlist_ids().filter(func(id): return Workshop.has_playlist(Workshop.file_id_of(id))))
	selector.set_playlists(ids)
	selector.select(Global.OFFICIAL_POOL)
	var play := _button("Play Normal", "CtaButton", func():
		var id := selector.get_selected_id()
		_start_single_player(false, null if id.is_empty() or id == Global.OFFICIAL_POOL else id))
	play.clip_text = true
	play.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	normal.add_child(play)
	selector.playlist_selected.connect(func(id: String):
		play.text = "Play Normal" if id == Global.OFFICIAL_POOL else "Play " + Global.get_playlist_display_name(id).trim_suffix(" (Community)"))

	# Hardcore: its own card, no playlist.
	var hardcore := _mode_card("trophy", "Hardcore", "Every official article, no playlist. Scored by how obscure each article is - the rarer, the more points.", "Ranked")
	row.add_child(hardcore.get_parent())
	hardcore.add_child(_button("Play Hardcore", "CtaButton", func(): _start_single_player(true, null)))
	# The original game, untouched: its own old menu (Main.tscn) and look.
	var legacy := _button("Legacy", "OutlineButton", func():
		Global.open_legacy_menu = true
		get_tree().change_scene_to_file("res://Main/Main.tscn"))
	legacy.add_theme_font_size_override("font_size", 11)
	legacy.add_theme_color_override("font_color", get_theme_color("muted", "Hub"))
	legacy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(legacy)
	_add_modal_close(box, "Back")


# --- Matchmaking overlay ---------------------------------------------------------

func _start_matchmaking(mode_label: String, against_bot := false) -> void:
	if not against_bot and not Steam.loggedOn():
		_show_toast("Matchmaking needs Steam running")
		return
	var playlist := Global.OFFICIAL_POOL
	var box := _open_modal("", 400)
	box.get_child(0).queue_free()  # no generic title - built below
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)

	var eyebrow := _label(mode_label.to_upper(), "Eyebrow")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	mm_title = _label("Finding opponent", "HeaderMedium")
	mm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mm_title)
	mm_time = _label("0:00", "QueueTimer")
	mm_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mm_time)

	# Opponent (shown once found).
	mm_opponent = HBoxContainer.new()
	mm_opponent.alignment = BoxContainer.ALIGNMENT_CENTER
	mm_opponent.add_theme_constant_override("separation", 10)
	mm_opponent.visible = false
	box.add_child(mm_opponent)

	# Scanning bar: a short accent block sliding back and forth.
	mm_scan = ProgressBar.new()
	mm_scan.theme_type_variation = "HubProgress"
	mm_scan.show_percentage = false
	mm_scan.value = 0
	mm_scan.custom_minimum_size = Vector2(0, 4)
	box.add_child(mm_scan)
	mm_scan_fill = Panel.new()
	mm_scan_fill.add_theme_stylebox_override("panel", get_theme_stylebox("fill", "HubProgress"))
	mm_scan_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm_scan.add_child(mm_scan_fill)

	mm_sub = _label("Dev: matching you with %s" % DummyOpponent.BOT_NAME if against_bot else "Official articles · Searching worldwide", "SmallMuted")
	mm_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mm_sub)
	box.add_child(_notice(FAIR_PLAY_TEXT, "accent", true))
	var cancel := _button("Cancel", "GhostButton", func():
		matchmaker.cancel()
		_close_modal())
	cancel.custom_minimum_size.x = 160
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.add_to_group("back_button")
	box.add_child(cancel)

	mm_started_at = Time.get_ticks_msec() / 1000.0
	matchmaker.start(playlist, mode_label, against_bot)


func _on_matchmaking_state(state: int) -> void:
	if not is_instance_valid(mm_title):
		return
	match state:
		Matchmaker.State.FOUND:
			mm_title.text = "Match found"
			mm_sub.text = "Starting..."
			_show_mm_opponent(matchmaker.opponent_id)
			SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/hit", "SFX")
		Matchmaker.State.CONNECTING:
			mm_sub.text = "Connecting..."
		Matchmaker.State.SEARCHING, Matchmaker.State.WAITING:
			mm_title.text = "Finding opponent"
			mm_opponent.visible = false


func _show_mm_opponent(steam_id: int) -> void:
	for c in mm_opponent.get_children():
		c.queue_free()
	var opponent_name := DummyOpponent.BOT_NAME if steam_id == 0 else Steam.getFriendPersonaName(steam_id)
	mm_opponent.add_child(_label("vs", "MutedLabel"))
	mm_opponent.add_child(_avatar(opponent_name, 32, steam_id))
	mm_opponent.add_child(_label(opponent_name, "StrongLabel"))
	mm_opponent.visible = true


func _tick_matchmaking(delta: float) -> void:
	if not is_instance_valid(mm_time) or not is_instance_valid(mm_scan):
		return
	var state: int = matchmaker.state
	var searching := state != Matchmaker.State.FOUND and state != Matchmaker.State.CONNECTING
	if searching:
		var secs := int(Time.get_ticks_msec() / 1000.0 - mm_started_at)
		mm_time.text = "%d:%02d" % [secs / 60, secs % 60]
		mm_scan_t += delta
		var w := mm_scan.size.x * 0.35
		var travel := (sin(mm_scan_t * 2.6) * 0.5 + 0.5) * (mm_scan.size.x - w)
		mm_scan_fill.position = Vector2(travel, 0)
		mm_scan_fill.size = Vector2(w, mm_scan.size.y)
	else:
		mm_scan_fill.position = Vector2.ZERO
		mm_scan_fill.size = mm_scan.size
