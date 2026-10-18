extends Control

func _ready() -> void:
	%LoadButton.pressed.connect(_on_load_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	%IdInput.text_submitted.connect(_on_id_submitted)
	%IdInput.grab_focus()


func _on_id_submitted(_text: String) -> void:
	_on_load_pressed()


func _on_load_pressed() -> void:
	var text = %IdInput.text.strip_edges()
	if not text.is_valid_int():
		%StatusLabel.text = "Enter a numeric Wikipedia page ID."
		return

	# Same solo-vs-dummy-opponent setup MultiplayerLobby._start_dummy_match()
	# uses (no real opponent or P2P connection), just aimed at one forced article ID
	# via Global.debug_forced_article_id instead of the normal shuffled
	# mp_ck.json pool - so a candidate ID can be checked in the actual
	# multiplayer board/UI without needing a second player for every article.
	Global.start_new_run()
	Global.run.current_game_mode = Global.run.GameMode.NORMAL
	Global.multiplayer_article_seed = randi()
	Global.is_multiplayer_match = true
	Global.is_dummy_opponent = true
	Global.multiplayer_opponent_id = 0
	Global.multiplayer_opponent_name = DummyOpponent.BOT_NAME
	Global.debug_forced_article_id = text.to_int()
	get_tree().change_scene_to_file("res://scenes/Round.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main/Main.tscn")
