extends RefCounted

# Daily Challenge bookkeeping (static helpers - preload this script):
#   - which day it is (#1 = DAILY_EPOCH, resets at UTC midnight),
#   - today's articles, the same for everyone and independent of the game
#     version: an online schedule (SCHEDULE_URL, a JSON file on the repo's
#     daily-data branch, filled ahead by a GitHub Action - see
#     tools/daily_schedule.py) lists 5 + spare Wikipedia ids per UTC date.
#     Offline (or no entry yet) it falls back to every official playlist's
#     ids (Global.OFFICIAL_POOL, sorted) shuffled with a seed made from the day,
#   - the player's progress, saved after every article so there's exactly
#     one attempt (leaving mid-article counts that article as failed).

const ARTICLES_PER_DAY := 5
# Spare candidates in case an article's intro is too short or fails to load.
const CANDIDATES := 12
const DAILY_EPOCH := "2026-11-01T00:00:00"
const STATE_PATH := "user://daily.cfg"
const SCHEDULE_URL := "https://raw.githubusercontent.com/davidkovacwebdev/Cite/daily-data/daily/schedule.json"
const SCHEDULE_CACHE := "user://daily_schedule.json"  # last download, for offline / instant hub
const SCHEDULE_TIMEOUT := 6.0

# Scoring (per article) - the same curve as multiplayer damage
# (MultiplayerBoard._current_guess_damage): full points while only the first
# sentence shows, then a fixed step (MAX_POINTS / sentences) less for every
# sentence revealed since. Wrong guesses cost 50, like the 50 HP in a match.
const MAX_POINTS := 1000
const WRONG_GUESS_PENALTY := 50
const MIN_SOLVED_POINTS := 50  # a solve is never worth 0, whatever the penalties
# Summary tiers: >= GREAT_POINTS green, solved yellow, failed red.
const GREAT_POINTS := 700


static func today_number() -> int:
	var epoch := Time.get_unix_time_from_datetime_string(DAILY_EPOCH)
	var now := int(Time.get_unix_time_from_system())
	return int(floor(float(now - epoch) / 86400.0)) + 1


# Today's UTC date, "YYYY-MM-DD" - the schedule's key.
static func today_date() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()))


# Downloads the schedule into SCHEDULE_CACHE (await it). False = offline or
# bad response; the last cached copy stays in use.
static func fetch_schedule(host: Node) -> bool:
	var http := HTTPRequest.new()
	http.timeout = SCHEDULE_TIMEOUT
	host.add_child(http)
	# The minute in the query skips GitHub's ~5 min raw-file cache.
	var url := SCHEDULE_URL + "?t=%d" % int(Time.get_unix_time_from_system() / 60.0)
	if http.request(url) != OK:
		http.queue_free()
		return false
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return false
	var text: String = res[3].get_string_from_utf8()
	var data = JSON.parse_string(text)
	if not (data is Dictionary and data.get("days") is Dictionary):
		return false
	var file := FileAccess.open(SCHEDULE_CACHE, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
	return true


# Ids for `date` from the cached schedule ([] if none).
static func scheduled_ids(date: String) -> Array:
	var file := FileAccess.open(SCHEDULE_CACHE, FileAccess.READ)
	if not file:
		return []
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary and data.get("days") is Dictionary):
		return []
	var entry = data["days"].get(date)
	var ids: Array = []
	if entry is Dictionary and entry.get("ids") is Array:
		for id in entry["ids"]:
			ids.append(int(id))
	return ids


# Today's set: {"ids": candidates in order, "key": identifies the set (state
# and leaderboard are per set), "source": "online" / "offline" / "local"}.
# `reroll` > 0 = a dev reset (local set, no leaderboard).
static func todays_set(daily_number: int, reroll := 0) -> Dictionary:
	if reroll > 0:
		return {"ids": candidate_ids(daily_number, reroll), "key": "local%d" % reroll, "source": "local"}
	var ids := scheduled_ids(today_date())
	if not ids.is_empty():
		return {"ids": ids, "key": str(ids).md5_text().substr(0, 8), "source": "online"}
	return {"ids": candidate_ids(daily_number), "key": "seed", "source": "offline"}


static func seconds_until_reset() -> int:
	var now := int(Time.get_unix_time_from_system())
	return 86400 - (now % 86400)


# Deterministic: every player gets the same list for the same day.
# `reroll` > 0 only after a dev reset (reset_day) - a different set, local only.
static func candidate_ids(daily_number: int, reroll := 0) -> Array:
	var ids: Array = Global.get_playlist_article_ids(Global.OFFICIAL_POOL)  # sorted, unique
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * daily_number + 104729 + 1000003 * reroll  # plain ints - String.hash() could change between engine versions
	# Fisher-Yates with our own RNG (Array.shuffle uses the global one).
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	return ids.slice(0, CANDIDATES)


# Same seed for everyone, per article: which order its sentences reveal in.
static func reveal_order(daily_number: int, article_id: int, chunk_count: int) -> Array:
	var order: Array = range(chunk_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * daily_number + article_id
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order


static func points_for(solved: bool, sentences_shown: int, sentence_count: int, wrong_guesses: int) -> int:
	if not solved:
		return 0
	var step := float(MAX_POINTS) / float(maxi(sentence_count, 1))
	var base := int(round(MAX_POINTS - float(maxi(sentences_shown, 1) - 1) * step))
	return maxi(MIN_SOLVED_POINTS, base - WRONG_GUESS_PENALTY * wrong_guesses)


# {"results": [{"id", "title", "solved", "points", "wrong"}...],
#  "next_candidate": int, "started_id": int (article in progress, 0 = none),
#  "reroll": int, "set": todays_set()'s key}
# With `set_key`, progress saved for a different set (the schedule changed
# today) doesn't count - it starts fresh.
static func load_day(daily_number: int, set_key := "") -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	var section := "day_%d" % daily_number
	var saved_set: String = cfg.get_value(section, "set", "")
	if set_key != "" and saved_set != "" and saved_set != set_key:
		return {"results": [], "next_candidate": 0, "started_id": 0, "started_title": "",
			"reroll": cfg.get_value(section, "reroll", 0), "set": set_key}
	return {
		"results": cfg.get_value(section, "results", []),
		"next_candidate": cfg.get_value(section, "next_candidate", 0),
		"started_id": cfg.get_value(section, "started_id", 0),
		"started_title": cfg.get_value(section, "started_title", ""),
		"reroll": cfg.get_value(section, "reroll", 0),
		"set": set_key if set_key != "" else saved_set,
	}


static func save_day(daily_number: int, state: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	var section := "day_%d" % daily_number
	for key in state:
		cfg.set_value(section, key, state[key])
	cfg.save(STATE_PATH)


# Dev tools. reset_day: wipe today's attempt and switch to a fresh local set
# of 5 (the next reroll; rerolled days don't upload to the Steam daily
# leaderboard). official_day: wipe today's attempt and go back to the
# official (online) set.
static func reset_day(daily_number: int) -> void:
	_wipe_day(daily_number, load_day(daily_number)["reroll"] + 1)


static func official_day(daily_number: int) -> void:
	_wipe_day(daily_number, 0)


static func _wipe_day(daily_number: int, reroll: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	var section := "day_%d" % daily_number
	if cfg.has_section(section):
		cfg.erase_section(section)
	if reroll > 0:
		cfg.set_value(section, "reroll", reroll)
	cfg.save(STATE_PATH)


# Leaderboard entry details (int32s) for the Daily's progress, so deleting
# daily.cfg doesn't give a second attempt:
#   [0] solved count (the hub's friends list shows it), [1] articles done,
#   [2] next_candidate, [3] article in progress (0 = none),
#   [4..8] points, [9..13] page ids, [14..18] wrong guesses - per article.
const DETAILS_SIZE := 4 + 3 * ARTICLES_PER_DAY


static func progress_details(state: Dictionary) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(DETAILS_SIZE)
	d.fill(0)
	var results: Array = state["results"]
	d[0] = solved_count(state)
	d[1] = results.size()
	d[2] = int(state["next_candidate"])
	d[3] = int(state["started_id"])
	for i in mini(results.size(), ARTICLES_PER_DAY):
		d[4 + i] = int(results[i]["points"])
		d[4 + ARTICLES_PER_DAY + i] = int(results[i]["id"])
		d[4 + 2 * ARTICLES_PER_DAY + i] = int(results[i].get("wrong", 0))
	return d


# Brings `state` up to the leaderboard record when the record is further
# along (daily.cfg deleted, or played on another computer). True if changed.
static func merge_progress(state: Dictionary, details: Array) -> bool:
	if details.size() < DETAILS_SIZE:
		return false
	var done := mini(int(details[1]), ARTICLES_PER_DAY)
	var results: Array = state["results"]
	var remote_started := int(details[3])
	var behind := done > results.size() \
		or (done == results.size() and remote_started != 0 and int(state["started_id"]) == 0)
	if not behind:
		return false
	var restored: Array = []
	for i in done:
		if i < results.size():
			restored.append(results[i])
			continue
		var id := int(details[4 + ARTICLES_PER_DAY + i])
		var points := int(details[4 + i])
		restored.append({"id": id, "title": scheduled_title(id, "Article %d" % (i + 1)),
			"solved": points > 0, "points": points, "wrong": int(details[4 + 2 * ARTICLES_PER_DAY + i])})
	state["results"] = restored
	state["next_candidate"] = maxi(int(state["next_candidate"]), int(details[2]))
	if remote_started != 0 and int(state["started_id"]) == 0:
		state["started_id"] = remote_started
		state["started_title"] = scheduled_title(remote_started, "?")
	return true


# An article's title from today's cached schedule ("titles" next to "ids").
static func scheduled_title(page_id: int, fallback: String) -> String:
	var file := FileAccess.open(SCHEDULE_CACHE, FileAccess.READ)
	if not file:
		return fallback
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary and data.get("days") is Dictionary):
		return fallback
	var entry = data["days"].get(today_date())
	if not (entry is Dictionary and entry.get("ids") is Array and entry.get("titles") is Array):
		return fallback
	var ids: Array = entry["ids"]
	for i in ids.size():
		if int(ids[i]) == page_id and i < entry["titles"].size():
			return String(entry["titles"][i])
	return fallback


static func is_finished(state: Dictionary) -> bool:
	return state["results"].size() >= ARTICLES_PER_DAY


static func total_points(state: Dictionary) -> int:
	var total := 0
	for r in state["results"]:
		total += int(r["points"])
	return total


static func solved_count(state: Dictionary) -> int:
	var n := 0
	for r in state["results"]:
		if r["solved"]:
			n += 1
	return n


# "great" / "solved" / "failed" - colour tier for the progress pips and summary.
static func tier(result: Dictionary) -> String:
	if not result["solved"]:
		return "failed"
	return "great" if int(result["points"]) >= GREAT_POINTS else "solved"
