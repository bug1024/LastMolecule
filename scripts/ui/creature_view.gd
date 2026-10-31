class_name CreatureView
extends Control
## 程序绘制的敌人形象：细胞 / 团块 / 尖刺 / 晶体 / 毒云五种形态，用 Shading 画出明暗、膜、细胞器与刺突等细节，
## 带呼吸、眨眼、受击闪白与死亡消散。
## 另有最终 Boss 专用的 molecule 形态：就是标题页上那颗 LM-001 分子（多环结构 + 金色光环 + 核心里的脸），
## 受伤时外圈原子逐个熄灭，生命低于一半时转得更快并泛红。
## 眼睛朝向左侧（玩家方向）；精英与 Boss 的上眼睑压低。

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
	var body := color.lerp(Color(0.44, 0.47, 0.39), 0.45).lerp(Color.WHITE, flash * 0.85)
	body.a = alpha
	draw_set_transform(Vector2.ZERO)
	_ellipse(c + Vector2(0, r * 1.05), Vector2(r * 0.9, r * 0.18), Color(0, 0, 0, 0.35 * alpha))
	for i in 4:
		draw_circle(c, r * (1.5 - i * 0.12), Color(color, 0.03 * alpha))
	# 标本图集只有 6 种形态：每个敌人再按自己的颜色上色、按 id 左右翻转 / 微转，并在身后衬一圈本色光晕，
	# 这样同一形态的不同敌人也一眼分得开（两只天然配体之间也略有差别）
	var cells := {"blob": 0, "cell": 1, "crystal": 2, "cloud": 3, "spiky": 4, "molecule": 5}
	var cell: int = cells.get(shape, 0)
	Shading.glow(self, c, r * 1.55, Color(color, (0.42 if menace > 0 else 0.3) * alpha))
	var flip := 1.0 if int(_seed * 10.0) % 2 == 0 else -1.0
	var tint := color.lerp(Color.WHITE, 0.5).lerp(Color.WHITE, flash * 0.8)
	tint.a = alpha
	draw_set_transform(c, sin(_time * 0.6 + _seed) * 0.04 + (_seed - 5.0) * 0.02, Vector2(flip, 1.0))
	var rect := Rect2(-Vector2(r * 1.45, r * 1.28), Vector2(r * 2.9, r * 2.56))
	var ok := UIKit.atlas(self, "specimens", cell, rect, tint)
	draw_set_transform(Vector2.ZERO)
	if not ok:
		_draw_cell(c, r, body, alpha)
	if menace > 0:   # 精英 / Boss：一圈黄铜刻度环，标出它的分量
		var ring := r * 1.42
		for i in 36:
			var a0 := i * TAU / 36.0 + _time * 0.05
			var long := i % 3 == 0
			draw_line(c + Vector2.from_angle(a0) * ring, c + Vector2.from_angle(a0) * (ring + (9.0 if long else 4.0)),
				Color(UIKit.BRASS if menace == 1 else UIKit.DANGER, 0.7 * alpha), 1.5, true)



func _wobble_points(c: Vector2, r: float, amp: float, lobes: int, speed: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		var k := 1.0 + amp * sin(lobes * a + _time * speed + _seed) + amp * 0.6 * sin((lobes + 2) * a - _time * speed * 1.4)
		pts.append(c + Vector2(cos(a), sin(a)) * r * k)
	return pts


## 团块（聚集体、酶、外排泵等）：有明暗的胶质身体 + 半透明外膜 + 体内漂浮的颗粒和表面孔洞
func _draw_blob(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var outer := _wobble_points(c, r * 1.06, 0.06, 3, 1.3)
	draw_colored_polygon(outer, Color(body.lightened(0.3), 0.18 * alpha))
	var pts := _wobble_points(c, r, 0.06, 3, 1.3)
	Shading.shaded_polygon(self, pts, c, r, body)
	for i in 7:   # 体内颗粒（有深度：小而暗的在后）
		var a := _seed * 3.0 + i * 0.9 + _time * 0.25 * (1.0 if i % 2 == 0 else -1.0)
		var d := r * (0.25 + 0.4 * fmod(i * 0.37 + _seed, 1.0))
		var gr := r * (0.06 + 0.035 * (i % 3))
		Shading.sphere(self, c + Vector2(cos(a), sin(a) * 0.8) * d, gr, Color(body.lightened(0.25), 0.75 * alpha), 0.6)
	for i in 4:   # 表面孔洞
		var a := _seed + i * 1.7
		_ellipse(c + Vector2(cos(a), sin(a)) * r * 0.72, Vector2(r * 0.07, r * 0.045), Color(body.darkened(0.55), 0.6 * alpha))
	pts.append(pts[0])
	draw_polyline(pts, Color(body.lightened(0.35), 0.55 * alpha), 2.0, true)


## 细胞：纤毛、双层膜、有明暗的胞质、细胞核（带核仁）、线粒体与囊泡
func _draw_cell(c: Vector2, r: float, body: Color, alpha: float) -> void:
	for i in 26:   # 纤毛：柔软弯曲的细线
		var a := TAU * i / 26.0 + _time * 0.15
		var base := c + Vector2.from_angle(a) * r * 1.02
		var sway := 0.22 * sin(_time * 3.0 + i * 0.8)
		var mid := c + Vector2.from_angle(a + sway * 0.5) * r * 1.13
		var tip := c + Vector2.from_angle(a + sway) * r * 1.24
		draw_polyline(PackedVector2Array([base, mid, tip]), Color(body.lightened(0.2), 0.55 * alpha), 1.5, true)
	var pts := _wobble_points(c, r, 0.04, 5, 1.0)
	Shading.shaded_polygon(self, pts, c, r, Color(body.lightened(0.05), 0.92 * alpha))
	var membrane := pts.duplicate()
	membrane.append(pts[0])
	draw_polyline(membrane, Color(body.lightened(0.45), 0.7 * alpha), 2.5, true)
	draw_polyline(_wobble_points(c, r * 0.93, 0.04, 5, 1.0) + PackedVector2Array([_wobble_points(c, r * 0.93, 0.04, 5, 1.0)[0]]),
		Color(body.darkened(0.3), 0.5 * alpha), 1.5, true)
	for i in 3:   # 线粒体
		var a := _seed + i * 2.1 + _time * 0.2
		var p := c + Vector2(cos(a), sin(a)) * r * 0.55
		draw_set_transform(p, a + 0.6)
		_ellipse(Vector2.ZERO, Vector2(r * 0.13, r * 0.06), Color(body.darkened(0.35), 0.85 * alpha))
		draw_line(Vector2(-r * 0.09, 0), Vector2(r * 0.09, 0), Color(body.lightened(0.3), 0.6 * alpha), 1.2, true)
		draw_set_transform(Vector2.ZERO)
	for i in 5:   # 囊泡
		var a := _seed * 2.0 + i * 1.25 - _time * 0.3
		draw_arc(c + Vector2(cos(a), sin(a)) * r * 0.68, r * 0.045, 0, TAU, 12, Color(body.lightened(0.5), 0.7 * alpha), 1.2, true)
	var nucleus := c + Vector2(r * 0.26, r * 0.22)
	Shading.sphere(self, nucleus, r * 0.3, Color(body.darkened(0.4), alpha), 0.6)
	Shading.sphere(self, nucleus + Vector2(r * 0.05, r * 0.03), r * 0.1, Color(body.darkened(0.65), alpha), 0.4)


## 尖刺（脱靶激酶、活性氧、DNA 损伤……）：有明暗的衣壳球 + 一圈带球头的刺突蛋白 + 淡淡的表面网格
func _draw_spiky(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var spikes := 14
	var rot := _time * 0.2
	for i in spikes:
		var a := rot + TAU * i / spikes
		var length := r * (1.38 + 0.06 * sin(_time * 3.0 + i))
		var base := c + Vector2.from_angle(a) * r * 0.85
		var tip := c + Vector2.from_angle(a) * length
		draw_line(base, tip, Color(body.darkened(0.35), alpha), r * 0.07, true)
		draw_line(base, tip, Color(body.lightened(0.2), 0.6 * alpha), r * 0.025, true)
		Shading.sphere(self, tip, r * 0.1, Color(body.lightened(0.15), alpha), 0.7)
	Shading.sphere(self, c, r * 0.9, body)
	for i in 6:   # 衣壳表面的六边形网格
		var a := rot * 0.5 + i * TAU / 6.0
		var p := c + Vector2.from_angle(a) * r * 0.45
		var hex := PackedVector2Array()
		for k in 7:
			hex.append(p + Vector2.from_angle(k * TAU / 6.0) * r * 0.2)
		draw_polyline(hex, Color(body.lightened(0.4), 0.22 * alpha), 1.2, true)


## 晶体（hERG 通道、结合口袋……）：渐变的多面体刻面 + 内部折射线 + 星芒高光
func _draw_crystal(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var sides := 6
	var rot := _time * 0.15 + _seed
	var outer: Array[Vector2] = []
	for i in sides:
		outer.append(c + Vector2.from_angle(rot + TAU * i / sides) * r * Vector2(1.0, 1.25))
	var top := c + Vector2(-r * 0.12, -r * 0.18)   # 偏心的顶点，让刻面更立体
	for i in sides:
		var tri := PackedVector2Array([top, outer[i], outer[(i + 1) % sides]])
		var light := 0.5 + 0.5 * cos(rot + TAU * (i + 0.5) / sides + 2.3)
		Shading.shaded_polygon(self, tri, c, r * 1.2, body.darkened(0.35).lerp(body.lightened(0.4), light))
	for i in sides:
		draw_line(top, outer[i], Color(1, 1, 1, 0.3 * alpha), 1.5, true)
		draw_line(outer[i], outer[(i + 1) % sides], Color(body.lightened(0.5), 0.8 * alpha), 2.0, true)
	for i in 3:   # 内部折射线
		var a := rot * 2.0 + i * 2.0
		draw_line(c + Vector2.from_angle(a) * r * 0.2, c + Vector2.from_angle(a + 0.8) * r * 0.75, Color(1, 1, 1, 0.12 * alpha), 1.0, true)
	var tw := 0.5 + 0.5 * sin(_time * 3.0 + _seed)
	var star := outer[0].lerp(top, 0.3)
	draw_line(star - Vector2(r * 0.18 * tw, 0), star + Vector2(r * 0.18 * tw, 0), Color(1, 1, 1, 0.8 * alpha), 1.5, true)
	draw_line(star - Vector2(0, r * 0.18 * tw), star + Vector2(0, r * 0.18 * tw), Color(1, 1, 1, 0.8 * alpha), 1.5, true)
	Shading.glow(self, star, r * 0.15, Color(1, 1, 1, 0.6 * tw * alpha))


## 毒云（器官毒性、细胞因子风暴……）：几团半透明、有明暗的烟团 + 内部辉光 + 向上飘散的颗粒
func _draw_cloud(c: Vector2, r: float, body: Color, alpha: float) -> void:
	Shading.glow(self, c, r * 1.4, Color(body, 0.35 * alpha))
	for i in 9:
		var a := TAU * i / 9.0 + _time * 0.2
		var d := r * (0.55 + 0.12 * sin(_time * 1.3 + i))
		var p := c + Vector2(cos(a) * d * 1.2, sin(a) * d * 0.8)
		Shading.sphere(self, p, r * (0.46 + 0.06 * sin(_time * 2.0 + i * 2.0)), Color(body.darkened(0.15), 0.6 * alpha), 0.3)
	Shading.sphere(self, c, r * 0.72, Color(body, 0.9 * alpha), 0.5)
	for i in 14:
		var t := fmod(_time * 0.35 + i * 0.07, 1.0)
		var a := i * 2.4 + _seed
		var p := c + Vector2(cos(a), sin(a)) * r * (0.6 + t * 0.9) + Vector2(0, -t * r * 0.6)
		Shading.glow(self, p, r * 0.08 * (1.0 - t) + 2.0, Color(body.lightened(0.5), (1.0 - t) * 0.8 * alpha))


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


## 眼睛：有光泽的眼球 + 带颜色的虹膜和竖瞳，朝向玩家（左）；精英和 Boss 是向内下斜的细长杏眼，显得凶；不画嘴
func _draw_face(c: Vector2, r: float, alpha: float) -> void:
	var eye_r := r * (0.15 if menace == 0 else 0.14)
	var gap := r * 0.3
	var look := Vector2(-eye_r * 0.3, eye_r * 0.08)
	var iris := color.lightened(0.55) if menace == 0 else Color(1.0, 0.75, 0.3)
	var squint := 1.0 if menace == 0 else 0.55
	for side in [-1, 1]:
		var e := c + Vector2(side * gap, 0)
		var open := (1.0 - _blink) * squint
		Shading.glow(self, e, eye_r * 1.9, Color(0, 0, 0, 0.35 * alpha))
		draw_set_transform(e, side * 0.28 if menace > 0 else 0.0)
		_ellipse(Vector2.ZERO, Vector2(eye_r * 1.1, eye_r * maxf(open, 0.08)), Color(0.95, 0.96, 0.92, alpha))
		if open > 0.2:
			var h := eye_r * minf(0.6, open)
			_ellipse(look, Vector2(eye_r * 0.6, h), Color(iris, alpha))
			_ellipse(look, Vector2(eye_r * 0.15, h * 0.85), Color(0.05, 0.04, 0.06, alpha))
			draw_circle(look + Vector2(-eye_r * 0.22, -h * 0.4), eye_r * 0.13, Color(1, 1, 1, 0.9 * alpha))
		var rim := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			rim.append(Vector2(cos(a) * eye_r * 1.1, sin(a) * eye_r * maxf(open, 0.08)))
		draw_polyline(rim, Color(0, 0, 0, 0.55 * alpha), 1.5, true)
		draw_set_transform(Vector2.ZERO)


func _ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)
