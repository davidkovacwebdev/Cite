extends "res://ui/hub/hub_screen.gd"

# Daily Challenge: 5 Wikipedia articles, the same for everyone each day
# (DailyState picks them). Per article one sentence shows at the start and
# another reveals on a timer (same pace as multiplayer); guess the title any
# time. A solve scores 1,000 points while only the first sentence shows, a
# fixed step less per sentence revealed after (the multiplayer damage curve),
# minus 50 per wrong guess; giving up / running out of time scores 0. After the fifth
# article: summary and the Steam daily leaderboard.
#
# Not part of the Round/Board system - no cards, HP or mana - but it reuses
# Article's censoring (format_text / split_sentences) and Global's guess
# matching, so titles hide and match exactly like in the other modes.

const DailyState := preload("res://ui/daily/daily_state.gd")
# Extract + redirects: redirects give the title's other spellings ("Sulphur"
# for "Sulfur"), which get blanked in the text and count as correct guesses.
const ARTICLE_URL := "https://en.wikipedia.org/w/api.php?action=query&prop=extracts%%7Credirects&rdlimit=max&rdnamespace=0&pageids=%d&explaintext=true&exintro=true&format=json&origin=*"
const VARIANT_SIMILARITY := 0.6  # how close a redirect must be to the title to count as a spelling of it
const MIN_CHUNKS := 4  # intros with fewer sentences are skipped (too little to reveal)
const MAX_CHUNKS := 10  # only the intro's first sentences are used (~1.5 min per article max)
const HIDDEN_ALPHA := 0.35  # hidden sentences: faint underscores, so revealed text stands out
const GRACE_SECONDS := 10.0  # after the last sentence, then the article is lost
const WRONG_FLASH_SECONDS := 0.5
const PANEL_WIDTH := 860
const CLICK := "res://assets/sounds/sfx/click"
const TIMER_END_SOUND := "res://assets/sounds/sfx/multiplayer/timer-end.wav"

enum Phase { LOADING, PLAYING, ANSWER, SUMMARY, ERROR }

var daily_number := 0
var state := {}
var candidates: Array = []
var phase: int = Phase.LOADING

# Current article.
var article_id := 0
var title := ""
var alt_title := ""
var set_key := ""  # which set of articles today is (DailyState.todays_set)
var set_source := ""  # "online" / "offline" / "local"
var final_uploaded := false  # the leaderboard has the finished Daily
var final_upload_busy := false
var variants: Array = []
var chunk_starts: Array = []  # other spellings of the title (from redirects)
var chunks: Array = []
var order: Array = []
var revealed := 0  # how many of `order` are showing
var interval_left := 0.0
var interval_total := 1.0
var in_grace := false
var wrong := 0
var guess_locked := false

var http: HTTPRequest
var article_tool  # Article (components/article_component.gd), off-tree, for censoring

# Widgets.
var pips_row: HBoxContainer
var score_label: Label
var panel_box: VBoxContainer
var article_label: Label
var worth_label: Label
var title_label: Label
var letters_label: Label
var timer_bar: ProgressBar
var text_label: RichTextLabel
var feedback_label: Label
var bottom_row: HBoxContainer
var guess_input: LineEdit
var guess_button: Button
var give_up_button: Button
var next_button: Button
var quit_button: Button


func _ready() -> void:
	var column := _setup_screen("Play", false)
	daily_number = DailyState.today_number()
	state = DailyState.load_day(daily_number)  # provisional, for the header until the set is known
	article_tool = preload("res://components/article_component.gd").new()

	http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(_on_article_loaded)

	_build(column)
	title_label.text = "Loading today's articles..."
	_set_guessing(false)

	# Today's set comes from the online schedule (cached copy / local seed
	# if that fails) - see DailyState.todays_set.
	await DailyState.fetch_schedule(self)
	if not is_inside_tree():
		return
	var day_set := DailyState.todays_set(daily_number, int(state["reroll"]))
	candidates = day_set["ids"]
	set_key = day_set["key"]
	set_source = day_set["source"]
	state = DailyState.load_day(daily_number, set_key)

	# The leaderboard entry is the record of today's attempt: if it's further
	# along than daily.cfg (file deleted), continue from it.
	if _uploads_progress():
		title_label.text = "Checking your Daily..."
		var own: Dictionary = await Leaderboards.own_entry(Leaderboards.daily_board_name(daily_number, set_key))
		if not is_inside_tree():
			return
		var remote: Array = own["entry"].get("details", [])
		if not own["entry"].is_empty() and DailyState.merge_progress(state, remote):
			DailyState.save_day(daily_number, state)
		# Record already up to date: viewing the results again needn't re-upload.
		final_uploaded = DailyState.is_finished(state) and Array(DailyState.progress_details(state)) == remote.slice(0, DailyState.DETAILS_SIZE)
	_refresh_header()

	# Left mid-article last time: that article counts as failed.
	if int(state["started_id"]) != 0 and not DailyState.is_finished(state):
		state["results"].append({"id": state["started_id"], "title": state.get("started_title", "?"),
			"solved": false, "points": 0, "wrong": 0})
		state["started_id"] = 0
		DailyState.save_day(daily_number, state)
		# No upload here - the next article's start (or the summary) sends it.

	if DailyState.is_finished(state):
		_show_summary()
	else:
		_load_next_article()


# Dev rerolls (local sets) never touch the leaderboard.
func _uploads_progress() -> bool:
	return set_source != "local" and Steam.loggedOn()


func _upload_progress() -> bool:
	if not _uploads_progress():
		return false
	return await Leaderboards.submit_daily_progress(daily_number, set_key, DailyState.total_points(state), DailyState.progress_details(state))


# Once per finished Daily (both the last article and the summary call it).
func _upload_final() -> void:
	while final_upload_busy:
		await get_tree().process_frame
	if final_uploaded or not is_inside_tree():
		return
	final_upload_busy = true
	if await _upload_progress():
		final_uploaded = true
	final_upload_busy = false


func _exit_tree() -> void:
	if article_tool:
		article_tool.free()
		article_tool = null


# --- Layout -------------------------------------------------------------------

func _build(column: VBoxContainer) -> void:
	# Header: Quit ............ DAILY CHALLENGE + progress pips | Score
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 52
	column.add_child(header)

	quit_button = _button("‹  Quit", "GhostButton", _on_quit_pressed)
	quit_button.custom_minimum_size.x = 160
	# Not in the "back_button" group: Esc opens Settings here (see _input).
	header.add_child(quit_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Right: DAILY CHALLENGE + progress pips, then the score.
	var progress_box := VBoxContainer.new()
	progress_box.alignment = BoxContainer.ALIGNMENT_CENTER
	progress_box.add_theme_constant_override("separation", 6)
	var eyebrow := _label("DAILY CHALLENGE", "ColumnHeader")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_box.add_child(eyebrow)
	pips_row = HBoxContainer.new()
	pips_row.alignment = BoxContainer.ALIGNMENT_END
	pips_row.add_theme_constant_override("separation", 6)
	progress_box.add_child(pips_row)
	header.add_child(progress_box)

	var divider := VSeparator.new()
	divider.custom_minimum_size.x = 32
	var line := StyleBoxLine.new()
	line.vertical = true
	line.color = get_theme_color("border", "Hub")
	line.color.a = 0.25
	line.grow_begin = -10
	line.grow_end = -10
	divider.add_theme_stylebox_override("separator", line)
	header.add_child(divider)

	var score_box := VBoxContainer.new()
	score_box.custom_minimum_size.x = 90
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	score_box.add_theme_constant_override("separation", -4)
	var score_title := _label("SCORE", "ColumnHeader")
	score_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_box.add_child(score_title)
	score_label = _label("0", "HeaderMedium")
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_box.add_child(score_label)
	header.add_child(score_box)

	# The article card.
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TablePanel"
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 545)
	center.add_child(panel)
	panel_box = VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 10)
	panel.add_child(panel_box)

	var info := HBoxContainer.new()
	article_label = _label("", "SmallMuted")
	article_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(article_label)
	worth_label = _label("", "AccentSmall")
	worth_label.add_theme_font_size_override("font_size", 13)
	info.add_child(worth_label)
	panel_box.add_child(info)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	title_label = _label("", "HeaderLarge")
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	letters_label = _label("", "MutedLabel")
	letters_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(letters_label)
	panel_box.add_child(title_row)

	timer_bar = ProgressBar.new()
	timer_bar.theme_type_variation = "HubProgress"
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size.y = 6
	timer_bar.max_value = 1.0
	timer_bar.step = 0.0
	panel_box.add_child(timer_bar)

	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.scroll_following = false
	text_label.add_theme_font_size_override("normal_font_size", 16)
	text_label.add_theme_constant_override("line_separation", 4)
	panel_box.add_child(text_label)

	feedback_label = _label("", "StrongLabel")
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.custom_minimum_size.y = 24
	panel_box.add_child(feedback_label)

	# Guess row (or Next once the answer is showing).
	bottom_row = HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 10)
	panel_box.add_child(bottom_row)
	guess_input = LineEdit.new()
	guess_input.placeholder_text = "Type the article's title and press Enter"
	guess_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guess_input.custom_minimum_size.y = 44
	guess_input.add_theme_font_size_override("font_size", 16)
	guess_input.keep_editing_on_text_submit = true
	guess_input.text_submitted.connect(func(_t): _submit_guess())
	bottom_row.add_child(guess_input)
	guess_button = _button("Guess", "CtaButton", _submit_guess)
	guess_button.add_theme_font_size_override("font_size", 17)
	guess_button.custom_minimum_size.x = 120
	bottom_row.add_child(guess_button)
	give_up_button = _button("Give up", "GhostButton", _on_give_up)
	bottom_row.add_child(give_up_button)
	next_button = _button("Next article  ›", "CtaButton", _next_article)
	next_button.add_theme_font_size_override("font_size", 17)
	next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_button.visible = false
	panel_box.add_child(next_button)

	_refresh_header()


func _refresh_header() -> void:
	for c in pips_row.get_children():
		c.queue_free()
	var results: Array = state["results"]
	for i in DailyState.ARTICLES_PER_DAY:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(34, 8)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		if i < results.size():
			var t := DailyState.tier(results[i])
			sb.bg_color = get_theme_color({"great": "added", "solved": "warning", "failed": "accent"}[t], "Hub")
		elif i == results.size() and phase != Phase.SUMMARY:
			sb.bg_color = Color.TRANSPARENT
			sb.set_border_width_all(2)
			sb.border_color = get_theme_color("text", "Hub")
		else:
			sb.bg_color = Color(get_theme_color("text", "Hub"), 0.15)
		pip.add_theme_stylebox_override("panel", sb)
		pips_row.add_child(pip)
	score_label.text = _thousands(DailyState.total_points(state))


# --- Loading articles -------------------------------------------------------------

func _load_next_article() -> void:
	phase = Phase.LOADING
	var index: int = state["next_candidate"]
	if index >= candidates.size():
		_show_error("Couldn't load today's articles. Check your connection and try again.")
		return
	article_label.text = "Article %d of %d" % [state["results"].size() + 1, DailyState.ARTICLES_PER_DAY]
	worth_label.text = ""
	title_label.text = "Loading..."
	letters_label.text = ""
	text_label.text = ""
	feedback_label.text = ""
	_set_guessing(false)
	article_id = int(candidates[index])
	var err := http.request(ARTICLE_URL % article_id)
	if err != OK:
		_show_error("Couldn't reach Wikipedia.")


func _on_article_loaded(result: int, code: int, _headers, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_show_error("Couldn't reach Wikipedia. Check your connection and try again.")
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	var page: Dictionary = {}
	if json is Dictionary and json.has("query") and json["query"].has("pages"):
		var pages: Dictionary = json["query"]["pages"]
		if not pages.is_empty():
			page = pages.values()[0]
	var extract := String(page.get("extract", ""))
	var page_title: String = article_tool.strip_disambiguation(String(page.get("title", "")))
	var spellings := _title_variants(page_title, page.get("redirects", []))
	# Blank the spellings' words too ("or sulphur" in the Sulfur intro). Only
	# words that are a respelling of a title word - not a piece of one ("space"
	# from "Space X" would blank every "space" in the SpaceX intro).
	var extra_words := PackedStringArray()
	var title_words := _simplify(page_title).split(" ")
	for v in spellings:
		for w in _simplify(v).split(" "):
			if w.length() < 4 or w in extra_words:
				continue
			for tw in title_words:
				if tw.length() >= 4 and not tw.contains(w) and not w.contains(tw) \
						and Global.similarity_ratio(w, tw) >= VARIANT_SIMILARITY:
					extra_words.append(w)
					break
	# Article.format_text blanks the lead's "(pronunciation, native name,
	# romanized: ...)" asides, but its helper edits a copy of the word list,
	# so do that pass here first.
	var words: Array = Array(extract.split(" "))
	article_tool.censor_pronunciation_and_alias_parens(words)
	var censored: String = article_tool.format_text(page_title, " ".join(extra_words), " ".join(words))
	var split: Array = article_tool.split_sentences(censored)

	# Too short (or missing): skip to the next candidate - the same for everyone.
	state["next_candidate"] = int(state["next_candidate"]) + 1
	if extract.is_empty() or split.size() < MIN_CHUNKS:
		DailyState.save_day(daily_number, state)
		_load_next_article()
		return

	title = page_title
	alt_title = page_title
	variants = spellings
	chunks = split.slice(0, MAX_CHUNKS)
	order = DailyState.reveal_order(daily_number, article_id, chunks.size())
	revealed = 1
	wrong = 0
	in_grace = false

	# Counts as attempted from now on (leaving = failed).
	state["started_id"] = article_id
	state["started_title"] = title
	DailyState.save_day(daily_number, state)
	_upload_progress()

	phase = Phase.PLAYING
	guess_input.clear()
	title_label.text = _censored_title()
	letters_label.text = "(%d letters)" % _letter_count()
	_start_interval(_interval_for(2) if chunks.size() > 1 else GRACE_SECONDS)
	_render_text()
	_set_guessing(true)
	_refresh_header()


# Same pace as multiplayer: reveals 2-3 every 6s, 4-6 every 9s, then 12s.
func _interval_for(reveal_number: int) -> float:
	if reveal_number <= 3:
		return 6.0
	elif reveal_number <= 6:
		return 9.0
	return 12.0


func _start_interval(seconds: float) -> void:
	interval_total = seconds
	interval_left = seconds


func _process(delta: float) -> void:
	if phase != Phase.PLAYING:
		return
	interval_left -= delta
	timer_bar.value = clampf(interval_left / interval_total, 0.0, 1.0)
	worth_label.text = "Worth %s pts" % _thousands(DailyState.points_for(true, revealed, chunks.size(), wrong))
	if interval_left > 0.0:
		return
	SoundManagerScript.play_sfx_overlapping(TIMER_END_SOUND, -24.0)
	if in_grace:
		_finish_article(false)
		return
	revealed += 1
	_render_text()
	_scroll_to_newest()
	if revealed >= chunks.size():
		in_grace = true
		_start_interval(GRACE_SECONDS)
		feedback_label.text = "Last sentence - %d seconds left" % int(GRACE_SECONDS)
		feedback_label.add_theme_color_override("font_color", get_theme_color("warning", "Hub"))
	else:
		_start_interval(_interval_for(revealed + 1))


# Revealed sentences in ink (title words already blanked), hidden ones as
# muted underscores of the same word lengths.
func _render_text() -> void:
	var shown := {}
	for i in mini(revealed, order.size()):
		shown[order[i]] = true
	var muted := Color(get_theme_color("muted", "Hub"), HIDDEN_ALPHA).to_html(true)
	var parts: Array = []
	var starts: Array = []  # visible-character offset of each chunk (for auto-scroll)
	var offset := 0
	for i in chunks.size():
		var chunk: String = chunks[i]
		starts.append(offset)
		if shown.has(i) or phase == Phase.ANSWER:
			parts.append(chunk.replace("[", "[lb]"))
			offset += chunk.length() + 1
		else:
			var words: Array = []
			for w in chunk.split(" ", false):
				words.append("_".repeat(w.length()))
			var hidden := " ".join(words)
			parts.append("[color=#%s]%s[/color]" % [muted, hidden])
			offset += hidden.length() + 1
	text_label.text = " ".join(parts)
	chunk_starts = starts


# Settings' "Scroll to revealed sentences": bring the newest one into view.
func _scroll_to_newest() -> void:
	if not Global.auto_scroll_to_reveal or revealed < 1 or revealed > order.size():
		return
	await get_tree().process_frame  # let the label lay out the new text
	if not is_inside_tree():
		return
	var start: int = chunk_starts[order[revealed - 1]]
	text_label.scroll_to_line(maxi(0, text_label.get_character_line(start) - 1))


# Letters as spaced underscores ("_ _ _ _"), words separated by wider gaps.
func _censored_title() -> String:
	var words: Array = []
	for word in title.split(" ", false):
		var letters: Array = []
		for c in word:
			letters.append("_" if _is_letter(c) else c)
		words.append(" ".join(letters))
	return "   ".join(words)


func _letter_count() -> int:
	var n := 0
	for c in title:
		if _is_letter(c):
			n += 1
	return n


static func _is_letter(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")


# --- Guessing -----------------------------------------------------------------

func _set_guessing(on: bool) -> void:
	guess_input.editable = on
	guess_button.disabled = not on
	give_up_button.disabled = not on
	bottom_row.visible = phase != Phase.ANSWER
	next_button.visible = phase == Phase.ANSWER
	if on:
		guess_input.grab_focus()


func _is_correct(typed: String) -> bool:
	var guess := _simplify(typed)
	for answer in [title] + variants:
		if Global.is_guess_match(guess, _simplify(answer)):
			return true
	return false


# Redirect titles that are spellings of the title (similar enough as text) -
# not every redirect: "Element 16" or a nickname shouldn't count or be blanked.
func _title_variants(page_title: String, redirects) -> Array:
	var out: Array = []
	if not redirects is Array:
		return out
	var simple_title := _simplify(page_title)
	for r in redirects:
		if not r is Dictionary:
			continue
		var t: String = article_tool.strip_disambiguation(String(r.get("title", "")))
		var simple := _simplify(t)
		# Skip ones containing the title ("Sulfuric", "London, UK") - already
		# blanked, and they shouldn't count as answers.
		if simple.length() < 4 or simple.contains(simple_title) or t in out:
			continue
		if Global.similarity_ratio(simple, simple_title) >= VARIANT_SIMILARITY:
			out.append(t)
	return out


func _simplify(text: String) -> String:
	var s := text.to_lower().strip_edges()
	s = " ".join(s.split(" ", false))
	return Global.strip_accents(s)


func _submit_guess() -> void:
	if phase != Phase.PLAYING or guess_locked:
		return
	var typed := guess_input.text.strip_edges()
	guess_input.clear()
	if typed.is_empty():
		return
	if _is_correct(typed):
		_finish_article(true)
		return
	wrong += 1
	guess_locked = true
	feedback_label.text = "Not quite  ·  -%d" % DailyState.WRONG_GUESS_PENALTY
	feedback_label.add_theme_color_override("font_color", get_theme_color("accent", "Hub"))
	await get_tree().create_timer(WRONG_FLASH_SECONDS).timeout
	guess_locked = false
	if phase == Phase.PLAYING and feedback_label.text.begins_with("Not quite"):
		feedback_label.text = ""


func _on_give_up() -> void:
	if phase == Phase.PLAYING:
		_finish_article(false)


func _finish_article(solved: bool) -> void:
	var points := DailyState.points_for(solved, revealed, chunks.size(), wrong)
	state["results"].append({"id": article_id, "title": title, "solved": solved, "points": points, "wrong": wrong})
	state["started_id"] = 0
	DailyState.save_day(daily_number, state)
	if DailyState.is_finished(state):
		_upload_final()  # earlier results go up with each next article's start

	phase = Phase.ANSWER
	title_label.text = title
	letters_label.text = ""
	worth_label.text = ""
	timer_bar.value = 0.0
	_render_text()
	if solved:
		feedback_label.text = "Correct!  +%s pts" % _thousands(points)
		feedback_label.add_theme_color_override("font_color", get_theme_color("added", "Hub"))
		SoundManagerScript.play_random_sound_from_folder_with_pitch("res://assets/sounds/sfx/hit", "SFX")
	else:
		feedback_label.text = "The answer was %s" % title
		feedback_label.add_theme_color_override("font_color", get_theme_color("accent", "Hub"))
	next_button.text = "See results  ›" if DailyState.is_finished(state) else "Next article  ›"
	_set_guessing(false)
	next_button.grab_focus()
	_refresh_header()


func _next_article() -> void:
	if DailyState.is_finished(state):
		_show_summary()
	else:
		_load_next_article()


# Esc: closes an open popup (Global presses its close button), otherwise
# opens Settings. The timer keeps running, like in a match.
func _input(event: InputEvent) -> void:
	super(event)
	if get_viewport().is_input_handled():
		return
	if event is InputEventKey and event.pressed and not event.is_echo() \
			and event.keycode == KEY_ESCAPE and not _modal_open():
		get_viewport().set_input_as_handled()
		_open_settings()


func _unhandled_key_input(event: InputEvent) -> void:
	if phase == Phase.ANSWER and event is InputEventKey and event.pressed and not event.is_echo() \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_next_article()


func _on_quit_pressed() -> void:
	if _modal_open():
		_close_modal()  # Esc while the confirm is open = keep playing
		return
	if phase == Phase.PLAYING:
		# Leaving now forfeits this article (one attempt per day).
		var box := _open_modal("Leave the Daily?", 380)
		var note := _label("This article will count as failed. You can come back to finish the rest today.", "MutedLabel")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(note)
		box.add_child(_button("Leave", "CtaButton", func():
			_finish_article(false)
			_on_nav_play()))
		_add_modal_close(box, "Keep playing")
		return
	_on_nav_play()


# --- Summary ------------------------------------------------------------------

func _show_summary() -> void:
	phase = Phase.SUMMARY
	_refresh_header()
	quit_button.text = "‹  Back to Play"
	for c in panel_box.get_children():
		c.queue_free()

	var head := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_label("DAILY COMPLETE", "Eyebrow"))
	titles.add_child(_label("%s points" % _thousands(DailyState.total_points(state)), "HeaderLarge"))
	titles.add_child(_label("%d of %d solved  ·  Next Daily in %s" % [DailyState.solved_count(state),
		DailyState.ARTICLES_PER_DAY, _hms(DailyState.seconds_until_reset())], "MutedLabel"))
	head.add_child(titles)
	panel_box.add_child(head)
	panel_box.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	panel_box.add_child(cols)

	# Left: the five articles.
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	list.add_child(_label("YOUR ARTICLES", "ColumnHeader"))
	for r in state["results"]:
		list.add_child(_result_row(r))
	cols.add_child(list)

	# Right: friends' scores today (Steam).
	var friends := VBoxContainer.new()
	friends.custom_minimum_size.x = 300
	friends.add_theme_constant_override("separation", 2)
	friends.add_child(_label("FRIENDS TODAY", "ColumnHeader"))
	var loading := _label("Loading..." if Steam.loggedOn() else "Open Steam to compare with friends.", "MutedLabel")
	friends.add_child(loading)
	cols.add_child(friends)

	_submit_and_load_friends(friends, loading)


func _result_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36
	row.add_theme_constant_override("separation", 10)
	var pip := Panel.new()
	pip.custom_minimum_size = Vector2(12, 12)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.bg_color = get_theme_color({"great": "added", "solved": "warning", "failed": "accent"}[DailyState.tier(r)], "Hub")
	pip.add_theme_stylebox_override("panel", sb)
	row.add_child(pip)
	var t := _label(String(r["title"]), "NameLabel")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_font_size_override("font_size", 15)
	row.add_child(t)
	var extra := ""
	if int(r.get("wrong", 0)) > 0:
		extra = "%d wrong  ·  " % int(r["wrong"])
	row.add_child(_label(extra + ("%s pts" % _thousands(int(r["points"])) if r["solved"] else "missed"), "SmallMuted"))
	return row


func _submit_and_load_friends(box: VBoxContainer, loading: Label) -> void:
	if not Steam.loggedOn():
		return
	if not final_uploaded:
		await _upload_final()  # first time here, or the upload after the last article failed
	var result: Dictionary = await Leaderboards.download(Leaderboards.daily_board_name(daily_number, set_key), true)
	if not is_inside_tree():
		return
	loading.queue_free()
	if not result["ok"]:
		box.add_child(_label("Couldn't load scores.", "MutedLabel"))
		return
	var own_id := Steam.getSteamID()
	var entries: Array = result["entries"]
	if entries.is_empty():
		box.add_child(_label("No friends have played today yet.", "MutedLabel"))
	for i in entries.size():
		var e: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 36
		row.add_theme_constant_override("separation", 10)
		var is_own := int(e.get("steam_id", 0)) == own_id
		var style := "AccentSmall" if is_own else "SmallMuted"
		var rank := _label(str(i + 1), style)
		rank.custom_minimum_size.x = 18
		row.add_child(rank)
		var sid := int(e.get("steam_id", 0))
		var who := Global.get_own_name() if is_own else Steam.getFriendPersonaName(sid)
		row.add_child(_avatar(who, 24, sid))
		var n := _label(who, "AccentSmall" if is_own else "NameLabel")
		n.add_theme_font_size_override("font_size", 14)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(n)
		row.add_child(_label(_thousands(int(e.get("score", 0))), style))
		for c in row.get_children():
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(row)
	if not result["own"].is_empty():
		var note := _label("You're #%s of %s worldwide" % [_thousands(int(result["own"].get("global_rank", 0))), _thousands(int(result["count"]))], "SmallMuted")
		box.add_child(_spacer(true))
		box.add_child(note)


func _show_error(message: String) -> void:
	phase = Phase.ERROR
	title_label.text = "Can't load the Daily"
	letters_label.text = ""
	text_label.text = message
	_set_guessing(false)
	bottom_row.visible = false
	next_button.visible = true
	next_button.text = "Try again"
	for c in next_button.pressed.get_connections():
		next_button.pressed.disconnect(c["callable"])
	next_button.pressed.connect(func(): get_tree().reload_current_scene())


static func _hms(secs: int) -> String:
	return "%dh %02dm" % [secs / 3600, (secs / 60) % 60]
