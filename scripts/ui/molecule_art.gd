class_name MoleculeArt
extends Control
## 主界面中央的候选分子插画：随研发阶段推进逐步“长大”（环数增加），
## 缓慢旋转并呼吸发光；健康度（疗效 / 安全）影响主色调。

var stage_index := 0:
	set(value):
		stage_index = value
		_rebuild()
var health := 0.5          # 0..1，越高越偏绿，越低越偏红
var _atoms: Array[Vector3] = []   # x, y, 颜色索引
var _bonds: Array[Vector2i] = []
var _time := 0.0

const ATOM_COLORS := [Color(0.95, 0.97, 1.0), Color(0.45, 0.75, 1.0), Color(0.6, 0.48, 0.95), Color(0.95, 0.72, 0.35), Color(0.93, 0.45, 0.45)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()


func _rebuild() -> void:
	_atoms.clear()
	_bonds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1024
	var rings := clampi(stage_index + 1, 1, 6)
	var centers := [Vector2.ZERO, Vector2(1.732, 0), Vector2(0.866, 1.5), Vector2(-0.866, 1.5), Vector2(-1.732, 0), Vector2(0.866, -1.5)]
	var index_of := {}
	for r in rings:
		var ring_ids: Array[int] = []
		for k in 6:
			var angle := PI / 6 + k * TAU / 6
			var p: Vector2 = centers[r] + Vector2(cos(angle), sin(angle))
			var key := Vector2i(roundi(p.x * 100), roundi(p.y * 100))
			if not index_of.has(key):
				index_of[key] = _atoms.size()
				_atoms.append(Vector3(p.x, p.y, 0 if rng.randf() < 0.7 else rng.randi_range(1, 4)))
			ring_ids.append(index_of[key])
		for k in 6:
			var bond := Vector2i(mini(ring_ids[k], ring_ids[(k + 1) % 6]), maxi(ring_ids[k], ring_ids[(k + 1) % 6]))
			if not _bonds.has(bond):
				_bonds.append(bond)
	# 侧链
	for s in mini(stage_index + 1, 4):
		var from := rng.randi_range(0, _atoms.size() - 1)
		var base := Vector2(_atoms[from].x, _atoms[from].y)
		var dir := base.normalized() if base.length() > 0.1 else Vector2.RIGHT
		var tip := base + dir * 1.0
		_atoms.append(Vector3(tip.x, tip.y, rng.randi_range(1, 4)))
		_bonds.append(Vector2i(from, _atoms.size() - 1))
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	if UIKit.atlas(self, "specimens", 5, Rect2(Vector2.ZERO, size)):
		return
	if _atoms.is_empty():
		return
	var center := size * 0.5
	var extent := 0.0
	for a in _atoms:
		extent = maxf(extent, Vector2(a.x, a.y).length())
	var scale_px := minf(size.x, size.y) * 0.42 / maxf(extent, 1.0)
	var tone := Color(0.93, 0.42, 0.42).lerp(Color(0.31, 0.85, 0.6), clampf(health, 0.0, 1.0))
	var pulse := 0.5 + 0.5 * sin(_time * 1.6)
	for i in 8:
		draw_circle(center, minf(size.x, size.y) * (0.48 - i * 0.04), Color(tone, 0.018 + 0.008 * pulse))
	var rot := _time * 0.18
	var squash := 0.85 + 0.15 * cos(_time * 0.37)
	var points: Array[Vector2] = []
	var centroid := Vector2.ZERO
	for a in _atoms:
		centroid += Vector2(a.x, a.y)
	centroid /= _atoms.size()
	for a in _atoms:
		var p := (Vector2(a.x, a.y) - centroid).rotated(rot)
		points.append(center + Vector2(p.x, p.y * squash) * scale_px)
	for b in _bonds:
		draw_line(points[b.x], points[b.y], Color(tone, 0.25), 9.0, true)
		draw_line(points[b.x], points[b.y], Color(tone.lightened(0.3), 0.9), 3.0, true)
	for i in _atoms.size():
		var c: Color = ATOM_COLORS[int(_atoms[i].z)]
		var r := 7.0 if int(_atoms[i].z) == 0 else 10.0
		draw_circle(points[i], r + 5, Color(c, 0.15 + 0.1 * pulse))
		draw_circle(points[i], r, c)
