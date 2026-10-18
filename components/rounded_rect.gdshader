shader_type canvas_item;

// Draws a flat, anti-aliased rounded rectangle filling the node's rect,
// independent of any assigned texture - used for the health/mana bar
// track and fill so the fill can be resized every frame while keeping
// pill-shaped rounded corners. Also supports an optional inset border
// (border_width = 0 skips it, keeping old callers unaffected) for flat
// bordered panels like the multiplayer card background.
uniform vec4 color : source_color = vec4(1.0);
uniform vec2 size = vec2(300.0, 40.0);
uniform float radius = 20.0;
uniform vec4 border_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float border_width = 0.0;

// Optional glow pinned to the top edge (UV.y = 0) of the shape, like a lit
// wick - inert by default (glow_strength = 0) so existing callers are
// unaffected; used by the multiplayer reveal timer bar, whose height
// shrinks over time, so the glow rides along at the top of whatever's left
// instead of sweeping through the whole bar. A gentle flicker in intensity
// (not position) gives it some life.
uniform float glow_strength : hint_range(0.0, 5.0) = 0.0;
uniform float glow_width : hint_range(0.01, 1.0) = 0.15;
uniform float glow_flicker_speed = 3.0;

void fragment() {
	vec2 pos = UV * size;
	vec2 center = size * 0.5;
	float r = min(radius, min(center.x, center.y));
	vec2 d = abs(pos - center) - (center - vec2(r));
	float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
	float alpha = 1.0 - smoothstep(-1.0, 1.0, dist);

	vec4 col = color;
	if (border_width > 0.0) {
		float inner_dist = dist + border_width;
		float inner_alpha = 1.0 - smoothstep(-1.0, 1.0, inner_dist);
		col = mix(border_color, color, inner_alpha);
	}

	if (glow_strength > 0.0) {
		float glow = max(0.0, 1.0 - UV.y / glow_width);
		glow = pow(glow, 2.0);
		float flicker = 0.8 + 0.2 * sin(TIME * glow_flicker_speed);
		col.rgb += glow * glow_strength * flicker;
	}

	COLOR = vec4(col.rgb, col.a * alpha);
}
