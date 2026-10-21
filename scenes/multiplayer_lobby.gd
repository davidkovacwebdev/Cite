extends Control

class_name MultiplayerLobby

const GAME_STARTED_LOBBY_KEY := "game_started"
const ARTICLE_SEED_LOBBY_KEY := "article_seed"
const PLAYLIST_LOBBY_KEY := "playlist"
# Display name / Workshop version / file fingerprint of the host's playlist,
# so the guest can show and fetch a community playlist it doesn't have yet
# and both sides can confirm they're on the exact same file.
const PLAYLIST_NAME_LOBBY_KEY := "playlist_name"
const PLAYLIST_VERSION_LOBBY_KEY := "playlist_version"
const PLAYLIST_HASH_LOBBY_KEY := "playlist_hash"
const TITLE_LOBBY_KEY := "title"
const HOST_NAME_LOBBY_KEY := "host_name"
const LOCKED_LOBBY_KEY := "locked"
const VERSION_LOBBY_KEY := "cite_version"
# Bump whenever lobby/match messaging changes in a way older builds can't
# handle - Find / Host a Game only lists lobbies with this exact value, so players
# on different builds never end up in the same match.
const LOBBY_VERSION := "1"
const CONNECTION_TIMEOUT_SECONDS := 15.0
const PASSWORD_CHECK_TIMEOUT_SECONDS := 10.0
const BROWSER_REFRESH_SECONDS := 5.0
const MAX_CHAT_LENGTH := 200
const MIN_GAME_NAME_LENGTH := 3
const NO_IMAGE_TEXT := "No image (optional, PNG/JPG under 1 MB)"

# Lobby chat carries both player chat and the password check - every message
# is "<type>|<payload>" so control messages never show up as chat.
const MSG_CHAT := "chat"
const MSG_PASSWORD := "pw"
const MSG_KICK := "kick"
const MSG_PLAYLIST_READY := "plready"  # guest -> host, payload = guest's playlist hash

const HOST_CHAT_COLOR := "#8b9cff"
const GUEST_CHAT_COLOR := "#fb923c"
# Find / Host a Game table: column titles and their width ratios, shared by
# the header and every row so they line up. The Join button column is fixed.
const LOBBY_COLUMNS := [["Game", 3.0], ["Host", 2.0], ["Playlist", 2.5], ["Access", 1.2]]
const LOBBY_JOIN_COLUMN_WIDTH := 100
const LOBBY_ROW_COLORS := [Color(0.106, 0.114, 0.141, 1), Color(0.13, 0.138, 0.168, 1)]
const LOBBY_HEADER_COLOR := Color(0.62, 0.64, 0.7)
const LOBBY_LOCKED_COLOR := Color(1.0, 0.78, 0.36)
const LOBBY_OPEN_COLOR := Color(0.49, 0.88, 0.63)

# Dummy lobby (Global.multiplayer_lobby_entry == "dummy"): the regular host
# flow, but entirely local - no Steam lobby is created, and the guest is a
# bot that joins after a moment and chats. These ids stand in for the lobby
# and bot Steam IDs - real ones are never this small.
const DUMMY_LOBBY_ID := 1
const DUMMY_GUEST_ID := 1
const DUMMY_JOIN_DELAY_SECONDS := 2.0

enum Visibility { PUBLIC, PRIVATE }

var lobby_id: int = 0
var is_host: bool = false
var match_starting: bool = false
var connection_timeout_timer: SceneTreeTimer

var host_id: int = 0
var guest_id: int = 0
var pending_avatars: Dictionary = {}  # steam_id -> TextureRect awaiting avatar_image_loaded

# IDs of every playlist this player has (Global.get_available_playlist_ids):
# built-in filenames plus "ws_<file_id>" community ones. Shown by
# %PlaylistPicker (host form) and %PlaylistList (room), both PlaylistSelector.
var available_playlists: Array = []
# Guest: the host's playlist when this player doesn't have it yet, as
# {playlist_id: host's display name}, so the room can still show it.
var lobby_only_playlists: Dictionary = {}

# Host form values, held from Create until lobby_created hands back the id.
var host_game_name: String = ""
var host_password: String = ""

# Host only: hash of this lobby's password, "" when there is none. Kept out
# of lobby data on purpose - anyone browsing can read that - so the guest
# sends their hash over lobby chat on joining and the host checks it here,
# kicking them if it's wrong (or never arrives).
var password_hash: String = ""
var guest_verified: bool = false

# Guest only: password typed for the lobby being joined, and which lobby the
# password prompt is currently asking about.
var pending_password: String = ""
var password_prompt_lobby_id: int = 0

var browser_refresh_timer: Timer
# Last lobby list from Steam - kept so the search box and playlist filter can
# re-filter it without waiting for the next refresh.
var browser_lobby_ids: Array = []

var dummy_lobby: bool = false
var dummy_chat_timer: Timer

# Host: hash of the playlist the guest last said it has ready. Play only
# unlocks once it matches the host's own.
var guest_playlist_hash: String = ""
# Guest: the hash last reported to the host, and the Workshop item being
# downloaded for this lobby (0 = none).
var reported_playlist_hash: String = ""
var downloading_file_id: int = 0

# Playlist picked on the Submit Playlist screen, already validated by
# Workshop.validate_playlist_file() and waiting for Upload.
var submit_playlist: Dictionary = {}
var submit_preview_path: String = ""  # optional preview image, "" = none
var uploaded_file_id: int = 0


func _ready() -> void:
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_message.connect(_on_lobby_message)
	Steam.join_requested.connect(_on_join_requested)
	Steam.avatar_image_loaded.connect(_on_avatar_image_loaded)

	_load_available_playlists()
	%PlaylistList.playlist_selected.connect(_on_playlist_item_selected)

	%VisibilityPicker.add_item("Public - listed in the game list", Visibility.PUBLIC)
	%VisibilityPicker.add_item("Private - join by code or invite", Visibility.PRIVATE)
	%VisibilityPicker.item_selected.connect(_on_visibility_selected)

	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%CreateButton.pressed.connect(_on_create_pressed)
	%GameNameInput.text_changed.connect(func(_text): _update_create_button())
	%GameNameInput.text_submitted.connect(func(_text): _on_create_pressed())
	%ConnectButton.pressed.connect(_on_connect_pressed)
	%LobbyCodeInput.text_submitted.connect(func(_text): _on_connect_pressed())
	%PasswordSubmitButton.pressed.connect(_on_password_submit_pressed)
	%PasswordPromptInput.text_submitted.connect(func(_text): _on_password_submit_pressed())
	%InviteButton.pressed.connect(_on_invite_pressed)
	%CopyCodeButton.pressed.connect(_on_copy_code_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	%RoomBackButton.pressed.connect(_on_room_back_pressed)
	%PlayButton.pressed.connect(_on_play_pressed)
	%RefreshButton.pressed.connect(_on_refresh_pressed)
	%BrowserSearch.text_changed.connect(func(_text): _rebuild_lobby_rows())
	%BrowserPlaylistFilter.item_selected.connect(func(_index): _rebuild_lobby_rows())
	%HostBackButton.pressed.connect(_on_back_pressed)
	_build_lobby_header()
	%BrowserHostButton.pressed.connect(_on_host_pressed)
	%BrowserJoinButton.pressed.connect(_on_join_pressed)
	%BrowserBackButton.pressed.connect(_go_to_main_menu)
	%ChatSendButton.pressed.connect(_send_chat)
	%ChatInput.text_submitted.connect(func(_text): _send_chat())
	%SubmitPlaylistButton.pressed.connect(_show_submit_panel)
	%ChooseFileButton.pressed.connect(func(): %PlaylistFileDialog.popup_centered_ratio(0.6))
	%PlaylistFileDialog.file_selected.connect(_on_playlist_file_selected)
	%ChooseImageButton.pressed.connect(func(): %PreviewImageDialog.popup_centered_ratio(0.6))
	%PreviewImageDialog.file_selected.connect(_on_preview_image_selected)
	%WorkshopTitleInput.text_changed.connect(func(_text): _update_upload_button())
	%UploadButton.pressed.connect(_on_upload_pressed)
	%ViewItemButton.pressed.connect(func(): Workshop.open_item_page(uploaded_file_id))
	%LegalAgreementButton.pressed.connect(Workshop.open_legal_agreement)
	Workshop.upload_progress.connect(_on_upload_progress)
	Workshop.upload_finished.connect(_on_upload_finished)
	Workshop.community_playlists_changed.connect(_on_community_playlists_changed)
	Workshop.playlist_ready.connect(_on_workshop_playlist_ready)
	Workshop.refresh_community_playlists()

	browser_refresh_timer = Timer.new()
	browser_refresh_timer.wait_time = BROWSER_REFRESH_SECONDS
	browser_refresh_timer.timeout.connect(_request_lobby_list)
	add_child(browser_refresh_timer)

	dummy_lobby = Global.multiplayer_lobby_entry == "dummy"
	dummy_chat_timer = Timer.new()
	dummy_chat_timer.wait_time = DummyOpponent.CHAT_INTERVAL_SECONDS
	dummy_chat_timer.timeout.connect(func(): _add_player_chat(DUMMY_GUEST_ID, DummyOpponent.random_chat_line()))
	add_child(dummy_chat_timer)

	_show_entry_screen()


# --- Screens ---------------------------------------------------------------

func _show_entry_screen(message: String = "") -> void:
	if dummy_lobby:
		_show_host_form()
	elif Global.multiplayer_lobby_entry == "submit":
		_show_submit_panel()
	elif Global.multiplayer_lobby_entry == "browse":
		_show_browser()
	else:
		_show_choice_state()
	if not message.is_empty():
		_set_status(message)


func _show_screen(screen: Control) -> void:
	%CenterContainer.visible = screen == %CenterContainer
	%BrowserContainer.visible = screen == %BrowserContainer
	%RoomContainer.visible = screen == %RoomContainer
	if screen == %BrowserContainer:
		browser_refresh_timer.start()
	else:
		browser_refresh_timer.stop()


func _show_center_panel(panel: Control) -> void:
	_show_screen(%CenterContainer)
	for candidate in [%ChoicePanel, %HostForm, %CodePanel, %PasswordPanel, %SubmitPanel]:
		candidate.visible = candidate == panel
	# The host form is tall enough that it carries its own Back next to Create.
	%BackButton.visible = panel != %HostForm


func _show_choice_state() -> void:
	_show_center_panel(%ChoicePanel)
	_set_status("Host a public or private game, or connect to a private one with its code.")


func _show_host_form() -> void:
	_show_center_panel(%HostForm)
	_update_create_button()
	%PasswordInput.clear()
	_on_visibility_selected(%VisibilityPicker.selected)
	%GameNameInput.grab_focus()
	if dummy_lobby:
		# Always private, so visibility/password don't apply.
		%VisibilityPicker.visible = false
		%PasswordInput.visible = false
		_set_status("Dummy game - a bot joins once it's created. The game name needs at least %d characters." % MIN_GAME_NAME_LENGTH)
		return
	_set_status("Set up your game. The game name needs at least %d characters." % MIN_GAME_NAME_LENGTH)


func _game_name_valid() -> bool:
	return %GameNameInput.text.strip_edges().length() >= MIN_GAME_NAME_LENGTH


func _update_create_button() -> void:
	%CreateButton.disabled = not _game_name_valid()


func _show_code_panel() -> void:
	_show_center_panel(%CodePanel)
	%LobbyCodeInput.grab_focus()
	_set_status("Enter the lobby code your opponent shared with you.")


func _show_password_prompt(target_lobby_id: int) -> void:
	password_prompt_lobby_id = target_lobby_id
	_show_center_panel(%PasswordPanel)
	%PasswordPromptInput.clear()
	%PasswordPromptInput.grab_focus()
	_set_status("This game is password protected.")


func _show_browser() -> void:
	_show_screen(%BrowserContainer)
	_set_status("")
	_request_lobby_list()


func _set_status(text: String) -> void:
	%StatusLabel.text = text
	%BrowserStatus.text = text
	%RoomStatus.text = text


func _on_back_pressed() -> void:
	if Workshop.is_uploading:
		return
	# Back from whichever screen Main opened us on goes straight to the menu.
	if %ChoicePanel.visible or (dummy_lobby and %HostForm.visible) \
			or (Global.multiplayer_lobby_entry == "submit" and %SubmitPanel.visible):
		_go_to_main_menu()
	else:
		_show_entry_screen()


# Back to Main's Multiplayer submenu, where every way into this scene starts.
func _go_to_main_menu() -> void:
	_leave_lobby()
	Global.return_to_multiplayer_menu = true
	get_tree().change_scene_to_file("res://Main/Main.tscn")


# --- Submit playlist to Workshop -----------------------------------------

func _show_submit_panel() -> void:
	_show_center_panel(%SubmitPanel)
	submit_playlist = {}
	uploaded_file_id = 0
	%WorkshopTitleInput.clear()
	%WorkshopDescriptionInput.text = ""
	%ChosenFileLabel.text = "No file chosen"
	submit_preview_path = ""
	%ChosenImageLabel.text = NO_IMAGE_TEXT
	%UploadProgress.visible = false
	%ViewItemButton.visible = false
	%LegalAgreementButton.visible = false
	_set_submit_inputs_enabled(true)
	%WorkshopTitleInput.grab_focus()
	_set_status("Share a playlist: a .json file of {\"Article Title\": wikipedia_page_id}.")


func _on_playlist_file_selected(path: String) -> void:
	var check = Workshop.validate_playlist_file(path)
	if not check.ok:
		submit_playlist = {}
		%ChosenFileLabel.text = "No file chosen"
		_set_status(check.error)
		_update_upload_button()
		return

	submit_playlist = check.playlist
	%ChosenFileLabel.text = "%s (%d articles)" % [path.get_file(), submit_playlist.size()]
	if %WorkshopTitleInput.text.strip_edges().is_empty():
		%WorkshopTitleInput.text = path.get_file().get_basename().replace("_", " ").capitalize()
	_set_status("Playlist looks good. Give it a name and upload it.")
	_update_upload_button()


func _on_preview_image_selected(path: String) -> void:
	var check = Workshop.validate_preview_image(path)
	if not check.ok:
		submit_preview_path = ""
		%ChosenImageLabel.text = NO_IMAGE_TEXT
		_set_status(check.error)
		return
	submit_preview_path = path
	%ChosenImageLabel.text = path.get_file()
	_set_status("Image added.")


func _update_upload_button() -> void:
	%UploadButton.disabled = Workshop.is_uploading or submit_playlist.is_empty() \
		or %WorkshopTitleInput.text.strip_edges().is_empty()


func _set_submit_inputs_enabled(enabled: bool) -> void:
	%WorkshopTitleInput.editable = enabled
	%WorkshopDescriptionInput.editable = enabled
	%ChooseFileButton.disabled = not enabled
	%ChooseImageButton.disabled = not enabled
	%BackButton.disabled = not enabled
	_update_upload_button()


func _on_upload_pressed() -> void:
	if submit_playlist.is_empty():
		return
	%ViewItemButton.visible = false
	%LegalAgreementButton.visible = false
	%UploadProgress.value = 0.0
	%UploadProgress.visible = true
	Workshop.upload_playlist(submit_playlist, %WorkshopTitleInput.text, %WorkshopDescriptionInput.text, submit_preview_path)
	_set_submit_inputs_enabled(not Workshop.is_uploading)


func _on_upload_progress(stage: String, fraction: float) -> void:
	%UploadProgress.value = fraction
	_set_status(stage)


func _on_upload_finished(success: bool, file_id: int, message: String, needs_legal_agreement: bool) -> void:
	_set_submit_inputs_enabled(true)
	%UploadProgress.visible = false
	if not success:
		_set_status(message)
		return

	uploaded_file_id = file_id
	submit_playlist = {}
	%ChosenFileLabel.text = "No file chosen"
	submit_preview_path = ""
	%ChosenImageLabel.text = NO_IMAGE_TEXT
	_update_upload_button()
	%ViewItemButton.visible = true
	%LegalAgreementButton.visible = needs_legal_agreement
	_set_status(message)


# --- Hosting ---------------------------------------------------------------

func _on_host_pressed() -> void:
	_show_host_form()


func _on_visibility_selected(index: int) -> void:
	# Private games are already gated by the lobby code, so a password only
	# makes sense for public ones.
	%PasswordInput.visible = %VisibilityPicker.get_item_id(index) == Visibility.PUBLIC


func _on_create_pressed() -> void:
	if %CreateButton.disabled:
		return
	if not _game_name_valid():
		_set_status("The game name needs at least %d characters." % MIN_GAME_NAME_LENGTH)
		%GameNameInput.grab_focus()
		return
	if %PlaylistPicker.get_selected_id().is_empty():
		_set_status("Pick a playlist first.")
		return
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")

	var is_public = %VisibilityPicker.get_selected_id() == Visibility.PUBLIC
	host_game_name = %GameNameInput.text.strip_edges()
	host_password = %PasswordInput.text if is_public else ""
	Global.multiplayer_playlist_id = %PlaylistPicker.get_selected_id()

	if dummy_lobby:
		_create_dummy_lobby()
		return
	%CreateButton.disabled = true
	_set_status("Creating game...")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC if is_public else Steam.LOBBY_TYPE_PRIVATE, 2)


func _on_lobby_created(connect: int, new_lobby_id: int) -> void:
	_update_create_button()
	if connect != Steam.RESULT_OK:
		_set_status("Failed to create the game (error %d)." % connect)
		return

	lobby_id = new_lobby_id
	is_host = true
	host_id = Steam.getSteamID()
	guest_id = 0
	guest_verified = false
	password_hash = "" if host_password.is_empty() else _hash_password(host_password, lobby_id)
	host_password = ""

	Steam.setLobbyData(lobby_id, "name", host_game_name)
	Steam.setLobbyData(lobby_id, "game", "Cite")
	Steam.setLobbyData(lobby_id, VERSION_LOBBY_KEY, LOBBY_VERSION)
	Steam.setLobbyData(lobby_id, TITLE_LOBBY_KEY, host_game_name)
	Steam.setLobbyData(lobby_id, HOST_NAME_LOBBY_KEY, Steam.getPersonaName())
	Steam.setLobbyData(lobby_id, LOCKED_LOBBY_KEY, "0" if password_hash.is_empty() else "1")
	# The room's list starts on what the host form picked.
	%PlaylistList.select(Global.multiplayer_playlist_id)
	_publish_playlist(Global.multiplayer_playlist_id)
	Steam.setLobbyData(lobby_id, GAME_STARTED_LOBBY_KEY, "0")

	%ChatLog.clear()
	_show_room()
	if %VisibilityPicker.get_selected_id() == Visibility.PUBLIC:
		_set_status("Your game is listed publicly. Waiting for an opponent...")
	else:
		_set_status("Private game - lobby code: %d. Copy it or invite a friend." % lobby_id)


func _hash_password(password: String, for_lobby_id: int) -> String:
	# Salted with the lobby id so the same password hashes differently per game.
	return (str(for_lobby_id) + ":" + password).sha256_text()


func _on_guest_entered(member_id: int) -> void:
	guest_id = member_id
	guest_verified = password_hash.is_empty()
	if guest_verified:
		_add_system_chat("%s joined." % Steam.getFriendPersonaName(guest_id))
	else:
		get_tree().create_timer(PASSWORD_CHECK_TIMEOUT_SECONDS).timeout.connect(_on_password_check_timeout.bind(member_id))
	_update_room()


func _create_dummy_lobby() -> void:
	lobby_id = DUMMY_LOBBY_ID
	is_host = true
	host_id = Steam.getSteamID()
	guest_id = 0
	guest_verified = false
	%PlaylistList.select(Global.multiplayer_playlist_id)
	%ChatLog.clear()
	_show_room()
	_set_status("Waiting for the bot to join...")
	get_tree().create_timer(DUMMY_JOIN_DELAY_SECONDS).timeout.connect(_on_dummy_guest_joined)


func _on_dummy_guest_joined() -> void:
	if lobby_id != DUMMY_LOBBY_ID or guest_id != 0:
		return  # host left before the bot showed up
	guest_id = DUMMY_GUEST_ID
	guest_verified = true
	_add_system_chat("%s joined." % _member_name(guest_id))
	_set_status("")
	dummy_chat_timer.start()
	_update_room()


func _member_name(steam_id: int) -> String:
	if dummy_lobby and steam_id == DUMMY_GUEST_ID:
		return DummyOpponent.BOT_NAME
	if steam_id == Steam.getSteamID():
		return Global.get_own_name()  # the friends lookup isn't reliable for yourself
	return Steam.getFriendPersonaName(steam_id)


func _on_guest_left() -> void:
	if guest_verified:
		_add_system_chat("%s left." % Steam.getFriendPersonaName(guest_id))
	guest_id = 0
	guest_verified = false
	guest_playlist_hash = ""
	%GuestAvatar.texture = null
	_update_room()


func _on_password_check_timeout(for_guest: int) -> void:
	if lobby_id != 0 and guest_id == for_guest and not guest_verified:
		_kick_guest()


func _kick_guest() -> void:
	# Steam has no host-side kick for lobbies, so this asks the guest's client
	# to leave. Their slot frees up once they do (_on_guest_left).
	_send_lobby_message(MSG_KICK, str(guest_id))


# --- Joining ---------------------------------------------------------------

func _on_join_pressed() -> void:
	_show_code_panel()


func _on_connect_pressed() -> void:
	var code = %LobbyCodeInput.text.strip_edges()
	if not code.is_valid_int():
		_set_status("That doesn't look like a valid lobby code.")
		return
	_join_lobby(code.to_int())


func _on_password_submit_pressed() -> void:
	var password = %PasswordPromptInput.text
	if password.is_empty():
		return
	_join_lobby(password_prompt_lobby_id, password)


func _on_join_requested(requested_lobby_id: int, _friend_id: int) -> void:
	# Fired when the player accepts a Steam invite / clicks "Join Game" on a
	# friend from the Steam client overlay while this scene is active.
	_join_lobby(requested_lobby_id)


func _join_lobby(target_lobby_id: int, password: String = "") -> void:
	if lobby_id != 0:
		return
	pending_password = password
	_set_status("Joining game...")
	Steam.joinLobby(target_lobby_id)


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if is_host:
		# Steam fires this for anyone who enters a lobby, including the host
		# entering the lobby they just created - _on_lobby_created already
		# fully set up hosting, so there's nothing left to do here.
		return

	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		pending_password = ""
		_set_status(_join_failure_text(response))
		return

	if Steam.getLobbyData(joined_lobby_id, LOCKED_LOBBY_KEY) == "1" and pending_password.is_empty():
		# Reached a locked game through a code or invite, which skips the
		# browser's password prompt - step back out, ask, then rejoin.
		Steam.leaveLobby(joined_lobby_id)
		_show_password_prompt(joined_lobby_id)
		return

	lobby_id = joined_lobby_id
	host_id = Steam.getLobbyOwner(lobby_id)
	guest_id = Steam.getSteamID()
	%ChatLog.clear()
	if not pending_password.is_empty():
		_send_lobby_message(MSG_PASSWORD, _hash_password(pending_password, lobby_id))
		pending_password = ""
	_show_room()
	_set_status("")


func _join_failure_text(response: int) -> String:
	match response:
		Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
			return "That game is already full."
		Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
			return "That game doesn't exist anymore."
		_:
			return "Couldn't join that game (code %d)." % response


func _on_host_left() -> void:
	_leave_lobby()
	_show_entry_screen("The host left the game.")


func _leave_lobby() -> void:
	if lobby_id != 0 and not dummy_lobby:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	dummy_chat_timer.stop()
	is_host = false
	host_id = 0
	guest_id = 0
	guest_verified = false
	password_hash = ""
	pending_password = ""
	guest_playlist_hash = ""
	reported_playlist_hash = ""
	downloading_file_id = 0
	if not lobby_only_playlists.is_empty():
		lobby_only_playlists.clear()
		_load_available_playlists()


# --- Lobby events ----------------------------------------------------------

func _on_lobby_chat_update(updated_lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if updated_lobby_id != lobby_id:
		return
	var left_states = Steam.CHAT_MEMBER_STATE_CHANGE_LEFT | Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED \
		| Steam.CHAT_MEMBER_STATE_CHANGE_KICKED | Steam.CHAT_MEMBER_STATE_CHANGE_BANNED
	var has_left = (chat_state & left_states) != 0

	if is_host:
		if (chat_state & Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED) != 0 and changed_id != host_id:
			_on_guest_entered(changed_id)
		elif has_left and changed_id == guest_id:
			_on_guest_left()
	elif has_left and changed_id == host_id and not match_starting:
		# Mid-handshake the connection timeout already covers this.
		_on_host_left()


func _on_lobby_data_update(_success: int, updated_lobby_id: int, _member_id: int) -> void:
	if updated_lobby_id != lobby_id or is_host:
		return
	_apply_playlist_from_lobby()
	if not match_starting and Steam.getLobbyData(lobby_id, GAME_STARTED_LOBBY_KEY) == "1":
		_join_match()


func _on_lobby_message(message_lobby_id: int, user: int, message: String, _chat_type: int) -> void:
	if message_lobby_id != lobby_id:
		return
	var separator = message.find("|")
	if separator == -1:
		return
	var type = message.substr(0, separator)
	var payload = message.substr(separator + 1)

	match type:
		MSG_CHAT:
			# Chat from someone who hasn't passed the password check yet is
			# dropped, so a wrong-password joiner can't spam the room.
			if is_host and user == guest_id and not guest_verified:
				return
			_add_player_chat(user, payload)
		MSG_PASSWORD:
			if not is_host or user != guest_id or guest_verified:
				return
			if payload == password_hash:
				guest_verified = true
				_add_system_chat("%s joined." % Steam.getFriendPersonaName(guest_id))
				_update_room()
			else:
				_kick_guest()
		MSG_PLAYLIST_READY:
			if is_host and user == guest_id:
				guest_playlist_hash = payload
				_update_play_button()
		MSG_KICK:
			if not is_host and user == host_id and payload == str(Steam.getSteamID()):
				_leave_lobby()
				_show_entry_screen("Wrong password.")


func _send_lobby_message(type: String, payload: String) -> void:
	Steam.sendLobbyChatMsg(lobby_id, type + "|" + payload)


# --- Browser ---------------------------------------------------------------

func _on_refresh_pressed() -> void:
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	_request_lobby_list()


func _request_lobby_list() -> void:
	# Steam only searches nearby regions by default - worldwide or most games
	# would never show up.
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game", "Cite", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(VERSION_LOBBY_KEY, LOBBY_VERSION, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(GAME_STARTED_LOBBY_KEY, "0", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.addRequestLobbyListResultCountFilter(100)
	Steam.requestLobbyList()


func _on_lobby_match_list(lobbies: Array) -> void:
	if not %BrowserContainer.visible:
		return
	browser_lobby_ids = lobbies
	_rebuild_lobby_rows()


func _rebuild_lobby_rows() -> void:
	for row in %LobbyRows.get_children():
		row.queue_free()
	var query = %BrowserSearch.text.strip_edges().to_lower()
	var playlist_filter = ""
	if %BrowserPlaylistFilter.selected > 0:
		playlist_filter = str(%BrowserPlaylistFilter.get_item_metadata(%BrowserPlaylistFilter.selected))
	var shown = 0
	for found_id in browser_lobby_ids:
		var info = _lobby_row_info(found_id)
		if not playlist_filter.is_empty() and info.playlist_id != playlist_filter:
			continue
		if not query.is_empty() and not (query in info.title.to_lower() or query in info.host.to_lower() or query in info.playlist.to_lower()):
			continue
		%LobbyRows.add_child(_build_lobby_row(found_id, info, shown))
		shown += 1
	%BrowserEmptyLabel.visible = shown == 0
	if browser_lobby_ids.is_empty():
		%BrowserEmptyLabel.text = "No games are being hosted right now. Host one below!"
	else:
		%BrowserEmptyLabel.text = "No games match your search."


func _lobby_row_info(found_id: int) -> Dictionary:
	var playlist_id = Steam.getLobbyData(found_id, PLAYLIST_LOBBY_KEY)
	return {
		"title": Steam.getLobbyData(found_id, TITLE_LOBBY_KEY),
		"host": Steam.getLobbyData(found_id, HOST_NAME_LOBBY_KEY),
		"playlist_id": playlist_id,
		"playlist": _lobby_playlist_name(found_id, playlist_id),
		"locked": Steam.getLobbyData(found_id, LOCKED_LOBBY_KEY) == "1",
	}


# "All playlists" plus every playlist this player has, rebuilt alongside the
# pickers so new community playlists show up; keeps the current choice.
func _update_browser_playlist_filter() -> void:
	var picker: OptionButton = %BrowserPlaylistFilter
	var current = "" if picker.selected <= 0 else str(picker.get_item_metadata(picker.selected))
	picker.clear()
	picker.add_item("All playlists")
	picker.set_item_metadata(0, "")
	var names = {}
	for playlist_id in available_playlists:
		names[playlist_id] = _playlist_display_name(playlist_id)
	var sorted_ids = available_playlists.duplicate()
	sorted_ids.sort_custom(func(a, b): return names[a].naturalnocasecmp_to(names[b]) < 0)
	for playlist_id in sorted_ids:
		picker.add_item(names[playlist_id])
		picker.set_item_metadata(picker.item_count - 1, playlist_id)
		if playlist_id == current:
			picker.select(picker.item_count - 1)
	if picker.selected < 0:
		picker.select(0)


func _build_lobby_header() -> void:
	for column in LOBBY_COLUMNS:
		%LobbyHeader.add_child(_make_lobby_cell(column[0].to_upper(), column[1], LOBBY_HEADER_COLOR, 15))
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(LOBBY_JOIN_COLUMN_WIDTH, 0)
	%LobbyHeader.add_child(spacer)


# A plain Label, not RichTextLabel - host name and title are typed by other
# players, so they must never be parsed as BBCode.
func _make_lobby_cell(text: String, ratio: float, color: Color, font_size: int = 18) -> Label:
	var label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = ratio
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _build_lobby_row(found_id: int, info: Dictionary, index: int) -> Control:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = LOBBY_ROW_COLORS[index % LOBBY_ROW_COLORS.size()]
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var white = Color(0.93, 0.94, 0.96)
	row.add_child(_make_lobby_cell(info.title, LOBBY_COLUMNS[0][1], white))
	row.add_child(_make_lobby_cell(info.host, LOBBY_COLUMNS[1][1], Color(HOST_CHAT_COLOR)))
	row.add_child(_make_lobby_cell(info.playlist, LOBBY_COLUMNS[2][1], white))
	row.add_child(_make_lobby_cell("Password" if info.locked else "Open", LOBBY_COLUMNS[3][1],
		LOBBY_LOCKED_COLOR if info.locked else LOBBY_OPEN_COLOR))

	var join_button = Button.new()
	join_button.text = "Join"
	join_button.custom_minimum_size = Vector2(LOBBY_JOIN_COLUMN_WIDTH, 0)
	join_button.pressed.connect(_on_browser_join_pressed.bind(found_id, info.locked))
	row.add_child(join_button)
	return panel


func _on_browser_join_pressed(target_lobby_id: int, locked: bool) -> void:
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	if locked:
		_show_password_prompt(target_lobby_id)
	else:
		_join_lobby(target_lobby_id)


# --- Room ------------------------------------------------------------------

func _show_room() -> void:
	_show_screen(%RoomContainer)
	_update_room()


func _update_room() -> void:
	var host_name = _member_name(host_id)
	var title = host_game_name if dummy_lobby else Steam.getLobbyData(lobby_id, TITLE_LOBBY_KEY)
	%RoomTitle.text = "%s's game - %s" % [host_name, title]

	%HostName.text = host_name
	%HostName.add_theme_color_override("font_color", Color(HOST_CHAT_COLOR))
	_load_avatar(host_id, %HostAvatar)

	# Same colors as their names in the lobby chat - only once someone's there.
	var guest_named = guest_id != 0 and not (is_host and not guest_verified)
	if guest_named:
		%GuestName.add_theme_color_override("font_color", Color(GUEST_CHAT_COLOR))
	else:
		%GuestName.remove_theme_color_override("font_color")
	if guest_id == 0:
		%GuestName.text = "Waiting for opponent..."
		%GuestAvatar.texture = null
	elif is_host and not guest_verified:
		%GuestName.text = "Checking password..."
		%GuestAvatar.texture = null
	elif dummy_lobby:
		%GuestName.text = _member_name(guest_id)
		%GuestAvatar.texture = null
	else:
		%GuestName.text = Steam.getFriendPersonaName(guest_id)
		_load_avatar(guest_id, %GuestAvatar)

	# The guest can see but not change the playlist.
	%PlaylistList.set_interactive(is_host)
	if is_host:
		_sync_playlist_to_lobby()
	else:
		_apply_playlist_from_lobby()

	%PlayButton.visible = is_host
	_update_play_button()
	%InviteButton.visible = is_host and not dummy_lobby
	%CopyCodeButton.visible = is_host and not dummy_lobby


func _update_play_button() -> void:
	if not is_host:
		return
	if dummy_lobby and guest_id != 0:
		guest_playlist_hash = _selected_playlist_hash()  # the bot has every playlist
	var guest_ready = guest_id != 0 and guest_verified
	var playlist_matches = not guest_playlist_hash.is_empty() and guest_playlist_hash == _selected_playlist_hash()
	%PlayButton.disabled = not guest_ready or not playlist_matches or match_starting
	if guest_ready and not playlist_matches and not match_starting:
		%PlayButton.tooltip_text = "Waiting for your opponent to get the playlist..."
	else:
		%PlayButton.tooltip_text = ""


func _selected_playlist_hash() -> String:
	var playlist_id = %PlaylistList.get_selected_id()
	return "" if playlist_id.is_empty() else Global.get_playlist_hash(playlist_id)


func _on_room_back_pressed() -> void:
	if match_starting:
		return
	_leave_lobby()
	_show_entry_screen()


func _send_chat() -> void:
	var text = %ChatInput.text.strip_edges().left(MAX_CHAT_LENGTH)
	if text.is_empty() or lobby_id == 0:
		return
	if dummy_lobby:
		_add_player_chat(host_id, text)  # no Steam lobby to echo it back
		%ChatInput.clear()
		%ChatInput.grab_focus()
		return
	# Steam echoes lobby chat back to the sender too, so the message is added
	# to the log when it arrives in _on_lobby_message, not here.
	_send_lobby_message(MSG_CHAT, text)
	%ChatInput.clear()
	%ChatInput.grab_focus()  # keep typing - also after clicking Send


func _add_player_chat(user: int, text: String) -> void:
	var color = HOST_CHAT_COLOR if user == host_id else GUEST_CHAT_COLOR
	%ChatLog.append_text("[color=%s][b]%s:[/b][/color] %s\n" % [
		color,
		_escape_bbcode(_member_name(user)),
		_escape_bbcode(text.left(MAX_CHAT_LENGTH)),
	])


func _add_system_chat(text: String) -> void:
	%ChatLog.append_text("[i]%s[/i]\n" % _escape_bbcode(text))


func _escape_bbcode(text: String) -> String:
	# Player names and messages are typed by other people - without this,
	# "[url]" / "[font_size=500]" etc. would be rendered by ChatLog.
	return text.replace("[", "[lb]")


# --- Playlists -------------------------------------------------------------

# Built-in playlists (drop a new .json in Global.MULTIPLAYER_PLAYLIST_FOLDER)
# and approved Workshop ones - both show up here with no code changes.
# Rebuilt whenever Workshop finishes refreshing, keeping whatever was
# selected.
func _load_available_playlists() -> void:
	available_playlists = Global.get_available_playlist_ids()
	var form_choice = %PlaylistPicker.get_selected_id()
	var room_choice = %PlaylistList.get_selected_id()
	%PlaylistPicker.set_playlists(available_playlists)
	%PlaylistList.set_playlists(available_playlists, lobby_only_playlists)
	%PlaylistPicker.select(form_choice if not form_choice.is_empty() else _default_playlist_id())
	%PlaylistList.select(room_choice if not room_choice.is_empty() else _default_playlist_id())
	_update_browser_playlist_filter()
	if %BrowserContainer.visible:
		_rebuild_lobby_rows()


func _default_playlist_id() -> String:
	if Global.multiplayer_playlist_id in available_playlists:
		return Global.multiplayer_playlist_id
	return available_playlists[0] if not available_playlists.is_empty() else ""


func _playlist_display_name(playlist_id: String) -> String:
	return Global.get_playlist_display_name(playlist_id)


# The host's own name for the playlist wins for community ones, since this
# player may not have that playlist (or its title) yet.
func _lobby_playlist_name(for_lobby_id: int, playlist_id: String) -> String:
	var lobby_name = Steam.getLobbyData(for_lobby_id, PLAYLIST_NAME_LOBBY_KEY)
	if Workshop.is_community_id(playlist_id) and not lobby_name.is_empty():
		return lobby_name
	return _playlist_display_name(playlist_id)


func _on_community_playlists_changed() -> void:
	_load_available_playlists()
	if lobby_id == 0:
		return
	if is_host:
		_sync_playlist_to_lobby()
	else:
		_apply_playlist_from_lobby()


func _on_playlist_item_selected(_playlist_id: String) -> void:
	if not is_host:
		return
	_sync_playlist_to_lobby()


func _sync_playlist_to_lobby() -> void:
	var playlist_id = %PlaylistList.get_selected_id()
	if playlist_id.is_empty():
		return
	_publish_playlist(playlist_id)


# Host: everything the guest needs to show, fetch and verify the playlist.
func _publish_playlist(playlist_id: String) -> void:
	if dummy_lobby:
		_update_play_button()
		return
	var version = 0
	if Workshop.is_community_id(playlist_id):
		version = Workshop.get_time_updated(Workshop.file_id_of(playlist_id))
	Steam.setLobbyData(lobby_id, PLAYLIST_LOBBY_KEY, playlist_id)
	Steam.setLobbyData(lobby_id, PLAYLIST_NAME_LOBBY_KEY, _playlist_display_name(playlist_id))
	Steam.setLobbyData(lobby_id, PLAYLIST_VERSION_LOBBY_KEY, str(version))
	Steam.setLobbyData(lobby_id, PLAYLIST_HASH_LOBBY_KEY, Global.get_playlist_hash(playlist_id))
	_update_play_button()


func _apply_playlist_from_lobby() -> void:
	var playlist_id = Steam.getLobbyData(lobby_id, PLAYLIST_LOBBY_KEY)
	if playlist_id.is_empty():
		return
	if playlist_id not in available_playlists and not lobby_only_playlists.has(playlist_id):
		# A community playlist this player hasn't got yet - list it under the
		# host's name for it while it downloads.
		lobby_only_playlists[playlist_id] = _lobby_playlist_name(lobby_id, playlist_id).trim_suffix(" (Community)")
		%PlaylistList.set_playlists(available_playlists, lobby_only_playlists)
	if %PlaylistList.get_selected_id() != playlist_id:
		%PlaylistList.select(playlist_id)
	_prepare_guest_playlist(playlist_id)


# Guest: make sure we hold the exact file the host picked, then tell them.
func _prepare_guest_playlist(playlist_id: String) -> void:
	var expected_hash = Steam.getLobbyData(lobby_id, PLAYLIST_HASH_LOBBY_KEY)
	var own_hash = Global.get_playlist_hash(playlist_id)
	if not own_hash.is_empty() and own_hash == expected_hash:
		downloading_file_id = 0
		_report_playlist_ready(own_hash)
		return

	if not Workshop.is_community_id(playlist_id):
		_report_playlist_ready(own_hash)
		_set_status("Your copy of this playlist is different from the host's - make sure you're both on the latest version of Cite.")
		return

	var file_id = Workshop.file_id_of(playlist_id)
	if downloading_file_id == file_id:
		return
	downloading_file_id = file_id
	_set_status("Downloading playlist...")
	Workshop.ensure_playlist(file_id, Steam.getLobbyData(lobby_id, PLAYLIST_NAME_LOBBY_KEY).trim_suffix(" (Community)"),
		Steam.getLobbyData(lobby_id, PLAYLIST_VERSION_LOBBY_KEY).to_int(), not own_hash.is_empty())


func _on_workshop_playlist_ready(file_id: int, ok: bool) -> void:
	if is_host or lobby_id == 0 or file_id != downloading_file_id:
		return
	downloading_file_id = 0
	if not ok:
		_set_status("Couldn't download the host's playlist. Ask them to pick another one.")
		return
	var playlist_id = Workshop.playlist_id_of(file_id)
	if Steam.getLobbyData(lobby_id, PLAYLIST_LOBBY_KEY) != playlist_id:
		return  # host switched playlists meanwhile; that change re-runs this
	var own_hash = Global.get_playlist_hash(playlist_id)
	_report_playlist_ready(own_hash)
	if own_hash == Steam.getLobbyData(lobby_id, PLAYLIST_HASH_LOBBY_KEY):
		_set_status("")
	else:
		_set_status("Your copy of this playlist is different from the host's. The host may need to reopen the lobby to get the latest version.")


func _report_playlist_ready(playlist_hash: String) -> void:
	if playlist_hash == reported_playlist_hash:
		return
	reported_playlist_hash = playlist_hash
	_send_lobby_message(MSG_PLAYLIST_READY, playlist_hash)


# --- Avatars ---------------------------------------------------------------

func _load_avatar(steam_id: int, target: TextureRect) -> void:
	# getXFriendAvatar returns an image handle immediately if it's already
	# cached locally, or <= 0 if Steam still needs to download it - in that
	# case the avatar_image_loaded signal delivers it once ready.
	var handle = Steam.getMediumFriendAvatar(steam_id)
	if handle > 0:
		_apply_avatar_handle(handle, target)
	else:
		pending_avatars[steam_id] = target


func _on_avatar_image_loaded(steam_id: int, width: int, height: int, buffer: PackedByteArray) -> void:
	if not pending_avatars.has(steam_id):
		return
	var target: TextureRect = pending_avatars[steam_id]
	pending_avatars.erase(steam_id)
	_apply_avatar_image(width, height, buffer, target)


func _apply_avatar_handle(handle: int, target: TextureRect) -> void:
	var size_data = Steam.getImageSize(handle)
	if not size_data.get("success", false):
		return
	var buffer_data = Steam.getImageRGBA(handle)
	if not buffer_data.get("success", false):
		return
	_apply_avatar_image(int(size_data["width"]), int(size_data["height"]), buffer_data["buffer"], target)


func _apply_avatar_image(width: int, height: int, buffer: PackedByteArray, target: TextureRect) -> void:
	if width <= 0 or height <= 0 or buffer.is_empty():
		return
	var image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, buffer)
	target.texture = ImageTexture.create_from_image(image)


# --- Starting the match ----------------------------------------------------

func _on_play_pressed() -> void:
	if not is_host or match_starting or guest_id == 0 or not guest_verified:
		return
	SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/click","SFX")
	if dummy_lobby:
		_start_dummy_match()
		return
	match_starting = true
	%PlayButton.disabled = true

	var playlist_id = %PlaylistList.get_selected_id()
	if not playlist_id.is_empty():
		Global.multiplayer_playlist_id = playlist_id
	Global.multiplayer_article_seed = randi()
	# Unjoinable also drops it from everyone's Find / Host a Game list.
	Steam.setLobbyJoinable(lobby_id, false)
	Steam.setLobbyData(lobby_id, ARTICLE_SEED_LOBBY_KEY, str(Global.multiplayer_article_seed))
	_publish_playlist(Global.multiplayer_playlist_id)
	Steam.setLobbyData(lobby_id, GAME_STARTED_LOBBY_KEY, "1")

	# The handshake (MultiplayerSync.start_as_host/connection_established) is
	# what confirms the message channel actually works both ways, rather than
	# assuming it worked, so a genuine failure fails loudly instead of
	# dropping both players into a silently broken match.
	_set_status("Waiting for opponent to connect...")
	MultiplayerSync.connection_established.connect(_on_host_connected, CONNECT_ONE_SHOT)
	MultiplayerSync.connection_failed.connect(_on_connection_failed_signal, CONNECT_ONE_SHOT)
	MultiplayerSync.start_as_host(guest_id)
	_start_connection_timeout()


# No opponent to hand the seed to or handshake with - drop the Steam lobby
# and go straight in, with DummyOpponent (added by Round) playing the guest.
func _start_dummy_match() -> void:
	var playlist_id = %PlaylistList.get_selected_id()
	if not playlist_id.is_empty():
		Global.multiplayer_playlist_id = playlist_id
	_leave_lobby()

	Global.start_new_run()
	Global.run.current_game_mode = Global.run.GameMode.NORMAL
	Global.multiplayer_article_seed = randi()
	Global.is_multiplayer_match = true
	Global.is_dummy_opponent = true
	Global.dummy_opponent_hp = 2000
	Global.dummy_opponent_max_hp = 2000
	Global.last_known_opponent_hp = 2000
	Global.last_known_opponent_max_hp = 2000
	Global.multiplayer_opponent_id = 0
	Global.multiplayer_opponent_name = DummyOpponent.BOT_NAME
	MultiplayerSync.chat_history.clear()
	get_tree().change_scene_to_file("res://scenes/Round.tscn")


func _on_host_connected() -> void:
	_cancel_connection_timeout()
	if MultiplayerSync.connection_failed.is_connected(_on_connection_failed_signal):
		MultiplayerSync.connection_failed.disconnect(_on_connection_failed_signal)

	Global.start_new_run()
	Global.run.current_game_mode = Global.run.GameMode.NORMAL
	Global.is_multiplayer_match = true
	Global.multiplayer_opponent_id = guest_id
	Global.multiplayer_opponent_name = Steam.getFriendPersonaName(guest_id)
	# Stashed for Global to leave once the match actually ends, rather than
	# left here - the messaging session is keyed by Steam ID, not lobby
	# membership, so this is just tidiness, not a connection dependency.
	Global.multiplayer_lobby_id = lobby_id
	lobby_id = 0

	get_tree().change_scene_to_file("res://scenes/Round.tscn")


func _join_match() -> void:
	match_starting = true

	_set_status("Connecting to host...")
	MultiplayerSync.connection_established.connect(_on_guest_connected, CONNECT_ONE_SHOT)
	MultiplayerSync.connection_failed.connect(_on_connection_failed_signal, CONNECT_ONE_SHOT)
	MultiplayerSync.start_as_guest(host_id)
	_start_connection_timeout()


func _on_guest_connected() -> void:
	_cancel_connection_timeout()
	if MultiplayerSync.connection_failed.is_connected(_on_connection_failed_signal):
		MultiplayerSync.connection_failed.disconnect(_on_connection_failed_signal)

	Global.start_new_run()
	Global.run.current_game_mode = Global.run.GameMode.NORMAL
	Global.multiplayer_article_seed = int(Steam.getLobbyData(lobby_id, ARTICLE_SEED_LOBBY_KEY))
	Global.multiplayer_playlist_id = Steam.getLobbyData(lobby_id, PLAYLIST_LOBBY_KEY)
	Global.is_multiplayer_match = true
	Global.multiplayer_opponent_id = host_id
	Global.multiplayer_opponent_name = Steam.getFriendPersonaName(host_id)
	Global.multiplayer_lobby_id = lobby_id
	lobby_id = 0

	get_tree().change_scene_to_file("res://scenes/Round.tscn")


func _on_connection_failed_signal() -> void:
	_cancel_connection_timeout()
	if MultiplayerSync.connection_established.is_connected(_on_host_connected):
		MultiplayerSync.connection_established.disconnect(_on_host_connected)
	if MultiplayerSync.connection_established.is_connected(_on_guest_connected):
		MultiplayerSync.connection_established.disconnect(_on_guest_connected)
	_reset_failed_connection()


# start_as_host()/start_as_guest() report nothing synchronously about whether
# the other side is actually reachable - the handshake message might just
# never arrive (offline friend, Steam down, etc.) without Steam ever calling
# network_messages_session_failed. This timeout is the backstop for that.
func _start_connection_timeout() -> void:
	connection_timeout_timer = get_tree().create_timer(CONNECTION_TIMEOUT_SECONDS)
	connection_timeout_timer.timeout.connect(_on_connection_timeout)


func _cancel_connection_timeout() -> void:
	if connection_timeout_timer:
		connection_timeout_timer.timeout.disconnect(_on_connection_timeout)
		connection_timeout_timer = null


func _on_connection_timeout() -> void:
	connection_timeout_timer = null
	if MultiplayerSync.connection_established.is_connected(_on_host_connected):
		MultiplayerSync.connection_established.disconnect(_on_host_connected)
	if MultiplayerSync.connection_established.is_connected(_on_guest_connected):
		MultiplayerSync.connection_established.disconnect(_on_guest_connected)
	if MultiplayerSync.connection_failed.is_connected(_on_connection_failed_signal):
		MultiplayerSync.connection_failed.disconnect(_on_connection_failed_signal)
	_reset_failed_connection()


func _reset_failed_connection() -> void:
	match_starting = false
	MultiplayerSync.reset_connection()
	if is_host and lobby_id != 0:
		# Flip back to "0" so the guest's watcher can catch a real re-attempt
		# later instead of seeing an already-"1" flag as nothing new.
		Steam.setLobbyData(lobby_id, GAME_STARTED_LOBBY_KEY, "0")
		Steam.setLobbyJoinable(lobby_id, true)
	if lobby_id != 0:
		_update_room()
	_set_status("Couldn't connect to your opponent. Check that Steam is running for both of you, then try again.")


# --- Invites ---------------------------------------------------------------

func _on_invite_pressed() -> void:
	Steam.activateGameOverlayInviteDialog(lobby_id)


func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(str(lobby_id))
	_set_status("Lobby code copied to clipboard!")
