extends RefCounted

# Matches in the hub's "Redacted paper" look: multiplayer and single player
# Normal/Hardcore (Global.uses_modern_ui()). Legacy shares Round.tscn, cards
# and the bars, and keeps its original look.
#
# Round is a Node2D, so Controls under it don't inherit a theme from it;
# apply() gives every Control whose parent isn't a Control the hub theme,
# including ones added later (cards, overlays, answer box).

const HUB_THEME := preload("res://ui/hub/hub_theme.tres")


static func active() -> bool:
	return Global.uses_modern_ui()


static func color(color_name: String) -> Color:
	return HUB_THEME.get_color(color_name, "Hub")


static func apply(root: Node) -> void:
	_apply_to(root)
	var tree := root.get_tree()
	var on_added := func(node: Node):
		if is_instance_valid(root) and root.is_ancestor_of(node):
			_theme_node(node)
	tree.node_added.connect(on_added)
	root.tree_exiting.connect(func():
		if tree.node_added.is_connected(on_added):
			tree.node_added.disconnect(on_added), CONNECT_ONE_SHOT)


static func _apply_to(node: Node) -> void:
	_theme_node(node)
	for child in node.get_children():
		_apply_to(child)


static func _theme_node(node: Node) -> void:
	if node is Control and not (node.get_parent() is Control):
		node.theme = HUB_THEME
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


# Banner/status colours were picked for the dark match background - map the
# known ones to paper equivalents.
static func paper(c: Color) -> Color:
	if c.is_equal_approx(Color(0.45, 0.9, 0.5)):  # Round.DAMAGE_DEALT_COLOR
		return color("added")
	if c.is_equal_approx(Color(0.95, 0.3, 0.3)) or c.is_equal_approx(Color(0.75, 0.08, 0.08)):  # damage taken / default banner
		return color("accent")
	if c.is_equal_approx(Color(0.62, 0.86, 1.0)):  # Round.FROZEN_STATUS_COLOR
		return color("host_name")
	if c.is_equal_approx(Color(1.0, 0.78, 0.36)):  # Round.SCRAMBLED_STATUS_COLOR
		return color("warning")
	if c.is_equal_approx(Color.WHITE):
		return color("text")
	return c


# Rounded-rect shader (cards, health bar): paper fill + ink border.
static func set_rect(mat: ShaderMaterial, fill: Color, border := Color.TRANSPARENT, border_width := 0.0, radius := 3.0) -> void:
	if not mat:
		return
	mat.set_shader_parameter("color", fill)
	mat.set_shader_parameter("border_color", border)
	mat.set_shader_parameter("border_width", border_width)
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("glow_strength", 0.0)
