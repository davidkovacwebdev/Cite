extends "res://ui/hub/hub_screen.gd"

# "Roadmaps" tab: what's coming and what already shipped, each with its
# expected date (and the release date once it's out). Items come from
# RoadmapData (edited in the F12 dev panel, published by pushing to main).

const RoadmapData := preload("res://ui/hub/roadmap_data.gd")
const COLUMN_WIDTH := 680

var list: VBoxContainer


func _ready() -> void:
	var column := _setup_screen("Roadmaps")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	list = VBoxContainer.new()
	list.custom_minimum_size.x = COLUMN_WIDTH
	list.add_theme_constant_override("separation", 12)
	center.add_child(list)

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	head.add_child(_label("ROADMAPS", "Eyebrow"))
	head.add_child(_label("What's coming to Cite", "HeaderLarge"))
	var intro := _label("Planned features and when we expect them. Dates can move.", "MutedLabel")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(intro)
	list.add_child(head)
	var loading := _label("Loading...", "MutedLabel")
	list.add_child(loading)

	var items: Array = await RoadmapData.fetch(self)
	if not is_inside_tree():
		return
	loading.queue_free()
	_fill(items)


func _fill(items: Array) -> void:
	# Pinned first, then soonest expected; items without a date go last.
	var sorted := items.duplicate()
	sorted.sort_custom(func(a, b):
		if a["pinned"] != b["pinned"]:
			return a["pinned"]
		return _sort_key(a["expected"]) < _sort_key(b["expected"]))
	if sorted.is_empty():
		list.add_child(_label("Nothing on the roadmap yet. Check back soon.", "MutedLabel"))
	for item in sorted:
		list.add_child(_item_card(item))
	var back := _button("Back to Play", "GhostButton", _on_nav_play)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list.add_child(back)
	list.add_child(_spacer(false, 8))


# Real dates first (soonest first), then text like "Q1 2027", then no date.
static func _sort_key(expected: String) -> String:
	if RoadmapData.is_valid_date(expected):
		return expected
	return "9999-98 " + expected.to_lower() if not expected.is_empty() else "9999-99-99"


func _item_card(item: Dictionary) -> Control:
	var pinned: bool = item["pinned"]
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TablePanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	if pinned:
		# Featured: the table card with a heavier red border and more room.
		var sb: StyleBoxFlat = get_theme_stylebox("panel", "TablePanel").duplicate()
		sb.border_color = get_theme_color("accent", "Hub")
		sb.set_border_width_all(2)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 18
		sb.content_margin_bottom = 18
		panel.add_theme_stylebox_override("panel", sb)
		var eyebrow := _label("PINNED", "Eyebrow")
		eyebrow.add_theme_color_override("font_color", get_theme_color("accent", "Hub"))
		box.add_child(eyebrow)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var title := _label(item["title"], "HeaderMedium" if pinned else "StrongLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(title)
	var expected := String(item["expected"])
	var when := _label("Expected %s" % RoadmapData.pretty_date(expected) if not expected.is_empty() else "Date to be announced", "TagLabel")
	when.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(when)
	box.add_child(top)

	if not String(item["description"]).is_empty():
		var desc := _label(item["description"], "BodyLabel")
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)
	if not String(item["added"]).is_empty():
		box.add_child(_label("Added %s" % RoadmapData.pretty_date(item["added"]), "SmallMuted"))
	return panel
