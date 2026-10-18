shader_type canvas_item;

void vertex() {
	// optional UV scroll
	UV.x += 0.01 * TIME;
	UV.y += 0.01 * TIME;
}

void fragment() {
    // rotate UV by 45 degrees
    float angle = radians(45.0);
    mat2 rotation = mat2(
        vec2(cos(angle), -sin(angle)),
        vec2(sin(angle),  cos(angle))
    );
    // center rotation around the middle (0.5, 0.5)
    vec2 uv = UV - vec2(0.5);
    uv = rotation * uv;
    uv += vec2(0.5);
    // sample the texture
    vec4 tex = texture(TEXTURE, uv);
    // make it transparent
    tex.a *= 0.2;
    COLOR = tex;
}
