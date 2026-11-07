class_name MoleculeCharacter
extends RefCounted
## Authored torso and membrane, with animated attachment points and real substituents.
const BONE := Color("f1dbab")
const GOLD := Color("e9ac51")
const FRONT := Vector2(3.12, -0.40)
const FRAME := Rect2(-4.37, -2.56, 8.44, 5.94)
const SUPPORTS := [Vector2(-2.22, 3.35), Vector2(1.55, 3.35)]
const CORE := "geometric-hero"
# Pixel calibration of the illustrated ring center, ground line, and visible trim.
const CORE_SOURCE := Rect2(105, 113, 1197, 848)
const CORE_ORIGIN := Vector2(924, 316)
const CORE_UNIT := 191.0
const CORE_ROWS := [0.0, 0.42, 0.70, 1.0]
const ANCHORS := {
	"L1": Vector2(-1.71, 0.23), "L2": Vector2(1.67, -0.49),
	"R1": Vector2(-1.06, -1.56), "R2": Vector2(0.70, -1.93),
	"R3": Vector2(0.81, 1.20), "T1": Vector2(-3.06, 0.88), "T2": FRONT,
}
const ROOTS := {
	"L1": Vector2(-0.93, 0.23), "L2": Vector2(0.91, -0.18),
	"R1": Vector2(-0.56, -0.70), "R2": Vector2(0.18, -0.83),
	"R3": Vector2(0.52, 0.70),
}


static func anchor(id: String, profile: String, pose := 0.0) -> Vector2:
	var point: Vector2 = ANCHORS[id]
	if id == "T2" and profile == "potent":
		point.x += 0.21
	elif id == "R2" and profile == "selective":
		point.y -= 0.14
	var reach := maxf(point.x, 0.0) * 0.14
	return point + Vector2(0.36 + reach, -0.13) * pose


static func part_unit(fragment: String, id: String) -> float:
	if fragment.is_empty():
		return 0.60
	return 0.80 if id in ["L1", "L2", "T1", "T2"] else 0.69


static func attack_anchor(fragments: Dictionary, profile: String, pose: float) -> Vector2:
	var id := String(fragments.get("T2", ""))
	var part := id if not id.is_empty() else "hydrogen"
	var center := anchor("T2", profile, pose)
	var bounds := MoleculeSpecimen.bounds(part, center, part_unit(id, "T2"))
	return Vector2(bounds.end.x, center.y)


## ribbon：丝带末梢相对身体的滞后量（分子单位）。丝带根部固定在腰部节点，末梢按滞后量甩动
static func draw(ci: CanvasItem, slots: Dictionary, fragments: Dictionary, level: int, pose: float, ribbon := Vector2.ZERO) -> void:
	if level >= 3:
		# A second thin pennant grows from the same waist node. The trailing tip moves first.
		var waist := _core_shift(0.90, pose)
		var extent := lerpf(2.55, 3.32, clampf((level - 3) * 0.5, 0.0, 1.0))
		var source := MoleculeSpecimen.region("membrane")
		var rect := Rect2(Vector2(-extent + 0.04, 0.30 - pose * 0.19) + waist, Vector2(extent, 1.28))
		if source.has_area():
			var tip := ribbon.limit_length(1.2)
			PaintedArt.textured_quad(ci, MoleculeSpecimen.texture(), source, PackedVector2Array([
				rect.position + tip, Vector2(rect.end.x, rect.position.y),
				rect.end, Vector2(rect.position.x, rect.end.y) + tip * 0.8]))
	_draw_core(ci, pose)
	for id in ANCHORS:
		var point: Vector2 = slots[id]
		var root: Vector2
		if id == "T1":
			root = slots["L1"]
		elif id == "T2":
			root = slots["L2"]
		else:
			root = ROOTS[id]
			root += _core_shift(root.y, pose)
		_draw_branch(ci, root, point, 0.26 if id in ["R1", "R2", "R3"] else 0.37)
	for id in ANCHORS:
		var fragment := String(fragments.get(id, ""))
		MoleculeSpecimen.draw_fragment(ci, fragment if not fragment.is_empty() else "hydrogen", slots[id],
			part_unit(fragment, id))


static func _core_shift(y: float, pose: float) -> Vector2:
	var weight := clampf((SUPPORTS[0].y - y) / 4.0, 0.0, 1.0)
	return Vector2(0.47, -0.13) * weight * pose


static func _draw_core(ci: CanvasItem, pose: float) -> void:
	var texture := UIKit.art(CORE)
	if texture == null:
		return
	# Contiguous painted strips bend the body above its planted feet without gaps between parts.
	for i in range(CORE_ROWS.size() - 1):
		var a := float(CORE_ROWS[i])
		var b := float(CORE_ROWS[i + 1])
		var source := Rect2(CORE_SOURCE.position + Vector2(0, a * CORE_SOURCE.size.y),
			Vector2(CORE_SOURCE.size.x, (b - a) * CORE_SOURCE.size.y))
		var area := Rect2((source.position - CORE_ORIGIN) / CORE_UNIT, source.size / CORE_UNIT)
		var top := _core_shift(area.position.y, pose)
		var base := _core_shift(area.end.y, pose)
		PaintedArt.textured_quad(ci, texture, source, PackedVector2Array([
			area.position + top, Vector2(area.end.x, area.position.y) + top,
			area.end + base, Vector2(area.position.x, area.end.y) + base]))


static func _draw_branch(ci: CanvasItem, a: Vector2, b: Vector2, thickness: float) -> void:
	# Use left-to-right UVs for both arms so the painted light stays on the upper edge.
	if a.x > b.x or (is_equal_approx(a.x, b.x) and a.y > b.y):
		var swap := a
		a = b
		b = swap
	var axis := b - a
	if axis.length_squared() < 0.0025:
		return
	var direction := axis.normalized()
	var edge := direction.orthogonal() * thickness * 0.5
	a -= direction * 0.07
	b += direction * 0.06
	var source := MoleculeSpecimen.region("chain")
	if source.has_area():
		PaintedArt.textured_quad(ci, MoleculeSpecimen.texture(), source,
			PackedVector2Array([a - edge, b - edge, b + edge, a + edge]))
