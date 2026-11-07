shader_type canvas_item;

uniform vec2 fringe = vec2(0.32, 0.72);

// The production sheet stores the silhouette above the fringe's alpha range.
void fragment() {
	float coverage = texture(TEXTURE, UV).a;
	COLOR.a *= smoothstep(fringe.x, fringe.y, coverage);
}
