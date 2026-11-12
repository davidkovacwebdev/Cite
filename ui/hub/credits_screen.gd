extends "res://ui/hub/hub_screen.gd"

# Credits in the hub's paper look (Settings > Credits). The original credits
# screen (scenes/Credits.tscn) is still there, linked from Legacy.

const COLUMN_WIDTH := 640

# [section, text, link label, url]
const SECTIONS := [
	["Data & content", "This game uses text snippets from Wikipedia, the free encyclopedia. All content is licensed under CC BY-SA 4.0.",
		"Wikipedia", "https://www.wikipedia.org/"],
	["Music", "Composed by Uros Predic.",
		"Listen on Spotify", "https://open.spotify.com/artist/3RJb9GBvOZegHgWRqIQjh1"],
	["Emotional and technical support", "My best friend Jeoum. Check out his game in progress, Prowl.",
		"Prowl on Steam", "https://store.steampowered.com/app/4349340/Prowl/"],
	["Trailer video", "Edited by Igor Timčenko.",
		"Igor on LinkedIn", "https://www.linkedin.com/in/igor-tim%C4%8Denko-246b9233a/"],
]

# Third-party software and assets shipped with the game.
const BUILT_WITH := [
	["Godot Engine", "MIT License"],
	["GodotSteam", "MIT License"],
	["Lucide icons", "ISC License"],
	["Fraunces, IBM Plex Sans", "SIL Open Font License 1.1"],
]

const THIRD_PARTY_NOTICES := """GodotSteam - MIT License
Copyright (c) 2015-Current GP Garcia, Chris Ridenour, and Contributors.

Lucide icons - ISC License
Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022.

Fraunces - SIL Open Font License, Version 1.1. Copyright 2018 The Fraunces Project Authors (https://github.com/undercasetype/Fraunces).
IBM Plex Sans - SIL Open Font License, Version 1.1. Copyright 2017 IBM Corp. with Reserved Font Name "Plex".

Wikipedia text - Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0)."""


func _ready() -> void:
	var column := _setup_screen("")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = COLUMN_WIDTH
	list.add_theme_constant_override("separation", 14)
	center.add_child(list)

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	head.add_child(_label("CREDITS", "Eyebrow"))
	head.add_child(_label("Thanks to everyone who helped make Cite", "HeaderLarge"))
	list.add_child(head)

	for s in SECTIONS:
		list.add_child(_section_card(s[0], s[1], s[2], s[3]))
	list.add_child(_built_with_card())

	var back := _button("Back to Play", "GhostButton", _on_nav_play)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list.add_child(back)
	list.add_child(_spacer(false, 8))


func _section_card(title: String, text: String, link_text: String, url: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TablePanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label(title.to_upper(), "Eyebrow"))
	var body := _label(text, "BodyLabel")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	var link := _button(link_text, "OutlineButton", func(): OS.shell_open(url))
	link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	link.tooltip_text = url
	box.add_child(link)
	return panel


func _built_with_card() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TablePanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_label("BUILT WITH", "Eyebrow"))
	for entry in BUILT_WITH:
		var row := HBoxContainer.new()
		var name_label := _label(entry[0], "BodyLabel")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_label(entry[1], "SmallMuted"))
		box.add_child(row)
	var licenses := _button("Licenses", "OutlineButton", _open_licenses)
	licenses.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(_spacer(false, 2))
	box.add_child(licenses)
	return panel


# Full license texts: Godot's own (Engine.get_license_text) + the others.
func _open_licenses() -> void:
	var box := _open_modal("Licenses", 560)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var text := _label("Godot Engine - MIT License\n" + Engine.get_license_text() + "\n\n" + THIRD_PARTY_NOTICES, "SmallMuted")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	box.add_child(scroll)
	_add_modal_close(box)
