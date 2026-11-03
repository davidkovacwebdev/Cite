extends SceneTree

# Generates res://ui/hub/hub_theme.tres - the "Redacted paper" look for the
# new hub menus (picked in the UI playground artifact). Only the hub screens
# use this theme; the project-wide main_theme.tres (and so Legacy) is left
# alone.
#
# Run:  Godot --headless --path . --script res://tools/make_hub_theme.gd
#
# Every colour/radius/border/font lives here. Scripts read the few extra
# colours they need from the "Hub" theme type (get_theme_color(name, "Hub")).

const OUT := "res://ui/hub/hub_theme.tres"

# Palette (playground preset "Redacted paper").
const BG := Color("#ece6da")
const SURFACE := Color("#f8f4ec")
const BTN_BG := Color("#161514")
const BTN_TEXT := Color("#ece6da")
const BORDER := Color("#161514")
const TEXT := Color("#161514")
const MUTED := Color("#6d665b")
const ACCENT := Color("#c8102e")
const ON_ACCENT := Color("#ffffff")
const ONLINE := Color("#2f9e5b")
const LIVE := Color("#d98a00")
const OFFLINE := Color("#9a9285")
const GOLD_TOP := Color("#ffe08a")
const GOLD_BOTTOM := Color("#8a5a12")
const GOLD_TEXT := Color("#3a2500")
const GOLD := Color("#e2b84b")
const SILVER := Color("#c4beb2")
const BRONZE := Color("#c58a5a")
const HOST_NAME := Color("#1f4fa8")
const GUEST_NAME := Color("#c2410c")
const WARNING := Color("#b26b00")

const RADIUS := 2
const BW := 1
const FONT_SIZE := 16

var plex_400: FontVariation
var plex_500: FontVariation
var plex_600: FontVariation
var plex_700: FontVariation
var fraunces_600: FontVariation


func _init() -> void:
	_make_fonts()
	var t := Theme.new()
	t.default_font = plex_400
	t.default_font_size = FONT_SIZE

	_hub_colors(t)
	_labels(t)
	_buttons(t)
	_panels(t)
	_inputs(t)
	_misc(t)

	var err := ResourceSaver.save(t, OUT)
	print("saved ", OUT, " err=", err)
	quit()


# --- helpers ------------------------------------------------------------------

static func mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, t)


static func box(bg: Color, border := Color.TRANSPARENT, bw := 0, radius := RADIUS,
		margin_h := 0.0, margin_v := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.draw_center = bg.a > 0.0
	if bw > 0:
		s.set_border_width_all(bw)
		s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = radius > 0
	return s


func _variation(path: String, axes: Dictionary, save_as: String, spacing_glyph := 0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(path)
	var ts := TextServerManager.get_primary_interface()
	var coords := {}
	for k in axes:
		coords[ts.name_to_tag(k)] = axes[k]
	fv.variation_opentype = coords
	fv.spacing_glyph = spacing_glyph
	ResourceSaver.save(fv, save_as)
	return load(save_as)


func _make_fonts() -> void:
	var plex := "res://ui/fonts/IBMPlexSans.ttf"
	var fraunces := "res://ui/fonts/Fraunces.ttf"
	plex_400 = _variation(plex, {"wght": 400, "wdth": 100}, "res://ui/fonts/plex_400.tres")
	plex_500 = _variation(plex, {"wght": 500, "wdth": 100}, "res://ui/fonts/plex_500.tres")
	plex_600 = _variation(plex, {"wght": 600, "wdth": 100}, "res://ui/fonts/plex_600.tres")
	plex_700 = _variation(plex, {"wght": 700, "wdth": 100}, "res://ui/fonts/plex_700.tres", 1)
	# Spaced letters for the match's censored title ("_ _ _ _").
	_variation(plex, {"wght": 600, "wdth": 100}, "res://ui/fonts/plex_600_spaced.tres", 3)
	fraunces_600 = _variation(fraunces, {"wght": 600, "opsz": 24, "SOFT": 0, "WONK": 0}, "res://ui/fonts/fraunces_600.tres")


# --- theme sections -----------------------------------------------------------

func _hub_colors(t: Theme) -> void:
	# Free-form colours for scripts: get_theme_color("accent", "Hub") etc.
	var c := {
		"bg": BG, "surface": SURFACE, "text": TEXT, "muted": MUTED, "accent": ACCENT,
		"on_accent": ON_ACCENT, "border": BORDER, "online": ONLINE, "live": LIVE,
		"offline": OFFLINE, "gold_top": GOLD_TOP, "gold_bottom": GOLD_BOTTOM,
		"gold_text": GOLD_TEXT, "hero_glow": Color(ACCENT, 0.16),
		"overlay_dim": Color(0.09, 0.08, 0.07, 0.55),
		"host_name": HOST_NAME, "guest_name": GUEST_NAME, "warning": WARNING,
		"added": ONLINE,
	}
	for k in c:
		t.set_color(k, "Hub", c[k])


func _label_variation(t: Theme, name: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)


func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	t.set_constant("outline_size", "Label", 0)

	_label_variation(t, "HeaderLarge", fraunces_600, 34, TEXT)
	_label_variation(t, "HeaderMedium", fraunces_600, 19, TEXT)
	_label_variation(t, "HeaderSmall", fraunces_600, 16, TEXT)
	_label_variation(t, "QueueTimer", fraunces_600, 42, TEXT)
	_label_variation(t, "Eyebrow", plex_700, 11, ACCENT)
	_label_variation(t, "BodyLabel", plex_400, 15, TEXT)
	_label_variation(t, "StrongLabel", plex_600, 17, TEXT)
	_label_variation(t, "MutedLabel", plex_400, 14, MUTED)
	_label_variation(t, "SmallMuted", plex_400, 12, MUTED)
	_label_variation(t, "SmallLabel", plex_400, 12, TEXT)
	_label_variation(t, "AccentSmall", plex_500, 12, ACCENT)
	_label_variation(t, "NameLabel", plex_500, 14, TEXT)
	_label_variation(t, "RankLetter", plex_700, 20, GOLD_TEXT)
	_label_variation(t, "ColumnHeader", plex_700, 11, MUTED)
	_label_variation(t, "MedalLabel", plex_700, 12, TEXT)
	_label_variation(t, "TableNumber", plex_500, 15, TEXT)
	_label_variation(t, "BigNumber", fraunces_600, 40, TEXT)
	_label_variation(t, "PageTitle", fraunces_600, 30, TEXT)
	_label_variation(t, "HintLabel", plex_600, 15, ONLINE)

	# RichTextLabel (lobby titles, status lines, chat).
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", plex_400)
	t.set_font("bold_font", "RichTextLabel", plex_600)
	t.set_font("italics_font", "RichTextLabel", plex_400)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		t.set_font_size(k, "RichTextLabel", 15)
	t.set_constant("outline_size", "RichTextLabel", 0)
	t.set_type_variation("PageTitleRich", "RichTextLabel")
	t.set_font("normal_font", "PageTitleRich", fraunces_600)
	t.set_font_size("normal_font_size", "PageTitleRich", 32)
	t.set_type_variation("StatusRich", "RichTextLabel")
	t.set_color("default_color", "StatusRich", MUTED)
	t.set_type_variation("CountdownRich", "RichTextLabel")
	t.set_font("normal_font", "CountdownRich", fraunces_600)
	t.set_font_size("normal_font_size", "CountdownRich", 96)
	t.set_type_variation("ChatLog", "RichTextLabel")
	t.set_stylebox("normal", "ChatLog", box(mix(SURFACE, Color.WHITE, 0.25), BORDER, BW, RADIUS + 1, 12, 8))
	t.set_stylebox("focus", "ChatLog", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS))

	# Pill tag (e.g. Daily "#412") and notification badge.
	for n in ["TagLabel", "BadgeLabel"]:
		t.set_type_variation(n, "Label")
		t.set_font("font", n, plex_700)
		t.set_font_size("font_size", n, 10 if n == "TagLabel" else 11)
		t.set_color("font_color", n, ON_ACCENT)
		t.set_stylebox("normal", n, box(ACCENT, Color.TRANSPARENT, 0, 9, 7.0, 1.0))


func _button_states(t: Theme, type: String, normal: StyleBox, hover: StyleBox,
		pressed: StyleBox, disabled: StyleBox, fg: Color, fg_hover: Color, fg_disabled: Color) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, box(Color.TRANSPARENT, ACCENT, 2, RADIUS + 1))
	for k in ["font_color", "font_focus_color"]:
		t.set_color(k, type, fg)
	for k in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(k, type, fg_hover)
	t.set_color("font_disabled_color", type, fg_disabled)
	for k in ["icon_normal_color", "icon_focus_color"]:
		t.set_color(k, type, fg)
	for k in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		t.set_color(k, type, fg_hover)
	t.set_color("icon_disabled_color", type, fg_disabled)


func _buttons(t: Theme) -> void:
	var btn_hover := mix(BTN_BG, Color.WHITE, 0.12)
	var dis_bg := mix(BTN_BG, BG, 0.65)

	# Base Button: dark ink fill, paper text.
	_button_states(t, "Button",
		box(BTN_BG, BORDER, BW, RADIUS, 18, 8),
		box(btn_hover, ACCENT, BW, RADIUS, 18, 8),
		box(mix(BTN_BG, Color.BLACK, 0.2), ACCENT, BW, RADIUS, 18, 8),
		box(dis_bg, dis_bg, BW, RADIUS, 18, 8),
		BTN_TEXT, BTN_TEXT, mix(BTN_TEXT, BG, 0.4))
	t.set_font("font", "Button", plex_500)
	t.set_font_size("font_size", "Button", 16)
	t.set_constant("h_separation", "Button", 8)

	# CtaButton: the accent call to action (Find Match).
	t.set_type_variation("CtaButton", "Button")
	_button_states(t, "CtaButton",
		box(ACCENT, ACCENT, BW, RADIUS, 18, 8),
		box(mix(ACCENT, Color.WHITE, 0.12), ACCENT, BW, RADIUS, 18, 8),
		box(mix(ACCENT, Color.BLACK, 0.15), ACCENT, BW, RADIUS, 18, 8),
		box(mix(ACCENT, BG, 0.6), mix(ACCENT, BG, 0.6), BW, RADIUS, 18, 8),
		ON_ACCENT, ON_ACCENT, Color(ON_ACCENT, 0.7))
	t.set_font("font", "CtaButton", plex_600)
	t.set_font_size("font_size", "CtaButton", 22)

	# SmallButton: compact rows (friends list, Join).
	t.set_type_variation("SmallButton", "Button")
	t.set_font_size("font_size", "SmallButton", 13)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var b: StyleBoxFlat = t.get_stylebox(s, "Button").duplicate()
		b.content_margin_left = 10
		b.content_margin_right = 10
		b.content_margin_top = 4
		b.content_margin_bottom = 4
		t.set_stylebox(s, "SmallButton", b)

	# GhostButton: Back / Cancel / Close - no fill, muted text.
	t.set_type_variation("GhostButton", "Button")
	_button_states(t, "GhostButton",
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 18, 8),
		box(mix(SURFACE, Color.BLACK, 0.06), Color.TRANSPARENT, 0, RADIUS, 18, 8),
		box(mix(SURFACE, Color.BLACK, 0.1), Color.TRANSPARENT, 0, RADIUS, 18, 8),
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 18, 8),
		MUTED, TEXT, Color(MUTED, 0.5))

	# TextLink: underlined-looking accent text button ("Browse public rooms").
	t.set_type_variation("TextLink", "Button")
	var empty := StyleBoxEmpty.new()
	_button_states(t, "TextLink", empty, empty, empty, empty,
		ACCENT, mix(ACCENT, Color.BLACK, 0.25), Color(ACCENT, 0.5))
	t.set_font("font", "TextLink", plex_500)
	t.set_font_size("font_size", "TextLink", 13)

	# NavTab: top bar tabs. Toggle buttons; the pressed one gets an accent
	# underline.
	t.set_type_variation("NavTab", "Button")
	var tab_normal := box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 12, 6)
	var tab_hover := box(Color(TEXT, 0.07), Color.TRANSPARENT, 0, RADIUS, 12, 6)
	var tab_on := box(Color.TRANSPARENT, ACCENT, 0, 0, 12, 6)
	tab_on.border_width_bottom = 2
	_button_states(t, "NavTab", tab_normal, tab_hover, tab_on, tab_normal,
		Color(TEXT, 0.72), TEXT, Color(TEXT, 0.35))
	t.set_color("font_pressed_color", "NavTab", TEXT)
	t.set_font("font", "NavTab", plex_500)
	t.set_font_size("font_size", "NavTab", 15)

	# IconButton: square top bar buttons (bell, friends, settings).
	t.set_type_variation("IconButton", "Button")
	_button_states(t, "IconButton",
		box(BTN_BG, BORDER, BW, RADIUS, 9, 9),
		box(btn_hover, ACCENT, BW, RADIUS, 9, 9),
		box(mix(BTN_BG, Color.BLACK, 0.2), ACCENT, BW, RADIUS, 9, 9),
		box(dis_bg, dis_bg, BW, RADIUS, 9, 9),
		BTN_TEXT, BTN_TEXT, mix(BTN_TEXT, BG, 0.4))

	# RowIconButton: small borderless icon button inside list rows (chat).
	t.set_type_variation("RowIconButton", "Button")
	_button_states(t, "RowIconButton",
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 6, 6),
		box(Color(ACCENT, 0.12), Color.TRANSPARENT, 0, RADIUS, 6, 6),
		box(Color(ACCENT, 0.2), Color.TRANSPARENT, 0, RADIUS, 6, 6),
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 6, 6),
		MUTED, ACCENT, Color(MUTED, 0.4))

	# SegButton: segmented filter (playlists screen). Pressed = accent.
	t.set_type_variation("SegButton", "Button")
	_button_states(t, "SegButton",
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 12, 5),
		box(mix(SURFACE, Color.BLACK, 0.06), Color.TRANSPARENT, 0, RADIUS, 12, 5),
		box(ACCENT, Color.TRANSPARENT, 0, RADIUS, 12, 5),
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 12, 5),
		MUTED, TEXT, Color(MUTED, 0.5))
	for k in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(k, "SegButton", ON_ACCENT)
	t.set_font_size("font_size", "SegButton", 14)

	# PlaylistRow: selectable rows in the playlist picker (toggle buttons).
	var input_bg := mix(SURFACE, Color.WHITE, 0.25)
	t.set_type_variation("PlaylistRow", "Button")
	var sel := box(Color(ACCENT, 0.1), ACCENT, 2, RADIUS, 8, 4)
	_button_states(t, "PlaylistRow",
		box(input_bg, Color(BORDER, 0.25), BW, RADIUS, 8, 4),
		box(input_bg, ACCENT, BW, RADIUS, 8, 4),
		sel, box(input_bg, Color(BORDER, 0.15), BW, RADIUS, 8, 4),
		TEXT, TEXT, MUTED)
	t.set_stylebox("hover_pressed", "PlaylistRow", sel)
	t.set_font("font", "PlaylistRow", plex_500)
	t.set_font_size("font_size", "PlaylistRow", 15)

	# RowButton: flat list rows (builder search results / playlist entries).
	t.set_type_variation("RowButton", "Button")
	_button_states(t, "RowButton",
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 8, 4),
		box(mix(SURFACE, Color.BLACK, 0.06), Color.TRANSPARENT, 0, RADIUS, 8, 4),
		box(Color(ACCENT, 0.12), Color.TRANSPARENT, 0, RADIUS, 8, 4),
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 8, 4),
		TEXT, TEXT, MUTED)
	t.set_font("font", "RowButton", plex_400)
	t.set_font_size("font_size", "RowButton", 14)

	# CheckBox (settings).
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", TEXT)
	t.set_color("font_focus_color", "CheckBox", TEXT)
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(s, "CheckBox", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 2, 2))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_constant("h_separation", "CheckBox", 10)


func _check_icon(on: bool) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(BTN_BG if on else BORDER)
	if not on:
		img.fill_rect(Rect2i(1, 1, 14, 14), mix(SURFACE, Color.WHITE, 0.25))
	else:
		# Simple tick.
		for i in range(4):
			img.set_pixel(3 + i, 7 + i, BTN_TEXT)
			img.set_pixel(3 + i, 8 + i, BTN_TEXT)
		for i in range(7):
			img.set_pixel(6 + i, 10 - i, BTN_TEXT)
			img.set_pixel(6 + i, 9 - i, BTN_TEXT)
	return ImageTexture.create_from_image(img)


func _panel_variation(t: Theme, name: String, sb: StyleBox) -> void:
	t.set_type_variation(name, "PanelContainer")
	t.set_stylebox("panel", name, sb)


func _panels(t: Theme) -> void:
	var r := RADIUS + 1
	t.set_stylebox("panel", "PanelContainer", box(SURFACE, BORDER, BW, r, 14, 14))
	t.set_stylebox("panel", "Panel", box(SURFACE, BORDER, BW, r))
	# Hero padding comes from a MarginContainer inside (so the glow can fill the panel).
	_panel_variation(t, "HeroPanel", box(SURFACE, BORDER, BW, r, 0, 0))
	_panel_variation(t, "ModeCard", box(SURFACE, BORDER, BW, r, 16, 16))
	_panel_variation(t, "SidePanel", box(SURFACE, BORDER, BW, r, 14, 14))
	_panel_variation(t, "ModalPanel", box(SURFACE, BORDER, BW, r, 26, 24))
	var drop := box(SURFACE, BORDER, BW, r, 14, 12)
	drop.shadow_color = Color(TEXT, 0.14)
	drop.shadow_size = 10
	drop.shadow_offset = Vector2(0, 4)
	_panel_variation(t, "DropdownPanel", drop)
	var chip := box(SURFACE, BORDER, BW, RADIUS, 0, 4)
	chip.content_margin_left = 4
	chip.content_margin_right = 14
	_panel_variation(t, "ProfileChip", chip)
	_panel_variation(t, "ModeIcon", box(Color(ACCENT, 0.13), Color.TRANSPARENT, 0, RADIUS, 9, 9))
	_panel_variation(t, "SegBar", box(SURFACE, BORDER, BW, RADIUS, 3, 3))
	_panel_variation(t, "RowHover", box(mix(SURFACE, Color.BLACK, 0.06), Color.TRANSPARENT, 0, RADIUS, 6, 0))
	# Leaderboard rows: plain, and the player's own (accent tint + left rule).
	_panel_variation(t, "TableRow", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS, 10, 0))
	_panel_variation(t, "TableRowHover", box(mix(SURFACE, Color.BLACK, 0.05), Color.TRANSPARENT, 0, RADIUS, 10, 0))
	var own := box(Color(ACCENT, 0.08), ACCENT, 0, RADIUS, 10, 0)
	own.border_width_left = 3
	_panel_variation(t, "OwnRow", own)
	_panel_variation(t, "TablePanel", box(SURFACE, BORDER, BW, r, 18, 16))
	_panel_variation(t, "TableRowAlt", box(mix(SURFACE, Color.BLACK, 0.035), Color.TRANSPARENT, 0, RADIUS, 10, 0))
	_panel_variation(t, "AvatarFrame", box(SURFACE, BORDER, BW, r, 6, 6))
	_panel_variation(t, "ChatPanel", box(SURFACE, BORDER, BW, r, 8, 8))
	# Rank medals (1st-3rd) - small round chips.
	_panel_variation(t, "MedalGold", box(GOLD, Color.TRANSPARENT, 0, 12, 0, 0))
	_panel_variation(t, "MedalSilver", box(SILVER, Color.TRANSPARENT, 0, 12, 0, 0))
	_panel_variation(t, "MedalBronze", box(BRONZE, Color.TRANSPARENT, 0, 12, 0, 0))
	_panel_variation(t, "Avatar", box(BTN_BG, Color.TRANSPARENT, 0, 16, 0, 0))
	# Playlist card: no padding (the cover is edge to edge).
	_panel_variation(t, "PlaylistCard", box(SURFACE, BORDER, BW, r, 0, 0))
	_panel_variation(t, "PlaylistCardHover", box(SURFACE, ACCENT, BW, r, 0, 0))
	# Full-screen dim behind modals/the matchmaking overlay.
	_panel_variation(t, "OverlayDim", box(Color(0.09, 0.08, 0.07, 0.55), Color.TRANSPARENT, 0, 0))


func _inputs(t: Theme) -> void:
	var input_bg := mix(SURFACE, Color.WHITE, 0.25)
	for type in ["LineEdit", "OptionButton"]:
		t.set_font_size("font_size", type, 14)
	t.set_stylebox("normal", "LineEdit", box(input_bg, BORDER, BW, RADIUS, 12, 6))
	t.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, ACCENT, 2, RADIUS))
	t.set_stylebox("read_only", "LineEdit", box(mix(input_bg, BG, 0.5), BORDER, BW, RADIUS, 12, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.25))
	t.set_color("font_selected_color", "LineEdit", TEXT)

	# OptionButton looks like an input with a chevron.
	_button_states(t, "OptionButton",
		box(input_bg, BORDER, BW, RADIUS, 12, 6),
		box(input_bg, ACCENT, BW, RADIUS, 12, 6),
		box(input_bg, ACCENT, BW, RADIUS, 12, 6),
		box(mix(input_bg, BG, 0.5), BORDER, BW, RADIUS, 12, 6),
		TEXT, TEXT, MUTED)
	t.set_font("font", "OptionButton", plex_400)
	t.set_icon("arrow", "OptionButton", load("res://ui/icons/chevron-down-small.svg"))
	t.set_color("icon_normal_color", "OptionButton", MUTED)
	t.set_constant("arrow_margin", "OptionButton", 10)

	t.set_stylebox("normal", "TextEdit", box(input_bg, BORDER, BW, RADIUS, 12, 8))
	t.set_stylebox("focus", "TextEdit", box(Color.TRANSPARENT, ACCENT, 2, RADIUS))
	t.set_color("font_color", "TextEdit", TEXT)
	t.set_color("font_placeholder_color", "TextEdit", MUTED)
	t.set_color("caret_color", "TextEdit", ACCENT)
	t.set_color("selection_color", "TextEdit", Color(ACCENT, 0.25))
	t.set_font_size("font_size", "TextEdit", 14)
	t.set_stylebox("background", "ProgressBar", box(Color(TEXT, 0.14), Color.TRANSPARENT, 0, 4))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color.TRANSPARENT, 0, 4))
	t.set_color("font_color", "ProgressBar", TEXT)

	# GuessInput: the match's big centred guess popup (shadowed paper card).
	t.set_type_variation("GuessInput", "LineEdit")
	var guess := box(SURFACE, BORDER, BW, RADIUS + 1, 16, 8)
	guess.shadow_color = Color(TEXT, 0.22)
	guess.shadow_size = 18
	t.set_stylebox("normal", "GuessInput", guess)
	t.set_stylebox("focus", "GuessInput", guess)
	t.set_font_size("font_size", "GuessInput", 24)
	t.set_font("font", "GuessInput", plex_500)

	# Dropdown list.
	t.set_stylebox("panel", "PopupMenu", box(SURFACE, BORDER, BW, RADIUS, 4, 4))
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.12), Color.TRANSPARENT, 0, RADIUS))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_color("font_disabled_color", "PopupMenu", MUTED)
	t.set_font("font", "PopupMenu", plex_400)
	t.set_font_size("font_size", "PopupMenu", 14)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_icon("radio_checked", "PopupMenu", _dot_icon(ACCENT))
	t.set_icon("radio_unchecked", "PopupMenu", _dot_icon(Color.TRANSPARENT))

	# Sliders (settings).
	var track := box(Color(TEXT, 0.18), Color.TRANSPARENT, 0, 2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := box(ACCENT, Color.TRANSPARENT, 0, 2)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _knob_icon(BTN_BG))
	t.set_icon("grabber_highlight", "HSlider", _knob_icon(ACCENT))


func _dot_icon(c: Color) -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in 12:
		for x in 12:
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(6, 6)) <= 3.5:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _knob_icon(c: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in 16:
		for x in 16:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8))
			if d <= 7.0:
				img.set_pixel(x, y, c if d <= 6.0 else Color(c, 7.0 - d + 0.0))
	return ImageTexture.create_from_image(img)


func _misc(t: Theme) -> void:
	# Progress bars: RP bar / level bar / queue scan.
	t.set_type_variation("HubProgress", "ProgressBar")
	t.set_stylebox("background", "HubProgress", box(Color(TEXT, 0.14), Color.TRANSPARENT, 0, 4))
	t.set_stylebox("fill", "HubProgress", box(ACCENT, Color.TRANSPARENT, 0, 4))
	t.set_color("font_color", "HubProgress", Color.TRANSPARENT)

	# Thin dividers.
	var sep := StyleBoxLine.new()
	sep.color = Color(TEXT, 0.15)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 8)

	# Scrollbars: thin ink.
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 3, 3))
		t.set_stylebox("grabber", type, box(Color(TEXT, 0.3), Color.TRANSPARENT, 0, 3, 3, 3))
		t.set_stylebox("grabber_highlight", type, box(Color(TEXT, 0.5), Color.TRANSPARENT, 0, 3, 3, 3))
		t.set_stylebox("grabber_pressed", type, box(ACCENT, Color.TRANSPARENT, 0, 3, 3, 3))

	# Tooltips.
	t.set_stylebox("panel", "TooltipPanel", box(BTN_BG, Color.TRANSPARENT, 0, RADIUS, 8, 5))
	t.set_color("font_color", "TooltipLabel", BTN_TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)
