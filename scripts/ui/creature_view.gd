class_name CreatureView
extends Control
## 程序绘制的敌人形象：细胞 / 团块 / 尖刺 / 晶体 / 毒云五种形态，带呼吸、眨眼、受击闪白与死亡消散。
## 另有最终 Boss 专用的 molecule 形态：就是标题页上那颗 LM-001 分子（多环结构 + 金色光环 + 核心里的脸），
## 受伤时外圈原子逐个熄灭，生命低于一半时转得更快并泛红。
## 眼睛朝向左侧（玩家方向）；精英与 Boss 额外画怒眉和獠牙。

var shape := "blob"
var color := Color(0.6, 0.5, 0.9)
var radius := 60.0
var menace := 0        # 0 普通 / 1 精英 / 2 Boss
var flash := 0.0       # 受击闪白 0..1
var dying := 0.0       # 死亡进度 0..1
var _time := 0.0
var _seed := 0.0
var _blink := 0.0
var _next_blink := 2.0
var hp_ratio := 1.0                 # 当前生命比例（molecule 形态用来熄灭原子）
var _mol_atoms: Array[Vector2] = []  # molecule 形态：单位半径内的原子坐标（外圈在后）
var _mol_bonds: Array[Vector2i] = []
var _mol_colors: Array[int] = []


func setup(def: Dictionary, boss := false, elite := false) -> void:
	shape = String(def.get("shape", "blob"))
	color = Color.from_string(String(def.get("color", "#9b6cf2")), Color(0.6, 0.5, 0.9))
	radius = 58.0 * float(def.get("size", 1.0))
	menace = 2 if boss else (1 if elite else 0)
	_seed = float(hash(String(def.get("id", ""))) % 1000) / 100.0
	custom_minimum_size = Vector2(radius * 2.8, radius * 2.6)
	if shape == "molecule":
		_build_molecule()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit() -> void:
	flash = 1.0


func _process(delta: float) -> void:
	_time += delta
	flash = maxf(0.0, flash - delta * 4.0)
	_next_blink -= delta
	if _next_blink <= 0:
		_blink = 1.0
		_next_blink = randf_range(2.0, 4.5)
	_blink = maxf(0.0, _blink - delta * 7.0)
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.55)
	var breathe := 1.0 + 0.03 * sin(_time * 2.0 + _seed)
	var r := radius * breathe * (1.0 - dying * 0.4)
	var alpha := 1.0 - dying
	var body := color.lerp(Color.WHITE, flash * 0.85)
	body.a = alpha
	draw_set_transform(Vector2.ZERO)
	_ellipse(c + Vector2(0, r * 1.05), Vector2(r * 0.9, r * 0.18), Color(0, 0, 0, 0.35 * alpha))
	for i in 4:
		draw_circle(c, r * (1.5 - i * 0.12), Color(color, 0.03 * alpha))
	match shape:
		"spiky":
			_draw_spiky(c, r, body, alpha)
		"crystal":
			_draw_crystal(c, r, body, alpha)
		"cloud":
			_draw_cloud(c, r, body, alpha)
		"cell":
			_draw_cell(c, r, body, alpha)
		"molecule":
			_draw_molecule(c, r, body, alpha)
		_:
			_draw_blob(c, r, body, alpha)
	if shape == "molecule":
		_draw_face(c + Vector2(0, -r * 0.06), r * 0.72, alpha)   # 脸缩小放进分子核心
	else:
		_draw_face(c + Vector2(-r * 0.12, -r * 0.08), r, alpha)


func _wobble_points(c: Vector2, r: float, amp: float, lobes: int, speed: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		var k := 1.0 + amp * sin(lobes * a + _time * speed + _seed) + amp * 0.6 * sin((lobes + 2) * a - _time * speed * 1.4)
		pts.append(c + Vector2(cos(a), sin(a)) * r * k)
	return pts


func _draw_blob(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var pts := _wobble_points(c, r, 0.06, 3, 1.3)
	draw_colored_polygon(pts, body.darkened(0.15))
	draw_colored_polygon(_wobble_points(c + Vector2(-r * 0.1, -r * 0.12), r * 0.78, 0.05, 4, 1.7), body)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.16, Color(1, 1, 1, 0.25 * alpha))
	pts.append(pts[0])
	draw_polyline(pts, body.darkened(0.45), 3.0, true)


func _draw_cell(c: Vector2, r: float, body: Color, alpha: float) -> void:
	for i in 18:
		var a := TAU * i / 18.0 + _time * 0.3
		var base := c + Vector2(cos(a), sin(a)) * r
		var tip := c + Vector2(cos(a + 0.15 * sin(_time * 3 + i)), sin(a + 0.15 * sin(_time * 3 + i))) * r * 1.18
		draw_line(base, tip, body.darkened(0.3), 2.0, true)
	var pts := _wobble_points(c, r, 0.04, 5, 1.0)
	draw_colored_polygon(pts, Color(body.lightened(0.1), 0.85 * alpha))
	pts.append(pts[0])
	draw_polyline(pts, body.darkened(0.4), 3.5, true)
	draw_colored_polygon(_wobble_points(c + Vector2(r * 0.28, r * 0.25), r * 0.32, 0.08, 3, 2.0), body.darkened(0.35))
	for i in 5:
		var a := _seed + i * 1.3 + _time * 0.4
		draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.6, r * 0.07, Color(body.lightened(0.4), 0.8 * alpha))


func _draw_spiky(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var spikes := 12
	var rot := _time * 0.25
	for i in spikes:
		var a := rot + TAU * i / spikes
		var length := r * (1.45 + 0.08 * sin(_time * 3.0 + i))
		var left := c + Vector2(cos(a - 0.16), sin(a - 0.16)) * r * 0.85
		var right := c + Vector2(cos(a + 0.16), sin(a + 0.16)) * r * 0.85
		var tip := c + Vector2(cos(a), sin(a)) * length
		draw_colored_polygon(PackedVector2Array([left, tip, right]), body.darkened(0.25))
		draw_circle(tip, r * 0.06, Color(body.lightened(0.5), alpha))
	draw_circle(c, r * 0.92, body.darkened(0.1))
	draw_circle(c + Vector2(-r * 0.08, -r * 0.1), r * 0.75, body)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.15, Color(1, 1, 1, 0.25 * alpha))
	draw_arc(c, r * 0.92, 0, TAU, 48, body.darkened(0.45), 3.0, true)


func _draw_crystal(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var sides := 6
	var rot := _time * 0.15 + _seed
	var outer: Array[Vector2] = []
	for i in sides:
		var a := rot + TAU * i / sides
		var stretch := Vector2(1.0, 1.25)
		outer.append(c + Vector2(cos(a), sin(a)) * r * stretch)
	for i in sides:
		var shade := 0.25 + 0.5 * (0.5 + 0.5 * sin(rot * 2.0 + i * 1.7))
		var tri := PackedVector2Array([c, outer[i], outer[(i + 1) % sides]])
		draw_colored_polygon(tri, body.darkened(0.5).lerp(body.lightened(0.35), shade))
	for i in sides:
		draw_line(c, outer[i], Color(1, 1, 1, 0.25 * alpha), 1.5, true)
		draw_line(outer[i], outer[(i + 1) % sides], body.darkened(0.5), 3.0, true)
	for i in 3:
		var a := _time * 0.8 + i * TAU / 3.0
		draw_circle(c + Vector2(cos(a), sin(a) * 0.4) * r * 1.4, r * 0.08, Color(body.lightened(0.4), 0.7 * alpha))


func _draw_cloud(c: Vector2, r: float, body: Color, alpha: float) -> void:
	for i in 9:
		var a := TAU * i / 9.0 + _time * 0.2
		var d := r * (0.55 + 0.12 * sin(_time * 1.3 + i))
		var p := c + Vector2(cos(a) * d * 1.2, sin(a) * d * 0.8)
		draw_circle(p, r * (0.48 + 0.06 * sin(_time * 2.0 + i * 2.0)), Color(body.darkened(0.2), 0.75 * alpha))
	draw_circle(c, r * 0.72, body)
	for i in 10:
		var t := fmod(_time * 0.35 + i * 0.1, 1.0)
		var a := i * 2.4 + _seed
		var p := c + Vector2(cos(a), sin(a)) * r * (0.6 + t * 0.9) + Vector2(0, -t * r * 0.6)
		draw_circle(p, r * 0.05 * (1.0 - t), Color(body.lightened(0.4), (1.0 - t) * 0.8 * alpha))


## 与标题页 / 总览的 MoleculeArt 同一套多环结构（6 个苯环 + 侧链），归一化到单位半径
func _build_molecule() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1024
	var centers := [Vector2.ZERO, Vector2(1.732, 0), Vector2(0.866, 1.5), Vector2(-0.866, 1.5), Vector2(-1.732, 0), Vector2(0.866, -1.5)]
	var index_of := {}
	var pts: Array[Vector2] = []
	for ring in centers:
		var ids: Array[int] = []
		for k in 6:
			var a := PI / 6 + k * TAU / 6
			var p: Vector2 = ring + Vector2(cos(a), sin(a))
			var key := Vector2i(roundi(p.x * 100), roundi(p.y * 100))
			if not index_of.has(key):
				index_of[key] = pts.size()
				pts.append(p)
				_mol_colors.append(0 if rng.randf() < 0.65 else rng.randi_range(1, 4))
			ids.append(index_of[key])
		for k in 6:
			var b := Vector2i(mini(ids[k], ids[(k + 1) % 6]), maxi(ids[k], ids[(k + 1) % 6]))
			if not _mol_bonds.has(b):
				_mol_bonds.append(b)
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= pts.size()
	var extent := 0.0
	for p in pts:
		extent = maxf(extent, (p - centroid).length())
	for p in pts:
		_mol_atoms.append((p - centroid) / extent)


func _draw_molecule(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var hurt := clampf(1.0 - hp_ratio, 0.0, 1.0)
	var spin := _time * (0.25 if hp_ratio > 0.5 else 0.6)
	var tone := body.lerp(Color(1.0, 0.35, 0.35), (0.5 + 0.5 * sin(_time * 5.0)) * 0.6 if hp_ratio <= 0.5 else 0.0)
	var span := r * 1.25
	# 金色光环
	for i in 12:
		var a := -spin * 0.6 + i * TAU / 12.0
		draw_arc(c, span * 1.12, a, a + TAU / 24.0, 6, Color(1.0, 0.85, 0.4, 0.6 * alpha), 3.0, true)
	var pts: Array[Vector2] = []
	for p in _mol_atoms:
		pts.append(c + p.rotated(spin) * span * Vector2(1.0, 0.9))
	# 熄灭顺序：离中心越远越先熄灭
	var order := range(_mol_atoms.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _mol_atoms[a].length() > _mol_atoms[b].length())
	var dark := {}
	for k in int(round(hurt * order.size() * 0.85)):
		dark[order[k]] = true
	for b in _mol_bonds:
		var lit := not dark.has(b.x) and not dark.has(b.y)
		draw_line(pts[b.x], pts[b.y], Color(tone, (0.3 if lit else 0.1) * alpha), 10.0, true)
		draw_line(pts[b.x], pts[b.y], Color(tone.lightened(0.35), (0.9 if lit else 0.25) * alpha), 3.5, true)
	var palette := [Color(0.95, 0.97, 1.0), Color(0.45, 0.75, 1.0), Color(0.6, 0.48, 0.95), Color(0.95, 0.72, 0.35), Color(0.93, 0.45, 0.45)]
	for i in pts.size():
		var col: Color = palette[_mol_colors[i]]
		if dark.has(i):
			draw_circle(pts[i], r * 0.07, Color(0.25, 0.27, 0.3, 0.8 * alpha))
		else:
			draw_circle(pts[i], r * 0.13, Color(col, 0.2 * alpha))
			draw_circle(pts[i], r * 0.08, Color(col.lerp(Color.WHITE, flash * 0.8), alpha))
	# 核心（脸画在这里）
	draw_circle(c, r * 0.5, Color(0.05, 0.06, 0.09, 0.9 * alpha))
	draw_circle(c, r * 0.46, Color(tone.darkened(0.35).lerp(Color.WHITE, flash * 0.6), alpha))
	draw_arc(c, r * 0.5, 0, TAU, 40, Color(1.0, 0.85, 0.4, 0.9 * alpha), 3.0, true)


func _draw_face(c: Vector2, r: float, alpha: float) -> void:
	var eye_r := r * (0.16 if menace == 0 else 0.14)
	var gap := r * 0.3
	var look := Vector2(-eye_r * 0.35, eye_r * 0.1)
	for side in [-1, 1]:
		var e := c + Vector2(side * gap, 0)
		var open := 1.0 - _blink
		_ellipse(e, Vector2(eye_r, eye_r * maxf(open, 0.08)), Color(1, 1, 1, 0.95 * alpha))
		if open > 0.3:
			draw_circle(e + look, eye_r * 0.5, Color(0.08, 0.06, 0.1, alpha))
			draw_circle(e + look + Vector2(-eye_r * 0.18, -eye_r * 0.2), eye_r * 0.15, Color(1, 1, 1, alpha))
		if menace > 0:
			var inner := e + Vector2(-side * eye_r * 0.2, -eye_r * 1.25)
			var outer := e + Vector2(side * eye_r * 1.2, -eye_r * 1.75)
			draw_line(inner, outer, Color(0.08, 0.05, 0.08, alpha), 4.0, true)
	var mouth := c + Vector2(0, r * 0.38)
	if menace == 2:
		var w := r * 0.42
		var pts := PackedVector2Array()
		for i in 7:
			pts.append(mouth + Vector2(-w + w * 2 * i / 6.0, (6.0 if i % 2 == 0 else -2.0) + 3.0 * sin(_time * 4.0)))
		draw_polyline(pts, Color(0.08, 0.05, 0.08, alpha), 4.0, true)
	else:
		draw_arc(mouth + Vector2(0, 8), r * 0.18, PI * 1.15, PI * 1.85, 12, Color(0.08, 0.05, 0.08, alpha), 3.0, true)


func _ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)
