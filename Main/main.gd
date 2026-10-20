extends Control

signal play_pressed
signal options_pressed
signal credits_pressed
signal quit_pressed

@onready var master_volume: HSlider = $CenterContainer/VBoxContainer/MasterVolume
@onready var sfx_volume: HSlider = $CenterContainer/VBoxContainer/SFXVolume
@onready var music_volume: HSlider = $CenterContainer/VBoxContainer/MusicVolume

var settings: SaveData

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	settings = ResourceLoader.load("user://scene_data.tres") as SaveData

	if settings and settings.fullscreen == true:
		get_window().mode = Window.MODE_FULLSCREEN

	# Window mode can change without going through _on_fullscreen_toggled -
	# e.g. double-clicking the window border/title bar triggers the OS's
	# native fullscreen toggle directly. Sync once now, and keep listening
	# so the checkbox never lies about what's actually on screen.
	_sync_fullscreen_checkbox()
	get_window().size_changed.connect(_sync_fullscreen_checkbox)

	$MainMenuQuotes.text = get_random_menu_quote()
	Global.load_and_extract_card_data()
	%Tips.visible = false

	if Global.return_to_multiplayer_menu:
		Global.return_to_multiplayer_menu = false
		show_mode_selection()
		show_multiplayer_menu()



	master_volume.set_value_no_signal(SoundManagerScript.master_volume * 100)
	sfx_volume.set_value_no_signal(SoundManagerScript.sfx_volume * 100)
	music_volume.set_value_no_signal(SoundManagerScript.music_volume * 100)

	if settings:
		SoundManagerScript.set_master_volume(settings.master_volume)
		$CenterContainer/VBoxContainer/MasterVolume.set_value_no_signal(settings.master_volume * 100)

		SoundManagerScript.set_sfx_volume(settings.sfx_volume)
		$CenterContainer/VBoxContainer/SFXVolume.set_value_no_signal(settings.sfx_volume * 100)

		SoundManagerScript.set_music_volume(settings.music_volume)
		$CenterContainer/VBoxContainer/MusicVolume.set_value_no_signal(settings.music_volume * 100)




	# Connect all buttons
	$CenterContainer/VBoxContainer/Play.pressed.connect(_on_play_pressed)
	$CenterContainer/VBoxContainer/Credits.pressed.connect(_on_credits_pressed)
	$CenterContainer/VBoxContainer/Tutorial.pressed.connect(_on_tutorial_pressed)

	$CenterContainer/VBoxContainer/Settings.pressed.connect(_on_settings_pressed)
	$CenterContainer/VBoxContainer/TestArticle.pressed.connect(_on_test_article_pressed)
	$CenterContainer/VBoxContainer/TestMultiplayerId.pressed.connect(_on_test_multiplayer_id_pressed)
	$CenterContainer/VBoxContainer/Fullscreen.toggled.connect(_on_fullscreen_toggled)
	$CenterContainer/VBoxContainer/Exit.pressed.connect(_on_exit_pressed)
	$CenterContainer/VBoxContainer/NormalMode.pressed.connect(_on_normal_mode_pressed)
	$CenterContainer/VBoxContainer/Multiplayer.pressed.connect(_on_multiplayer_pressed)
	$CenterContainer/VBoxContainer/FindMatch.pressed.connect(_on_find_match_pressed)
	$CenterContainer/VBoxContainer/SubmitPlaylist.pressed.connect(_on_submit_playlist_pressed)
	$CenterContainer/VBoxContainer/LobbyDummy.pressed.connect(_on_lobby_dummy_pressed)
	$CenterContainer/VBoxContainer/MultiplayerBack.pressed.connect(_on_multiplayer_back_pressed)
	$CenterContainer/VBoxContainer/HardcoreMode.pressed.connect(_on_hardcore_mode_pressed)
	$CenterContainer/VBoxContainer/Back.pressed.connect(_on_back_pressed)
	$CenterContainer/VBoxContainer/Start.pressed.connect(_on_start_pressed)
	

	
	
	
		# For checkboxes in CategorySelection
	for child in $CenterContainer/VBoxContainer.get_children():
		if child is BaseButton and not child.disabled:
			connect_hover_signals(child)

	# Set initial state - show main menu buttons, hide mode selection
	show_main_menu()
	

# Show main menu (Play, Ranking, Settings, Exit)
func show_main_menu():
	$CenterContainer/VBoxContainer/Play.visible = true
	$CenterContainer/VBoxContainer/Credits.visible = true
	$CenterContainer/VBoxContainer/Tutorial.visible = true
	$CenterContainer/VBoxContainer/Settings.visible = true
	$CenterContainer/VBoxContainer/TestArticle.visible = false
	$CenterContainer/VBoxContainer/TestMultiplayerId.visible = false
	$CenterContainer/VBoxContainer/Exit.visible = true

	# Hide mode selection buttons
	$CenterContainer/VBoxContainer/NormalMode.visible = false
	$CenterContainer/VBoxContainer/Start.visible = false
	$CenterContainer/VBoxContainer/Multiplayer.visible = false
	$CenterContainer/VBoxContainer/HardcoreMode.visible = false
	$CenterContainer/VBoxContainer/Back.visible = false
	$CenterContainer/VBoxContainer/CategorySelection.visible = false
	$CenterContainer/VBoxContainer/SearchFilter.visible = false

	# Hide multiplayer submenu buttons
	$CenterContainer/VBoxContainer/FindMatch.visible = false
	$CenterContainer/VBoxContainer/SubmitPlaylist.visible = false
	$CenterContainer/VBoxContainer/LobbyDummy.visible = false
	$CenterContainer/VBoxContainer/MultiplayerBack.visible = false

	$CenterContainer/VBoxContainer/Fullscreen.visible = false
	$CenterContainer/VBoxContainer/MasterVolumeLabel.visible = false
	$CenterContainer/VBoxContainer/MasterVolume.visible = false
	$CenterContainer/VBoxContainer/SFXVolumeLabel.visible = false
	$CenterContainer/VBoxContainer/SFXVolume.visible = false
	$CenterContainer/VBoxContainer/MusicVolumeLabel.visible = false
	$CenterContainer/VBoxContainer/MusicVolume.visible = false
	
	$MainMenuQuotes.text = get_random_menu_quote()
	

# Show game mode selection (Normal, Multiplayer, Hardcore, Back)
func show_mode_selection():
	# Hide main menu buttons
	$CenterContainer/VBoxContainer/Play.visible = false
	$CenterContainer/VBoxContainer/Credits.visible = false
	$CenterContainer/VBoxContainer/Tutorial.visible = false
	$CenterContainer/VBoxContainer/Settings.visible = false
	$CenterContainer/VBoxContainer/TestArticle.visible = false
	$CenterContainer/VBoxContainer/TestMultiplayerId.visible = false
	$CenterContainer/VBoxContainer/Exit.visible = false

	# Show mode selection buttons
	$CenterContainer/VBoxContainer/NormalMode.visible = true
	$CenterContainer/VBoxContainer/Multiplayer.visible = true
	$CenterContainer/VBoxContainer/HardcoreMode.visible = true
	$CenterContainer/VBoxContainer/Back.visible = true

	# Hide multiplayer submenu buttons (in case we got here from there)
	$CenterContainer/VBoxContainer/FindMatch.visible = false
	$CenterContainer/VBoxContainer/SubmitPlaylist.visible = false
	$CenterContainer/VBoxContainer/LobbyDummy.visible = false
	$CenterContainer/VBoxContainer/MultiplayerBack.visible = false

	$MainMenuQuotes.text = get_random_menu_quote()

# Show multiplayer submenu (Find / Host a Game, Submit Playlist, Lobby Dummy, Back)
func show_multiplayer_menu():
	$CenterContainer/VBoxContainer/NormalMode.visible = false
	$CenterContainer/VBoxContainer/Multiplayer.visible = false
	$CenterContainer/VBoxContainer/HardcoreMode.visible = false
	$CenterContainer/VBoxContainer/Back.visible = false

	$CenterContainer/VBoxContainer/FindMatch.visible = true
	$CenterContainer/VBoxContainer/SubmitPlaylist.visible = true
	$CenterContainer/VBoxContainer/LobbyDummy.visible = true
	$CenterContainer/VBoxContainer/MultiplayerBack.visible = true

	$MainMenuQuotes.text = get_random_menu_quote()

# Button handlers
func _on_play_pressed():
	show_mode_selection()
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","UI")
	

func _on_back_pressed():
	show_main_menu()
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","UI")
	%Tips.text = ""
	%Tips.visible = false

func _on_normal_mode_pressed():
	Global.run.current_game_mode = Global.run.GameMode.NORMAL
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","UI")
	$CenterContainer/VBoxContainer/Play.visible = false
	$CenterContainer/VBoxContainer/Credits.visible = false
	$CenterContainer/VBoxContainer/Tutorial.visible = false
	$CenterContainer/VBoxContainer/Settings.visible = false
	$CenterContainer/VBoxContainer/TestArticle.visible = false
	$CenterContainer/VBoxContainer/TestMultiplayerId.visible = false
	$CenterContainer/VBoxContainer/Exit.visible = false
	populate_category_scrollcontainer(Global.all_categories)
	populate_playset_scrollcontainer(Global.all_playsets)
	$CenterContainer/VBoxContainer/NormalMode.visible = false
	$CenterContainer/VBoxContainer/Multiplayer.visible = false
	$CenterContainer/VBoxContainer/HardcoreMode.visible = false
	$CenterContainer/VBoxContainer/Back.visible = true
	$CenterContainer/VBoxContainer/CategorySelection.visible = true
	$CenterContainer/VBoxContainer/Start.visible = true
	$CenterContainer/VBoxContainer/SearchFilter.visible = true
	
	$MainMenuQuotes.text = get_random_menu_quote()
	
	
	#Global.start_new_run()  # Reset the run
	#get_tree().change_scene_to_file("res://scenes/Round.tscn")
func _on_multiplayer_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	show_multiplayer_menu()

func _on_multiplayer_back_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","UI")
	show_mode_selection()

func _on_find_match_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	Global.multiplayer_lobby_entry = "browse"
	get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")

func _on_submit_playlist_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	Global.multiplayer_lobby_entry = "submit"
	get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")

func _on_lobby_dummy_pressed():
	# Debug: the regular hosting flow, except a local bot (DummyOpponent)
	# joins instead of a real player - see MultiplayerLobby's dummy_lobby.
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	Global.multiplayer_lobby_entry = "dummy"
	get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")

func _on_hardcore_mode_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	# TODO: Implement hardcore mode
	Global.start_new_run()  # Reset the run
	Global.run.current_game_mode = Global.run.GameMode.HARDCORE
	get_tree().change_scene_to_file("res://scenes/Round.tscn")

func _on_credits_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	get_tree().change_scene_to_file("res://scenes/Credits.tscn")
	

func _on_settings_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	
	$CenterContainer/VBoxContainer/MasterVolumeLabel.visible = true
	$CenterContainer/VBoxContainer/MasterVolume.visible = true
	$CenterContainer/VBoxContainer/SFXVolumeLabel.visible = true
	$CenterContainer/VBoxContainer/SFXVolume.visible = true
	$CenterContainer/VBoxContainer/MusicVolumeLabel.visible = true
	$CenterContainer/VBoxContainer/MusicVolume.visible = true
	$CenterContainer/VBoxContainer/Back.visible = true
	$CenterContainer/VBoxContainer/Fullscreen.visible = true
	$CenterContainer/VBoxContainer/TestArticle.visible = true
	$CenterContainer/VBoxContainer/TestMultiplayerId.visible = true

	$CenterContainer/VBoxContainer/Play.visible = false
	$CenterContainer/VBoxContainer/Credits.visible = false
	$CenterContainer/VBoxContainer/Settings.visible = false
	$CenterContainer/VBoxContainer/Tutorial.visible = false
	$CenterContainer/VBoxContainer/Exit.visible = false

	# Hide mode selection buttons
	$CenterContainer/VBoxContainer/NormalMode.visible = false
	$CenterContainer/VBoxContainer/Multiplayer.visible = false
	$CenterContainer/VBoxContainer/HardcoreMode.visible = false
	$CenterContainer/VBoxContainer/CategorySelection.visible = false
	
	$MainMenuQuotes.text = get_random_menu_quote()

	
	
func _on_tutorial_pressed():
	get_tree().change_scene_to_file("res://scenes/Tutorial.tscn")

func _on_test_article_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	get_tree().change_scene_to_file("res://scenes/ArticleTester.tscn")

func _on_test_multiplayer_id_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	get_tree().change_scene_to_file("res://scenes/MultiplayerIdTester.tscn")

func _on_exit_pressed():
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")

	get_tree().quit()
	
func _on_start_pressed():
	SoundManagerScript.play_music_direct("res://assets/sounds/music/music.mp3")
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/hit","SFX")
	Global.start_new_run()  # Reset the run
	get_tree().change_scene_to_file("res://scenes/Round.tscn")



func _on_any_checkbox_toggled(toggled: bool, checkbox: CheckBox):
	var category = checkbox.text.to_lower()  # Convert to lowercase first
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	
	var parent_name = checkbox.get_parent().name
	if parent_name == "CategoryList":
		if toggled:
			if not category in Global.selected_categories:
				Global.selected_categories.append(category)
		else:
			Global.selected_categories.erase(category)
	if parent_name == "PlaysetList":
		if toggled:
			if not category in Global.selected_playsets:
				Global.selected_playsets.append(category)
		else:
			Global.selected_playsets.erase(category)
	

	
	


func connect_hover_signals(button: BaseButton):
	button.mouse_entered.connect(_on_button_hover.bind(button, true))
	button.mouse_exited.connect(_on_button_hover.bind(button, false))

func _on_button_hover(button: BaseButton, is_hovered: bool):
	if is_hovered:
		# No more path strings, just call the specific random function
		SoundManagerScript.play_random_click("SFX")


func populate_category_scrollcontainer(categories: Array):
	var vbox = %ScrollContainer2.get_child(0) as VBoxContainer
	for child in vbox.get_children():
		child.queue_free()  # Clear previous
	for category in categories:
		var checkbox = CheckBox.new()
		checkbox.text = category
		checkbox.add_theme_color_override("font_color", Color.BLACK)
		checkbox.add_theme_color_override("font_pressed_color", Color.BLACK)
		checkbox.add_theme_color_override("font_focus_color", Color.BLACK)
		checkbox.toggled.connect(_on_any_checkbox_toggled.bind(checkbox))
		vbox.add_child(checkbox)

func populate_playset_scrollcontainer(playsets: Array):
	var vbox = %ScrollContainer.get_child(0) as VBoxContainer
	for child in vbox.get_children():
		child.queue_free()  # Clear previous
	for playset in playsets:
		var checkbox = CheckBox.new()
		checkbox.text = playset
		checkbox.add_theme_color_override("font_color", Color.BLACK)
		checkbox.add_theme_color_override("font_pressed_color", Color.BLACK)
		checkbox.add_theme_color_override("font_focus_color", Color.BLACK)
		checkbox.toggled.connect(_on_any_checkbox_toggled.bind(checkbox))
		vbox.add_child(checkbox)
		
func _on_fullscreen_toggled(toggled_on: bool):
	get_window().mode = Window.MODE_FULLSCREEN if toggled_on else Window.MODE_WINDOWED
	if not settings:
		settings = SaveData.new()
	settings.fullscreen = toggled_on
	ResourceSaver.save(settings, "user://scene_data.tres")

	SoundManagerScript.play_random_click("SFX")


func _sync_fullscreen_checkbox() -> void:
	var is_fullscreen = get_window().mode == Window.MODE_FULLSCREEN
	$CenterContainer/VBoxContainer/Fullscreen.set_pressed_no_signal(is_fullscreen)

	# Also persist it - fullscreen toggled via OS gesture (e.g. double-click
	# the window border) should stick on next launch just like the checkbox.
	if not settings:
		settings = SaveData.new()
	if settings.fullscreen != is_fullscreen:
		settings.fullscreen = is_fullscreen
		ResourceSaver.save(settings, "user://scene_data.tres")


func _on_master_volume_value_changed(value: float) -> void:
	SoundManagerScript.play_sound_with_pitch("res://assets/sounds/sfx/click/click5.wav","SFX")
	SoundManagerScript.set_master_volume(value / 100.0)

	if not settings:
		settings = SaveData.new()
	settings.master_volume = value / 100.0
	ResourceSaver.save(settings,"user://scene_data.tres")



func _on_sfx_volume_value_changed(value: float) -> void:
	SoundManagerScript.play_sound_with_pitch("res://assets/sounds/sfx/click/click5.wav","SFX")
	SoundManagerScript.set_sfx_volume(value / 100.0)

	if not settings:
		settings = SaveData.new()
	settings.sfx_volume = value / 100.0
	ResourceSaver.save(settings,"user://scene_data.tres")


func _on_music_volume_value_changed(value: float) -> void:
	SoundManagerScript.set_music_volume(value / 100.0)

	if not settings:
		settings = SaveData.new()
	settings.music_volume = value / 100.0
	ResourceSaver.save(settings,"user://scene_data.tres")


func _on_search_filter_text_changed(new_text: String) -> void:
	var filter_text = new_text.to_lower()
	
	# Filter Categories
	var category_vbox = %ScrollContainer2.get_child(0)
	for checkbox in category_vbox.get_children():
		if checkbox is CheckBox:
			# Show if text matches OR if search bar is empty
			checkbox.visible = filter_text == "" or filter_text in checkbox.text.to_lower()
			
	# Filter Playsets
	var playset_vbox = %ScrollContainer.get_child(0)
	for checkbox in playset_vbox.get_children():
		if checkbox is CheckBox:
			checkbox.visible = filter_text == "" or filter_text in checkbox.text.to_lower()


func _on_normal_mode_mouse_entered() -> void:
	%Tips.visible = true
	%Tips.text = "In normal mode articless are pulled from Wikipedia using the local database"


func _on_normal_mode_mouse_exited() -> void:
	%Tips.visible = false
	%Tips.text = ""


func _on_hardcore_mode_mouse_entered() -> void:
	%Tips.visible = true
	%Tips.text = "This is difficult! Articles are totally random. Good luck lol"


func _on_hardcore_mode_mouse_exited() -> void:
	%Tips.text = ""
	%Tips.visible = false


func _on_multiplayer_mouse_entered() -> void:
	%Tips.visible = true
	%Tips.text = "Play against another person online, matched via Steam"


func _on_multiplayer_mouse_exited() -> void:
	%Tips.text = ""
	%Tips.visible = false


func _on_scroll_container_mouse_entered() -> void:
	%Tips.text = "Think of Playsets as specific playlists and Categories as broad themes. Multiple selection will result in all articles being bundled up in the game"
	%Tips.visible = true

func get_random_menu_quote() -> String:
	var file_path = "res://assets/data/menu_quotes.json"
	if FileAccess.file_exists(file_path):
		var content = FileAccess.get_file_as_string(file_path)
		var json_data = JSON.parse_string(content)
		if json_data is Array:
			return json_data.pick_random().get("text", "")
	return ""
