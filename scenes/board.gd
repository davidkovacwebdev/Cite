extends Control

class_name Board

var chunks
var shake_tween: Tween
var round_advancing: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.run.current_round.current_board = self
	Global.run.current_round.article_title_length = get_title_count(Global.run.current_round.article_title)
	Global.run.current_round.vowels_revealed = false

	$RoundCounter.text = "Round %d" % Global.run.round_number
	$ArticleTitleLabel.position.x = (get_viewport_rect().size.x / 2) - ($ArticleTitle.size.x / 2)
	$ArticleTitle.position.x = (get_viewport_rect().size.x / 2) - ($ArticleTitle.size.x / 2)
	$ArticleTitle.position.y = 40
	$InputField.reset_border()
	$ArticleTitle.add_theme_constant_override("letter_spacing", 102)
	if Global.run.current_game_mode == 1:
		Global.run.legacy_heal = 5
		Global.run.legacy_mana_restore = 5

	update_legacy_effects()

	if Global.run.current_round.article_chunks:
		chunks = Global.run.current_round.article_chunks
	update_board_chunks()
	
	
	#for each chunk we create a new text label child with all the relevant data

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# reveal specific part of text
func reveal_chunk(index: int, chunk:String):
	index-=1
	var scroll = $ScrollContainer
	var vbox = $ScrollContainer/VBoxContainer

	var label = vbox.get_child(index) as RichTextLabel
	if label:
		# Store original text color
		var original_color = label.get_theme_color("default_color")
		
		# Set the text
		label.text = chunk
		
		# Create tween for smooth color transition with your custom color
		var tween = create_tween()
		tween.tween_method(
			func(color): 
				label.add_theme_color_override("default_color", color),
			Color("#78FF67"),  # Your custom hex color
			original_color,
			0.5
		)
		
		if is_inside_tree() and get_tree():
			await get_tree().process_frame # Wait one frame for layout to update
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
		
		


func _input(event):
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ENTER:
		var guess = simplify_string($InputField.text.strip_edges().to_lower())
		var solution = simplify_string(Global.run.current_round.article_title.strip_edges().to_lower()) 
		var alternative_solution =  simplify_string(Global.run.current_round.article_alternative_title.strip_edges().to_lower())
		if Global.is_guess_match(guess, solution) or Global.is_guess_match(guess, alternative_solution):
			correct_guess()
			
		else:
			$InputField.wrong_border()
			await get_tree().create_timer(0.5).timeout
			$InputField.reset_border()
			if $InputField.text.strip_edges() != "":
				Global.run.Health.damage(50)
			$InputField.text=""
			Global.run.number_of_wrong_guesses += 1

func correct_guess():
	if round_advancing:
		return
	round_advancing = true

	Global.setAchievement(Global.getArticleAch(Global.run.current_round.current_id))
	SoundManagerScript.play_sound("res://assets/sounds/achievements/"+Global.getArticleAchSound(Global.run.current_round.current_id),"SFX")
	Global.run.current_round.card_playable = false
	Global.run.Health.heal(50)

	$InputField.text = "Bingooo"
	$ArticleTitle.text = Global.run.current_round.article_title
	$InputField.success_border()
	await get_tree().create_timer(2).timeout
	Global.run.current_round.card_playable = true

	_advance_round()


func _advance_round() -> void:
	Global.run.round_number += 1
	$RoundCounter.text = "Round %d" % Global.run.round_number
	if Global.run.last_article == true:
		get_tree().change_scene_to_file("res://scenes/EndScreen.tscn")
	else:
		Global.run.current_round.end_round()
	


func update_board_title():
	var title = Global.run.current_round.article_censored_title
	var title_length = Global.run.current_round.article_title_length
	
	$ArticleTitle.text = title + " (" + str(title_length) + ")"
	$ArticleTitle.add_theme_constant_override("letter_spacing", 102)
	
	shake_board($ArticleTitle, 5, 0.03)  # Smaller, faster shake for title
	
	
func get_title_count(text: String) -> int:
	var count = 0
	for c in text:
		# Includes A-Z, a-z, and 0-9
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			count += 1
	return count
	
func update_legacy_effects():
	$LegacyRoundHeal.text = "Healing each round: " + str(Global.run.legacy_heal * 10)
	$LegacyMaxHP.text = "Additional Max HP: " + str(Global.run.legacy_max_hp *10) 
	$LegacyManaRestore.text = "Mana Restore each round: %d" % Global.run.legacy_mana_restore
	$LegacyMaxMana.text = "Additional Max Mana: %d" % Global.run.legacy_max_mana
	shake_board($LegacyEffects, 5, 0.03)  # Smaller, faster shake for title

	

func update_deck_counter():
	$DeckCounter.text = str(Global.run.current_round.current_deck_card_count) + "/" + str(Global.run.current_round.current_deck.round_deck.size())


func update_heal_combo():
	$HealCombo.text = "Heal Combo: " + str(Global.run.Health.combo_modifier)
	shake_board($HealCombo, 5, 0.03)  # Smaller, faster shake for title
	
func update_mana_combo():
	$ManaCombo.text = "Mana Combo: " + str(Global.run.Mana.combo_modifier)
	shake_board($ManaCombo, 5, 0.03)  # Smaller, faster shake for title
	
	
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
