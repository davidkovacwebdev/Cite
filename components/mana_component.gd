extends Node2D

class_name ManaComponent

@export var is_display_only: bool = false

var max_mana:int
var current_mana:int
var combo_modifier:int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_apply_skin()
	if Global.is_multiplayer_match:
		visible = false  # multiplayer doesn't use mana at all - no card spends it
	if is_display_only:
		max_mana = 100
		current_mana = max_mana
		update_mana_bar()
		return

	Global.run.Mana = self
	if Global.run.round_number == 1 and not Global.run.first_skipped:
		max_mana = 100
		current_mana = max_mana
		Global.run.current_mana = 100
		Global.run.max_mana = 100
	else:
		current_mana = Global.run.current_mana
		max_mana = Global.run.max_mana

	update_mana_bar()


func _apply_skin() -> void:
	$MinimalSkin.visible = Global.uses_modern_ui()
	$ClassicSkin.visible = not Global.uses_modern_ui()
	if preload("res://ui/match/match_style.gd").active():
		_apply_paper_skin()


# Hub paper look, matching the health bar above it (blue fill instead of red).
func _apply_paper_skin() -> void:
	var style := preload("res://ui/match/match_style.gd")
	style.set_rect($MinimalSkin/Track.material, style.color("surface").darkened(0.08), style.color("border"), 1.0, 3.0)
	style.set_rect($MinimalSkin/Fill.material, style.color("host_name"), Color.TRANSPARENT, 0.0, 3.0)
	var label: RichTextLabel = $MinimalSkin/Label
	label.add_theme_font_override("normal_font", preload("res://ui/fonts/plex_600.tres"))
	label.add_theme_font_size_override("normal_font_size", 16)
	label.add_theme_color_override("default_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", style.color("text"))
	label.add_theme_constant_override("outline_size", 5)


func set_display_vitals(mana: int, mana_max: int) -> void:
	current_mana = mana
	max_mana = mana_max
	update_mana_bar()



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func increase_max_mana(value):
	max_mana += value
	Global.run.max_mana += value
	update_mana_bar()

func reduce_max_mana(value):
	max_mana -= value
	Global.run.max_mana -= value
	if Global.run.max_mana < current_mana:
		current_mana = max_mana
		Global.run.current_mana = Global.run.current_mana
	if max_mana <= 0:
		max_mana = 0
		Global.run.max_mana = 0
	update_mana_bar()
		
	
func restore_mana(value):
	current_mana += value
	Global.run.current_mana += value
	if current_mana>max_mana:
		current_mana = max_mana
		Global.run.current_mana = Global.run.max_mana
		
	update_mana_bar()
		
	
func spend_mana(value):
	current_mana -= value
	Global.run.current_mana -= value
	
	if current_mana< 0:
		current_mana = 0
		Global.run.current_mana = 0
	update_mana_bar()


func update_mana_bar():
	var text = "%d/%d" % [current_mana, max_mana]
	$ClassicSkin/RichTextLabel.text = text
	$MinimalSkin/Label.text = text

	var mana_ratio = float(current_mana) / float(max_mana)
	$ClassicSkin/ColorRect.size.x = 300 * mana_ratio

	var fill_width = 246 * mana_ratio
	$MinimalSkin/Fill.size.x = fill_width
	var mat: ShaderMaterial = $MinimalSkin/Fill.material
	mat.set_shader_parameter("size", Vector2(fill_width, $MinimalSkin/Fill.size.y))
	mat.set_shader_parameter("radius", min(3.0 if preload("res://ui/match/match_style.gd").active() else 6.0, fill_width * 0.5))

	if not is_display_only:
		Global.broadcast_vitals()
	
