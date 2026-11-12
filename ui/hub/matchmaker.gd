extends Node

# Find Match / Quick Play: pairs two players through Steam lobbies, then starts
# the normal multiplayer match (same handshake as MultiplayerLobby's Play).
#
#   1. Search (worldwide) for a waiting matchmaking lobby on the same playlist
#      and playlist hash (so nobody needs to download anything).
#   2. Found one -> join it. None -> create one and wait, re-searching every
#      RESEARCH_SECONDS.
#   3. Two players waiting in their own lobbies at once would never meet, so
#      while waiting alone we keep searching: if another waiting lobby has a
#      lower id than ours, we leave ours and join that one. Both sides apply the
#      same rule, so exactly one of them moves.
#   4. Second player in -> "match found" for FOUND_PAUSE_SECONDS, then the host
#      publishes the article seed + game_started and both run the
#      MultiplayerSync handshake, then load Round.tscn.
#
# Matchmaking lobbies use game = "Cite-mm", so they never show up in the
# public room browser (which lists game = "Cite").

signal state_changed(state: int)
signal failed(message: String)

enum State { IDLE, SEARCHING, CREATING, WAITING, JOINING, FOUND, CONNECTING }

const GAME_KEY := "game"
const GAME_VALUE := "Cite-mm"
const VERSION_KEY := "cite_version"
const LOBBY_VERSION := "3"  # same as MultiplayerLobby.LOBBY_VERSION
const PLAYLIST_KEY := "playlist"
const HASH_KEY := "playlist_hash"
const STARTED_KEY := "game_started"
const SEED_KEY := "article_seed"
const MODE_KEY := "mm_mode"
# Waiting host's Ranked rating - searches sort lobbies by closeness to it.
const RATING_KEY := "rating"
const RANKED_MODE := "Ranked"

const RESEARCH_SECONDS := 3.0
const RETRY_SECONDS := 1.0
const FOUND_PAUSE_SECONDS := 2.0
const CONNECTION_TIMEOUT_SECONDS := 15.0
const MAX_RESULTS := 20
# Dev dummy matchmaking (start(..., true)): no Steam - the states play out on
# timers, then the match starts against DummyOpponent.
const DUMMY_SEARCH_SECONDS := 1.0
const DUMMY_WAIT_SECONDS := [2.0, 5.0]
const DUMMY_CONNECT_SECONDS := 0.6
const DUMMY_RATING_SPREAD := 150

var state: int = State.IDLE
var playlist_id := ""
var mode := ""
var lobby_id := 0
var is_host := false
var opponent_id := 0
var awaiting_list := false
var guest_connecting := false
var research_timer: Timer
var connection_timer: SceneTreeTimer
var dummy := false
var dummy_token := 0  # bumps on cancel so stale dummy timers do nothing


func _ready() -> void:
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	research_timer = Timer.new()
	research_timer.wait_time = RESEARCH_SECONDS
	research_timer.timeout.connect(func():
		if state == State.WAITING:
			_search())
	add_child(research_timer)


func _exit_tree() -> void:
	# Leaving the hub mid-search (lobby_id is handed to Global once the match
	# starts, so this doesn't drop a real match).
	_leave()


func start(for_playlist: String, for_mode: String, against_bot := false) -> void:
	playlist_id = for_playlist
	mode = for_mode
	dummy = against_bot
	_set_state(State.SEARCHING)
	if dummy:
		_run_dummy()
	else:
		_search()


func cancel() -> void:
	dummy_token += 1
	dummy = false
	_disconnect_sync()
	if state == State.CONNECTING:
		MultiplayerSync.reset_connection()
	_leave()
	_set_state(State.IDLE)


# --- Dummy (dev) -------------------------------------------------------------------

# Same states the hub's overlay shows for a real search, on timers.
func _run_dummy() -> void:
	var token := dummy_token
	await get_tree().create_timer(DUMMY_SEARCH_SECONDS).timeout
	if token != dummy_token:
		return
	_set_state(State.WAITING)
	await get_tree().create_timer(randf_range(DUMMY_WAIT_SECONDS[0], DUMMY_WAIT_SECONDS[1])).timeout
	if token != dummy_token:
		return
	opponent_id = 0
	_set_state(State.FOUND)
	await get_tree().create_timer(FOUND_PAUSE_SECONDS).timeout
	if token != dummy_token:
		return
	_set_state(State.CONNECTING)
	await get_tree().create_timer(DUMMY_CONNECT_SECONDS).timeout
	if token != dummy_token:
		return
	_start_dummy_match()


# MultiplayerLobby._start_dummy_match's setup, plus the mode: Ranked runs
# Ratings in practice mode (result shown, nothing saved).
func _start_dummy_match() -> void:
	dummy = false
	Global.start_new_run()
	Global.run.current_game_mode = Global.run.GameMode.NORMAL
	Global.multiplayer_article_seed = randi()
	Global.is_multiplayer_match = true
	Global.is_dummy_opponent = true
	Global.multiplayer_playlist_id = playlist_id
	Global.multiplayer_opponent_id = 0
	Global.multiplayer_opponent_name = DummyOpponent.BOT_NAME
	MultiplayerSync.chat_history.clear()
	if mode == RANKED_MODE:
		Global.multiplayer_ranked = true
		MultiplayerSync.opponent_rating = maxi(Ratings.MIN_RATING,
			Ratings.rating + randi_range(-DUMMY_RATING_SPREAD, DUMMY_RATING_SPREAD))
		Ratings.begin_match(true)
	_set_state(State.IDLE)
	get_tree().change_scene_to_file("res://scenes/Round.tscn")


# --- Searching --------------------------------------------------------------------

func _search() -> void:
	awaiting_list = true
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter(GAME_KEY, GAME_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(VERSION_KEY, LOBBY_VERSION, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(PLAYLIST_KEY, playlist_id, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(HASH_KEY, Global.get_playlist_hash(playlist_id), Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(STARTED_KEY, "0", Steam.LOBBY_COMPARISON_EQUAL)
	# Ranked and Quick Play never meet.
	Steam.addRequestLobbyListStringFilter(MODE_KEY, mode, Steam.LOBBY_COMPARISON_EQUAL)
	if mode == RANKED_MODE:
		# Closest rating first - never excludes anyone, so a quiet queue still
		# finds a match.
		Steam.addRequestLobbyListNearValueFilter(RATING_KEY, Ratings.rating)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.addRequestLobbyListResultCountFilter(MAX_RESULTS)
	Steam.requestLobbyList()


func _on_lobby_match_list(lobbies: Array) -> void:
	if not awaiting_list:
		return
	awaiting_list = false
	var others := lobbies.filter(func(id): return int(id) != lobby_id)
	if state == State.SEARCHING:
		if others.is_empty():
			_set_state(State.CREATING)
			# Invisible: still found by the search, but friends don't see it
			# (no "Join" in their friends list - matchmaking isn't joinable).
			Steam.createLobby(Steam.LOBBY_TYPE_INVISIBLE, 2)
		else:
			_join(int(others[0]))
	elif state == State.WAITING:
		if Steam.getNumLobbyMembers(lobby_id) > 1:
			return  # someone just joined us - chat_update handles it
		var lower := others.filter(func(id): return int(id) < lobby_id)
		if not lower.is_empty():
			_leave()
			_join(int(lower.min()))


func _retry_search() -> void:
	_set_state(State.SEARCHING)
	get_tree().create_timer(RETRY_SECONDS).timeout.connect(func():
		if state == State.SEARCHING:
			_search())


# --- Hosting a waiting lobby ------------------------------------------------------------

func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	if state != State.CREATING:
		return
	if result != Steam.RESULT_OK:
		_set_state(State.IDLE)
		failed.emit("Couldn't start matchmaking (Steam error %d)." % result)
		return
	lobby_id = new_lobby_id
	is_host = true
	opponent_id = 0
	Steam.setLobbyData(lobby_id, GAME_KEY, GAME_VALUE)
	Steam.setLobbyData(lobby_id, VERSION_KEY, LOBBY_VERSION)
	Steam.setLobbyData(lobby_id, PLAYLIST_KEY, playlist_id)
	Steam.setLobbyData(lobby_id, HASH_KEY, Global.get_playlist_hash(playlist_id))
	Steam.setLobbyData(lobby_id, STARTED_KEY, "0")
	Steam.setLobbyData(lobby_id, MODE_KEY, mode)
	Steam.setLobbyData(lobby_id, RATING_KEY, str(Ratings.rating))
	_set_state(State.WAITING)
	research_timer.start()


# --- Joining someone else's ----------------------------------------------------------------

func _join(target: int) -> void:
	_set_state(State.JOINING)
	Steam.joinLobby(target)


func _on_lobby_joined(joined_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if state != State.JOINING:
		return  # e.g. the host entering the lobby it just created
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_retry_search()  # full or gone - someone else got there first
		return
	var owner := Steam.getLobbyOwner(joined_id)
	if Steam.getNumLobbyMembers(joined_id) < 2 or owner == Steam.getSteamID():
		Steam.leaveLobby(joined_id)
		_retry_search()
		return
	lobby_id = joined_id
	is_host = false
	opponent_id = owner
	_found()


func _on_lobby_chat_update(updated_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if updated_id != lobby_id or lobby_id == 0:
		return
	var left_states := Steam.CHAT_MEMBER_STATE_CHANGE_LEFT | Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED \
		| Steam.CHAT_MEMBER_STATE_CHANGE_KICKED | Steam.CHAT_MEMBER_STATE_CHANGE_BANNED
	if state == State.WAITING and is_host and (chat_state & Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED) != 0 \
			and changed_id != Steam.getSteamID():
		opponent_id = changed_id
		Steam.setLobbyJoinable(lobby_id, false)
		_found()
	elif (chat_state & left_states) != 0 and changed_id == opponent_id and state == State.FOUND:
		# Opponent backed out before the match started - keep looking.
		opponent_id = 0
		if is_host:
			Steam.setLobbyJoinable(lobby_id, true)
			_set_state(State.WAITING)
			research_timer.start()
		else:
			_leave()
			_retry_search()


# --- Starting the match ------------------------------------------------------------------

func _found() -> void:
	research_timer.stop()
	_set_state(State.FOUND)
	get_tree().create_timer(FOUND_PAUSE_SECONDS).timeout.connect(func():
		if state == State.FOUND:
			_start_connection())


func _start_connection() -> void:
	_set_state(State.CONNECTING)
	MultiplayerSync.connection_established.connect(_on_connected, CONNECT_ONE_SHOT)
	MultiplayerSync.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	connection_timer = get_tree().create_timer(CONNECTION_TIMEOUT_SECONDS)
	connection_timer.timeout.connect(_on_connection_failed)
	if is_host:
		Global.multiplayer_article_seed = randi()
		Steam.setLobbyData(lobby_id, SEED_KEY, str(Global.multiplayer_article_seed))
		Steam.setLobbyData(lobby_id, STARTED_KEY, "1")
		MultiplayerSync.start_as_host(opponent_id)
	else:
		guest_connecting = false
		_maybe_connect_guest()


func _on_lobby_data_update(_success: int, updated_id: int, _member_id: int) -> void:
	if updated_id == lobby_id and not is_host and state == State.CONNECTING:
		_maybe_connect_guest()


func _maybe_connect_guest() -> void:
	if guest_connecting or Steam.getLobbyData(lobby_id, STARTED_KEY) != "1":
		return
	guest_connecting = true
	Global.multiplayer_article_seed = int(Steam.getLobbyData(lobby_id, SEED_KEY))
	MultiplayerSync.start_as_guest(opponent_id)


func _on_connected() -> void:
	if state != State.CONNECTING:
		return
	_disconnect_sync()
	Global.start_new_run()
	Global.run.current_game_mode = Global.run.GameMode.NORMAL
	Global.is_multiplayer_match = true
	Global.is_dummy_opponent = false
	Global.multiplayer_playlist_id = playlist_id
	Global.multiplayer_opponent_id = opponent_id
	Global.multiplayer_opponent_name = Steam.getFriendPersonaName(opponent_id)
	if mode == RANKED_MODE:
		Global.multiplayer_ranked = true
		Ratings.begin_match()
		MultiplayerSync.send_rating(Ratings.rating)
	# Global leaves the Steam lobby once the match ends.
	Global.multiplayer_lobby_id = lobby_id
	lobby_id = 0
	_set_state(State.IDLE)
	get_tree().change_scene_to_file("res://scenes/Round.tscn")


func _on_connection_failed() -> void:
	if state != State.CONNECTING:
		return
	_disconnect_sync()
	MultiplayerSync.reset_connection()
	_leave()
	_set_state(State.IDLE)
	failed.emit("Couldn't connect to your opponent. Check that Steam is running, then try again.")


func _disconnect_sync() -> void:
	if MultiplayerSync.connection_established.is_connected(_on_connected):
		MultiplayerSync.connection_established.disconnect(_on_connected)
	if MultiplayerSync.connection_failed.is_connected(_on_connection_failed):
		MultiplayerSync.connection_failed.disconnect(_on_connection_failed)
	if connection_timer and connection_timer.timeout.is_connected(_on_connection_failed):
		connection_timer.timeout.disconnect(_on_connection_failed)
	connection_timer = null


# --- Helpers ---------------------------------------------------------------------------

func _leave() -> void:
	research_timer.stop()
	awaiting_list = false
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	opponent_id = 0
	guest_connecting = false


func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(state)
