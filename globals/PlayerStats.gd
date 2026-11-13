extends Node

# Lifetime stats for the Profile screen (ui/hub/profile_screen.gd), saved to
# SAVE_PATH and mirrored to Steam Cloud (CLOUD_FILE) so the collection
# follows the player to other PCs / reinstalls. On launch the cloud copy and
# the local one are merged (union of collections, highest totals...), so
# playing offline on two machines loses nothing. Steam leaderboards keep the
# ranked/run bests that other players see; this is the player's own history:
#   - the article collection (every article guessed right, in any mode),
#   - recent multiplayer matches and the Ranked rating over time,
#   - totals: guesses, accuracy, damage, runs, fastest and rarest guess.
# Daily Challenge history isn't duplicated here - it's read straight from
# DailyState's own save (daily_days below).

const DailyState := preload("res://ui/daily/daily_state.gd")
const SAVE_PATH := "user://player_stats.json"
# Steam Remote Storage file name. Needs Steam Cloud enabled for the app in
# Steamworks (App Admin > Steam Cloud: byte quota + file count).
const CLOUD_FILE := "player_stats.json"
const MAX_MATCHES := 30
const MAX_RATING_POINTS := 200

# page id (String) -> {"t": title, "n": times guessed, "d": first guessed (unix)}
var collection := {}
# Newest first: {"time", "opponent", "opponent_id", "outcome", "ranked",
# "rating", "delta", "mine", "theirs", "damage"}
var matches: Array = []
# [[unix, rating], ...] oldest first, one point per Ranked match (plus the start).
var rating_history: Array = []
var totals := {
	"correct": 0, "wrong": 0, "damage": 0,
	"runs": 0, "matches": 0, "wins": 0, "losses": 0,
	"streak": 0, "best_streak": 0,
}
# {"t", "pct"} - the guess made with the smallest share of the article shown.
var fastest := {}
# {"t", "views"} - the least-read article guessed (Hardcore knows the views).
var rarest := {}

var _achievement_ids := {}


func _ready() -> void:
	_load()


# --- Recording ----------------------------------------------------------------

# A correct guess in any mode. shown/total = sentences visible / in the
# article; daily_views < 0 = unknown.
func record_correct(page_id: int, title: String, shown: int, total: int, daily_views := -1.0) -> void:
	if page_id == 0 or Global.debug_forced_article_id != 0:
		return
	totals["correct"] += 1
	var key := str(page_id)
	if collection.has(key):
		collection[key]["n"] = int(collection[key]["n"]) + 1
	else:
		collection[key] = {"t": title, "n": 1, "d": int(Time.get_unix_time_from_system())}
	if total > 0:
		var pct := clampf(float(maxi(shown, 1)) / total, 0.0, 1.0)
		if fastest.is_empty() or pct < float(fastest["pct"]):
			fastest = {"t": title, "pct": pct}
	if daily_views >= 0.0 and (rarest.is_empty() or daily_views < float(rarest["views"])):
		rarest = {"t": title, "views": daily_views}
	_save()


func record_wrong() -> void:
	totals["wrong"] += 1
	_save()


# Single player run ended (end screen).
func record_run() -> void:
	totals["runs"] += 1
	_save()


# Multiplayer match ended (end screen) - reads the match from Global/Run.
func record_match() -> void:
	if Global.is_dummy_opponent:
		return
	var won := Global.multiplayer_match_outcome == "won"
	var mine := 0
	var theirs := 0
	var damage := 0
	for entry in Global.run.mp_log:
		if entry["result"] == "you":
			mine += 1
			damage += int(entry["damage"])
		elif entry["result"] == "opponent":
			theirs += 1
	var ranked := Global.multiplayer_ranked and not Ratings.last_result.is_empty()
	matches.push_front({
		"time": int(Time.get_unix_time_from_system()),
		"opponent": Global.multiplayer_opponent_name,
		"opponent_id": Global.multiplayer_opponent_id,
		"outcome": Global.multiplayer_match_outcome,
		"ranked": ranked,
		"rating": int(Ratings.last_result.get("new", 0)) if ranked else 0,
		"delta": int(Ratings.last_result.get("delta", 0)) if ranked else 0,
		"mine": mine, "theirs": theirs, "damage": damage,
	})
	matches = matches.slice(0, MAX_MATCHES)
	totals["matches"] += 1
	totals["wins" if won else "losses"] += 1
	totals["damage"] += damage
	if ranked:
		if rating_history.is_empty():
			rating_history.append([int(matches[0]["time"]) - 1, int(Ratings.last_result["old"])])
		rating_history.append([int(matches[0]["time"]), int(Ratings.last_result["new"])])
		rating_history = rating_history.slice(-MAX_RATING_POINTS)
		totals["streak"] = int(totals["streak"]) + 1 if won else 0
		totals["best_streak"] = maxi(int(totals["best_streak"]), int(totals["streak"]))
	_save()


# --- Reading ------------------------------------------------------------------

func accuracy() -> float:
	var attempts := int(totals["correct"]) + int(totals["wrong"])
	return float(totals["correct"]) / attempts if attempts > 0 else 0.0


func has_collected(page_id: int) -> bool:
	return collection.has(str(page_id))


# How many of a playlist's articles have been guessed: [collected, total].
func playlist_progress(playlist_id: String) -> Array:
	var ids: Array = Global.get_playlist_article_ids(playlist_id)
	var got := 0
	for id in ids:
		if collection.has(str(int(id))):
			got += 1
	return [got, ids.size()]


func is_achievement_article(page_id: int) -> bool:
	if _achievement_ids.is_empty() and Global.achievement_data is Array:
		for entry in Global.achievement_data:
			_achievement_ids[int(entry["id"])] = true
	return _achievement_ids.has(page_id)


# Days the Daily Challenge was played: {daily_number: solved count}, from
# DailyState's save. Rerolled (dev) days count too - they're still played.
func daily_days() -> Dictionary:
	var days := {}
	var cfg := ConfigFile.new()
	if cfg.load(DailyState.STATE_PATH) != OK:
		return days
	for section in cfg.get_sections():
		if not section.begins_with("day_"):
			continue
		var results: Array = cfg.get_value(section, "results", [])
		if results.is_empty():
			continue
		days[int(section.trim_prefix("day_"))] = DailyState.solved_count({"results": results})
	return days


# [current, best] consecutive days played. Today not played yet doesn't
# break the current streak until the day is over.
func daily_streaks() -> Array:
	var days := daily_days()
	var today := DailyState.today_number()
	var current := 0
	var day := today if days.has(today) else today - 1
	while days.has(day):
		current += 1
		day -= 1
	var best := 0
	var run := 0
	var numbers := days.keys()
	numbers.sort()
	var previous := -10
	for n in numbers:
		run = run + 1 if n == previous + 1 else 1
		best = maxi(best, run)
		previous = n
	return [current, best]


# --- Saving -------------------------------------------------------------------

func _load() -> void:
	var local = _parse(FileAccess.get_file_as_string(SAVE_PATH)) if FileAccess.file_exists(SAVE_PATH) else null
	var cloud = _parse(_cloud_read())
	if local == null and cloud == null:
		return
	if local != null:
		_apply(local)
	if cloud != null:
		_merge(cloud)
	# Write the merged result back to both, so each side has everything.
	if cloud != null:
		_save()


func _parse(text: String):
	if text.is_empty():
		return null
	var data = JSON.parse_string(text)
	return data if typeof(data) == TYPE_DICTIONARY else null


func _apply(data: Dictionary) -> void:
	collection = data.get("collection", {})
	matches = data.get("matches", [])
	rating_history = data.get("rating_history", [])
	fastest = data.get("fastest", {})
	rarest = data.get("rarest", {})
	var saved: Dictionary = data.get("totals", {})
	for key in totals:
		totals[key] = int(saved.get(key, 0))


# Folds another save into this one without losing anything from either.
func _merge(other: Dictionary) -> void:
	var other_collection: Dictionary = other.get("collection", {})
	for key in other_collection:
		var theirs: Dictionary = other_collection[key]
		if not collection.has(key):
			collection[key] = theirs
			continue
		var mine: Dictionary = collection[key]
		mine["n"] = maxi(int(mine.get("n", 1)), int(theirs.get("n", 1)))
		mine["d"] = mini(int(mine.get("d", 0)), int(theirs.get("d", 0)))
	# Matches: union by time, newest first.
	var by_time := {}
	for m in matches + Array(other.get("matches", [])):
		by_time[int(m.get("time", 0))] = m
	var times := by_time.keys()
	times.sort()
	times.reverse()
	matches = []
	for t in times.slice(0, MAX_MATCHES):
		matches.append(by_time[t])
	# Rating history: union by time, oldest first.
	var points := {}
	for p in rating_history + Array(other.get("rating_history", [])):
		points[int(p[0])] = p
	var point_times := points.keys()
	point_times.sort()
	rating_history = []
	for t in point_times.slice(-MAX_RATING_POINTS):
		rating_history.append(points[t])
	var saved: Dictionary = other.get("totals", {})
	for key in totals:
		totals[key] = maxi(int(totals[key]), int(saved.get(key, 0)))
	var other_fastest: Dictionary = other.get("fastest", {})
	if not other_fastest.is_empty() and (fastest.is_empty() or float(other_fastest["pct"]) < float(fastest["pct"])):
		fastest = other_fastest
	var other_rarest: Dictionary = other.get("rarest", {})
	if not other_rarest.is_empty() and (rarest.is_empty() or float(other_rarest["views"]) < float(rarest["views"])):
		rarest = other_rarest


func _save() -> void:
	var text := JSON.stringify({
		"collection": collection, "matches": matches, "rating_history": rating_history,
		"totals": totals, "fastest": fastest, "rarest": rarest,
	})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
	_cloud_write(text)


# --- Steam Cloud ------------------------------------------------------------

func _cloud_available() -> bool:
	return Steam.loggedOn() and Steam.isCloudEnabledForAccount() and Steam.isCloudEnabledForApp()


func _cloud_read() -> String:
	if not _cloud_available() or not Steam.fileExists(CLOUD_FILE):
		return ""
	var size: int = Steam.getFileSize(CLOUD_FILE)
	if size <= 0:
		return ""
	var result: Dictionary = Steam.fileRead(CLOUD_FILE, size)
	var buf = result.get("buf", PackedByteArray())
	return buf.get_string_from_utf8() if buf is PackedByteArray else ""


func _cloud_write(text: String) -> void:
	if not _cloud_available():
		return
	var bytes := text.to_utf8_buffer()
	if not Steam.fileWrite(CLOUD_FILE, bytes, bytes.size()):
		push_warning("PlayerStats: Steam Cloud write failed")
