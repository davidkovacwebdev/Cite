extends Control

class_name MultiplayerBoard

const MAX_GUESS_DAMAGE := 600.0
# Correct-guess damage grows each round: x(1 + this x (round - 1)), so
# round 1 = 600 max, round 5 = 840, round 10 = 1140. Keeps late rounds decisive.
const GUESS_DAMAGE_GROWTH_PER_ROUND := 0.10
const TIMER_BAR_HEIGHT := 380.0
const GRACE_PERIOD_SECONDS := 5.0
# Colours: the hub's paper theme (ui/hub/hub_theme.tres, "Hub" type).
const MatchStyle := preload("res://ui/match/match_style.gd")
# A title letter is auto-revealed on every Nth chunk reveal (see
# _maybe_reveal_title_letter).
const TITLE_LETTER_EVERY_N_CHUNKS := 2
# How long a drawn round's answer box stays up before the next round.
const ANSWER_DISPLAY_SECONDS := 5.5
# The article's picture after your own correct guess.
const CORRECT_IMAGE_SECONDS := 3.5
# HP both players lose on a drawn round, times the round number.
const DRAW_DAMAGE_PER_ROUND := 100
# "Skip article": once both players vote, the round ends like a draw (same
# damage). Voting opens a moment after the round starts so nobody skips on
# reflex before reading anything.
const SKIP_VOTE_DELAY_SECONDS := 3.0
const REWARD_PICK_TIMEOUT_SECONDS := 5.0
const REWARD_TIMER_BAR_WIDTH := 420.0
const REWARD_TIMER_BAR_HEIGHT := 14.0
# How long the non-guesser waits for a "here's the picker" / "nothing to
# watch" message before giving up (should arrive near-instantly - this only
# needs to cover message latency, not the winner's actual pick time).
const REWARD_SYNC_TIMEOUT_SECONDS := 5.0
# How long the non-guesser waits for the winner's actual pick - comfortably
# longer than REWARD_PICK_TIMEOUT_SECONDS so it isn't the one giving up first.
const CARD_REWARD_WAIT_TIMEOUT_SECONDS := 20.0
# Riser played across each chunk-reveal interval (and the grace period), timed
# so its peak lands as the timer runs out - see _start_reveal_timer.
const TIMER_CHARGE_SOUND := "res://assets/sounds/sfx/multiplayer/timer-riser.wav"
const TIMER_CHARGE_VOLUME_DB := -14.0
# Hit played the moment a reveal timer (or the grace period) runs out. Starts
# barely audible and gets TIMER_END_STEP_DB louder with each timer in the
# round, up to TIMER_END_MAX_DB - tension builds as the article fills in.
const TIMER_END_SOUND := "res://assets/sounds/sfx/multiplayer/timer-end.wav"
const TIMER_END_MIN_DB := -30.0
const TIMER_END_STEP_DB := 2.5
const TIMER_END_MAX_DB := 0.0
# Tick on each 3-2-1 countdown number.
const COUNTDOWN_TICK_SOUND := "res://assets/sounds/sfx/multiplayer/tic.wav"
const COUNTDOWN_TICK_PITCH_VARIATION := 0.08
# Where the riser's abrupt cut-off sits in the file (a short release tail
# follows) - this is the moment lined up with the timer running out.
const TIMER_RISER_PEAK_SECONDS := 12.0
const TITLE_Y := 36.0

const CardScene = preload("res://scenes/Card.tscn")

# Round-win reward: same 5 cards the multiplayer deck already draws from
# (deck.gd's generate_multiplayer_hand), duplicated here rather than
# shared since deck.gd's copy is tied to building deck-pool dictionaries and
# this one is tied to building picker visuals - different enough shapes that
# sharing would need its own abstraction for no real benefit.
const REWARD_SPECIALS := {
	"double_down": Card.Action_sub_type.double_down,
	"letter_snipe": Card.Action_sub_type.letter_snipe,
	"letter_reveal": Card.Action_sub_type.letter_reveal,
	"freeze": Card.Action_sub_type.freeze,
	"chunk_scramble": Card.Action_sub_type.chunk_scramble,
	"heal": Card.Action_sub_type.mp_heal,  # reward-only, never in the starting deck
}

# Same sound each card makes when played (card.gd), reused when it's picked
# as a reward.
const REWARD_SOUNDS := {
	"double_down": "res://assets/sounds/sfx/multiplayer/double-down.wav",
	"letter_snipe": "res://assets/sounds/sfx/multiplayer/letter-snipe.wav",
	"letter_reveal": "res://assets/sounds/sfx/multiplayer/letter-reveal.wav",
	"freeze": "res://assets/sounds/sfx/multiplayer/chill.wav",
	"chunk_scramble": "res://assets/sounds/sfx/multiplayer/shamble.wav",
	"heal": "res://assets/sounds/sfx/multiplayer/heal.mp3",
}

var chunks
var reveal_order: Array = []
var shake_tween: Tween
var round_advancing: bool = false
var round_started: bool = false
var reveal_index: int = 0
var reveal_timer: Timer
# Two players taking turns, so one riser's release tail rings out while the
# next interval's riser starts on the other.
var timer_charge_players: Array[AudioStreamPlayer] = []
var timer_charge_index: int = 0
var in_grace_period: bool = false
var frozen: bool = false
# The guess field only shows while typing a guess: Enter opens it, Enter
# again submits, Esc (or Backspace on an empty field) cancels.
var guess_open: bool = false
var guess_checking: bool = false
var _base_chunk_font_size: int
var _base_title_font_size: int
var _reward_picked_key: String = ""
var _pending_reward_picker_info: Array = []
var _pending_reward_picker_ready: bool = false
var _pending_card_reward_winner_action: int = -1
var _pending_card_reward_ready: bool = false
var skip_voted: bool = false
var skip_button: Button
var skip_status: Label


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.run.current_round.current_board = self
	Global.run.current_round.article_title_length = get_title_count(Global.run.current_round.article_title)
	Global.run.current_round.vowels_revealed = false

	# An armed effect only lasts the round it was activated in - carrying it
	# into a fresh round (with a  different title) would be confusing. The
	# card that armed it is already gone from the hand either way.
	Global.run.double_down_armed = false
	Global.opponent_double_down_armed = false
	Global.run.letter_reveal_armed = false

	MultiplayerSync.opponent_guess_result.connect(_on_opponent_guess_result)
	MultiplayerSync.you_were_frozen.connect(_on_frozen)
	MultiplayerSync.chunks_scrambled.connect(_on_chunks_scrambled)
	MultiplayerSync.card_reward_received.connect(_on_card_reward_received)
	MultiplayerSync.reward_picker_started.connect(_on_reward_picker_started_signal)
	MultiplayerSync.reward_none.connect(_on_reward_none_signal)
	MultiplayerSync.chat_message_added.connect(_add_chat_line)
	MultiplayerSync.opponent_skip_voted.connect(_on_opponent_skip_voted)
	_build_skip_vote()
	_build_mute_toggle()
	# Enter/T/Esc for the chat are handled in _input; the placeholder doubles
	# as the key hint.
	%ChatInput.focus_entered.connect(_update_chat_hint)
	%ChatInput.focus_exited.connect(_update_chat_hint)
	_update_chat_hint()
	# This board is rebuilt every round - replay the match's chat so far.
	for entry in MultiplayerSync.chat_history:
		_add_chat_line(entry.name, entry.text, entry.own)

	# Reset here, once per round, rather than at the moment we start waiting
	# for them (_wait_for_reward_picker_signal used to do this) - the winner's
	# "reward_picker_started" message races against a LOCAL 2-second timer on
	# this client (the "OPPONENT GUESSED!" banner wait), not against another
	# network message, so it can genuinely arrive and set these flags before
	# we start watching for them. Resetting at that later point would wipe an
	# already-correct "got it" flag and then wait forever for a signal that
	# already fired - which is exactly why this only failed intermittently.
	_pending_reward_picker_ready = false
	_pending_reward_picker_info = []
	_pending_card_reward_ready = false
	_pending_card_reward_winner_action = -1

	$ArticleTitle.position.y = TITLE_Y
	_center_title()
	# Room for the draw damage after the guess damage (_update_stake_label).
	$StakeLabel.offset_left = 216.0
	$StakeLabel.offset_right = 936.0
	# The text size option can grow the title past its default width.
	$ArticleTitle.resized.connect(_center_title)
	$InputField.reset_border()
	$ArticleTitle.add_theme_constant_override("letter_spacing", 102)

	if Global.run.current_round.article_chunks:
		chunks = Global.run.current_round.article_chunks
	update_board_chunks()
	_build_round_hints()
	_base_chunk_font_size = $ScrollContainer.get_theme_font_size("normal_font_size", "RichTextLabel")
	_base_title_font_size = $ArticleTitle.get_theme_font_size("normal_font_size")
	apply_text_size()
	Global.match_display_settings_changed.connect(apply_text_size)

	if chunks:
		reveal_order = range(chunks.size())
		reveal_order.shuffle()

	reveal_timer = Timer.new()
	reveal_timer.one_shot = true
	reveal_timer.timeout.connect(_on_reveal_timer_timeout)
	add_child(reveal_timer)

	var riser = load(TIMER_CHARGE_SOUND)
	for i in range(2):
		var player = AudioStreamPlayer.new()
		player.stream = riser
		player.volume_db = TIMER_CHARGE_VOLUME_DB
		player.bus = "SFX"
		add_child(player)
		timer_charge_players.append(player)

	Global.run.current_round.card_playable = false
	_start_countdown()


# 3, 2, 1 pre-round countdown - guessing and playing cards are locked out
# until it finishes, then the phased chunk-reveal timer kicks off.
func _start_countdown() -> void:
	$CountdownLabel.visible = true
	for n in ["3", "2", "1"]:
		if Global.multiplayer_match_over or not is_inside_tree():
			return  # opponent left/match ended in the first couple seconds of the round
		$CountdownLabel.text = n
		SoundManagerScript.play_sfx_overlapping(COUNTDOWN_TICK_SOUND, 0.0, COUNTDOWN_TICK_PITCH_VARIATION)
		await get_tree().create_timer(1.0, false).timeout
	if Global.multiplayer_match_over or not is_inside_tree():
		return
	$CountdownLabel.visible = false
	round_started = true
	Global.run.current_round.card_playable = true
	$RevealTimerBar.visible = true
	_schedule_next_reveal()
	await get_tree().create_timer(SKIP_VOTE_DELAY_SECONDS, false).timeout
	if is_inside_tree() and not round_advancing and not skip_voted:
		skip_button.disabled = false


# First 3 reveals every 6s, next 3 every 9s, the rest every 12s.
func _interval_for(reveal_number: int) -> float:
	if reveal_number <= 3:
		return 6.0
	elif reveal_number <= 6:
		return 9.0
	else:
		return 12.0


func _schedule_next_reveal() -> void:
	if not chunks or reveal_index >= chunks.size():
		_start_grace_period()
		return
	_start_reveal_timer(_interval_for(reveal_index + 1))


# Starts the reveal timer and the riser with it. The riser builds for 12s
# (longer than any interval), so it starts partway in at normal speed and
# hits its cut-off right as the timer runs out.
func _start_reveal_timer(seconds: float) -> void:
	reveal_timer.start(seconds)
	var player = timer_charge_players[timer_charge_index]
	timer_charge_index = (timer_charge_index + 1) % timer_charge_players.size()
	if player.stream:
		player.play(max(TIMER_RISER_PEAK_SECONDS - seconds, 0.0))


func _stop_timer_charge() -> void:
	for player in timer_charge_players:
		player.stop()


func _on_reveal_timer_timeout() -> void:
	# reveal_index = timers already finished this round (0 for the first).
	var end_db = min(TIMER_END_MIN_DB + TIMER_END_STEP_DB * reveal_index, TIMER_END_MAX_DB)
	SoundManagerScript.play_sfx_overlapping(TIMER_END_SOUND, end_db)
	if in_grace_period:
		_on_grace_period_expired()
		return
	if not chunks or reveal_index >= chunks.size():
		return
	var chunk_index = reveal_order[reveal_index]
	reveal_chunk(chunk_index + 1, chunks[chunk_index])
	reveal_index += 1
	_update_round_hints()
	_maybe_reveal_title_letter()
	_schedule_next_reveal()


# Every TITLE_LETTER_EVERY_N_CHUNKS chunks, reveals one random hidden letter
# of the title. Per word (n = its letters): it may show at most (n - 1) / 3
# letters in total, card reveals included (1-3 letter words never, 4-6 one,
# 7-9 two, ...), always keeps at least one hidden, and short words wait -
# nothing until chunk 9 - n (a 4-letter word from chunk 5, 8+ right away).
func _maybe_reveal_title_letter() -> void:
	if reveal_index % TITLE_LETTER_EVERY_N_CHUNKS != 0:
		return
	var title: String = Global.run.current_round.article_title
	var censored: String = Global.run.current_round.article_censored_title
	var candidates: Array[int] = []
	var word_start = 0
	for i in range(title.length() + 1):
		if i == title.length() or title[i] == " ":
			candidates.append_array(_revealable_letters(title, censored, word_start, i))
			word_start = i + 1
	if candidates.is_empty():
		return
	var index = candidates.pick_random()
	Global.run.current_round.article_censored_title = censored.substr(0, index) + title[index] + censored.substr(index + 1)
	update_board_title()


# Hidden letter indices in title[from, to) if that word may get another
# letter right now, else empty - see _maybe_reveal_title_letter().
func _revealable_letters(title: String, censored: String, from: int, to: int) -> Array[int]:
	var hidden: Array[int] = []
	for i in range(from, to):
		if censored[i] == "_":
			hidden.append(i)
	var letters = get_title_count(title.substr(from, to - from))
	var max_revealed = int((letters - 1) / 3.0)
	if hidden.size() <= 1 or letters - hidden.size() >= max_revealed or reveal_index < 9 - letters:
		return []
	return hidden


# All chunks are revealed and nobody's guessed yet - give both players one
# last 5s chance (bar turns red) before the round ends in a draw, which
# costs both players DRAW_DAMAGE_PER_ROUND x round number HP.
func _start_grace_period() -> void:
	in_grace_period = true
	var mat: ShaderMaterial = $RevealTimerBar.material
	mat.set_shader_parameter("color", MatchStyle.color("accent"))
	_start_reveal_timer(GRACE_PERIOD_SECONDS)


func _on_grace_period_expired() -> void:
	_end_round_as_draw()


# Nobody got it (timer ran out, or both players voted to skip) - show the
# answer, cost both players the draw damage, move on.
func _end_round_as_draw(caption: String = "The answer was") -> void:
	if round_advancing or Global.multiplayer_match_over or not is_inside_tree():
		return
	round_advancing = true
	reveal_timer.stop()
	_stop_timer_charge()
	in_grace_period = false
	close_guess()
	skip_button.disabled = true
	Global.run.current_round.card_playable = false
	# Show the answer, in the title bar and as the banner.
	var title: String = Global.run.current_round.article_title
	Global.run.current_round.article_censored_title = title
	update_board_title()
	get_parent().show_answer(title, ANSWER_DISPLAY_SECONDS, caption)
	Global.run.log_article("timeout" if caption == "The answer was" else "skipped", _skip_damage())
	# Each client damages only itself; the opponent sees it via vitals sync.
	# Lethal damage ends the match right here (HealthComponent.die()).
	if Global.is_dummy_opponent:
		MultiplayerSync.dummy_damage_taken.emit(_skip_damage())  # the bot has no client of its own
	Global.run.Health.damage(_skip_damage())
	if Global.multiplayer_match_over or not is_inside_tree():
		return
	await get_tree().create_timer(ANSWER_DISPLAY_SECONDS, false).timeout
	if Global.multiplayer_match_over or not is_inside_tree():
		return
	Global.run.current_round.card_playable = true
	_advance_round()


# Small "Skip article" button under the opponent's panel, with the vote
# state underneath it.
func _build_skip_vote() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(952, 124)
	box.size = Vector2(188, 0)
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	skip_button = Button.new()
	skip_button.theme_type_variation = &"SmallButton"
	skip_button.text = "Skip article"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.disabled = true
	skip_button.tooltip_text = "If both players vote, the article is skipped and both take %d damage." % _skip_damage()
	skip_button.pressed.connect(_on_skip_pressed)
	box.add_child(skip_button)
	skip_status = Label.new()
	skip_status.theme_type_variation = &"SmallMuted"
	skip_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(skip_status)
	_update_skip_status()


func _skip_damage() -> int:
	return DRAW_DAMAGE_PER_ROUND * Global.run.round_number


func _opponent_skip_voted() -> bool:
	return MultiplayerSync.opponent_skip_round == Global.run.round_number


func _on_skip_pressed() -> void:
	if skip_voted or round_advancing or not round_started:
		return
	skip_voted = true
	skip_button.disabled = true
	MultiplayerSync.send_skip_vote(Global.run.round_number)
	_update_skip_status()
	_check_skip_vote()


func _on_opponent_skip_voted(round_number: int) -> void:
	if round_number != Global.run.round_number or not is_inside_tree():
		return
	if not skip_voted and not round_advancing:
		SoundManagerScript.play_sfx_overlapping(COUNTDOWN_TICK_SOUND)
	_update_skip_status()
	_check_skip_vote()


func _update_skip_status() -> void:
	var damage := _skip_damage()
	if skip_voted:
		skip_button.text = "Skip voted"
		skip_status.text = "Waiting for opponent (both take %d)" % damage
	elif _opponent_skip_voted():
		skip_status.text = "Opponent wants to skip (both take %d)" % damage
		skip_status.add_theme_color_override("font_color", MatchStyle.color("warning"))
	else:
		skip_status.text = ""


func _check_skip_vote() -> void:
	if skip_voted and _opponent_skip_voted():
		skip_status.text = ""
		_end_round_as_draw("Both players skipped")


# "Freeze" card - opponent locked us out of guessing for a bit.
func _on_frozen(duration: float) -> void:
	if not is_inside_tree() or Global.multiplayer_match_over:
		return  # match already ended and this board's scene is gone - nothing to freeze
	SoundManagerScript.play_sfx_overlapping("res://assets/sounds/sfx/multiplayer/chill.wav", 0.0, Card.MP_EFFECT_PITCH_VARIATION)
	show_status("Frozen", Round.FROZEN_STATUS_COLOR)
	frozen = true
	await get_tree().create_timer(duration, false).timeout
	if Global.multiplayer_match_over:
		return
	frozen = false


const CHAT_HINT_IDLE := "Press T to chat"
const CHAT_HINT_TYPING := "Enter to send · Esc to close"


func _update_chat_hint() -> void:
	%ChatInput.placeholder_text = CHAT_HINT_TYPING if %ChatInput.has_focus() else CHAT_HINT_IDLE


func _focus_chat() -> void:
	%ChatInput.grab_focus()


# Enter in the chat: send (if anything's typed) and leave the chat. The guess
# field doesn't open - press Enter again for that.
func _submit_chat_and_leave() -> void:
	var text: String = %ChatInput.text.strip_edges()
	if not text.is_empty():
		MultiplayerSync.send_chat(text)
	%ChatInput.clear()
	%ChatInput.release_focus()


# "Mute" above the chat: hides the opponent's messages, now and in every
# later match against them (Global.set_player_muted saves it).
var mute_button: Button

func _build_mute_toggle() -> void:
	const HubScreen := preload("res://ui/hub/hub_screen.gd")
	HubScreen._ensure_outline_button(HubScreen.HUB_THEME)
	mute_button = Button.new()
	mute_button.theme = HubScreen.HUB_THEME
	mute_button.theme_type_variation = "OutlineButton"
	mute_button.toggle_mode = true
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.add_theme_font_size_override("font_size", 12)
	mute_button.button_pressed = Global.is_player_muted(Global.multiplayer_opponent_id)
	mute_button.toggled.connect(func(on: bool):
		Global.set_player_muted(Global.multiplayer_opponent_id, on, Global.multiplayer_opponent_name)
		_update_mute_button()
		_rebuild_chat_log())
	%ChatInput.get_parent().add_child(mute_button)
	%ChatInput.get_parent().move_child(mute_button, 0)
	_update_mute_button()


func _update_mute_button() -> void:
	var muted := Global.is_player_muted(Global.multiplayer_opponent_id)
	mute_button.text = "Unmute %s" % Global.multiplayer_opponent_name if muted else "Mute %s" % Global.multiplayer_opponent_name
	mute_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mute_button.clip_text = true
	mute_button.tooltip_text = ("Their messages are hidden. Remembered for future matches." if muted
		else "Hide their chat messages. Remembered for future matches.")


func _rebuild_chat_log() -> void:
	%ChatLog.clear()
	for entry in MultiplayerSync.chat_history:
		_add_chat_line(entry.name, entry.text, entry.own)


func _add_chat_line(sender_name: String, text: String, is_own: bool) -> void:
	if not is_own and Global.is_player_muted(Global.multiplayer_opponent_id):
		return  # muted (still kept in chat_history, so unmuting shows it)
	# Both strings come from other players - escape "[" so they can't inject
	# BBCode into the log.
	%ChatLog.append_text("[color=#%s][b]%s:[/b][/color] [color=#%s]%s[/color]\n" % [
		MatchStyle.color("host_name" if is_own else "guest_name").to_html(false),
		sender_name.replace("[", "[lb]"),
		MatchStyle.color("text").to_html(false),
		text.replace("[", "[lb]"),
	])


# Global.run.current_round is Run's data-only Round, not the scene - the
# real Round (which owns the overlay) is this board's parent.
# --- Round hints (bottom left) ----------------------------------------------
# Same hints as Normal single player, but free and automatic: the difficulty
# (pageview tier) after the 3rd chunk reveal, Wikipedia's short description
# after the 5th. Shown as "after N chunks" until then; left out when the
# article is shorter than that or Wikipedia had nothing.
const DIFFICULTY_AT_CHUNK := 3
const DESCRIPTION_AT_CHUNK := 5
# Left of the hand (Round's Hand starts at x 278), so they never overlap.
const HINT_WIDTH := 228.0
const HINT_BOTTOM := 604.0
# Before it unlocks, a hint grows by up to this much and warms to this red
# as its chunk approaches (_charge_hints).
const HINT_CHARGE_SCALE := 0.07
const HINT_CHARGE_COLOR := Color("#c8102e")
# Played when a hint unlocks (reuses the Letter Reveal card's sound).
const HINT_REVEAL_SOUND := "res://assets/sounds/sfx/multiplayer/letter-reveal.wav"
const HINT_REVEAL_PITCH_VARIATION := 0.05

var difficulty_hint: PanelContainer
var description_hint: PanelContainer


func _build_round_hints() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(12, HINT_BOTTOM - 196)
	box.size = Vector2(HINT_WIDTH, 196)
	# A long description grows the stack upward, not off the bottom.
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var total: int = chunks.size() if chunks else 0
	var current = Global.run.current_round
	if current.article_daily_views >= 0 and total >= DIFFICULTY_AT_CHUNK:
		difficulty_hint = _hint_card()
		box.add_child(difficulty_hint)
	if current.article_description != "" and total >= DESCRIPTION_AT_CHUNK:
		description_hint = _hint_card()
		box.add_child(description_hint)
	_update_round_hints()


# A paper card: small caps heading ("DIFFICULTY") over the value, with an
# accent bar on the left once it's unlocked.
func _hint_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size.x = HINT_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = MatchStyle.color("surface")
	style.border_color = MatchStyle.color("border")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var heading := Label.new()
	heading.theme_type_variation = &"Eyebrow"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	var value := Label.new()
	value.add_theme_font_override("font", preload("res://ui/fonts/plex_500.tres"))
	value.add_theme_font_size_override("font_size", 14)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(value)
	panel.set_meta("style", style)
	panel.set_meta("heading", heading)
	panel.set_meta("value", value)
	panel.set_meta("at_chunk", 0)
	return panel


func _update_round_hints() -> void:
	var current = Global.run.current_round
	if difficulty_hint:
		var views: float = current.article_daily_views
		_set_hint(difficulty_hint, reveal_index >= DIFFICULTY_AT_CHUNK, "Difficulty",
			"%s (~%d views/day)" % [Leaderboards.tier_label_for(views), roundi(views)], DIFFICULTY_AT_CHUNK)
	if description_hint:
		_set_hint(description_hint, reveal_index >= DESCRIPTION_AT_CHUNK, "Description",
			current.article_description, DESCRIPTION_AT_CHUNK)


func _set_hint(panel: PanelContainer, revealed: bool, title: String, value: String, at_chunk: int) -> void:
	var style: StyleBoxFlat = panel.get_meta("style")
	var heading: Label = panel.get_meta("heading")
	var value_label: Label = panel.get_meta("value")
	var was_revealed: bool = panel.get_meta("revealed", false)
	panel.set_meta("at_chunk", at_chunk)
	heading.text = title.to_upper()
	if revealed:
		value_label.text = value
		value_label.add_theme_color_override("font_color", MatchStyle.color("text"))
		heading.add_theme_color_override("font_color", MatchStyle.color("accent"))
		style.border_width_left = 4
		style.border_color = MatchStyle.color("accent")
		if not was_revealed:
			panel.set_meta("revealed", true)
			_play_hint_reveal(panel, style)
	else:
		value_label.text = "Unlocks after %d chunks" % at_chunk
		value_label.add_theme_color_override("font_color", Color(MatchStyle.color("muted"), 0.75))
		heading.add_theme_color_override("font_color", MatchStyle.color("muted"))
		style.border_width_left = 1
		style.border_color = Color(MatchStyle.color("border"), 0.35)


# Locked hints build up toward their unlock: progress = chunks revealed (plus
# the running reveal timer) out of the chunks needed, eased so most of the
# growth and red lands in the last interval before it opens.
func _charge_hints() -> void:
	if round_advancing:
		return
	var frac := 0.0
	if round_started and reveal_timer and reveal_timer.wait_time > 0.0 and reveal_timer.time_left > 0.0:
		frac = 1.0 - reveal_timer.time_left / reveal_timer.wait_time
	for panel in [difficulty_hint, description_hint]:
		if not is_instance_valid(panel) or panel.get_meta("revealed", false):
			continue
		var at_chunk: int = panel.get_meta("at_chunk", 0)
		if at_chunk <= 0:
			continue
		var t := clampf((reveal_index + frac) / float(at_chunk), 0.0, 1.0)
		t = t * t * t
		var style: StyleBoxFlat = panel.get_meta("style")
		panel.pivot_offset = Vector2(0, panel.size.y)  # grows up/right, away from the edge
		panel.scale = Vector2.ONE * (1.0 + HINT_CHARGE_SCALE * t)
		style.bg_color = MatchStyle.color("surface").lerp(HINT_CHARGE_COLOR, 0.28 * t)
		style.border_color = Color(MatchStyle.color("border"), 0.35).lerp(HINT_CHARGE_COLOR, t)
		var value_label: Label = panel.get_meta("value")
		value_label.add_theme_color_override("font_color",
			Color(MatchStyle.color("muted"), 0.75).lerp(HINT_CHARGE_COLOR, 0.8 * t))


# The unlock cue: a sound, a quick pop and a green flash that settles into
# the accent border.
func _play_hint_reveal(panel: PanelContainer, style: StyleBoxFlat) -> void:
	SoundManagerScript.play_sfx_overlapping(HINT_REVEAL_SOUND, -4.0, HINT_REVEAL_PITCH_VARIATION)
	await get_tree().process_frame  # size known after the new text lays out
	if not is_instance_valid(panel):
		return
	panel.pivot_offset = Vector2(0, panel.size.y)
	panel.scale = Vector2.ONE * (1.0 + HINT_CHARGE_SCALE)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.4)
	style.bg_color = MatchStyle.color("added").lerp(MatchStyle.color("surface"), 0.55)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.25)
	tween.tween_property(style, "bg_color", MatchStyle.color("surface"), 1.4).set_delay(0.3)


func show_status(text: String, color: Color) -> void:
	get_parent().show_status(text, color)


# "Static" card - opponent scrambled the visual order of our revealed
# chunks, then restores it once the effect wears off.
func _on_chunks_scrambled(duration: float) -> void:
	if not is_inside_tree() or Global.multiplayer_match_over:
		return  # match already ended and this board's scene is gone - nothing to scramble
	# Played before the size check so the victim still hears the card even
	# when there's too little revealed text for the scramble to be visible.
	SoundManagerScript.play_sfx_overlapping("res://assets/sounds/sfx/multiplayer/shamble.wav", 0.0, Card.MP_EFFECT_PITCH_VARIATION)
	show_status("Chunks are scrambled", Round.SCRAMBLED_STATUS_COLOR)
	var vbox = $ScrollContainer/VBoxContainer
	var original_order = vbox.get_children()
	if original_order.size() <= 1:
		return
	var shuffled = original_order.duplicate()
	shuffled.shuffle()
	for i in range(shuffled.size()):
		vbox.move_child(shuffled[i], i)

	await get_tree().create_timer(duration, false).timeout
	if Global.multiplayer_match_over or not is_inside_tree():
		return
	for i in range(original_order.size()):
		vbox.move_child(original_order[i], i)


# Guessing earlier (fewer chunks revealed) deals more damage. Max damage is
# dealt right after the first chunk is revealed, then drops by a fixed step
# (MAX_GUESS_DAMAGE / total chunks) for every chunk revealed since. All of it
# grows with the round number (GUESS_DAMAGE_GROWTH_PER_ROUND).
func _current_guess_damage() -> int:
	var round_factor := 1.0 + GUESS_DAMAGE_GROWTH_PER_ROUND * float(maxi(Global.run.round_number - 1, 0))
	if not chunks or chunks.size() <= 0:
		return int(round(MAX_GUESS_DAMAGE * round_factor))
	var step = MAX_GUESS_DAMAGE / float(chunks.size())
	var chunks_shown = max(reveal_index, 1)
	return int(round((MAX_GUESS_DAMAGE - float(chunks_shown - 1) * step) * round_factor))


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_update_stake_label()
	_charge_hints()
	if not round_started or reveal_timer.time_left <= 0.0 or reveal_timer.wait_time <= 0.0:
		return
	# Drains from full height down to 0, top edge sinking toward the fixed
	# bottom edge, over the current reveal interval - a countdown
	# "channeling in reverse" toward the next chunk reveal.
	var ratio = reveal_timer.time_left / reveal_timer.wait_time
	var height = TIMER_BAR_HEIGHT * clamp(ratio, 0.0, 1.0)
	$RevealTimerBar.offset_top = $RevealTimerBar.offset_bottom - height
	var mat: ShaderMaterial = $RevealTimerBar.material
	mat.set_shader_parameter("size", Vector2($RevealTimerBar.size.x, height))

# reveal specific part of text
func reveal_chunk(index: int, chunk:String):
	index-=1
	var scroll = $ScrollContainer
	var vbox = $ScrollContainer/VBoxContainer

	var label = vbox.get_child(index) as RichTextLabel
	if label:
		# Store original text color
		var original_color = MatchStyle.color("text")  # hidden ones are faint, revealed = ink

		# Set the text
		label.text = chunk

		# Create tween for smooth color transition with your custom color
		var tween = create_tween()
		tween.tween_method(
			func(color):
				label.add_theme_color_override("default_color", color),
			MatchStyle.color("added"),  # revealed chunk flashes green, then fades to ink
			original_color,
			0.5
		)

		if Global.auto_scroll_to_reveal and is_inside_tree() and get_tree():
			await get_tree().process_frame # Wait one frame for layout to update
			scroll.scroll_vertical = label.position.y

	shake_board()

func update_board_chunks():
	if !chunks:
		return
	var vbox = $ScrollContainer/VBoxContainer

	for sentence in chunks:
		var label = RichTextLabel.new()
		var hidden_text = ""

		# replace each character except spaces/newlines with "_"
		for c in sentence:
			hidden_text += c if c == " " or c == "\n" else "_"

		label.text = hidden_text
		label.fit_content = true
		# Hidden sentences are faint so the revealed ones stand out.
		label.add_theme_color_override("default_color", Color(MatchStyle.color("muted"), 0.45))
		vbox.add_child(label)


func open_guess() -> void:
	if guess_open or not round_started or round_advancing:
		return
	guess_open = true
	$InputField.text = ""
	$InputField.reset_border()
	$InputField.visible = true
	$LetterRevealHint.visible = Global.run.letter_reveal_armed
	$InputField.grab_focus()


func close_guess() -> void:
	guess_open = false
	$InputField.text = ""
	$InputField.visible = false
	$LetterRevealHint.visible = false
	$InputField.release_focus()


func _input(event):
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if Global.settings_overlay_open:
		return
	var is_enter = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
	if %ChatInput.has_focus():
		# Handled here, before the LineEdit sees the key.
		if is_enter:
			get_viewport().set_input_as_handled()
			_submit_chat_and_leave()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()  # not Global's Esc-presses-Back
			%ChatInput.release_focus()
		return
	if event.keycode == KEY_T and not guess_open:
		get_viewport().set_input_as_handled()  # so the "t" isn't typed into the chat
		_focus_chat()
		return
	if guess_open and (event.keycode == KEY_ESCAPE or (event.keycode == KEY_BACKSPACE and $InputField.text.is_empty())):
		close_guess()
		get_viewport().set_input_as_handled()
		return
	if not is_enter or not round_started or round_advancing:
		return
	get_viewport().set_input_as_handled()
	if not guess_open:
		open_guess()
		return
	if frozen:
		return  # field stays open - submit again once the freeze wears off
	if guess_checking:
		return  # still flashing the last wrong guess
	var typed = $InputField.text.strip_edges()
	if typed.is_empty():
		close_guess()
		return

	if Global.run.letter_reveal_armed:
		Global.run.letter_reveal_armed = false
		update_letter_reveal_hint(false)
		close_guess()
		Global.run.current_round.reveal_letter_value(typed.left(1))
		return

	var guess = simplify_string(typed.to_lower())
	var solution = simplify_string(Global.run.current_round.article_title.strip_edges().to_lower())
	var alternative_solution =  simplify_string(Global.run.current_round.article_alternative_title.strip_edges().to_lower())
	if Global.is_guess_match(guess, solution) or Global.is_guess_match(guess, alternative_solution):
		correct_guess(typed)
		return

	guess_checking = true
	$InputField.wrong_border()
	await get_tree().create_timer(0.5, false).timeout
	guess_checking = false
	if not is_inside_tree():
		return
	if Global.is_gibberish_guess(typed):
		close_guess()  # a stray "/" or single letter - not counted, no HP lost
		return
	Global.run.log_guess("you", typed, false)
	PlayerStats.record_wrong()
	var self_damage = 50
	if Global.run.double_down_armed:
		self_damage = 200
		Global.set_double_down_armed(false)
	Global.run.Health.damage(self_damage)
	if Global.multiplayer_match_over:
		return  # damage() can end the match mid-function - bail before touching the freed scene
	MultiplayerSync.send_guess_result(false, 0, typed)
	close_guess()
	Global.run.number_of_wrong_guesses += 1

# typed_guess is what the player entered, shown on the opponent's screen -
# empty when a Letter Reveal completed the title instead.
func correct_guess(typed_guess: String = ""):
	# not is_inside_tree() matters here specifically because this can be
	# reached two ways: the normal typed guess, and reveal_letter_value()
	# (round.gd) calling straight into this when a Letter Reveal happens to
	# complete the title - that second path has no guard of its own before
	# reaching here, so a board that's already detached from the tree (e.g.
	# the match just ended a moment earlier) would otherwise hit a null
	# get_tree() at the create_timer call below instead of a clean no-op.
	if round_advancing or Global.multiplayer_match_over or not is_inside_tree():
		return
	round_advancing = true
	reveal_timer.stop()  # pause chunk reveals until the next round starts
	_stop_timer_charge()
	skip_button.disabled = true

	Global.setAchievement(Global.getArticleAch(Global.run.current_round.current_id))
	Global.play_article_ach_sound(Global.run.current_round.current_id)
	Global.run.current_round.card_playable = false

	var damage = _current_guess_damage()
	if Global.run.double_down_armed:
		damage *= 2
		Global.set_double_down_armed(false)
	# The opponent's own Double Down doubles it again on their side.
	var damage_dealt = damage * 2 if Global.opponent_double_down_armed else damage
	# Logged first: in dummy mode the send below can end the match on the spot.
	Global.run.log_guess("you", typed_guess, true)
	Global.run.log_article("you", damage_dealt)
	PlayerStats.record_correct(Global.run.current_round.image_id, Global.run.current_round.article_title,
		reveal_index, chunks.size() if chunks else 0)
	MultiplayerSync.send_guess_result(true, damage, typed_guess)
	if Global.multiplayer_match_over or not is_inside_tree():
		return  # dummy-opponent mode routes this synchronously all the way through DummyOpponent -> opponent_match_over -> change_scene_to_file, unlike a real match where this just fires off an async network message - a killing blow here can end the match and free this scene before the next line runs

	close_guess()
	$ArticleTitle.text = Global.run.current_round.article_title
	get_parent().show_banner("-%d" % damage_dealt, Round.DAMAGE_DEALT_COLOR)
	get_parent().show_answer("", CORRECT_IMAGE_SECONDS)  # the article's picture, if it has one
	await get_tree().create_timer(CORRECT_IMAGE_SECONDS, false).timeout
	if Global.multiplayer_match_over or not is_inside_tree():
		return

	if not Global.run.last_article:
		# No point offering a reward right before the match itself ends -
		# there's no "next round" for it to carry into.
		await _run_card_reward_choice()
		if Global.multiplayer_match_over or not is_inside_tree():
			return

	Global.run.current_round.card_playable = true
	_advance_round()


# Called on the receiving end whenever the winner hands over the reward card
# they didn't pick. loser_action goes into Run.mp_hand, which
# survives the upcoming scene reload, so the next round's deal picks it up. winner_action is only needed by _watch_opponent_reward_choice
# below, to know which of the two mirrored cards to animate.
func _on_card_reward_received(winner_action: int, loser_action: int) -> void:
	print("[MPDEBUG] RECEIVED card_reward winner_action=%d loser_action=%d" % [winner_action, loser_action])
	if loser_action == Card.Action_sub_type.mp_heal:
		# A leftover Heal is applied right away instead of becoming a card -
		# same amount the picker showed (next round's value).
		if not Global.multiplayer_match_over:
			SoundManagerScript.play_sfx_overlapping(REWARD_SOUNDS["heal"], Card.MP_HEAL_SOUND_VOLUME_DB, Card.MP_EFFECT_PITCH_VARIATION)
			Global.run.Health.heal(Card.mp_heal_amount(Global.run.round_number + 1))
	else:
		Global.run.mp_hand.append(loser_action)
	_pending_card_reward_winner_action = winner_action
	_pending_card_reward_ready = true


func _on_reward_picker_started_signal(key_a: String, key_b: String) -> void:
	print("[MPDEBUG] RECEIVED reward_picker_started key_a=%s key_b=%s" % [key_a, key_b])
	_pending_reward_picker_info = [key_a, key_b]
	_pending_reward_picker_ready = true


func _on_reward_none_signal() -> void:
	print("[MPDEBUG] RECEIVED reward_none")
	_pending_reward_picker_info = []
	_pending_reward_picker_ready = true


# Every special is always on offer, including ones already played or still
# in hand this match - a reward is just one more card added to the hand.
func _available_reward_keys() -> Array:
	return REWARD_SPECIALS.keys()


# Winner picks 1 of 2 reward cards for themselves; the other is handed to the
# opponent. The fewer-than-2 fallback below can't trigger with the current
# always-full pool, but stays as a guard if the pool is ever filtered again -
# the opponent is told there's nothing to watch, so their mirror
# (_watch_opponent_reward_choice) doesn't sit waiting for a picker that will
# never come.
func _run_card_reward_choice() -> void:
	var available = _available_reward_keys()
	available.shuffle()
	print("[MPDEBUG] _run_card_reward_choice available=%s" % [available])
	if available.size() < 2:
		if available.size() == 1:
			Global.run.mp_hand.append(REWARD_SPECIALS[available[0]])
		print("[MPDEBUG] sending reward_none (fewer than 2 available)")
		MultiplayerSync.send_reward_none()
		return

	print("[MPDEBUG] sending reward_picker_started key_a=%s key_b=%s" % [available[0], available[1]])
	MultiplayerSync.send_reward_picker_started(available[0], available[1])
	var result = await _show_reward_picker(available[0], available[1])
	if Global.multiplayer_match_over or not is_inside_tree():
		return
	var picked: String = result.key
	var leftover = available[1] if picked == available[0] else available[0]
	Global.run.mp_hand.append(REWARD_SPECIALS[picked])
	print("[MPDEBUG] sending card_reward winner_action=%d loser_action=%d" % [REWARD_SPECIALS[picked], REWARD_SPECIALS[leftover]])
	MultiplayerSync.send_card_reward(REWARD_SPECIALS[picked], REWARD_SPECIALS[leftover])
	SoundManagerScript.play_sfx_overlapping(REWARD_SOUNDS[picked], Card.MP_HEAL_SOUND_VOLUME_DB if picked == "heal" else 0.0, Card.MP_EFFECT_PITCH_VARIATION)

	# Gives the opponent's mirrored view (_watch_opponent_reward_choice) time
	# to play its "opponent picked!" animation before both sides land in the
	# next round - the whole point being that they start together rather than
	# racing each other in on their own independent timers. The overlay stays
	# up (highlighting the pick) for the whole wait, so the finished round
	# underneath can't be interacted with in the meantime.
	var sync_wait = get_tree().create_timer(2.0, false)
	await _play_card_highlight(result.card)
	if Global.multiplayer_match_over or not is_inside_tree():
		return
	if sync_wait.time_left > 0.0:
		await sync_wait.timeout
	result.overlay.queue_free()


# Watches the SAME choice on the non-guesser's screen instead of racing ahead
# into the next round while the winner is still picking. Waits for the
# winner to actually finish (or for a "nothing to watch" signal / timeout),
# so both clients advance to the next round at roughly the same moment.
func _watch_opponent_reward_choice() -> void:
	print("[MPDEBUG] _watch_opponent_reward_choice: waiting for reward_picker_started/reward_none")
	var picker_info = await _wait_for_reward_picker_signal()
	if Global.multiplayer_match_over or not is_inside_tree():
		return
	if picker_info.is_empty():
		print("[MPDEBUG] _watch_opponent_reward_choice: nothing to watch (reward_none or timed out)")
		return  # reward_none, or the message never arrived - nothing to watch

	var key_a = picker_info[0]
	var key_b = picker_info[1]
	print("[MPDEBUG] _watch_opponent_reward_choice: showing mirrored picker key_a=%s key_b=%s" % [key_a, key_b])
	var built = _build_reward_overlay(key_a, key_b, "Opponent is choosing a reward...")
	var overlay = built.overlay
	var timer_bar = built.timer_bar

	# _pending_card_reward_ready is NOT reset here - it's reset once in
	# _ready() instead (see the comment there), so an already-arrived message
	# is never mistaken for "nothing yet" and wiped out from under us.
	var bar_timer = get_tree().create_timer(REWARD_PICK_TIMEOUT_SECONDS, false)
	var overall_timeout = get_tree().create_timer(CARD_REWARD_WAIT_TIMEOUT_SECONDS, false)
	while not _pending_card_reward_ready:
		if Global.multiplayer_match_over or not is_inside_tree():
			overlay.queue_free()
			return
		_set_timer_bar_ratio(timer_bar, clamp(bar_timer.time_left / REWARD_PICK_TIMEOUT_SECONDS, 0.0, 1.0))
		if overall_timeout.time_left <= 0.0:
			print("[MPDEBUG] _watch_opponent_reward_choice: timed out waiting for card_reward")
			break
		await get_tree().process_frame

	if _pending_card_reward_ready:
		var chosen_card = built.card_a if REWARD_SPECIALS[key_a] == _pending_card_reward_winner_action else built.card_b
		built.label.text = "Opponent picked their reward!"
		await _play_card_highlight(chosen_card)
	else:
		# The pick message never arrived in time - still worth a beat so this
		# doesn't slam back into the next round with no explanation at all.
		await get_tree().create_timer(2.0, false).timeout

	overlay.queue_free()


func _wait_for_reward_picker_signal() -> Array:
	# Not reset here - see the comment in _ready(). The message races a local
	# timer on this client, so it can legitimately already be true by the time
	# this function is even called.
	var timeout = get_tree().create_timer(REWARD_SYNC_TIMEOUT_SECONDS, false)
	while not _pending_reward_picker_ready:
		if Global.multiplayer_match_over or not is_inside_tree():
			return []
		if timeout.time_left <= 0.0:
			return []
		await get_tree().process_frame
	return _pending_reward_picker_info


# Keeps the ColorRect's own Control size and the rounded-rect shader's "size"
# parameter in sync - the shader draws the rounded/glowing shape based on its
# own uniform, not the node's actual rect, so both need updating together.
func _set_timer_bar_ratio(bar: ColorRect, ratio: float) -> void:
	var width = REWARD_TIMER_BAR_WIDTH * ratio
	bar.size.x = width
	var mat: ShaderMaterial = bar.material
	mat.set_shader_parameter("size", Vector2(width, REWARD_TIMER_BAR_HEIGHT))


func _build_reward_card_visual(key: String) -> Card:
	var card: Card = CardScene.instantiate()
	card.card_type = 3  # matches deck.gd's convention - Card.Type isn't actually used for this field
	card.action_type = REWARD_SPECIALS[key]
	var card_symbol = card.get_node("CardSymbol") as Sprite2D
	var card_title = card.get_node("CardTitle") as RichTextLabel
	var card_description = card.get_node("Description") as RichTextLabel
	var effect_text = card.get_node("EffectText") as RichTextLabel
	var effect_symbol = card.get_node("EffectIcon") as Sprite2D
	card_symbol.texture = load("res://assets/sprites/action_card.png")
	match key:
		"double_down":
			card_title.text = "Double Down"
			card_description.text = "Next correct guess deals 2x damage (including your opponent's).\nA wrong guess costs you 200 HP."
			effect_symbol.texture = load("res://assets/sprites/HP.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "2x"
		"letter_snipe":
			card_title.text = "Letter Snipe"
			card_description.text = "Instantly reveals one random letter in the title. Free."
			effect_symbol.texture = load("res://assets/sprites/mana.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "1x"
		"letter_reveal":
			card_title.text = "Letter Reveal"
			card_description.text = "Submit one letter next to reveal every match in the title."
			effect_symbol.texture = load("res://assets/sprites/mana.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "1x"
		"freeze":
			card_title.text = "Freeze"
			card_description.text = "Opponent can't submit guesses for 2 seconds."
			effect_text.text = "2s"
		"chunk_scramble":
			card_title.text = "Static"
			card_description.text = "Scrambles the order of the opponent's revealed text for 5 seconds."
			effect_text.text = "5s"
		"heal":
			# Reward cards are played next round, after _advance_round bumps
			# round_number - show what it'll actually heal then.
			var heal_amount = Card.mp_heal_amount(Global.run.round_number + 1)
			card_title.text = "Heal"
			card_description.text = "Restores %d HP next round.\nScales with the round: 300 x round / 2." % heal_amount
			effect_symbol.texture = load("res://assets/sprites/HP.png")
			effect_symbol.position = effect_symbol.position + Vector2(-5, 5)
			effect_text.text = "+%d" % heal_amount
	return card


# Builds the shared two-card overlay used by both the winner's interactive
# picker and the loser's read-only mirror. Neither card is parented under an
# HBoxContainer, so Card's own click-to-play handler (_on_gui_input, gated on
# get_parent() is HBoxContainer) never fires here.
func _build_reward_overlay(key_a: String, key_b: String, label_text: String) -> Dictionary:
	var overlay = ColorRect.new()
	overlay.color = MatchStyle.color("overlay_dim")
	overlay.position = Vector2.ZERO
	overlay.size = get_viewport_rect().size
	# STOP (rather than the board's usual click-through) is the point here -
	# it blocks clicks/hover from reaching the hand or input field underneath
	# while this is up, on top of round_advancing/card_playable already being
	# false so nothing would happen if a click did get through.
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_font_override("font", preload("res://ui/fonts/fraunces_600.tres"))
	label.add_theme_color_override("font_color", MatchStyle.color("surface"))
	overlay.add_child(label)
	label.position = Vector2(overlay.size.x / 2 - label.size.x / 2, 80)

	var card_a = _build_reward_card_visual(key_a)
	var card_b = _build_reward_card_visual(key_b)
	overlay.add_child(card_a)
	overlay.add_child(card_b)
	# Card._ready() (which just ran via add_child above) hides the whole node
	# in multiplayer by default, since drawn-but-unrevealed cards normally sit
	# hidden in the deck stack until draw_card() shows them - force it back on.
	card_a.visible = true
	card_b.visible = true
	card_a.position = Vector2(overlay.size.x / 2 - 190, overlay.size.y / 2 - 125)
	card_b.position = Vector2(overlay.size.x / 2 + 20, overlay.size.y / 2 - 125)
	# Scale/rotate happen around the card's center, not its top-left corner.
	card_a.pivot_offset = card_a.size / 2
	card_b.pivot_offset = card_b.size / 2

	# Same rounded-rect shader/style as the round's chunk-reveal timer bar
	# ($RevealTimerBar), just horizontal instead of vertical, sitting below
	# the two cards.
	var timer_bar = ColorRect.new()
	timer_bar.color = Color(1, 1, 1, 1)
	timer_bar.size = Vector2(REWARD_TIMER_BAR_WIDTH, REWARD_TIMER_BAR_HEIGHT)
	timer_bar.position = Vector2(overlay.size.x / 2 - REWARD_TIMER_BAR_WIDTH / 2, overlay.size.y / 2 + 160)
	var timer_bar_mat := ShaderMaterial.new()
	timer_bar_mat.shader = load("res://components/rounded_rect.gdshader")
	timer_bar_mat.set_shader_parameter("color", MatchStyle.color("accent"))
	timer_bar_mat.set_shader_parameter("size", Vector2(REWARD_TIMER_BAR_WIDTH, REWARD_TIMER_BAR_HEIGHT))
	timer_bar_mat.set_shader_parameter("radius", 6.0)
	timer_bar_mat.set_shader_parameter("glow_strength", 0.0)
	timer_bar_mat.set_shader_parameter("glow_width", 0.2)
	timer_bar_mat.set_shader_parameter("glow_flicker_speed", 3.0)
	timer_bar.material = timer_bar_mat
	overlay.add_child(timer_bar)

	return {"overlay": overlay, "label": label, "card_a": card_a, "card_b": card_b, "timer_bar": timer_bar}


# Returns {key, card, overlay} - the overlay is left up for the caller to free
# once it's done showing the result (see _run_card_reward_choice).
func _show_reward_picker(key_a: String, key_b: String) -> Dictionary:
	_reward_picked_key = ""

	var built = _build_reward_overlay(key_a, key_b, "Pick your reward card")
	var overlay = built.overlay
	var card_a = built.card_a
	var card_b = built.card_b
	var timer_bar = built.timer_bar

	card_a.gui_input.connect(_on_reward_card_gui_input.bind(key_a))
	card_b.gui_input.connect(_on_reward_card_gui_input.bind(key_b))
	_add_reward_card_hover(card_a)
	_add_reward_card_hover(card_b)

	var timed_out := false
	var timeout = get_tree().create_timer(REWARD_PICK_TIMEOUT_SECONDS, false)
	while _reward_picked_key == "":
		if Global.multiplayer_match_over or not is_inside_tree():
			overlay.queue_free()
			return {"key": key_a, "card": null, "overlay": null}  # caller re-checks match_over/is_inside_tree right after and bails anyway
		_set_timer_bar_ratio(timer_bar, clamp(timeout.time_left / REWARD_PICK_TIMEOUT_SECONDS, 0.0, 1.0))
		if timeout.time_left <= 0.0:
			_reward_picked_key = key_a
			timed_out = true
			break
		await get_tree().process_frame

	# Freeze both cards so hover tweens can't fight the caller's highlight.
	for card in [card_a, card_b]:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	built.label.text = "Time's up! You got:" if timed_out else "You picked:"
	var picked_card = card_a if _reward_picked_key == key_a else card_b
	return {"key": _reward_picked_key, "card": picked_card, "overlay": overlay}


# GDScript lambdas capture outer local variables by value, not reference, so
# an inline closure assigning to a local var (e.g. a "picked_key" declared in
# _show_reward_picker) would silently write to a throwaway copy - hence a
# real bound method writing to this instance field instead.
func _on_reward_card_gui_input(event: InputEvent, key: String) -> void:
	if _reward_picked_key == "" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_reward_picked_key = key


# Zoom + sway + purple glow on hover. Separate from Card's own built-in hover
# effect (_on_mouse_entered/_on_mouse_exited in card.gd), which only acts when
# the card sits in the Hand HBoxContainer - these picker cards never do.
func _add_reward_card_hover(card: Card) -> void:
	var bg := card.get_node("MinimalBackground") as ColorRect
	var mat := bg.material as ShaderMaterial
	var base_border_color: Color = mat.get_shader_parameter("border_color")
	var base_border_width: float = mat.get_shader_parameter("border_width")
	var glow_color := MatchStyle.color("accent")
	var glow_width := 6.0

	card.mouse_entered.connect(func():
		if card.sway_tween:
			card.sway_tween.kill()
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(card, "scale", Vector2(1.08, 1.08), 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_method(func(c): mat.set_shader_parameter("border_color", c), base_border_color, glow_color, 0.15)
		tween.tween_method(func(w): mat.set_shader_parameter("border_width", w), base_border_width, glow_width, 0.15)

		card.sway_tween = create_tween().set_loops()
		card.sway_tween.tween_property(card, "rotation_degrees", 4.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		card.sway_tween.tween_property(card, "rotation_degrees", -4.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	)

	card.mouse_exited.connect(func():
		if card.sway_tween:
			card.sway_tween.kill()
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(card, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(card, "rotation_degrees", 0.0, 0.15)
		tween.tween_method(func(c): mat.set_shader_parameter("border_color", c), glow_color, base_border_color, 0.15)
		tween.tween_method(func(w): mat.set_shader_parameter("border_width", w), glow_width, base_border_width, 0.15)
	)


# One-shot "this is the one" reveal for the non-guesser's mirrored picker -
# zoom/glow in, hold, zoom/glow back out. Same visual language as the hover
# effect above, just played once instead of on mouse enter/exit.
func _play_card_highlight(card: Card) -> void:
	var bg := card.get_node("MinimalBackground") as ColorRect
	var mat := bg.material as ShaderMaterial
	var base_border_color: Color = mat.get_shader_parameter("border_color")
	var base_border_width: float = mat.get_shader_parameter("border_width")
	var glow_color := MatchStyle.color("accent")
	var glow_width := 6.0

	var tween_in = create_tween()
	tween_in.set_parallel(true)
	tween_in.tween_property(card, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween_in.tween_method(func(c): mat.set_shader_parameter("border_color", c), base_border_color, glow_color, 0.25)
	tween_in.tween_method(func(w): mat.set_shader_parameter("border_width", w), base_border_width, glow_width, 0.25)
	await tween_in.finished
	if not is_inside_tree():
		return

	await get_tree().create_timer(1.3, false).timeout
	if not is_inside_tree():
		return

	var tween_out = create_tween()
	tween_out.set_parallel(true)
	tween_out.tween_property(card, "scale", Vector2.ONE, 0.2)
	tween_out.tween_method(func(c): mat.set_shader_parameter("border_color", c), glow_color, base_border_color, 0.2)
	tween_out.tween_method(func(w): mat.set_shader_parameter("border_width", w), glow_width, base_border_width, 0.2)
	await tween_out.finished


func _on_opponent_guess_result(correct: bool, damage: int, guess: String) -> void:
	# not is_inside_tree() matters here for the same reason it does in
	# correct_guess() - this fires off an incoming network message, so it can
	# land at any time, including after the match already ended and this
	# board got detached from the tree through some other path a moment
	# earlier (grace period expiring, opponent leaving, etc.).
	if not correct:
		# Their wrong guesses go in the end screen's per-article list (text
		# only from builds that send it).
		if round_started and not round_advancing and not Global.multiplayer_match_over:
			Global.run.log_guess("opponent", guess, false)
		return
	if round_advancing or Global.multiplayer_match_over or not is_inside_tree():
		return
	round_advancing = true
	close_guess()
	reveal_timer.stop()  # pause chunk reveals until the next round starts
	_stop_timer_charge()
	skip_button.disabled = true
	skip_status.text = ""
	Global.run.current_round.card_playable = false
	if Global.run.double_down_armed:
		damage *= 2  # our Double Down backfired - they guessed first
		Global.set_double_down_armed(false)
	Global.run.log_guess("opponent", guess, true)
	Global.run.log_article("opponent", damage)
	Global.run.Health.damage(damage)
	if Global.multiplayer_match_over:
		return  # damage() can end the match mid-function - bail before touching the freed scene
	get_parent().show_banner("-%d" % damage, Round.DAMAGE_TAKEN_COLOR)
	# Show what they typed (fuzzy matching means it can differ from the
	# title, so the real title goes underneath), and fill in the title bar.
	var title: String = Global.run.current_round.article_title
	Global.run.current_round.article_censored_title = title
	update_board_title()
	if guess == "":
		get_parent().show_answer(title, ANSWER_DISPLAY_SECONDS, "Opponent completed the title")
	else:
		var footer = "" if simplify_string(guess) == simplify_string(title) else "Answer: " + title
		get_parent().show_answer(guess, ANSWER_DISPLAY_SECONDS, "Opponent guessed", footer)
	await get_tree().create_timer(ANSWER_DISPLAY_SECONDS, false).timeout
	if Global.multiplayer_match_over or not is_inside_tree():
		return

	if not Global.run.last_article:
		await _watch_opponent_reward_choice()
		if Global.multiplayer_match_over or not is_inside_tree():
			return

	Global.run.current_round.card_playable = true
	_advance_round(false)  # opponent guessed correctly, not us - this client lost


# i_am_winner only matters when this is the last article: it's who guessed
# the final round, not a coin flip, so the client that didn't guess (the one
# reacting to opponent_guess_result) must be told explicitly.
func _advance_round(i_am_winner: bool = true) -> void:
	if Global.multiplayer_match_over or not is_inside_tree():
		return  # match already ended (e.g. opponent's match-over RPC beat us here) - scene may be gone
	Global.run.round_number += 1
	if Global.run.last_article == true:
		Global.end_multiplayer_match("won" if i_am_winner else "lost")
		Global.show_match_end()
	else:
		Global.run.current_round.end_round()


# What's riding on this round right now: the damage a correct guess deals -
# whoever makes it. Double Down doubles it both ways, so either player's
# armed card applies to both directions.
func _update_stake_label() -> void:
	var multiplier = 1
	if Global.run.double_down_armed:
		multiplier *= 2
	if Global.opponent_double_down_armed:
		multiplier *= 2
	var stake = _current_guess_damage() * multiplier
	# Plus what a drawn round (nobody guesses / both skip) costs each player.
	var draw_text := "  ·  Nobody guesses: %d each" % _skip_damage()
	if multiplier > 1:
		$StakeLabel.text = "Damage: %d (x%d)%s" % [stake, multiplier, draw_text]
		$StakeLabel.add_theme_color_override("font_color", MatchStyle.color("warning"))
	else:
		$StakeLabel.text = "Damage: %d%s" % [stake, draw_text]
		$StakeLabel.add_theme_color_override("font_color", MatchStyle.color("muted"))


func _center_title() -> void:
	$ArticleTitle.position.x = (get_viewport_rect().size.x / 2) - ($ArticleTitle.size.x / 2)


# Article text + title font size, shifted by the settings overlay's -/+ option.
func apply_text_size() -> void:
	var offset = Global.article_text_size_offset
	for label in $ScrollContainer/VBoxContainer.get_children():
		label.add_theme_font_size_override("normal_font_size", _base_chunk_font_size + offset)
	$ArticleTitle.add_theme_font_size_override("normal_font_size", _base_title_font_size + offset)


func update_board_title():
	var title = Global.run.current_round.article_censored_title
	var title_length = Global.run.current_round.article_title_length

	$ArticleTitle.text = title + " (" + str(title_length) + ")"
	$ArticleTitle.add_theme_constant_override("letter_spacing", 102)

	shake_board($ArticleTitle, 5, 0.03)  # Smaller, faster shake for title


# Called by card.gd right after arming Letter Reveal (Action_sub_type 14),
# same as the other update_* calls it makes on current_board. Caps the input
# field to one character while active so there's no ambiguity about what
# "submit one letter" means, on top of _input()'s own letter.left(1).
func update_letter_reveal_hint(active: bool) -> void:
	$LetterRevealHint.visible = active and guess_open
	$InputField.max_length = 1 if active else 0
	if active:
		open_guess()  # straight into typing the letter


func get_title_count(text: String) -> int:
	var count = 0
	for c in text:
		# Includes A-Z, a-z, and 0-9
		if Global.is_guessable_char(c):
			count += 1
	return count

# LegacyEffects/HealCombo/ManaCombo are hidden in this scene, but card.gd
# calls these unconditionally on whatever current_board is - kept so cards
# don't error out until the multiplayer deck removes legacy/combo cards.
func update_legacy_effects():
	$LegacyRoundHeal.text = "Healing each round: " + str(Global.run.legacy_heal * 10)
	$LegacyMaxHP.text = "Additional Max HP: " + str(Global.run.legacy_max_hp *10)
	$LegacyManaRestore.text = "Mana Restore each round: %d" % Global.run.legacy_mana_restore
	$LegacyMaxMana.text = "Additional Max Mana: %d" % Global.run.legacy_max_mana
	shake_board($LegacyEffects, 5, 0.03)  # Smaller, faster shake for title


func update_deck_counter():
	pass  # no card-count readout in multiplayer - just the deck-back stack visual


func update_heal_combo():
	$HealCombo.text = "Heal Combo: " + str(Global.run.Health.combo_modifier)
	shake_board($HealCombo, 5, 0.03)  # Smaller, faster shake for title

func update_mana_combo():
	$ManaCombo.text = "Mana Combo: " + str(Global.run.Mana.combo_modifier)
	shake_board($ManaCombo, 5, 0.03)  # Smaller, faster shake for title


func shake_board(target_node: Node = $ScrollContainer, shake_strength: float = 10, step_duration: float = 0.05):
	if shake_tween:
		shake_tween.kill()

	shake_tween = create_tween()
	shake_tween.set_parallel(true)

	var original_x = target_node.position.x

	# Create a quick back-and-forth shake
	shake_tween.tween_property(target_node, "position:x", original_x + shake_strength, step_duration)
	shake_tween.tween_property(target_node, "position:x", original_x - shake_strength, step_duration).set_delay(step_duration)
	shake_tween.tween_property(target_node, "position:x", original_x + shake_strength/2, step_duration).set_delay(step_duration * 2)
	shake_tween.tween_property(target_node, "position:x", original_x - shake_strength/2, step_duration).set_delay(step_duration * 3)
	shake_tween.tween_property(target_node, "position:x", original_x, step_duration).set_delay(step_duration * 4)

func simplify_string(text: String) -> String:
	var simplified = text.to_lower().strip_edges()
	# Collapse any run of internal whitespace (e.g. an accidental double
	# space) down to a single space, since is_guess_match() requires an
	# exact character-for-character match for titles 12 characters or
	# shorter, with zero tolerance.
	simplified = " ".join(simplified.split(" ", false))
	simplified = Global.strip_accents(simplified)

	return simplified
