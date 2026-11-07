class_name BattleStage
extends Control
## Separate receiving plane: broad matte shapes and contact shadows, never a baked scene.
var ground := 400.0
var shadows: Array = []
var impact := Vector2.ZERO
var impact_light := 0.0
var pressure := 0.0                       # Boss 压迫感 0–1：地面亮边和脚下的光都转成危险色
var pressure_color := Color(0.85, 0.2, 0.18)
var threat_x := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var w := size.x
	draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(w,0),Vector2(w,48),Vector2(0,48)]),PackedColorArray([Color(0.04,0.06,0.11,0.75),Color(0.04,0.06,0.11,0.75),Color(0.04,0.06,0.11,0.2),Color(0.04,0.06,0.11,0.2)]))
	var terrain := UIKit.art("geometric-ground")
	if terrain:
		var depth := clampf(size.y * 0.32, 155.0, 238.0)
		draw_texture_rect(terrain, Rect2(0, ground - depth * 0.68, w, depth), false, Color(0.89, 0.90, 0.98))
	else:
		draw_rect(Rect2(0, ground - 22, w, 80), Color(0.22, 0.24, 0.31, 0.8))
	if pressure > 0.01:
		Shading.glow(self, Vector2(threat_x, ground), 245, Color(pressure_color, 0.22 * pressure))

	for shadow in shadows:
		var c: Vector2 = shadow.center
		var opacity := float(shadow.get("opacity", 0.14))
		var depth := float(shadow.get("depth", 10.0))
		for j in 4:
			var points := PackedVector2Array()
			var offset := Vector2((3 - j) * 4, (3 - j) * 1.4)
			for k in 28:
				var a := k * TAU / 28.0
				points.append(c + offset + Vector2(cos(a) * float(shadow.width) * (0.52 - j * 0.074),
					sin(a) * depth * (1.0 - j * 0.16)))
			draw_colored_polygon(points, Color(0.035, 0.045, 0.085, opacity))
	if impact_light > 0:
		Shading.glow(self, Vector2(impact.x, ground), 160, Color(UIKit.GOLD, impact_light * 0.45))
	# Stable quiet UI reading plane, independent of the world illustration.
	# 没有硬分界线：地面渐渐沉进暗处，手牌像放在场景前景的阴影里
	var dock_y := ground + 83
	var fade := 70.0
	var dark := Color(0.05, 0.065, 0.115, 0.95)
	var top := dock_y - fade
	draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, dock_y), Vector2(0, dock_y)]),
		PackedColorArray([Color(dark, 0.0), Color(dark, 0.0), dark, dark]))
	draw_rect(Rect2(0, dock_y, w, maxf(0, size.y - dock_y)), dark)
