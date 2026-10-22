extends Control
class_name Card

var skip_scene = preload("res://scenes/Skip.tscn")

enum Type {
	common,
	legacy,
	action,
}

var sub_type
var card_type: Type
var content: String = ""
var order: int

enum Legacy_sub_type {
	max_hp,
	heal,
	max_mana,
	mana
}

var legacy_type = Legacy_sub_type

enum Action_sub_type {
	restore_mana,
	heal,
	reveal_letter,
	hp_to_mana,
	draw_one,
	draw_two,
	hard_pass,
	reveal_first,
	lucky_three,
	vowel_reveal,
	title_mash,
	exodia,

	# Multiplayer-only, once-per-match special cards. Deliberately left out
	# of card_weights below so set_action_type()'s random pool never draws
	# them - they're injected explicitly by deck.gd instead.
	double_down,
	letter_snipe,
	letter_reveal,
	freeze,
	chunk_scramble,

	# Multiplayer reward-only Heal - only ever offered by the round-win reward
	# picker, never in the starting deck. Separate from `heal` above, which is
	# single-player's combo heal.
	mp_heal
}

const MP_HEAL_BASE := 300
# Slight random pitch on each card effect sound so repeats don't sound canned.
const MP_EFFECT_PITCH_VARIATION := 0.05
# heal.mp3 is ~5 dB hotter than the other multiplayer card sounds.
const MP_HEAL_SOUND_VOLUME_DB := -5.0
# How far a hovered hand card rises. Multiplayer cards are text-only, so the
# description fits in the visible part and they don't need to pop up as far.
const HOVER_LIFT := 80.0
const MP_HOVER_LIFT := 30.0
# Legacy card's second line (its bonus) on the dark single player card.
const MODERN_SECONDARY_TEXT_COLOR := Color(0.78, 0.7, 1.0)

# Scales with the round it's played in: base * round / 2 (round 2 = 300,
# round 6 = 900, ...).
static func mp_heal_amount(round_number: int) -> int:
	return int(MP_HEAL_BASE * round_number / 2.0)

var action_type: Action_sub_type


var sway_tween: Tween

func _ready() -> void:
	randomize()
	pivot_offset = size / 2
	$MinimalBackground.visible = Global.uses_modern_ui()
	$Sprite2D.visible = not Global.uses_modern_ui()
	if Global.uses_modern_ui():
		$CardTitle.add_theme_color_override("default_color", Color.WHITE)
		$CardTitle.add_theme_font_size_override("normal_font_size", 18)
		$CardTitle.add_theme_constant_override("line_separation", -4)
		# No type icon - title spans the card and is centered.
		$CardSymbol.visible = false
		$CardTitle.offset_left = 12
		$CardTitle.offset_right = 156
		$CardTitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		$Description.add_theme_color_override("default_color", Color.WHITE)
		$Description2.add_theme_color_override("default_color", MODERN_SECONDARY_TEXT_COLOR)
		$EffectText.add_theme_color_override("default_color", Color.WHITE)
		# Cards live as real child nodes of Deck while undrawn, stacked at
		# its position - stay hidden there and only appear once draw_card()
		# moves them into Hand, so the pile of face-up cards never shows
		# through the deck.
		visible = false
	if Global.is_multiplayer_match:
		# Text-only in multiplayer: just title + description, which gets the
		# full card width and the space the effect text/icon used to take.
		$Description.offset_left = 12
		$Description.offset_right = 156
		$Description.offset_bottom = 240
		$Description2.visible = false
		$EffectText.visible = false
		$EffectIcon.visible = false


func _process(delta: float) -> void:
	pass


func play_card():
	Global.run.number_of_played_cards += 1
	if Global.run.current_round.card_playable == true:
		if Global.is_multiplayer_match:
			Global.run.mp_hand.erase(action_type)  # removes just this one copy
		if not (self.card_type == 3 and self.action_type == Action_sub_type.heal):
			Global.run.Health.combo_modifier = 0
			Global.run.current_round.current_board.update_heal_combo()
		if not (self.card_type == 3 and self.action_type == Action_sub_type.restore_mana):
			Global.run.Mana.combo_modifier = 0
			Global.run.current_round.current_board.update_mana_combo()
			
		# 1 = common
		# 2 = legacy
		# 3 = action    

		if (self.card_type == 1):
			Global.run.Health.damage(50)
			Global.run.current_round.current_board.reveal_chunk(self.order, self.content)
			
		if (self.card_type == 2):
			match self.legacy_type:
				0:
					print("max hp increased")
					Global.run.Health.increase_max_hp(10)
					Global.run.legacy_max_hp += 1
				1:
					print("round heal")
					Global.run.legacy_heal += 1
				2:
					print("max mana increased")
					Global.run.Mana.increase_max_mana(1)
					Global.run.legacy_max_mana += 1
				3:
					print("mana round restore")
					Global.run.legacy_mana_restore += 1

			Global.run.current_round.current_board.update_legacy_effects()
			Global.run.Health.damage(50)

		if (self.card_type == 3):
			match self.action_type:
				0:
					if Global.run.Mana.combo_modifier == 0:
						Global.run.Mana.restore_mana(10)
						Global.run.Mana.combo_modifier += 1
						Global.run.current_round.current_board.update_mana_combo()
					elif Global.run.Mana.combo_modifier == 1:
						Global.run.Mana.restore_mana(50)
						Global.run.Mana.combo_modifier += 1
						Global.run.current_round.current_board.update_mana_combo()
					elif Global.run.Mana.combo_modifier == 2:
						Global.run.Mana.restore_mana(100)
						Global.run.Mana.combo_modifier = 0
						Global.run.current_round.current_board.update_mana_combo()
						Global.run.number_of_combos +=1
						
					
				1:
					if Global.run.Health.combo_modifier == 0:
						Global.run.Health.heal(50)
						Global.run.Health.combo_modifier += 1
						Global.run.current_round.current_board.update_heal_combo()
					elif Global.run.Health.combo_modifier == 1:
						Global.run.Health.heal(200)
						Global.run.Health.combo_modifier += 1
						Global.run.current_round.current_board.update_heal_combo()
					elif Global.run.Health.combo_modifier == 2:
						Global.run.Health.heal(1000)
						Global.run.Health.combo_modifier = 0
						Global.run.current_round.current_board.update_heal_combo()
						Global.run.number_of_combos +=1
						
					
				2:
					if Global.run.current_mana >= 5:
						Global.run.Mana.spend_mana(5)
						reveal_letter()
					else:
#						insuficient Mana indicator here
						return
				3:
					Global.run.Mana.restore_mana(30)
					Global.run.Health.damage(50)
				4:
					if Global.run.current_mana >= 5:
						Global.run.Mana.spend_mana(5)
						Global.run.current_round.current_deck.draw_card()
					else:
#						insuficient Mana indicator here
						return
				5:
					if Global.run.current_mana >= 7:
						Global.run.Mana.spend_mana(7)
						Global.run.current_round.current_deck.draw_card()
						Global.run.current_round.current_deck.draw_card()
					else:
						#insuficient Mana indicator here
						return
#				hard pass
				6: 
					if Global.run.current_mana >= 50:
						Global.run.Mana.spend_mana(50)
						var skip_temp = skip_scene.instantiate()
						skip_temp.skip_round(true)
						skip_temp.queue_free() # Clean up immediately
					else:
#						insuficient mana indicator
						return
				7:
					if Global.run.current_mana >= 10:
					
						var hand = get_parent()
						var deck = hand.get_parent().get_node("Deck") # Adjust name if your Deck node is named differently
						var first_card = get_special_card(hand, deck)
#						Frist card is either first card, or if first card is already played, a random card
						if first_card != null:
							if first_card.order == 1:
								Global.run.Mana.spend_mana(10)
								Global.run.Health.heal(50)
								first_card.play_card()
							else:
								Global.run.Health.heal(50)
								first_card.play_card()
					else:
#						insuficient mana indicator
						return
				8:
		
					for i in range(3):
						var deck = Global.run.current_round.current_deck
						
						# 1. Check if deck actually has cards before drawing
						if deck.get_child_count() > 0:
							deck.draw_card()
							
							var hand = get_parent()
							var last_node = hand.get_children()[-1]
							
							# 2. VALIDATE: Ensure it's a Card and not 'self' or a Timer
							if last_node is Card and last_node != self:
								# Now it is safe to check card_type
								if last_node.card_type == 1:
									Global.run.Health.damage(30)
							else:
								# If it's a timer, this print will prove it
								print("Caught a non-card node: ", last_node.name)
						else:
							break
				9:
					if Global.run.current_mana >= 10:
						
						if Global.run.current_round.vowels_revealed == false:
							reveal_vowels()
							Global.run.current_round.vowels_revealed = true
						else:
							Global.run.Health.heal(50)
				10:
					if Global.run.current_mana >= 20:
						reveal_mashup()
				12:
					# Double Down - arms bonus/penalty for the player's very
					# next guess attempt, and doubles the opponent's damage if
					# they guess first (handled in multiplayer_board.gd).
					SoundManagerScript.play_sfx_overlapping("res://assets/sounds/sfx/multiplayer/double-down.wav", 0.0, MP_EFFECT_PITCH_VARIATION)
					Global.set_double_down_armed(true)
				13:
					# Letter Snipe - free instant version of reveal_letter().
					SoundManagerScript.play_sfx_overlapping("res://assets/sounds/sfx/multiplayer/letter-snipe.wav", 0.0, MP_EFFECT_PITCH_VARIATION)
					reveal_letter()
				14:
					# Letter Reveal - arms the guess field to treat the next
					# submission as a single letter instead of a guess.
					SoundManagerScript.play_sfx_overlapping("res://assets/sounds/sfx/multiplayer/letter-reveal.wav", 0.0, MP_EFFECT_PITCH_VARIATION)
					Global.run.letter_reveal_armed = true
					Global.run.current_round.current_board.update_letter_reveal_hint(true)
				15:
					# Freeze - opponent can't submit guesses for a bit.
					SoundManagerScript.play_sfx_overlapping("res://assets/sounds/sfx/multiplayer/chill.wav", 0.0, MP_EFFECT_PITCH_VARIATION)
					MultiplayerSync.send_freeze_opponent()
					Global.run.current_round.current_board.show_status("Frozen", Round.FROZEN_STATUS_COLOR)
				16:
					# Static - temporarily scrambles the opponent's revealed
					# chunk order.
					SoundManagerScript.play_sfx_overlapping("res://assets/sounds/sfx/multiplayer/shamble.wav", 0.0, MP_EFFECT_PITCH_VARIATION)
					MultiplayerSync.send_scramble_opponent()
					Global.run.current_round.current_board.show_status("Chunks are scrambled", Round.SCRAMBLED_STATUS_COLOR)
				17:
					# Heal - multiplayer reward card, see mp_heal_amount().
					SoundManagerScript.play_sfx_overlapping("res://assets/sounds/sfx/multiplayer/heal.mp3", MP_HEAL_SOUND_VOLUME_DB, MP_EFFECT_PITCH_VARIATION)
					Global.run.Health.heal(mp_heal_amount(Global.run.round_number))
				_:
					Global.run.Health.damage(500)
					Global.run.current_round.current_board.correct_guess()


		# Multiplayer has no deck to refill from - the hand only grows by the
		# round reward.
		if not Global.is_multiplayer_match:
			Global.run.current_round.current_deck.draw_card()
		self.queue_free()


func set_common_type():
	return randi_range(1, 2)

func set_legacy_type():
	var values = Legacy_sub_type.values()
	legacy_type = values[randi() % values.size()]
	return legacy_type


# we'll use 10 as the default value
#Anything less than that is more rare and vice versa
var card_weights = {
	Action_sub_type.restore_mana: 10, 
	Action_sub_type.heal: 10,           
	Action_sub_type.hp_to_mana: 5,     
	Action_sub_type.reveal_letter: 12,  
	Action_sub_type.draw_one: 7,
	Action_sub_type.draw_two: 5,       
	Action_sub_type.hard_pass: 3,
	Action_sub_type.reveal_first: 7,
	Action_sub_type.lucky_three: 4,
	Action_sub_type.vowel_reveal: 4,
	Action_sub_type.title_mash: 3,
	Action_sub_type.exodia: 1
	
}

func set_action_type():
	var weights = card_weights
	if Global.is_multiplayer_match:
		weights = card_weights.duplicate()
		weights.erase(Action_sub_type.restore_mana)
		weights.erase(Action_sub_type.heal)

	var total_weight = 0.0
	for weight in weights.values():
		total_weight += weight

	var roll = randf() * total_weight
	var cursor = 0.0

	for type in weights:
		cursor += weights[type]
		if roll < cursor:
			action_type = type
			return action_type


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_parent() is HBoxContainer:
			play_card()


func reveal_letter():
	var title = Global.run.current_round.article_title
	var censored = Global.run.current_round.article_censored_title

	var unrevealed_indices: Array[int] = []
	for i in range(title.length()):
		if censored[i] == "_" and title[i] != " ":
			unrevealed_indices.append(i)
	
	if unrevealed_indices.is_empty():
		return

	var index = unrevealed_indices[randi_range(0, unrevealed_indices.size() - 1)]

	var new_censored = ""
	for i in range(title.length()):
		new_censored += title[i] if i == index else censored[i]

	Global.run.current_round.article_censored_title = new_censored
	Global.run.current_round.current_board.update_board_title()

	if not "_" in new_censored:
		print("Bingo! That was the final letter.")
		Global.run.current_round.current_board.correct_guess()

func reveal_vowels():
	var title = Global.run.current_round.article_title
	var censored = Global.run.current_round.article_censored_title
	var vowels = "aeiouAEIOU"
	
	var found_any = false
	var new_censored = ""
	
	for i in range(title.length()):
		if title[i] in vowels and censored[i] == "_":
			new_censored += title[i]
			found_any = true
		else:
			new_censored += censored[i]
	
	if not found_any:
		return

	Global.run.current_round.article_censored_title = new_censored
	Global.run.current_round.current_board.update_board_title()
	
	if not "_" in new_censored:
		Global.run.current_round.current_board.correct_guess()

func reveal_mashup():
	var title = Global.run.current_round.article_title
	var letters = []
	
	for i in range(title.length()):
		if title[i] != " ":
			letters.append(title[i])
	
	letters.shuffle()
	
	var mashed_title = ""
	var letter_index = 0
	for i in range(title.length()):
		if title[i] == " ":
			mashed_title += " "
		else:
			mashed_title += letters[letter_index]
			letter_index += 1
			
	Global.run.current_round.article_censored_title = mashed_title
	Global.run.current_round.current_board.update_board_title()
		
func get_special_card(hand_node: Node, deck_node: Node):
	var all_nodes = hand_node.get_children() + deck_node.get_children()
	var common_cards: Array[Card] = []
	
	for child in all_nodes:
		if child is Card and child.card_type == 1:
			# If we find the "Holy Grail", return it immediately and stop
			if child.order == 1:
				return child
			
			# Otherwise, add it to our list of potential backups
			common_cards.append(child)
				
	if common_cards.size() > 0:
		return common_cards[randi() % common_cards.size()]
		
	print("No common cards found at all.")
	return null

func _on_mouse_entered() -> void:

	if get_parent() is HBoxContainer:
		var tween = create_tween()
		var lift = MP_HOVER_LIFT if Global.is_multiplayer_match else HOVER_LIFT
		tween.tween_property(self, "position:y", -lift, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		# start sway
		if sway_tween:
			sway_tween.kill()

		sway_tween = create_tween().set_loops()
		sway_tween.tween_property(self, "rotation_degrees", 5, 1.0)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway_tween.tween_property(self, "rotation_degrees", -5, 2.0)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		if Global.is_multiplayer_match:
			SoundManagerScript.play_sound_with_pitch("res://assets/sounds/sfx/multiplayer/card-woosh.wav", "SFX", 0.85, 1.15)
		else:
			SoundManagerScript.play_sound_with_pitch("res://assets/sounds/sfx//woosh/woosh2.wav","SFX")


func _on_mouse_exited() -> void:

	if get_parent() is HBoxContainer:
		var tween = create_tween()
		tween.tween_property(self, "position:y", 0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if sway_tween:
			sway_tween.kill()
		create_tween().tween_property(self, "rotation_degrees", 0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
