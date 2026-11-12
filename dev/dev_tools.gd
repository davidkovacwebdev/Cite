extends RefCounted

# Developer tools panel: F12 on any hub screen (hub_screen._input), but only
# when Global.dev_tools_available() - a debug build (running from the editor)
# that still has this res://dev/ folder. Every export preset excludes dev/*
# (export_presets.cfg exclude_filter), so shipped builds don't contain any of
# this, and F12 does nothing there.

const ARTICLE_TESTER := "res://dev/ArticleTester.tscn"
const MP_ID_TESTER := "res://dev/MultiplayerIdTester.tscn"
const DailyState := preload("res://ui/daily/daily_state.gd")


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
			["Official Daily", func(): _official_daily(hub)]]:
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
