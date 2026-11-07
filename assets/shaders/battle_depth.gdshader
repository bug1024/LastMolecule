shader_type canvas_item;
// Distant scenery stays low frequency and subordinate to the live stage.
void fragment() {
 vec2 d = TEXTURE_PIXEL_SIZE * 3.0;
 vec4 t = texture(TEXTURE, UV) * 0.28;
 t += texture(TEXTURE, UV + vec2(d.x,0.0)) * 0.18;
 t += texture(TEXTURE, UV - vec2(d.x,0.0)) * 0.18;
 t += texture(TEXTURE, UV + vec2(0.0,d.y)) * 0.18;
 t += texture(TEXTURE, UV - vec2(0.0,d.y)) * 0.18;
 float l = dot(t.rgb,vec3(0.299,0.587,0.114));
 vec3 c = mix(vec3(l),t.rgb,0.48);
 c = mix(vec3(0.15,0.19,0.27),c,0.56);
 COLOR = vec4(c * 0.70,t.a);
}
