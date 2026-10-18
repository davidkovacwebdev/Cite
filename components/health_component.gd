extends Control

class_name HealthComponent

@export var is_display_only: bool = false
@export var mirror_bar: bool = false

var max_hp:int
var current_hp:int
var combo_modifier:int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_apply_skin()
	_apply_layout()
	if is_display_only:
		max_hp = 2000
		current_hp = max_hp
		update_health_bar()
		return

	Global.run.Health = self
	if Global.run.round_number == 1 and not Global.run.first_skipped:
		var starting_hp = Global.DUMMY_TEST_HP if Global.is_dummy_opponent else 2000
		max_hp = starting_hp
		current_hp = max_hp
		Global.run.current_hp = starting_hp
		Global.run.max_hp = starting_hp
	else:
		current_hp = Global.run.current_hp
		max_hp = Global.run.max_hp
	update_health_bar()


func _apply_skin() -> void:
	$MinimalSkin.visible = Global.is_multiplayer_match
	$ClassicSkin.visible = not Global.is_multiplayer_match


# For the opponent's panel, the avatar sits to the right of the bar instead
# of the left, so the bar itself has to hug the opposite edge.
func _apply_layout() -> void:
	if not mirror_bar:
		return
	for node in [$MinimalSkin/Track, $MinimalSkin/Fill, $MinimalSkin/Label]:
		var width = node.offset_right - node.offset_left
		node.offset_left = 0.0
		node.offset_right = width


func set_display_vitals(hp: int, hp_max: int) -> void:
	current_hp = hp
	max_hp = hp_max
	update_health_bar()

	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
func increase_max_hp(value):
	max_hp += value
	Global.run.max_hp += value
	update_health_bar()
	die()

func reduce_max_hp(value):
	max_hp -= value
	Global.run.max_hp -= value
	if max_hp < current_hp:
		current_hp = max_hp
	update_health_bar()
	die()
	
func heal(value):
	current_hp += value
	Global.run.current_hp += value
	if current_hp > max_hp:
		current_hp = max_hp
	if Global.run.current_hp > max_hp:
		Global.run.current_hp = Global.run.max_hp
	update_health_bar()
	die()
	
func damage(value):
	current_hp -= value
	Global.run.current_hp -= value
	if current_hp <= 0:
		current_hp = 0
	update_health_bar()
	die()

func update_health_bar():
	var text = "%d/%d" % [current_hp, max_hp]
	$ClassicSkin/RichTextLabel.text = text
	$MinimalSkin/Label.text = text

	var hp_ratio = float(current_hp) / float(max_hp)
	$ClassicSkin/ColorRect.size.x = 300 * hp_ratio

	var fill_width = 246 * hp_ratio
	$MinimalSkin/Fill.size.x = fill_width
	var mat: ShaderMaterial = $MinimalSkin/Fill.material
	mat.set_shader_parameter("size", Vector2(fill_width, $MinimalSkin/Fill.size.y))
	mat.set_shader_parameter("radius", min(6.0, fill_width * 0.5))

	if not is_display_only:
		Global.broadcast_vitals()

func die():
	if is_display_only:
		return
	if current_hp<= 0:
		Global.end_multiplayer_match("lost")
		get_tree().change_scene_to_file("res://scenes/EndScreen.tscn")
