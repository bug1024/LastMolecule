class_name MoleculeBackground
extends Control
## 动态背景：深色渐变 + 柔光 + 缓慢漂浮旋转的分子结构线稿（纯绘制，无贴图）。

@export var molecule_count := 18
@export var top_color := Color(0.05, 0.07, 0.1)
@export var bottom_color := Color(0.02, 0.035, 0.05)
@export var line_color := Color(0.4, 0.85, 0.7)
@export var glow_color := Color(0.18, 0.55, 0.5)

var _molecules: Array = []
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 20261025
	for i in molecule_count:
		_molecules.append(_make_molecule())


func _make_molecule() -> Dictionary:
	var atoms: Array[Vector2] = []
	var bonds: Array[Vector2i] = []
	var rings := _rng.randi_range(1, 3)
	var bond := 1.0
	var origin := Vector2.ZERO
	for r in rings:
		var start := atoms.size()
		for k in 6:
			var angle := PI / 6 + k * TAU / 6
			atoms.append(origin + Vector2(cos(angle), sin(angle)) * bond)
		for k in 6:
			bonds.append(Vector2i(start + k, start + (k + 1) % 6))
		if r > 0:
			bonds.append(Vector2i(start - 3, start + 3))
		origin += Vector2(sqrt(3.0) * bond, 0).rotated(_rng.randf_range(-0.6, 0.6))
	for s in _rng.randi_range(1, 3):
		var from := _rng.randi_range(0, atoms.size() - 1)
		var dir := atoms[from].normalized() if atoms[from].length() > 0.01 else Vector2.UP
		atoms.append(atoms[from] + dir * bond)
		bonds.append(Vector2i(from, atoms.size() - 1))
	var colors: Array[Color] = []
	for a in atoms:
		colors.append([Color(0.45, 0.75, 1.0), Color(0.6, 0.48, 0.95), Color(0.95, 0.75, 0.35), line_color][_rng.randi_range(0, 3)])
	return {
		"atoms": atoms, "bonds": bonds, "colors": colors,
		"pos": Vector2(_rng.randf(), _rng.randf()),
		"vel": Vector2(_rng.randf_range(-0.006, 0.006), _rng.randf_range(-0.012, -0.003)),
		"rot": _rng.randf_range(0, TAU), "spin": _rng.randf_range(-0.12, 0.12),
		"scale": _rng.randf_range(14.0, 34.0), "alpha": _rng.randf_range(0.06, 0.2),
	}


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	for m in _molecules:
		m.pos += m.vel * delta
		m.rot += m.spin * delta
		if m.pos.y < -0.15:
			m.pos = Vector2(_rng.randf(), 1.15)
		m.pos.x = fposmod(m.pos.x + 0.15, 1.3) - 0.15
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, 0), rect.end, Vector2(0, rect.end.y)]),
		PackedColorArray([top_color, top_color, bottom_color, bottom_color]))
	_glow(Vector2(size.x * 0.22, size.y * 0.3), size.y * 0.55, glow_color, 0.05 + 0.015 * sin(_time * 0.4))
	_glow(Vector2(size.x * 0.82, size.y * 0.75), size.y * 0.5, Color(0.25, 0.35, 0.75), 0.045 + 0.015 * cos(_time * 0.3))
	for m in _molecules:
		var center: Vector2 = m.pos * size
		var xf := Transform2D(m.rot, center).scaled_local(Vector2.ONE * m.scale)
		var color := Color(line_color, m.alpha)
		for b in m.bonds:
			draw_line(xf * m.atoms[b.x], xf * m.atoms[b.y], color, 1.5, true)
		for i in m.atoms.size():
			draw_circle(xf * m.atoms[i], 2.6, Color(m.colors[i], m.alpha * 1.6))


func _glow(center: Vector2, radius: float, color: Color, strength: float) -> void:
	for i in 10:
		var t := float(i) / 10.0
		draw_circle(center, radius * (1.0 - t), Color(color, strength * 0.25))
