extends Control

class_name SingleplayerBoard

# Single player (Normal/Hardcore outside Legacy) laid out like the
# multiplayer match: centered title, wide article, guess popup on Enter and
# a run panel where the opponent would be. Same rules as the Legacy Board
# (board.gd) - card.gd and deck.gd call the same update_* methods on it.

const TITLE_Y := 36.0
const CORRECT_COLOR := Color(0.45, 0.9, 0.5)
const WRONG_GUESS_DAMAGE := 50
const CORRECT_GUESS_HEAL := 50
# Category / difficulty reveal cost, same as Legacy's CategoryReveal and
# DifficultyReveal.
const HELP_MANA_COST := 10

var chunks
var shake_tween: Tween
var round_advancing: bool = false
var guess_open: bool = false
var guess_checking: bool = false
var _base_chunk_font_size: int
var _base_title_font_size: int


func _ready() -> void:
	Global.run.current_round.current_board = self
	Global.run.current_round.article_title_length = get_title_count(Global.run.current_round.article_title)
	Global.run.current_round.vowels_revealed = false

	%RoundLabel.text = "Round %d" % Global.run.round_number
	$ArticleTitle.position.y = TITLE_Y
	_center_title()
	# The text size option can grow the title past its default width.
	$ArticleTitle.resized.connect(_center_title)
	$InputField.reset_border()
	$ArticleTitle.add_theme_constant_override("letter_spacing", 102)
	if Global.run.current_game_mode == Global.run.GameMode.HARDCORE:
		Global.run.legacy_heal = 5
		Global.run.legacy_mana_restore = 5

	update_legacy_effects()
	_build_skip_buttons()
	_setup_helps()

	if Global.run.current_round.article_chunks:
		chunks = Global.run.current_round.article_chunks
	update_board_chunks()
	_base_chunk_font_size = $ScrollContainer.get_theme_font_size("normal_font_size", "RichTextLabel")
	_base_title_font_size = $ArticleTitle.get_theme_font_size("normal_font_size")
	apply_text_size()
	Global.match_display_settings_changed.connect(apply_text_size)


func reveal_chunk(index: int, chunk: String):
	index -= 1
	var scroll = $ScrollContainer
	var vbox = $ScrollContainer/VBoxContainer

	var label = vbox.get_child(index) as RichTextLabel
	if label:
		var original_color = label.get_theme_color("default_color")
		label.text = chunk
		var tween = create_tween()
		tween.tween_method(
			func(color):
				label.add_theme_color_override("default_color", color),
			Color("#78FF67"),
			original_color,
			0.5
		)

		if Global.auto_scroll_to_reveal and is_inside_tree() and get_tree():
			await get_tree().process_frame  # wait one frame for layout to update
			scroll.scroll_vertical = label.position.y

	shake_board()


func update_board_chunks():
	if !chunks:
		return
	var vbox = $ScrollContainer/VBoxContainer

	for sentence in chunks:
		var label = RichTextLabel.new()
		var hidden_text = ""
		# replace each character except spaces/newlines with "_"
		for c in sentence:
			hidden_text += c if c == " " or c == "\n" else "_"
		label.text = hidden_text
		label.fit_content = true
		vbox.add_child(label)


func open_guess() -> void:
	if guess_open or round_advancing:
		return
	guess_open = true
	$InputField.text = ""
	$InputField.reset_border()
	$InputField.visible = true
	$InputField.grab_focus()


func close_guess() -> void:
	guess_open = false
	$InputField.text = ""
	$InputField.visible = false
	$InputField.release_focus()


# Enter opens the guess field, Enter again submits; Esc (or Backspace on an
# empty field) cancels.
func _input(event):
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if Global.settings_overlay_open:
		return
	var is_enter = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
	if guess_open and (event.keycode == KEY_ESCAPE or (event.keycode == KEY_BACKSPACE and $InputField.text.is_empty())):
		close_guess()
		get_viewport().set_input_as_handled()
		return
	if not is_enter or round_advancing:
		return
	get_viewport().set_input_as_handled()
	if not guess_open:
		open_guess()
		return
	if guess_checking:
		return  # still flashing the last wrong guess
	var typed = $InputField.text.strip_edges()
	if typed.is_empty():
		close_guess()
		return

	var guess = simplify_string(typed.to_lower())
	var solution = simplify_string(Global.run.current_round.article_title.strip_edges().to_lower())
	var alternative_solution = simplify_string(Global.run.current_round.article_alternative_title.strip_edges().to_lower())
	if Global.is_guess_match(guess, solution) or Global.is_guess_match(guess, alternative_solution):
		correct_guess()
		return

	guess_checking = true
	$InputField.wrong_border()
	await get_tree().create_timer(0.5).timeout
	guess_checking = false
	if not is_inside_tree():
		return
	Global.run.number_of_wrong_guesses += 1
	close_guess()
	Global.run.Health.damage(WRONG_GUESS_DAMAGE)


func correct_guess():
	if round_advancing:
		return
	round_advancing = true
	close_guess()

	Global.setAchievement(Global.getArticleAch(Global.run.current_round.current_id))
	SoundManagerScript.play_sound("res://assets/sounds/achievements/" + Global.getArticleAchSound(Global.run.current_round.current_id), "SFX")
	Global.run.current_round.card_playable = false
	Global.run.Health.heal(CORRECT_GUESS_HEAL)

	$ArticleTitle.text = Global.run.current_round.article_title
	get_parent().show_banner("Correct!", CORRECT_COLOR)
	await get_tree().create_timer(2).timeout
	Global.run.current_round.card_playable = true

	_advance_round()


func _advance_round() -> void:
	Global.run.round_number += 1
	if Global.run.last_article == true:
		get_tree().change_scene_to_file("res://scenes/EndScreen.tscn")
	else:
		Global.run.current_round.end_round()


func _build_skip_buttons() -> void:
	for i in range(Global.run.number_of_skips):
		var button = Button.new()
		button.text = ">"
		button.custom_minimum_size = Vector2(40, 0)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Skip this round"
		button.pressed.connect(_on_skip_pressed)
		%SkipButtons.add_child(button)


func _on_skip_pressed() -> void:
	if round_advancing:
		return
	round_advancing = true
	Skip.skip_current_round()


# Legacy's magnifier and puzzle-piece helps as plain buttons. Hardcore has
# none (its per-round heal and mana restore make up for it).
func _setup_helps() -> void:
	if Global.run.current_game_mode == Global.run.GameMode.HARDCORE:
		%CategoryButton.visible = false
		%DifficultyButton.visible = false
		%HardcoreNote.visible = true
		return
	%CategoryButton.pressed.connect(_on_category_pressed)
	%DifficultyButton.pressed.connect(_on_difficulty_pressed)


func _on_category_pressed() -> void:
	if not _pay_for_help():
		return
	var round_data = Global.run.current_round
	var related = round_data.article_related_categories
	if related is Array:
		related = ", ".join(related)
	var text = str(round_data.article_main_category)
	if str(related) != "":
		text += ", " + str(related)
	%CategoryButton.visible = false
	%CategoryResult.text = "Category: " + text
	%CategoryResult.visible = true


func _on_difficulty_pressed() -> void:
	if not _pay_for_help():
		return
	%DifficultyButton.visible = false
	%DifficultyResult.text = "Difficulty: " + str(Global.run.current_round.article_difficulty)
	%DifficultyResult.visible = true


func _pay_for_help() -> bool:
	if Global.run.current_mana < HELP_MANA_COST:
		return false
	SoundManagerScript.play_random_click("SFX")
	Global.run.Mana.spend_mana(HELP_MANA_COST)
	return true


func _center_title() -> void:
	$ArticleTitle.position.x = (get_viewport_rect().size.x / 2) - ($ArticleTitle.size.x / 2)


# Article text + title font size, shifted by the settings overlay's -/+ option.
func apply_text_size() -> void:
	var offset = Global.article_text_size_offset
	for label in $ScrollContainer/VBoxContainer.get_children():
		label.add_theme_font_size_override("normal_font_size", _base_chunk_font_size + offset)
	$ArticleTitle.add_theme_font_size_override("normal_font_size", _base_title_font_size + offset)


func update_board_title():
	var title = Global.run.current_round.article_censored_title
	var title_length = Global.run.current_round.article_title_length

	$ArticleTitle.text = title + " (" + str(title_length) + ")"
	$ArticleTitle.add_theme_constant_override("letter_spacing", 102)

	shake_board($ArticleTitle, 5, 0.03)  # smaller, faster shake for title


func get_title_count(text: String) -> int:
	var count = 0
	for c in text:
		# Includes A-Z, a-z, and 0-9
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			count += 1
	return count


func update_legacy_effects():
	%LegacyRoundHeal.text = "Healing each round: " + str(Global.run.legacy_heal * 10)
	%LegacyMaxHP.text = "Additional Max HP: " + str(Global.run.legacy_max_hp * 10)
	%LegacyManaRestore.text = "Mana restore each round: %d" % Global.run.legacy_mana_restore
	%LegacyMaxMana.text = "Additional Max Mana: %d" % Global.run.legacy_max_mana
	shake_board(%LegacyEffects, 5, 0.03)


func update_deck_counter():
	$DeckPanel/DeckCounter.text = str(Global.run.current_round.current_deck_card_count) + "/" + str(Global.run.current_round.current_deck.round_deck.size())


func update_heal_combo():
	%HealCombo.text = "Heal combo: " + str(Global.run.Health.combo_modifier)
	shake_board(%HealCombo, 5, 0.03)


func update_mana_combo():
	%ManaCombo.text = "Mana combo: " + str(Global.run.Mana.combo_modifier)
	shake_board(%ManaCombo, 5, 0.03)


func shake_board(target_node: Node = $ScrollContainer, shake_strength: float = 10, step_duration: float = 0.05):
	if shake_tween:
		shake_tween.kill()

	shake_tween = create_tween()
	shake_tween.set_parallel(true)

	var original_x = target_node.position.x

	# Create a quick back-and-forth shake
	shake_tween.tween_property(target_node, "position:x", original_x + shake_strength, step_duration)
	shake_tween.tween_property(target_node, "position:x", original_x - shake_strength, step_duration).set_delay(step_duration)
	shake_tween.tween_property(target_node, "position:x", original_x + shake_strength/2, step_duration).set_delay(step_duration * 2)
	shake_tween.tween_property(target_node, "position:x", original_x - shake_strength/2, step_duration).set_delay(step_duration * 3)
	shake_tween.tween_property(target_node, "position:x", original_x, step_duration).set_delay(step_duration * 4)


func simplify_string(text: String) -> String:
	var simplified = text.to_lower().strip_edges()
	# Collapse any run of internal whitespace (e.g. an accidental double
	# space) down to a single space, since is_guess_match() requires an
	# exact character-for-character match for titles 12 characters or
	# shorter, with zero tolerance.
	simplified = " ".join(simplified.split(" ", false))
	simplified = Global.strip_accents(simplified)

	return simplified
