class_name BattleLayout
extends RefCounted
## Space is budgeted before artwork. All positions are local to the battle viewport.
static func compose(view: Vector2, targets: int) -> Dictionary:
	var card_scale := 0.82
	var hand_height := CardFace.BASE.y * card_scale
	var hand_top := view.y - hand_height - 24
	var ground := minf(view.y * 0.58, hand_top - 108)
	var centers: Array = [0.73] if targets == 1 else ([0.66, 0.85] if targets == 2 else [0.60, 0.75, 0.90])
	var slots: Array = []
	for i in targets:
		var width := view.x * (0.374 if targets == 1 else (0.18 if targets == 2 else 0.145))
		var height := minf(ground - (66 if targets == 1 else 94), view.y * (0.495 if targets == 1 else 0.29))
		slots.append({"foot": Vector2(view.x * centers[i], ground), "body": Vector2(width, height)})
	return {"ground": ground, "hero": Vector2(view.x * 0.28, ground),
		"hero_size": Vector2(view.x * 0.335, minf(view.y * 0.39, ground - 110)),
		"slots": slots, "hand_top": hand_top, "hand_scale": card_scale,
		"hand_left": view.x * 0.18, "hand_right": view.x * 0.82, "status_y": ground + 22}


static func fan(view: Vector2, count: int, active := -1) -> Array:
	var layout := compose(view, 1)
	var width := CardFace.BASE.x * float(layout.hand_scale)
	var height := CardFace.BASE.y * float(layout.hand_scale)
	var available := float(layout.hand_right) - float(layout.hand_left)
	var spread := minf(width * 0.92, (available - width - 36) / maxf(1, count - 1))
	var result: Array = []
	for i in count:
		var d := i - (count - 1) * 0.5
		var angle := deg_to_rad(clampf(d * 3.5, -12, 12))
		var edge := absf(d) / maxf(1, (count - 1) * 0.5)
		var x := view.x * 0.5 + d * spread - width * 0.5
		var y := float(layout.hand_top) - 10 + edge * 8
		var scale := 1.0
		if i == active:
			angle = 0
			scale = 1.13
			y -= 32
		elif active >= 0:
			x += signf(i - active) * 12
		result.append({"position": Vector2(x, y), "rotation": angle, "scale": scale, "size": Vector2(width, height)})
	return result
