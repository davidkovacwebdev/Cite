shader_type canvas_item;

uniform vec4 color_left  : source_color = vec4(0.788, 0.537, 0.247, 1.0); // c9893f
uniform vec4 color_right : source_color = vec4(0.949, 0.737, 0.514, 1.0); // f2bc83

uniform float glow_width = 0.005;  // Very narrow glow
uniform float glow_strength = 0.1; // Increased strength for visibility

// how often glow occurs
uniform float glow_interval = 10.0;

// sweep speed
uniform float speed = 2.0;

void fragment() {
    float t = UV.x;

    // base gradient
    vec4 base_color = mix(color_left, color_right, t);

    // determine if glow should be active
    float phase = mod(TIME, glow_interval);

    // glow should only run within the first ~1 second
    float glow_active = step(phase, 1.0); // 1 if active, 0 if not

    // animated glow position
    float glow_pos = phase * speed;

    // Calculate glow with a different approach for a narrower effect
    float glow = 0.0;

    // Create a very narrow pulse
    float pulse_center = glow_pos;
    float pulse_width = glow_width;

    // Use a sharper falloff for a narrower glow
    float dist = abs(t - pulse_center);
    glow = max(0.0, 1.0 - dist / pulse_width);

    // Apply a power curve to make it even narrower
    glow = pow(glow, 4.0);

    vec4 glow_color = vec4(1.0) * glow * glow_strength * glow_active;

    COLOR = base_color + glow_color;
}