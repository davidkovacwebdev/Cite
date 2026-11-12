extends Control

class_name HealthComponent

@export var is_display_only: bool = false

# Multiplayer bar's damage trail (MinimalSkin/Trail): on a hit the red fill
# drops at once, the lost chunk stays lit behind it for TRAIL_HOLD_SECONDS,
# then drains down to the new value.
const TRAIL_HOLD_SECONDS := 0.4
const TRAIL_DRAIN_SECONDS := 0.6

# Multiplayer hit sound, on both bars (ours and the opponent's display). Louder
# the bigger the hit: DAMAGE_SOUND_MIN_DB for the smallest, up to
# DAMAGE_SOUND_MAX_DB at DAMAGE_SOUND_FULL_AT damage or more (a max-damage guess).
const DAMAGE_SOUND := "res://assets/sounds/sfx/multiplayer/woob.wav"
const DAMAGE_SOUND_MIN_DB := -18.0
const DAMAGE_SOUND_MAX_DB := 0.0
const DAMAGE_SOUND_FULL_AT := 600.0
const DAMAGE_SOUND_PITCH_VARIATION := 0.08

var max_hp:int
var current_hp:int
var combo_modifier:int = 0
var trail_tween: Tween
# False until the frame after _ready, so the initial vitals (and the opponent
# panel's last-known values right after) snap instead of animating.
var trail_ready: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_apply_skin()
	set_deferred("trail_ready", true)
	if is_display_only:
		max_hp = Global.MULTIPLAYER_START_HP  # opponent panel; real values arrive over the network
		current_hp = max_hp
		update_health_bar()
		return

	Global.run.Health = self
	if Global.run.round_number == 1 and not Global.run.first_skipped:
		var starting_hp = Global.MULTIPLAYER_START_HP if Global.is_multiplayer_match else Global.SINGLE_PLAYER_START_HP
		max_hp = starting_hp
		current_hp = max_hp
		Global.run.current_hp = starting_hp
		Global.run.max_hp = starting_hp
	else:
		current_hp = Global.run.current_hp
		max_hp = Global.run.max_hp
	update_health_bar()


func _apply_skin() -> void:
	$MinimalSkin.visible = Global.uses_modern_ui()
	$ClassicSkin.visible = not Global.uses_modern_ui()
	if preload("res://ui/match/match_style.gd").active():
		_apply_paper_skin()


# Hub paper look (multiplayer and single player; Legacy keeps the classic bar).
func _apply_paper_skin() -> void:
	var style := preload("res://ui/match/match_style.gd")
	style.set_rect($MinimalSkin/Track.material, style.color("surface").darkened(0.08), style.color("border"), 1.0, 3.0)
	style.set_rect($MinimalSkin/Trail.material, style.color("warning").lightened(0.45), Color.TRANSPARENT, 0.0, 3.0)
	style.set_rect($MinimalSkin/Fill.material, style.color("accent"), Color.TRANSPARENT, 0.0, 3.0)
	var label: RichTextLabel = $MinimalSkin/Label
	label.add_theme_font_override("normal_font", preload("res://ui/fonts/plex_600.tres"))
	label.add_theme_font_size_override("normal_font_size", 18)
	label.add_theme_color_override("default_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", style.color("text"))
	label.add_theme_constant_override("outline_size", 5)


func set_display_vitals(hp: int, hp_max: int) -> void:
	# trail_ready: the opponent panel's initial values at round start aren't a hit.
	if trail_ready and hp < current_hp:
		_play_damage_sound(current_hp - hp)
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
	if value > 0:
		_play_damage_sound(value)
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
	_set_bar_width($MinimalSkin/Fill, fill_width)
	_update_trail(fill_width)

	if not is_display_only:
		Global.broadcast_vitals()

func _play_damage_sound(amount: int) -> void:
	if not Global.is_multiplayer_match:
		return
	var t = clamp(amount / DAMAGE_SOUND_FULL_AT, 0.0, 1.0)
	SoundManagerScript.play_sfx_overlapping(DAMAGE_SOUND, lerp(DAMAGE_SOUND_MIN_DB, DAMAGE_SOUND_MAX_DB, t), DAMAGE_SOUND_PITCH_VARIATION)


# Size and the rounded-rect shader's own size/radius have to move together.
func _set_bar_width(bar: ColorRect, width: float) -> void:
	bar.size.x = width
	var mat: ShaderMaterial = bar.material
	mat.set_shader_parameter("size", Vector2(width, bar.size.y))
	mat.set_shader_parameter("radius", min(6.0, width * 0.5))


func _update_trail(fill_width: float) -> void:
	var trail: ColorRect = $MinimalSkin/Trail
	if trail_tween:
		trail_tween.kill()
	# Heals and the first draw just snap - only damage leaves a trail.
	if not trail_ready or fill_width >= trail.size.x:
		_set_bar_width(trail, fill_width)
		return
	trail_tween = create_tween()
	trail_tween.tween_interval(TRAIL_HOLD_SECONDS)
	trail_tween.tween_method(func(w): _set_bar_width(trail, w), trail.size.x, fill_width, TRAIL_DRAIN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func die():
	if is_display_only:
		return
	if current_hp<= 0:
		if Global.is_multiplayer_match:
			Global.end_multiplayer_match("lost")
			Global.show_match_end()
		else:
			get_tree().change_scene_to_file("res://scenes/EndScreen.tscn")
