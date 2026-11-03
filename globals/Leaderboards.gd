extends Node

# Single player Steam leaderboards. Normal has one per playlist - a run only
# counts when exactly one playlist and no categories were picked - and
# Hardcore has a single one. EndScreen uploads the run and Steam keeps each
# player's best. details[0] holds the run's correct guesses, since Hardcore's
# score is points (see HARDCORE_TIERS) rather than a plain count.
#
# GodotSteam answers each call with a signal that doesn't say which call it
# belongs to, so requests run one at a time (_lock).

const NORMAL_PREFIX := "sp_normal_"
const HARDCORE_NAME := "sp_hardcore"
# One board per Daily Challenge day and set ("daily_<number>_<set key>", see DailyState.todays_set).
const DAILY_PREFIX := "daily_"
const TOP_ENTRIES := 50
const REPLY_TIMEOUT_MS := 10000

# Hardcore points per correct guess, by the article's average daily
# Wikipedia views over the last 30 days: the fewer people read it, the more
# it's worth. Unknown views score as well known, so a failed lookup never
# pays more.
const HARDCORE_TIERS := [
	{"min_views": 1000.0, "points": 1, "label": "Well known"},
	{"min_views": 100.0, "points": 2, "label": "Known"},
	{"min_views": 10.0, "points": 3, "label": "Obscure"},
	{"min_views": 0.0, "points": 4, "label": "Deep cut"},
]

var _handles := {}  # leaderboard name -> Steam handle
var _busy := false
var _reply = null


func _ready() -> void:
	Steam.set_leaderboard_details_max(64)  # Steam's max - the Daily stores its progress there (DailyState.progress_details)
	Steam.leaderboard_find_result.connect(func(handle, found): _reply = [handle, found])
	Steam.leaderboard_score_uploaded.connect(func(success, handle, score): _reply = [success, handle, score])
	Steam.leaderboard_scores_downloaded.connect(func(message, handle, entries): _reply = [message, handle, entries])


static func hardcore_points_for(daily_views: float) -> int:
	for tier in HARDCORE_TIERS:
		if daily_views >= tier["min_views"]:
			return tier["points"]
	return HARDCORE_TIERS[0]["points"]


static func daily_board_name(daily_number: int, set_key: String) -> String:
	return DAILY_PREFIX + "%d_%s" % [daily_number, set_key]


# Daily Challenge: score = points, details[0] = articles solved.
# The Daily uploads when each article starts and once more at the end,
# overwriting the previous entry: the board is the record of what the player
# has played today - see DailyState.progress_details. True if Steam took it
# (it rate-limits uploads, so the Daily keeps them few).
func submit_daily_progress(daily_number: int, set_key: String, points: int, details: PackedInt32Array) -> bool:
	return await _upload(daily_board_name(daily_number, set_key), points, 0, details, false)


# {"ok": Steam answered, "entry": the player's entry or {} if they have none}.
func own_entry(board_name: String) -> Dictionary:
	var result = {"ok": false, "entry": {}}
	if not Steam.loggedOn():
		return result
	await _lock()
	var handle = await _find_handle(board_name)
	if handle != 0:
		Steam.downloadLeaderboardEntriesForUsers([Steam.getSteamID()], handle)
		var reply = await _wait_reply()
		if reply != null:
			result["ok"] = true
			if not reply[2].is_empty():
				result["entry"] = reply[2][0].duplicate(true)
	_busy = false
	return result


static func normal_board_name(playlist: String) -> String:
	var slug = ""
	for c in Global.strip_accents(playlist.to_lower()):
		slug += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	return NORMAL_PREFIX + slug


# The playlist a Normal run is ranked under, "" if it doesn't count.
static func run_playlist() -> String:
	if Global.selected_playsets.size() == 1 and Global.selected_categories.is_empty():
		return Global.selected_playsets[0]
	return ""


# Called by the boards on a correct guess. Returns the points it was worth
# (1 outside Hardcore).
func record_correct_guess() -> int:
	var run = Global.run
	run.correct_guesses += 1
	if run.current_game_mode != Run.GameMode.HARDCORE:
		return 1
	var points = hardcore_points_for(run.current_round.article_daily_views)
	run.hardcore_points += points
	return points


func submit_run() -> void:
	if Global.is_multiplayer_match or Global.debug_forced_article_id != 0:
		return
	var run = Global.run
	if run.correct_guesses == 0:
		return
	if run.current_game_mode == Run.GameMode.HARDCORE:
		_upload(HARDCORE_NAME, run.hardcore_points, run.correct_guesses)
	elif run.current_game_mode == Run.GameMode.NORMAL:
		var playlist = run_playlist()
		if playlist != "":
			_upload(normal_board_name(playlist), run.correct_guesses, run.correct_guesses)


# {"ok": bool, "entries": top TOP_ENTRIES, "own": the player's entry or {},
# "count": total entries on the board}. Entries are GodotSteam's dictionaries
# (score, steam_id, global_rank, details). friends_only = the player and their
# Steam friends instead of the global top.
func download(board_name: String, friends_only: bool = false) -> Dictionary:
	var result = {"ok": false, "entries": [], "own": {}, "count": 0}
	if not Steam.loggedOn():
		return result
	await _lock()
	var handle = await _find_handle(board_name)
	if handle != 0:
		result["count"] = Steam.getLeaderboardEntryCount(handle)
		var request = Steam.LEADERBOARD_DATA_REQUEST_FRIENDS if friends_only else Steam.LEADERBOARD_DATA_REQUEST_GLOBAL
		Steam.downloadLeaderboardEntries(1, TOP_ENTRIES, request, handle)
		var reply = await _wait_reply()
		if reply != null:
			result["ok"] = true
			# Copy: GodotSteam hands back an array it reuses for the next
			# download, so the own-entry request below would overwrite it.
			result["entries"] = reply[2].duplicate(true)
			Steam.downloadLeaderboardEntriesForUsers([Steam.getSteamID()], handle)
			var own_reply = await _wait_reply()
			if own_reply != null and not own_reply[2].is_empty():
				result["own"] = own_reply[2][0].duplicate(true)
	_busy = false
	return result


# keep_best: Steam only replaces the entry when the score is higher.
func _upload(board_name: String, score: int, guesses: int, details := PackedInt32Array(), keep_best := true) -> bool:
	if not Steam.loggedOn():
		return false
	if details.is_empty():
		details = PackedInt32Array([guesses])
	await _lock()
	var ok := false
	var handle = await _find_handle(board_name)
	if handle != 0:
		Steam.uploadLeaderboardScore(score, keep_best, details, handle)
		var reply = await _wait_reply()
		ok = reply != null and bool(reply[0])
	_busy = false
	return ok


# Call while holding the lock. 0 if Steam couldn't find or create it.
func _find_handle(board_name: String) -> int:
	if _handles.has(board_name):
		return _handles[board_name]
	Steam.findOrCreateLeaderboard(board_name, Steam.LEADERBOARD_SORT_METHOD_DESCENDING, Steam.LEADERBOARD_DISPLAY_TYPE_NUMERIC)
	var reply = await _wait_reply()
	if reply == null or int(reply[1]) == 0 or int(reply[0]) == 0:
		return 0
	_handles[board_name] = int(reply[0])
	return int(reply[0])


func _lock() -> void:
	while _busy:
		await get_tree().process_frame
	_busy = true
	_reply = null


# null if Steam didn't answer in time.
func _wait_reply():
	var deadline = Time.get_ticks_msec() + REPLY_TIMEOUT_MS
	while _reply == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var reply = _reply
	_reply = null
	return reply
