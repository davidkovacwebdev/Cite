extends Node2D

class_name Deck

var CardScene = preload("res://scenes/Card.tscn")
var round_deck = []

var swap_timer: Timer
var current_icon_index: int = 0

var confirmation_timer: Timer
var confirmation_visible: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process_input(true)
	%SpriteHappy.visible = true
	%SpriteDead.visible = false
	start_swap_timer()
	%Confirmation.visible = false
	if Global.is_multiplayer_match:
		$Sprite2D.visible = false

	# Setup confirmation timer
	confirmation_timer = Timer.new()
	confirmation_timer.one_shot = true
	confirmation_timer.timeout.connect(_on_confirmation_timeout)
	add_child(confirmation_timer)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func generate_deck(n,sentences):
	var sentence_count = 0
	var legacy_count = 0
	var action_count = 0
	var special_count = 0

	if Global.is_multiplayer_match:
		# Multiplayer only gets the 5 special cards - no common/legacy/old
		# action cards from the single-player kit.
		special_count = generate_multiplayer_special_cards()
	else:
		generate_common_cards(sentences)
		generate_legacy_cards(n)
		generate_action_cards(n * 2)
		sentence_count = len(sentences)
		legacy_count = int(floor(n / 3.0))
		action_count = int(floor(n / 2.0))

	Global.run.number_of_total_cards += sentence_count + legacy_count + action_count + special_count


	round_deck.shuffle()

	for item in round_deck:
		generate_card(item["type"], item["content"], item.get("order", 0), item.get("special_action", -1))


# Each of these is added to the deck every round until it's actually played,
# at which point mp_special_cards_used marks it permanently spent for the
# rest of the match - not just the current round.
func generate_multiplayer_special_cards() -> int:
	var specials = {
		"double_down": Card.Action_sub_type.double_down,
		"letter_snipe": Card.Action_sub_type.letter_snipe,
		"letter_reveal": Card.Action_sub_type.letter_reveal,
		"freeze": Card.Action_sub_type.freeze,
		"chunk_scramble": Card.Action_sub_type.chunk_scramble,
	}
	var count = 0
	for key in specials:
		if not Global.run.mp_special_cards_used.get(key, false):
			round_deck.append({
				"type": 3,
				"content": "Special card: %s" % key,
				"special_action": specials[key],
			})
			count += 1
	return count

func generate_card(type, content, order:int = 0, special_action = -1):
	var card = CardScene.instantiate()
	card.card_type = type
	card.content = content
	var card_title = card.get_node("CardTitle") as RichTextLabel
	var card_description = card.get_node("Description") as RichTextLabel
	var card_description2 = card.get_node("Description2") as RichTextLabel
	var card_symbol = card.get_node("CardSymbol") as Sprite2D
	var color_rect = card.get_node("ColorRect") as ColorRect
	var effect_text = card.get_node('EffectText') as RichTextLabel
	var effect_symbol = card.get_node('EffectIcon') as Sprite2D

	if type == 1:
		card_title.text="Common"
		card_symbol.texture = load("res://assets/sprites/common_card.png")
		card_description.text = "Reveal a text chunk in exchange for Health"
		effect_text.text = "-50"
		effect_symbol.texture = load("res://assets/sprites/HP.png")
		card.order = order
	if type == 2:
		card.legacy_type = card.set_legacy_type()
		card_title.text = "Legacy"
		card_symbol.texture = load("res://assets/sprites/legacy_card.png")
		card_description.text = "Legacy cards grants permanent bonuses; for a price"
		effect_text.text = "-50"
		effect_symbol.texture = load("res://assets/sprites/HP.png")
		if card.legacy_type == 0:
			card_description2.text = "Permanently increase Max HP"
		if card.legacy_type == 1:
			card_description2.text = "Permanently heals at the start of each round"
		if card.legacy_type == 2:
			card_description2.text = "Permanently increases Max Mana"
		if card.legacy_type == 3:
			card_description2.text = "Permanently restores mana at the start of each round"
	if type == 3:
		card.action_type = special_action if special_action != -1 else card.set_action_type()
		card_symbol.texture = load("res://assets/sprites/action_card.png")
		card_title.text = "Action"
		if  card.action_type == 0:
			card_description.text = "Instant mana restore. Playing multiple of these cards in a row adds a bonus"
			effect_text.text = "+10"
			effect_symbol.texture = load("res://assets/sprites/mana.png")
		elif card.action_type == 1:
			card_description.text = "Instant health restore. Playing multiple of these cards in a row adds a bonus"
			effect_text.text = "+50"
			effect_symbol.texture = load("res://assets/sprites/HP.png")
		elif card.action_type == 2:
			card_description.text = "Reveals single letter from the title in exchange for Mana"
			effect_text.text = "-5"
			effect_symbol.texture = load("res://assets/sprites/mana.png")
		elif card.action_type == 3:
			card_description.text = "Spend HP to refill some mana"
			effect_text.text = "-50\n+30"
			effect_text.add_theme_font_size_override("normal_font_size", 18)  # Only for this card type
			effect_symbol.texture = load("res://assets/sprites/exchange.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
		elif card.action_type == 4:
			card_description.text = "Spend 5 Mana to draw a card"
			effect_text.text = "-5"
			effect_text.add_theme_font_size_override("normal_font_size", 18)  # Only for this card type
			effect_symbol.texture = load("res://assets/sprites/Draw_one.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
		#elif card.action_type == 5:
		elif card.action_type == 5:
			card_description.text = "Spend 7 Mana to draw two cards"
			effect_text.text = "-7"
			effect_text.add_theme_font_size_override("normal_font_size", 18)  # Only for this card type
			effect_symbol.texture = load("res://assets/sprites/Draw_two.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
		#else:
		elif card.action_type == 6:
			card_description.text = "Skip current round \nBut at large cost"
			effect_text.text = "-50"
			effect_text.add_theme_font_size_override("normal_font_size", 18)  # Only for this card type
			effect_symbol.texture = load("res://assets/sprites/ManaSkip.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
		elif card.action_type == 7:
			card_description.text = "Reveal first setnence \nIf already revealed, reveals random chunk for no cost"
			effect_symbol.texture = load("res://assets/sprites/First_chunk.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "-10"
		elif card.action_type == 8:
			card_description.text = "Draw 3 cards free of cost \nBut loose HP for each drawn common card"
			effect_symbol.texture = load("res://assets/sprites/First_chunk.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = ""
		
		elif card.action_type == 9:

			card_description.text = "Reveal title vowels\nIf already revealed, heals for 50"
			effect_symbol.texture = load("res://assets/sprites/reveal_vowels.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "- 10"
		elif card.action_type == 10:
			card_description.text = "Reveal all title letters but with a twist"
			effect_symbol.texture = load("res://assets/sprites/mashup.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "-20"
		elif card.action_type == 12:
			card_title.text = "Double Down"
			card_description.text = "Guess now for 2x damage.\nA wrong guess deals extra damage to you instead. Once per match."
			effect_symbol.texture = load("res://assets/sprites/HP.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "2x"
		elif card.action_type == 13:
			card_title.text = "Letter Snipe"
			card_description.text = "Instantly reveals one random letter in the title. Free. Once per match."
			effect_symbol.texture = load("res://assets/sprites/mana.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "1x"
		elif card.action_type == 14:
			card_title.text = "Letter Reveal"
			card_description.text = "Submit one letter next to reveal every match in the title. Once per match."
			effect_symbol.texture = load("res://assets/sprites/mana.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "1x"
		elif card.action_type == 15:
			card_title.text = "Freeze"
			card_description.text = "Opponent can't submit guesses for 2 seconds. Once per match."
			effect_text.text = "2s"
		elif card.action_type == 16:
			card_title.text = "Static"
			card_description.text = "Scrambles the order of the opponent's revealed text for 5 seconds. Once per match."
			effect_text.text = "5s"
		elif card.action_type == 17:
			var heal_amount = Card.mp_heal_amount(Global.run.round_number)
			card_title.text = "Heal"
			card_description.text = "Restores %d HP.\nScales with the round: 300 x round / 2." % heal_amount
			effect_symbol.texture = load("res://assets/sprites/HP.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "+%d" % heal_amount
		else:
			card_description.text = "I'll let you win this round, mortal\nBut I need blood"
			effect_symbol.texture = load("res://assets/sprites/exodia_heart.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "-500"
		#elif card.action_type == 7: reveal first
		
	get_parent().get_node("Deck").add_child(card)
	return card

func generate_common_cards(sentences):
	var counter:int = 0
	for sentence in sentences:
		counter += 1
		var card = {
			"order": counter,
			"type": 1,
			"content": sentence,
		}
		round_deck.append(card)

func generate_legacy_cards(n):
	var card_number = int(floor(n / 5.0))
	for i in range(card_number):
		var legacy_card = {
			"type": 2,
			"content": "Legacy card %d" % i,
		}
		round_deck.append(legacy_card)

func generate_action_cards(n):
	var card_number = int(floor(n / 4.0))
	for i in range(card_number):
		var action_card = {
			"type": 3,
			"content": "Action card %d" % i,
		}
		round_deck.append(action_card)

func draw_card():
	var deck = Global.run.current_round.current_deck

	# Deck also holds the mascot Sprite2D and its swap/confirmation Timers
	# as children, so "last child" isn't necessarily a card - scan backwards
	# for the actual last Card instance instead.
	var last_card = null
	for i in range(deck.get_child_count() - 1, -1, -1):
		var child = deck.get_child(i)
		if child is Card:
			last_card = child
			break

	if last_card == null:
		print("No cards in deck")
		return

	if Global.run.current_round.current_deck_card_count > 0:
		Global.run.current_round.current_deck_card_count -= 1
	Global.run.current_round.current_board.update_deck_counter()

	var hand = get_parent().get_node("Hand")
	deck.remove_child(last_card)
	hand.add_child(last_card)
	last_card.visible = true

func draw_random_card_excluding(excluded_order: int):
	var deck = Global.run.current_round.current_deck
	var child_count = deck.get_child_count()
	
	if child_count == 0:
		print("No cards in deck")
		return
	
	var valid_cards: Array = []
	for i in range(child_count):
		var card = deck.get_child(i)
		if card is Card and card.card_type == Card.Type.common:
			if card.order != excluded_order and card.common_type_number_of_chunks == 1:
				valid_cards.append(card)
	
	if valid_cards.is_empty():
		print("No valid common cards found (excluded order: %d)" % excluded_order)
		return
	
	var random_card = valid_cards[randi() % valid_cards.size()]
	print("Random common card (excluding order %d): %s" % [excluded_order, random_card.name])
	return random_card
	
	
func _input(event):
	if Global.is_multiplayer_match:
		return  # mascot (and its click-to-forfeit hotspot) is hidden in multiplayer for now
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		var icon_pos = %Icon1.global_position
		
		# Check if click is near the icon
		if mouse_pos.distance_to(icon_pos) < 50:
			if not confirmation_visible:
				# First click - show confirmation for 3 seconds
				%Confirmation.visible = true
				confirmation_visible = true
				confirmation_timer.start(3.0)
				print("Confirmation shown")
			else:
				# Second click while confirmation visible - end game
				print("Game ended!")
				Global.end_multiplayer_match("lost")
				get_tree().change_scene_to_file("res://scenes/EndScreen.tscn")

func start_swap_timer():
	swap_timer = Timer.new()
	swap_timer.wait_time = 10.0  # Happy visible for 10 seconds
	swap_timer.timeout.connect(_on_swap_timer_timeout)
	add_child(swap_timer)
	swap_timer.start()
	
func _on_swap_timer_timeout():
	if current_icon_index == 0:
		# Switch to dead sprite for 1 second
		%SpriteHappy.visible = false
		%SpriteDead.visible = true
		current_icon_index = 1
		swap_timer.wait_time = 1.0
	else:
		# Switch back to happy sprite for 10 seconds
		%SpriteHappy.visible = true
		%SpriteDead.visible = false
		current_icon_index = 0
		swap_timer.wait_time = 10.0
	
	swap_timer.start()
	
func _on_confirmation_timeout():
	%Confirmation.visible = false
	confirmation_visible = false
	print("Confirmation hidden")
