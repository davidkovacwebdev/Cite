extends Control

# Ranked rating over time for the Profile screen: one 2px line, a marker on
# the latest point, the low/high of the range as quiet labels on the left,
# and a hover readout (match number + rating) on the nearest point. One
# series, so no legend - the panel title names it. Colors come from the hub
# theme (accent line, muted guides, text-colored labels).

const PAD_LEFT := 40.0
const PAD_RIGHT := 10.0
const PAD_Y := 12.0
const MARKER_RADIUS := 4.0
const HIT_RADIUS := 24.0

# [[unix, rating], ...] oldest first (PlayerStats.rating_history).
var points: Array = []:
	set(value):
		points = value
		queue_redraw()

var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func():
		_hover = -1
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and points.size() >= 2:
		var nearest := -1
		var best := HIT_RADIUS
		for i in points.size():
			var d: float = absf(_pos(i).x - event.position.x)
			if d < best:
				best = d
				nearest = i
		if nearest != _hover:
			_hover = nearest
			queue_redraw()


func _range() -> Vector2:
	var lo := INF
	var hi := -INF
	for p in points:
		lo = minf(lo, float(p[1]))
		hi = maxf(hi, float(p[1]))
	if hi - lo < 40.0:  # a flat start shouldn't look like a cliff
		var mid := (hi + lo) / 2.0
		lo = mid - 20.0
		hi = mid + 20.0
	return Vector2(lo, hi)


func _pos(i: int) -> Vector2:
	var r := _range()
	var w := size.x - PAD_LEFT - PAD_RIGHT
	var h := size.y - PAD_Y * 2.0
	var x := PAD_LEFT + w * float(i) / float(points.size() - 1)
	var y := PAD_Y + h * (1.0 - (float(points[i][1]) - r.x) / (r.y - r.x))
	return Vector2(x, y)


func _draw() -> void:
	var font := get_theme_font("font", "SmallMuted")
	var font_size := get_theme_font_size("font_size", "SmallMuted")
	var muted := get_theme_color("muted", "Hub")
	var text := get_theme_color("text", "Hub")
	var accent := get_theme_color("accent", "Hub")
	var surface := get_theme_color("surface", "Hub")

	if points.size() < 2:
		var msg := "Play Ranked matches to see your rating here."
		draw_string(font, Vector2(0, size.y / 2.0), msg, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, muted)
		return

	# Guides: the range's high and low, recessive.
	var r := _range()
	var guide := Color(muted, 0.35)
	for value: float in [r.y, r.x]:
		var y: float = PAD_Y + (size.y - PAD_Y * 2.0) * (1.0 - (value - r.x) / (r.y - r.x))
		draw_line(Vector2(PAD_LEFT, y), Vector2(size.x - PAD_RIGHT, y), guide, 1.0)
		draw_string(font, Vector2(0, y + font_size * 0.35), str(roundi(value)), HORIZONTAL_ALIGNMENT_LEFT, PAD_LEFT - 6.0, font_size, muted)

	var line := PackedVector2Array()
	for i in points.size():
		line.append(_pos(i))
	draw_polyline(line, accent, 2.0, true)

	# Latest point: marker with a surface ring, so it reads over the line.
	var last := _pos(points.size() - 1)
	draw_circle(last, MARKER_RADIUS + 2.0, surface)
	draw_circle(last, MARKER_RADIUS, accent)

	if _hover >= 0:
		var p := _pos(_hover)
		draw_line(Vector2(p.x, PAD_Y), Vector2(p.x, size.y - PAD_Y), Color(muted, 0.6), 1.0)
		draw_circle(p, MARKER_RADIUS + 2.0, surface)
		draw_circle(p, MARKER_RADIUS, accent)
		var label := "Rating %d" % int(points[_hover][1]) if _hover > 0 else "Start %d" % int(points[0][1])
		var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var lx := clampf(p.x - label_w / 2.0, PAD_LEFT, size.x - PAD_RIGHT - label_w)
		var ly := p.y - 10.0 if p.y > PAD_Y + font_size + 4.0 else p.y + font_size + 10.0
		draw_rect(Rect2(lx - 4.0, ly - font_size, label_w + 8.0, font_size + 6.0), surface)
		draw_string(font, Vector2(lx, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text)
