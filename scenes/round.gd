extends Node2D

class_name Round

const FROZEN_STATUS_COLOR := Color(0.62, 0.86, 1.0)
const SCRAMBLED_STATUS_COLOR := Color(1.0, 0.78, 0.36)
# Multiplayer round-end damage number (MultiplayerBoard): dealt vs taken.
const DAMAGE_DEALT_COLOR := Color(0.45, 0.9, 0.5)
const DAMAGE_TAKEN_COLOR := Color(0.95, 0.3, 0.3)
# Mana bar height under the health bar in the single player match layout.
const MANA_BAR_HEIGHT := 32.0
# Answer picture (show_answer): largest size inside the answer box, and for
# the picture-only card after a correct guess, which starts below the banner.
const ANSWER_IMAGE_MAX := Vector2(420, 240)
const ANSWER_IMAGE_ONLY_MAX := Vector2(380, 260)
const ANSWER_IMAGE_ONLY_TOP := 240.0
const ArticleImage := preload("res://components/article_image.gd")

var current_id
# Wikipedia page id whose lead image goes with the answer (ArticleImage) -
# set in every mode, unlike current_id which Hardcore leaves alone.
var image_id: int = 0
var article_chunks
var article_title
var article_alternative_title
var article_title_length
var article_main_category
var article_related_categories
var article_difficulty
# Hardcore only: the article's average daily Wikipedia views over the last
# 30 days, -1 if Wikipedia didn't say. Sets its leaderboard points.
var article_daily_views: float = -1.0
# Wikipedia's short description with the title words blanked ("" if the
# article has none) - Normal single player's description hint.
var article_description: String = ""
var article_censored_title
var current_board
var current_deck
var current_deck_card_count:int

var vowels_revealed:bool = false

var card_playable:bool = true


var curent_board

var SkipScene = preload("res://scenes/Skip.tscn")
const MatchStyle := preload("res://ui/match/match_style.gd")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	article_title = Global.run.current_round.article_title

	$Gradient.visible = not Global.uses_modern_ui()
	$BackgroundScroll.visible = not Global.uses_modern_ui()
	$Background.visible = Global.uses_modern_ui()
	# Outside Legacy, SingleplayerBoard has its own buttons for these.
	$CategoryReveal.visible = not Global.uses_modern_ui()
	$DifficultyReveal.visible = not Global.uses_modern_ui()

	Global.run.Health.heal(Global.run.legacy_heal * 10)
	Global.run.Mana.restore_mana(Global.run.legacy_mana_restore * 1)
	create_skip_icons()

	if Global.is_multiplayer_match:
		$CategoryReveal/Area2D.input_pickable = false
		$DifficultyReveal/Area2D.input_pickable = false
		$Control.position = Vector2(8, 8)  # health bar hugs the top-left edge, avatar + name below it
		%SelfAvatar.visible = true
		%SelfNameLabel.visible = true
		%SelfPlayerBox.visible = true
		add_child(SettingsOverlay.new())
		_setup_self_identity()
		if Global.is_dummy_opponent:
			add_child(DummyOpponent.new())
		_apply_match_style()
	elif Global.uses_modern_ui():
		# Single player in the match layout: same player box, with the mana
		# bar under the health bar pushing avatar + name down.
		$Control.position = Vector2(8, 8)
		%SelfAvatar.visible = true
		%SelfNameLabel.visible = true
		%SelfPlayerBox.visible = true
		%SelfAvatar.position.y += MANA_BAR_HEIGHT
		%SelfNameLabel.position.y += MANA_BAR_HEIGHT
		%SelfPlayerBox.size.y += MANA_BAR_HEIGHT
		$CategoryReveal/Area2D.input_pickable = false
		$DifficultyReveal/Area2D.input_pickable = false
		add_child(SettingsOverlay.new())
		_setup_self_identity()
		_apply_match_style()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Global.is_multiplayer_match:
		return
	var color_rect = $Gradient
	var health = Global.run.current_hp
	# Clamp to [0, 1]
	var t = clamp(health / float(Global.SINGLE_PLAYER_START_HP), 0.0, 1.0)
	# Define colors
	var low_color = Color("ff4b3c")   # near 0 HP
	var high_color = Color("dcdcdc")  # near 2000 HP
	# Lerp between them
	var new_color = low_color.lerp(high_color, t)
	color_rect.modulate = new_color



func censor_title():
	var censored = ""
	for c in article_title:
		# Letters/digits (accented ones included, e.g. "č") get blanked;
		# spaces and punctuation show through - same rule as get_title_count().
		if Global.is_guessable_char(c):
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


# Multiplayer and single player (not Legacy): the hub's paper look.
func _apply_match_style() -> void:
	MatchStyle.apply(self)
	$Background.color = MatchStyle.color("bg")
	# Player boxes: the theme's bordered paper panel instead of the grey tint.
	%SelfPlayerBox.remove_theme_stylebox_override("panel")
	%SelfNameLabel.theme_type_variation = "NameLabel"
	%SelfNameLabel.add_theme_font_size_override("font_size", 16)
	%StatusOverlay.add_theme_color_override("font_outline_color", Color(MatchStyle.color("bg"), 0.9))
	%StatusOverlay.add_theme_font_override("font", preload("res://ui/fonts/fraunces_600.tres"))
	%BigBanner.add_theme_font_override("normal_font", preload("res://ui/fonts/fraunces_600.tres"))


func show_banner(text: String, color: Color = Color(0.75, 0.08, 0.08)) -> void:
	if MatchStyle.active():
		color = MatchStyle.paper(color)
	var banner = %BigBanner
	banner.text = text
	banner.add_theme_color_override("default_color", color)
	banner.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.5)
	tween.tween_property(banner, "modulate:a", 0.0, 0.5)
	
	
# Centered box revealing the article title after a multiplayer round nobody
# guessed (or what the opponent typed when they got it - then `footer` holds
# the real title). Fades in, holds, fades out within `duration` seconds -
# built in code on its own CanvasLayer so it sits above everything.
#
# The article's Wikipedia image (ArticleImage) sits above the text when it
# has one. With an empty title it's a picture-only card, placed below the
# banner - correct guesses use that, since the title bar already shows the
# answer and the banner the result.
func show_answer(title: String, duration: float, caption_text: String = "The answer was", footer: String = "") -> void:
	var image_only := title == ""
	var image_id: int = Global.run.current_round.image_id
	if image_only and ArticleImage.get_cached(image_id) == null:
		return  # nothing to show (still loading or no image) - don't block the banner

	var layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if image_only:
		center.offset_top = ANSWER_IMAGE_ONLY_TOP  # clear of %BigBanner
	layer.add_child(center)

	var panel = PanelContainer.new()
	var paper := MatchStyle.active()
	var style = StyleBoxFlat.new()
	style.bg_color = MatchStyle.color("surface") if paper else Color(0.08, 0.085, 0.1, 0.95)
	style.border_color = MatchStyle.color("text") if paper else Color(0.533, 0.341, 0.71, 1)
	if paper:
		style.shadow_color = Color(MatchStyle.color("text"), 0.15)
		style.shadow_size = 12
	style.set_border_width_all(1 if paper else 3)
	style.set_corner_radius_all(3 if paper else 14)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 18
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	panel.modulate.a = 0.0
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	if image_only:
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 14
		style.content_margin_bottom = 14
		_add_answer_image(vbox, ArticleImage.get_cached(image_id), ANSWER_IMAGE_ONLY_MAX)

	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(max(duration - 0.8, 0.0))
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(layer.queue_free)
	if image_only:
		return

	var caption = Label.new()
	caption.text = caption_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", MatchStyle.color("muted") if paper else Color(0.7, 0.7, 0.75))
	caption.add_theme_font_size_override("font_size", 20)
	vbox.add_child(caption)

	var answer = Label.new()
	answer.text = title
	answer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	answer.add_theme_color_override("font_color", MatchStyle.color("text") if paper else Color.WHITE)
	if paper:
		answer.add_theme_font_override("font", preload("res://ui/fonts/fraunces_600.tres"))
	answer.add_theme_font_size_override("font_size", 48 if title.length() <= 16 else (36 if title.length() <= 26 else 28))
	vbox.add_child(answer)

	if footer != "":
		var footer_label = Label.new()
		footer_label.text = footer
		footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		footer_label.add_theme_color_override("font_color", MatchStyle.color("muted") if paper else Color(0.7, 0.7, 0.75))
		footer_label.add_theme_font_size_override("font_size", 18)
		vbox.add_child(footer_label)

	_add_answer_image_when_ready(vbox, image_id)


# Puts the image at the top of the answer box - right away if it's loaded,
# otherwise as soon as it arrives (if the box is still up by then).
func _add_answer_image_when_ready(vbox: VBoxContainer, image_id: int) -> void:
	var tex: Texture2D = ArticleImage.get_cached(image_id)
	if tex == null:
		tex = await ArticleImage.fetch(image_id)
	if tex != null and is_instance_valid(vbox) and vbox.is_inside_tree():
		_add_answer_image(vbox, tex, ANSWER_IMAGE_MAX)


func _add_answer_image(vbox: VBoxContainer, tex: Texture2D, max_size: Vector2) -> void:
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = ArticleImage.fit_size(tex, max_size)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(pic)
	vbox.move_child(pic, 0)
	if vbox.get_child_count() > 1:
		var gap := Control.new()
		gap.custom_minimum_size.y = 8
		vbox.add_child(gap)
		vbox.move_child(gap, 1)


# Big see-through text over the middle of the screen for a card effect
# (Freeze, Static) - pops in, holds, then drifts up as it fades out.
func show_status(text: String, color: Color = Color.WHITE) -> void:
	if MatchStyle.active():
		color = MatchStyle.paper(color)
	var label = %StatusOverlay
	if label.has_meta("tween"):
		label.get_meta("tween").kill()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 0.0
	label.scale = Vector2(1.25, 1.25)
	label.position.y = 230.0
	var tween = create_tween()
	label.set_meta("tween", tween)
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.8, 0.2)
	tween.tween_property(label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(1.0)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.parallel().tween_property(label, "position:y", 200.0, 0.8).set_ease(Tween.EASE_IN)


func create_skip_icons():
	if Global.uses_modern_ui():
		return  # SingleplayerBoard shows skip buttons instead; multiplayer has none

	var start_position = Vector2(750, 35)  # Start at x=700
	var spacing = 50  # Horizontal spacing between icons

	for i in range(Global.run.number_of_skips):
		var skip_instance = SkipScene.instantiate()
		add_child(skip_instance)

		# Position each skip icon with horizontal spacing
		skip_instance.position = start_position + Vector2(i * spacing, 0)


func _setup_self_identity() -> void:
	var steam_id = Steam.getSteamID()
	%SelfNameLabel.text = Global.get_own_name()
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
