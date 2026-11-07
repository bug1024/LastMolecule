class_name BattleStage
extends Control
## Separate receiving plane: broad matte shapes and contact shadows, never a baked scene.
var ground := 400.0
var shadows: Array = []
var impact := Vector2.ZERO
var impact_light := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(w,0),Vector2(w,48),Vector2(0,48)]),PackedColorArray([Color(0.04,0.06,0.11,0.75),Color(0.04,0.06,0.11,0.75),Color(0.04,0.06,0.11,0.2),Color(0.04,0.06,0.11,0.2)]))
	# A low-frequency ribbon plane replaces busy terrain at the combatants' feet.
	var ridge := PackedVector2Array([Vector2(0, ground - 27), Vector2(w * 0.18, ground - 17),
		Vector2(w * 0.43, ground - 29), Vector2(w * 0.70, ground - 19), Vector2(w, ground - 31),
		Vector2(w, ground + 69), Vector2(w * 0.60, ground + 77), Vector2(0, ground + 63)])
	draw_polygon(ridge,PackedColorArray([Color(0.25,0.27,0.34,0.82),Color(0.28,0.29,0.35,0.86),Color(0.30,0.30,0.36,0.85),Color(0.27,0.28,0.35,0.8),Color(0.25,0.27,0.34,0.8),Color(0.18,0.21,0.29,0.24),Color(0.18,0.21,0.29,0.20),Color(0.18,0.21,0.29,0.24)]))
	draw_polyline(PackedVector2Array([ridge[0],ridge[1],ridge[2],ridge[3],ridge[4]]), Color(0.48,0.45,0.46,0.6), 1.5, true)
	for i in 7:
		var x := w * (i + 0.4) / 7.0
		draw_line(Vector2(x, ground + 26), Vector2(x + 30, ground + 23), Color(0.12, 0.15, 0.23, 0.28), 2, true)
	for shadow in shadows:
		var c: Vector2 = shadow.center
		for j in 5:
			var points := PackedVector2Array()
			for k in 40:
				var a := k * TAU / 40.0
				points.append(c + Vector2(cos(a) * float(shadow.width) * (0.5 - j * 0.065), sin(a) * (9 - j)))
			draw_colored_polygon(points, Color(0.04, 0.05, 0.09, 0.11))
	if impact_light > 0:
		Shading.glow(self, Vector2(impact.x, ground), 160, Color(UIKit.GOLD, impact_light * 0.45))
	# Stable quiet UI reading plane, independent of the world illustration.
	var dock_y := ground + 83
	draw_rect(Rect2(0, dock_y, w, maxf(0,size.y-dock_y)), Color(0.06, 0.08, 0.14, 0.94))
	draw_line(Vector2(0,dock_y),Vector2(w,dock_y),Color(UIKit.PAPER,0.12),1,true)
