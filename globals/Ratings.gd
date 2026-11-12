extends Node

# Ranked Duels rating (Elo). Only matchmaking's "Ranked" mode counts - Quick
# Play, private rooms and the dummy bot don't touch it.
#
# There's no game server: each client works out its own new rating and
# uploads it to the Steam leaderboard Leaderboards.RATING_NAME (score =
# rating, details = [wins, losses], overwritten every match). That board is
# also the Multiplayer tab of the Leaderboards screen. A local copy
# (SAVE_PATH) covers offline play and failed uploads: on startup whichever
# copy has more matches on it wins, and the other is brought up to date.
#
# Ratings are swapped when the match connects (MultiplayerSync "rating"
# message). begin_match() saves a "match in progress" note before the first
# article; if the game dies mid-match, the next launch turns that note into a
# loss - otherwise closing the game would be a free way to dodge losses.

signal changed

const START_RATING := 1000
const MIN_RATING := 100
const PLACEMENT_MATCHES := 15
const K_PLACEMENT := 40.0
const K_SETTLED := 24.0
const SAVE_PATH := "user://rating.cfg"

var rating := START_RATING
var wins := 0
var losses := 0
# True once the Steam copy was read (or couldn't be) - before that the hub
# shows the local copy.
var synced := false

# The match in progress, if it's ranked.
var in_ranked_match := false
# Dummy-bot Ranked (dev): the end screen gets a result, but nothing is saved,
# uploaded or counted - and no "match in progress" note that would turn into
# a loss on the next launch.
var practice := false
var opponent_rating := START_RATING
# Set by finish_match for the end screen: {"old", "new", "delta"}, {} otherwise.
var last_result := {}


func _ready() -> void:
	_load_local()
	_settle_abandoned_match()
	_sync_with_steam()


func games() -> int:
	return wins + losses


func is_provisional() -> bool:
	return games() < PLACEMENT_MATCHES


# "1,042" or "1,042 (provisional)"-style text is up to the caller; this is the
# short tag shown next to the number.
func status_text() -> String:
	if is_provisional():
		return "Provisional · %d/%d placement matches" % [games(), PLACEMENT_MATCHES]
	return "%d W · %d L" % [wins, losses]


# Elo: the change for a result (1 win, 0 loss) against opponent_rating.
static func rating_change(own: int, opponent: int, score: float, k: float) -> int:
	var expected := 1.0 / (1.0 + pow(10.0, float(opponent - own) / 400.0))
	return int(round(k * (score - expected)))


# Called when a Ranked match connects, before the first article.
func begin_match(is_practice := false) -> void:
	in_ranked_match = true
	practice = is_practice
	# Their "rating" message may already be here; if not, set_opponent_rating
	# fills it in when it arrives.
	opponent_rating = MultiplayerSync.opponent_rating if MultiplayerSync.opponent_rating >= 0 else START_RATING
	last_result = {}
	if not practice:
		_save_local(true)


func set_opponent_rating(value: int) -> void:
	if not in_ranked_match:
		return
	opponent_rating = clampi(value, MIN_RATING, 5000)
	if not practice:
		_save_local(true)


# outcome = "won" / "lost". Safe to call more than once - only the first counts.
func finish_match(outcome: String) -> void:
	if not in_ranked_match:
		return
	in_ranked_match = false
	if practice:
		practice = false
		var k := K_PLACEMENT if is_provisional() else K_SETTLED
		var delta := rating_change(rating, opponent_rating, 1.0 if outcome == "won" else 0.0, k)
		last_result = {"old": rating, "new": maxi(MIN_RATING, rating + delta), "delta": delta, "practice": true}
		return
	var old := rating
	_apply(outcome == "won", opponent_rating)
	last_result = {"old": old, "new": rating, "delta": rating - old}
	_save_local(false)
	_upload()
	changed.emit()


func _apply(won: bool, against: int) -> void:
	var k := K_PLACEMENT if is_provisional() else K_SETTLED
	rating = maxi(MIN_RATING, rating + rating_change(rating, against, 1.0 if won else 0.0, k))
	if won:
		wins += 1
	else:
		losses += 1


# --- Saving -------------------------------------------------------------------

func _load_local() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	rating = int(cfg.get_value("rating", "rating", START_RATING))
	wins = int(cfg.get_value("rating", "wins", 0))
	losses = int(cfg.get_value("rating", "losses", 0))


func _save_local(match_pending: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("rating", "rating", rating)
	cfg.set_value("rating", "wins", wins)
	cfg.set_value("rating", "losses", losses)
	if match_pending:
		cfg.set_value("pending", "opponent_rating", opponent_rating)
	cfg.save(SAVE_PATH)


# The last ranked match never finished (crash, killed process, power cut).
func _settle_abandoned_match() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section("pending"):
		return
	_apply(false, int(cfg.get_value("pending", "opponent_rating", START_RATING)))
	_save_local(false)


func _sync_with_steam() -> void:
	# Steam initialises in Global; give it a frame.
	await get_tree().process_frame
	if not Steam.loggedOn():
		synced = true
		changed.emit()
		return
	var result: Dictionary = await Leaderboards.own_entry(Leaderboards.RATING_NAME)
	if result["ok"]:
		var entry: Dictionary = result["entry"]
		var details = entry.get("details", [])
		var steam_wins := int(details[0]) if details.size() > 0 else 0
		var steam_losses := int(details[1]) if details.size() > 1 else 0
		if not entry.is_empty() and steam_wins + steam_losses > games():
			# Played on another PC / reinstalled.
			rating = int(entry.get("score", START_RATING))
			wins = steam_wins
			losses = steam_losses
			_save_local(in_ranked_match)
		elif games() > steam_wins + steam_losses:
			_upload()  # an earlier upload failed or happened offline
	synced = true
	changed.emit()


func _upload() -> void:
	Leaderboards.submit_rating(rating, wins, losses)
