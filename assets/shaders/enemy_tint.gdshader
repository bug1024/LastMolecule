shader_type canvas_item;
// 敌人身份色：手绘精灵原本都偏紫，这里把色相整体转向每个敌人自己的颜色，
// 保留明暗和笔触；色相差被压缩，整只生物读作一个颜色家族，而不是一张换了色的贴图。
uniform float target_hue = 0.78;
uniform float strength = 0.82;
uniform float spread = 0.35;
uniform float heat = 0.0;   // 剂量毒性：整体发烫

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV) * COLOR;
	vec3 hsv = rgb2hsv(src.rgb);
	float off = fract(hsv.x - 0.78 + 0.5) - 0.5;          // 原图以紫色 0.78 为中心
	float hue = fract(target_hue + off * spread);
	vec3 shifted = hsv2rgb(vec3(hue, hsv.y, hsv.z));
	vec3 rgb = mix(src.rgb, shifted, strength * smoothstep(0.08, 0.3, hsv.y));
	rgb = mix(rgb, rgb * vec3(1.35, 0.72, 0.6) + vec3(0.08, 0.0, 0.0), heat);
	COLOR = vec4(rgb, src.a);
}
