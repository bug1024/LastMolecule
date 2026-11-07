class_name MoleculeCharacter
extends RefCounted
## Live illustration in scaffold units. Real substituents follow seven character anchors.
const INK := Color("132735")
const JADE := Color("4b9e83")
const MINT := Color("9bcaae")
const BONE := Color("f1dbab")
const GOLD := Color("e9ac51")
const FRONT := Vector2(2.92, -0.49)
const FRAME := Rect2(-3.72, -2.40, 7.30, 4.75)
const ANCHORS := {
	"L1": Vector2(-1.50, 0.10), "L2": Vector2(1.38, -0.53),
	"R1": Vector2(-0.93, -1.52), "R2": Vector2(0.59, -1.83),
	"R3": Vector2(-0.26, 0.87), "T1": Vector2(-2.63, 0.63), "T2": FRONT,
}
const RING := [Vector2(-0.94,-0.48), Vector2(-0.15,-0.98), Vector2(0.72,-0.69),
	Vector2(0.83,0.19), Vector2(0.08,0.67), Vector2(-0.84,0.37)]


static func draw(ci: CanvasItem, slots: Dictionary, fragments: Dictionary, level: int, profile: String, pose: float) -> void:
	var body_color := JADE
	var membrane := Color("578e83")
	if profile == "potent":
		body_color = Color("818d59")
		membrane = Color("95674f")
	elif profile == "selective":
		body_color = Color("478f93")
		membrane = Color("607da1")
	var lean := Vector2(0.38, -0.07) * pose
	var shoulder := Vector2(-0.12, 0.26) + lean
	var sash_end := Vector2(-3.55, 1.54 - 0.17 * level - pose * 0.16)
	# Back membrane: one thin fork at the start, a split pennant at mature levels.
	_ink_shape(ci, [shoulder, Vector2(-1.56, -0.30), Vector2(-2.66, -0.08), sash_end,
		Vector2(-3.46, 1.64), Vector2(-2.68, 1.18), Vector2(-1.83, 0.64), Vector2(-0.72, 0.64)], membrane)
	_fill(ci, [shoulder, Vector2(-1.56,-0.30), Vector2(-2.66,-0.08), sash_end,
		Vector2(-2.57,0.45), Vector2(-1.70,0.16)], BONE.darkened(0.11))
	if level >= 3:
		_ink_shape(ci, [shoulder, Vector2(-1.58,0.94), Vector2(-2.77,1.42), Vector2(-3.40,1.98),
			Vector2(-2.34,1.74), Vector2(-1.44,1.40), Vector2(-0.36,0.76)], membrane.lightened(0.06))
	if profile == "potent":
		_ink_shape(ci, [Vector2(-0.74,-0.65), Vector2(-2.02,-1.18), Vector2(-1.58,-0.39),
			Vector2(-1.08,-0.13)], body_color.darkened(0.2))
	elif profile == "selective":
		_ink_shape(ci, [Vector2(0.07,-0.69), Vector2(-0.07,-2.20), Vector2(-0.43,-2.02),
			Vector2(-0.51,-1.12), Vector2(-0.44,-0.58)], membrane)
		_fill(ci, [Vector2(-0.07,-2.20), Vector2(-0.17,-1.50), Vector2(-0.45,-1.23), Vector2(-0.43,-2.02)], BONE)

	var pelvis := Vector2(-0.31, 0.82) + lean * 0.68
	_ink_shape(ci, [Vector2(-0.10,0.39)+lean, pelvis, Vector2(-0.70,1.30),
		Vector2(-1.40,1.51), Vector2(-1.95,2.35), Vector2(-1.38,2.35), Vector2(-0.99,1.92),
		Vector2(-0.39,1.62), Vector2(0.04,1.10)], body_color)
	_fill(ci, [pelvis, Vector2(-0.70,1.30), Vector2(-1.40,1.51), Vector2(-1.95,2.35),
		Vector2(-1.51,2.09), Vector2(-1.18,1.69), Vector2(-0.41,1.39)], BONE)
	var knee := Vector2(1.27 + pose * 0.18, 1.48 - pose * 0.16)
	_ink_shape(ci, [pelvis, Vector2(0.25,0.69)+lean, knee + Vector2(0.18,-0.12),
		Vector2(1.10,1.87), Vector2(1.72,2.35), Vector2(1.14,2.35), Vector2(0.67,1.92),
		knee - Vector2(0.20,-0.20), Vector2(0.12,1.23)], body_color)
	_fill(ci, [Vector2(0.25,0.69)+lean, knee + Vector2(0.18,-0.12), knee - Vector2(0.12,0.02)], MINT)
	_fill(ci, [knee + Vector2(0.18,-0.12), Vector2(1.10,1.87), Vector2(1.72,2.35), Vector2(1.23,1.96)], MINT)
	if level >= 2:
		_ink_shape(ci, [pelvis, Vector2(0.46,0.76), Vector2(0.95,0.98), Vector2(1.81,1.36),
			Vector2(2.20,1.19), Vector2(1.81,1.65), Vector2(0.96,1.47), Vector2(0.25,1.06)], membrane)
		_fill(ci, [pelvis, Vector2(0.46,0.76), Vector2(0.95,0.98), Vector2(1.81,1.36),
			Vector2(1.16,1.28), Vector2(0.26,0.99)], BONE)

	for id in ANCHORS:
		var p: Vector2 = slots[id]
		var root := Vector2.ZERO
		match id:
			"L1": root = RING[5] + lean
			"L2": root = RING[2] + lean
			"R1": root = RING[0] + lean
			"R2": root = RING[1] + lean
			"R3": root = RING[4] + lean
			"T1": root = slots["L1"]
			"T2": root = slots["L2"]
		var direction := (p - root).normalized()
		var bend := root.lerp(p, 0.50) + direction.orthogonal() * (0.15 if id in ["T1", "R2"] else -0.12)
		_rib(ci, root, bend, 0.23, body_color)
		_rib(ci, bend, p, 0.15, body_color.lightened(0.12))
	_ring(ci, RING, lean, 0.77, body_color)
	# An irregular inner edge remains open even with a very large substituent.
	for i in RING.size():
		var a: Vector2 = RING[i] + lean
		var b: Vector2 = RING[(i + 1) % RING.size()] + lean
		var tangent := (b - a).normalized()
		for j in 3:
			var q := a.lerp(b, 0.21 + j * 0.17)
			ci.draw_line(q, q + tangent * (0.15 - j * 0.025), Color(BONE, 0.25), 0.014, true)
	for id in ANCHORS:
		_fragment(ci, String(fragments.get(id, "")), slots[id], body_color, id == "T2")
	if level >= 4:
		_fill(ci, [pelvis + Vector2(-0.25, -0.12), pelvis + Vector2(0.27,-0.19),
			pelvis + Vector2(0.37,-0.04), pelvis + Vector2(-0.17,0.03)], GOLD)


static func _fragment(ci: CanvasItem, id: String, p: Vector2, jade: Color, front: bool) -> void:
	if id in ["phenyl", "pyridine", "morpholine", "cyclopropyl"]:
		var count := 3 if id == "cyclopropyl" else 6
		var radius := 0.33 if count == 3 else 0.50
		var outline: Array = []
		for i in count:
			var vertex := Vector2.from_angle(-PI / 2.0 + TAU * i / count)
			outline.append(vertex * Vector2(radius, radius * (0.78 if id == "morpholine" else 1.0)))
		var ring_color := MINT if id == "morpholine" else jade
		_ring(ci, outline, p, 0.60 if count == 3 else 0.67, ring_color)
		if id == "pyridine":
			_tip(ci, p + Vector2(radius * 0.43, -radius * 0.72), 0.095, GOLD)
		return
	match id:
		"fluoro", "methyl", "hydroxyl", "":
			_tip(ci, p, 0.18 if front else (0.08 if id.is_empty() else 0.15),
				GOLD if front or id == "fluoro" else (MINT if id == "hydroxyl" else BONE))
		_:
			var branches := 3 if id in ["tbutyl", "sulfonamide"] else 2
			for i in branches:
				var end := p + Vector2.from_angle(-1.24 + i * 1.36) * (0.34 if i == 0 else 0.28)
				_rib(ci, p, end, 0.12, jade)
				_tip(ci, end, 0.13 if i == 0 else 0.10, GOLD if id in ["nitro", "sulfonamide"] else BONE)
			_tip(ci, p, 0.12, MINT)


static func _tip(ci: CanvasItem, p: Vector2, radius: float, color: Color) -> void:
	var outline: Array = []
	for i in 5:
		outline.append(p + Vector2.from_angle(i * TAU / 5.0 - 0.35) * radius)
	_ink_shape(ci, outline, color)
	_fill(ci, [outline[2], outline[3], outline[4], p], color.darkened(0.16))


static func _ring(ci: CanvasItem, points: Array, center: Vector2, aperture: float, color: Color) -> void:
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var rim := [center+a, center+b, center+b*aperture, center+a*aperture]
		_ink_shape(ci, rim, color if i % 2 == 0 else color.darkened(0.21))
		_fill(ci, [center+a, center+b, center+b*aperture, center+a*0.89], BONE if i <= 1 else color.lightened(0.25))


static func _rib(ci: CanvasItem, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var n := (b-a).normalized().orthogonal() * width
	_ink_shape(ci, [a-n*0.52, b-n*0.38, b+n*0.29, a+n*0.56], color)
	_fill(ci, [a-n*0.52, b-n*0.38, b+n*0.03, a-n*0.17], MINT)


static func _ink_shape(ci: CanvasItem, points: Array, color: Color) -> void:
	var outline := PackedVector2Array(points)
	_paint(ci, outline, color)
	outline.append(outline[0])
	ci.draw_polyline(outline, INK, 0.052, true)


static func _fill(ci: CanvasItem, points: Array, color: Color) -> void:
	_paint(ci, PackedVector2Array(points), color)


static func _paint(ci: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	# Sample the existing dry paper grain in character space. Each painted shape keeps a flat local value.
	var texture := UIKit.art("painted-ui")
	if texture == null:
		ci.draw_colored_polygon(points, color)
		return
	var uv := PackedVector2Array()
	var image_size := texture.get_size()
	var paper := image_size * Vector2(0.105, 0.615)
	for point in points:
		uv.append((paper + (point - FRAME.position) * 44.0) / image_size)
	ci.draw_polygon(points, PackedColorArray([color.lightened(0.075)]), uv, texture)
