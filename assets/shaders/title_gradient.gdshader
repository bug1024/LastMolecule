shader_type canvas_item;
// 标题字标：字面从受光的骨白过渡到底部的暖金。按顶点的本地 y 取值，字形图集的 UV 不能用。
uniform vec4 top_color : source_color = vec4(1.0, 0.97, 0.87, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.87, 0.71, 0.45, 1.0);
uniform float height = 100.0;
varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float t = smoothstep(0.3, 0.92, clamp(local_y / height, 0.0, 1.0));
	COLOR.rgb *= mix(top_color.rgb, bottom_color.rgb, t);
}
