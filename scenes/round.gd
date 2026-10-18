extends Node2D

class_name Round

var current_id
var article_chunks
var article_title
var article_alternative_title
var article_title_length
var article_main_category
var article_related_categories
var article_difficulty
var article_censored_title
var current_board
var current_deck
var current_deck_card_count:int

var vowels_revealed:bool = false

var card_playable:bool = true


var curent_board

var SkipScene = preload("res://scenes/Skip.tscn")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	article_title = Global.run.current_round.article_title

	$Gradient.visible = not Global.is_multiplayer_match
	$BackgroundScroll.visible = not Global.is_multiplayer_match
	$Background.visible = Global.is_multiplayer_match
	$CategoryReveal.visible = not Global.is_multiplayer_match
	$DifficultyReveal.visible = not Global.is_multiplayer_match

	Global.run.Health.heal(Global.run.legacy_heal * 10)
	Global.run.Mana.restore_mana(Global.run.legacy_mana_restore * 1)
	create_skip_icons()

	if Global.is_multiplayer_match:
		$CategoryReveal/Area2D.input_pickable = false
		$DifficultyReveal/Area2D.input_pickable = false
		%SelfAvatar.visible = true
		%SelfNameLabel.visible = true
		_setup_self_identity()
		if Global.is_dummy_opponent:
			add_child(DummyOpponent.new())


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Global.is_multiplayer_match:
		return
	var color_rect = $Gradient
	var health = Global.run.current_hp
	# Clamp to [0, 1]
	var t = clamp(health / 2000.0, 0.0, 1.0)
	# Define colors
	var low_color = Color("ff4b3c")   # near 0 HP
	var high_color = Color("dcdcdc")  # near 2000 HP
	# Lerp between them
	var new_color = low_color.lerp(high_color, t)
	color_rect.modulate = new_color



func censor_title():
	var censored = ""
	for c in article_title:
		# Only plain a-z/A-Z/0-9 get blanked - everything else (spaces,
		# punctuation, and accented/special letters like "á") shows through,
		# matching get_title_count()'s definition of a "guessable" letter.
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			censored += "_"
		else:
			censored += c
	article_censored_title = censored


# Wheel-of-Fortune style: reveals every still-hidden occurrence of one
# player-chosen letter (accent/case-insensitive) - used by the "Letter
# Reveal" multiplayer card.
func reveal_letter_value(letter: String) -> void:
	if letter == "":
		return
	var target = Global.strip_accents(letter.to_lower())
	var found_any = false
	var new_censored = ""
	for i in range(article_title.length()):
		var title_char = Global.strip_accents(article_title[i].to_lower())
		if title_char == target and article_censored_title[i] == "_":
			new_censored += article_title[i]
			found_any = true
		else:
			new_censored += article_censored_title[i]

	if not found_any:
		return

	article_censored_title = new_censored
	current_board.update_board_title()

	if not "_" in new_censored:
		current_board.correct_guess()



func end_round():
	Engine.get_main_loop().reload_current_scene()


func show_banner(text: String) -> void:
	var banner = %BigBanner
	banner.text = text
	banner.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.5)
	tween.tween_property(banner, "modulate:a", 0.0, 0.5)
	
	
func create_skip_icons():
	if Global.is_multiplayer_match:
		return

	var start_position = Vector2(750, 35)  # Start at x=700
	var spacing = 50  # Horizontal spacing between icons

	for i in range(Global.run.number_of_skips):
		var skip_instance = SkipScene.instantiate()
		add_child(skip_instance)

		# Position each skip icon with horizontal spacing
		skip_instance.position = start_position + Vector2(i * spacing, 0)


func _setup_self_identity() -> void:
	var steam_id = Steam.getSteamID()
	%SelfNameLabel.text = Steam.getFriendPersonaName(steam_id)
	var handle = Steam.getMediumFriendAvatar(steam_id)
	if handle > 0:
		_apply_self_avatar_handle(handle)
	else:
		Steam.avatar_image_loaded.connect(_on_self_avatar_image_loaded)


func _on_self_avatar_image_loaded(steam_id: int, width: int, height: int, buffer: PackedByteArray) -> void:
	if steam_id != Steam.getSteamID():
		return
	Steam.avatar_image_loaded.disconnect(_on_self_avatar_image_loaded)
	_apply_self_avatar_image(width, height, buffer)


func _apply_self_avatar_handle(handle: int) -> void:
	var size_data = Steam.getImageSize(handle)
	if not size_data.get("success", false):
		return
	var buffer_data = Steam.getImageRGBA(handle)
	if not buffer_data.get("success", false):
		return
	_apply_self_avatar_image(int(size_data["width"]), int(size_data["height"]), buffer_data["buffer"])


func _apply_self_avatar_image(width: int, height: int, buffer: PackedByteArray) -> void:
	if width <= 0 or height <= 0 or buffer.is_empty():
		return
	var image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, buffer)
	%SelfAvatar.texture = ImageTexture.create_from_image(image)
