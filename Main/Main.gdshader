shader_type canvas_item;

uniform float speed = 1.5;           // Slower for a smoother feel
uniform float scale_amount = 0.05;    // Reduced pulse intensity
uniform float rotation_amount = 0.02; // Very subtle wobble
uniform vec2 pivot_offset = vec2(0.5, 0.5); // Use normalized or actual center

void vertex() {
	// Using sin and cos but with lower multipliers for that "lazy" float
	float scale = 1.0 + sin(TIME * speed) * scale_amount;
	float angle = cos(TIME * speed) * rotation_amount;

	mat2 rotation = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));

	// If it's still jumping, ensure pivot_offset in Inspector
	// matches exactly half of your Label's Rect Size.
	VERTEX -= pivot_offset;
	VERTEX *= scale;
	VERTEX = rotation * VERTEX;
	VERTEX += pivot_offset;
}