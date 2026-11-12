extends RefCounted

# Developer tools panel: F12 on any hub screen (hub_screen._input), but only
# when Global.dev_tools_available() - a debug build (running from the editor)
# that still has this res://dev/ folder. Every export preset excludes dev/*
# (export_presets.cfg exclude_filter), so shipped builds don't contain any of
# this, and F12 does nothing there.

const ARTICLE_TESTER := "res://dev/ArticleTester.tscn"
const MP_ID_TESTER := "res://dev/MultiplayerIdTester.tscn"
const DailyState := preload("res://ui/daily/daily_state.gd")
const RoadmapData := preload("res://ui/hub/roadmap_data.gd")


# hub: the open hub screen (ui/hub/hub_screen.gd) - its modal and widget
# builders are reused so the panel looks like the rest of the menus.
static func open(hub: Control) -> void:
	var box: VBoxContainer = hub._open_modal("Dev tools", 380)
	box.add_child(hub._label("Only in debug builds with the dev/ folder. F12 opens this.", "SmallMuted"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for entry in [
			["Dummy Ranked", func(): _dummy_matchmaking(hub, "Ranked")],
			["Dummy Quick Play", func(): _dummy_matchmaking(hub, "Quick Play")],
			["Test Article", func(): hub.get_tree().change_scene_to_file(ARTICLE_TESTER)],
			["Test MP ID", func(): hub.get_tree().change_scene_to_file(MP_ID_TESTER)],
			["Reset Daily", func(): _reset_daily(hub)],
			["Official Daily", func(): _official_daily(hub)],
			["Roadmap editor", func(): _open_roadmap_editor(hub)]]:
		var b: Button = hub._button(entry[0], "SmallButton", entry[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	box.add_child(grid)

	# Which mode takes the hub's top spot (normally decided by how many people
	# are online - see hub.gd _wants_sp_first).
	var layout := _option_row(hub, box, "Hub top")
	layout.add_item("Auto (%d+ online = Ranked)" % Global.HUB_SP_FIRST_BELOW, Global.HubLayout.AUTO)
	layout.add_item("Single Player", Global.HubLayout.SINGLE_PLAYER)
	layout.add_item("Ranked", Global.HubLayout.MULTIPLAYER)
	layout.select(layout.get_item_index(Global.hub_layout_override))
	layout.item_selected.connect(func(i: int):
		Global.hub_layout_override = layout.get_item_id(i)
		if hub.scene_file_path == Global.MENU_SCENE:
			hub.get_tree().reload_current_scene())

	# How the bot in Dummy Ranked / Quick Play plays.
	var bot := _option_row(hub, box, "Bot")
	bot.add_item("Passive (never guesses)", Global.DummyBotLevel.PASSIVE)
	bot.add_item("Normal", Global.DummyBotLevel.NORMAL)
	bot.add_item("Fast", Global.DummyBotLevel.FAST)
	bot.select(bot.get_item_index(Global.dummy_bot_level))
	bot.item_selected.connect(func(i: int): Global.dummy_bot_level = bot.get_item_id(i))

	hub._add_modal_close(box)


static func _option_row(hub: Control, box: VBoxContainer, title: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label: Label = hub._label(title, "SmallLabel")
	label.custom_minimum_size.x = 70
	row.add_child(label)
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	box.add_child(row)
	return option


# The hub's matchmaking overlay (Ranked or Quick Play), but against
# DummyOpponent with no Steam involved - see Matchmaker._run_dummy.
static func _dummy_matchmaking(hub: Control, mode_label: String) -> void:
	Global.pending_dummy_matchmaking = mode_label
	hub.get_tree().change_scene_to_file(hub.HUB_SCENE)


# Fresh local set of 5 for today (no leaderboard - see DailyState.reset_day).
static func _reset_daily(hub: Control) -> void:
	DailyState.reset_day(DailyState.today_number())
	hub.get_tree().reload_current_scene()


# Wipe today's local attempt and go back to the official (online) set.
static func _official_daily(hub: Control) -> void:
	DailyState.official_day(DailyState.today_number())
	hub.get_tree().reload_current_scene()


# --- Roadmap editor -----------------------------------------------------------
# Adds / removes items in RoadmapData.BUNDLED_PATH (res://assets/data/
# roadmap.json). Running from the editor shows this file right away; players
# get it once it's committed and pushed to main (or in the next build).

static func _open_roadmap_editor(hub: Control) -> void:
	var box: VBoxContainer = hub._open_modal("Roadmap editor", 560)
	var note: Label = hub._label("Saves to assets/data/roadmap.json. Commit and push to main to publish it to players.", "SmallMuted")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	var items: Array = RoadmapData.load_bundled()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 200
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	box.add_child(scroll)
	if items.is_empty():
		rows.add_child(hub._label("No items yet - add one below.", "MutedLabel"))
	for i in items.size():
		rows.add_child(_roadmap_row(hub, items, i))

	box.add_child(HSeparator.new())
	box.add_child(hub._label("Add an item", "HeaderSmall"))
	var title := _field(box, "Title")
	var description := _field(box, "Description (optional)")
	var expected := _field(box, "Expected: a date (DD.MM.YYYY) or any text, e.g. Q1 2027 (optional)")
	box.add_child(hub._button("Add item", "CtaButton", func():
		var t := title.text.strip_edges()
		# A real date is stored as YYYY-MM-DD (shown DD.MM.YYYY); any other text
		# ("Q1 2027", "Soon") is kept as typed.
		var e_text := expected.text.strip_edges()
		var e := RoadmapData.from_input(e_text)
		if e == "":
			e = e_text
		if t.is_empty():
			hub._show_toast("Give it a title")
			return
		# "added" = today, automatically.
		items.append({"id": "%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000],
			"title": t, "description": description.text.strip_edges(), "expected": e,
			"added": RoadmapData.today(), "pinned": false})
		_save_roadmap(hub, items)))

	# Close (and Esc): refresh the Roadmaps screen if that's where we are.
	var close: Button = hub._button("Close", "GhostButton", func():
		hub._close_modal()
		if hub.scene_file_path == hub.ROADMAP_SCENE:
			hub.get_tree().reload_current_scene())
	close.add_to_group("back_button")
	box.add_child(close)


static func _roadmap_row(hub: Control, items: Array, index: int) -> Control:
	var item: Dictionary = items[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var title: Label = hub._label(item["title"], "StrongLabel")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 80
	text.add_child(title)
	var dates := "Expected %s" % (RoadmapData.pretty_date(item["expected"]) if item["expected"] != "" else "-")
	if item["added"] != "":
		dates += " · Added %s" % RoadmapData.pretty_date(item["added"])
	if item["pinned"]:
		dates = "Pinned · " + dates
	text.add_child(hub._label(dates, "SmallMuted"))
	row.add_child(text)
	row.add_child(hub._button("Unpin" if item["pinned"] else "Pin", "OutlineButton", func():
		items[index]["pinned"] = not items[index]["pinned"]
		_save_roadmap(hub, items)))
	var remove: Button = hub._button("Remove", "OutlineButton", func():
		items.remove_at(index)
		_save_roadmap(hub, items))
	remove.add_theme_color_override("font_color", hub.get_theme_color("accent", "Hub"))
	row.add_child(remove)
	return row


static func _field(box: VBoxContainer, placeholder: String) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	box.add_child(input)
	return input


static func _save_roadmap(hub: Control, items: Array) -> void:
	if RoadmapData.save_bundled(items):
		hub._show_toast("Roadmap saved")
	else:
		hub._show_toast("Couldn't write roadmap.json (only works when running from the editor)")
	_open_roadmap_editor(hub)  # rebuild with the new list

