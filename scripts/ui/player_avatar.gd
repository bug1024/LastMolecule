class_name PlayerAvatar
extends Control
## 玩家形象：研发团队的实验器材，随团队等级进化（form 1–5）：
##   1 小烧瓶 → 2 锥形瓶 → 3 反应装置（铁架台 + 侧管）→ 4 自动化工作站（机械臂）→ 5 智能实验室（光环 + 环绕分子）
## 液面高度 = 生命比例，颜色随生命从绿到红；带气泡、液面波动、受击闪白与升级闪光。
## 脚下是绿色光圈，与敌人的红色调区分。

var ratio := 1.0
var flash := 0.0
var shield := 0
var form := 1:
	set(value):
		form = clampi(value, 1, 5)
		queue_redraw()
var glow_burst := 0.0     # 升级闪光 0..1
var _time := 0.0
var _bubbles: Array = []

const GREEN := Color(0.35, 0.95, 0.6)


func _ready() -> void:
	custom_minimum_size = Vector2(200, 240)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 12:
		_bubbles.append(Vector3(randf_range(-0.6, 0.6), randf(), randf_range(0.2, 0.5)))


func hit() -> void:
	flash = 1.0


func level_up() -> void:
	glow_burst = 1.0


func _process(delta: float) -> void:
	_time += delta
	flash = maxf(0.0, flash - delta * 4.0)
	glow_burst = maxf(0.0, glow_burst - delta * 0.6)
	for i in _bubbles.size():
		var b: Vector3 = _bubbles[i]
		b.y -= delta * b.z
		if b.y < 0:
			b = Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(0.2, 0.5))
		_bubbles[i] = b
	queue_redraw()


func _liquid_color() -> Color:
	return Color(0.93, 0.35, 0.35).lerp(Color(0.95, 0.8, 0.35), clampf(ratio * 2.0, 0.0, 1.0)) \
		.lerp(Color(0.3, 0.9, 0.6), clampf(ratio * 2.0 - 1.0, 0.0, 1.0))


func _draw() -> void:
	var grow := 0.82 + form * 0.06
	var base := Vector2(size.x * 0.5, size.y * 0.88)
	var r := minf(size.x, size.y) * 0.3 * grow
	var liquid := _liquid_color()
	var glass := Color(0.78, 0.95, 1.0, 0.9).lerp(Color.WHITE, flash)
	if form >= 5:
		glass = glass.lerp(Color(1.0, 0.88, 0.5), 0.35)
	# 脚下绿色光圈（与敌人区分）
	var pulse := 0.5 + 0.5 * sin(_time * 2.0)
	_ellipse(base, Vector2(r * 1.25, r * 0.22), Color(GREEN, 0.18 + 0.08 * pulse))
	_ellipse_line(base, Vector2(r * 1.25, r * 0.22), Color(GREEN, 0.6), 2.0)
	if glow_burst > 0:
		for i in 6:
			draw_circle(base + Vector2(0, -r), r * (1.2 + glow_burst + i * 0.15), Color(1.0, 0.9, 0.5, 0.06 * glow_burst))
	if form >= 5:
		_draw_halo(base, r)
	if form >= 3:
		_draw_stand(base, r)
	if form >= 4:
		_draw_arms(base, r)
	var body := _body_polygon(base, r)
	for i in 5:
		draw_circle(base + Vector2(0, -r), r * (1.5 - i * 0.1), Color(liquid, 0.025))
	if shield > 0:
		var sp := 0.5 + 0.5 * sin(_time * 3.0)
		draw_arc(base + Vector2(0, -r * 1.1), r * 1.55, 0, TAU, 64, Color(0.45, 0.75, 1.0, 0.35 + 0.25 * sp), 5.0, true)
	_draw_liquid(body, base, r, liquid)
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, glass, 4.0, true)
	if form >= 3:
		_draw_side_tube(base, r, glass, liquid)
	_draw_face(base + Vector2(0, -r * 0.62), r)


## 瓶身轮廓：1 圆底烧瓶，2+ 锥形瓶（越高级越宽）
func _body_polygon(base: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var neck_w := r * 0.3
	var neck_top := base.y - r * 2.55
	if form == 1:
		var c := base + Vector2(0, -r)
		pts.append(Vector2(c.x - neck_w, neck_top))
		pts.append(Vector2(c.x - neck_w, c.y - r * 0.95))
		for i in 33:
			var a := PI * 0.6 + i * (TAU - PI * 0.2) / 32.0  # 从瓶颈左侧经瓶底绕到右侧
			pts.append(c + Vector2(cos(a), -sin(a)) * r)
		pts.append(Vector2(c.x + neck_w, c.y - r * 0.95))
		pts.append(Vector2(c.x + neck_w, neck_top))
	else:
		var half := r * (1.05 + form * 0.04)
		pts.append(Vector2(base.x - neck_w, neck_top))
		pts.append(Vector2(base.x - neck_w, base.y - r * 1.6))
		pts.append(Vector2(base.x - half, base.y - r * 0.12))
		pts.append(Vector2(base.x - half + r * 0.12, base.y))
		pts.append(Vector2(base.x + half - r * 0.12, base.y))
		pts.append(Vector2(base.x + half, base.y - r * 0.12))
		pts.append(Vector2(base.x + neck_w, base.y - r * 1.6))
		pts.append(Vector2(base.x + neck_w, neck_top))
	return pts


func _draw_liquid(body: PackedVector2Array, base: Vector2, r: float, liquid: Color) -> void:
	var bottom := base.y
	var top := base.y - r * (2.0 if form == 1 else 1.6)
	var level := bottom - (bottom - top) * clampf(ratio, 0.04, 1.0)
	var wave := PackedVector2Array()
	var left := base.x - r * 2.0
	var right := base.x + r * 2.0
	for i in 21:
		var x := left + (right - left) * i / 20.0
		wave.append(Vector2(x, level + 4.0 * sin(x * 0.07 + _time * 3.0)))
	wave.append(Vector2(right, bottom + 20))
	wave.append(Vector2(left, bottom + 20))
	var inner := PackedVector2Array()
	var center := base + Vector2(0, -r)
	for p in body:
		inner.append(p + (center - p).normalized() * r * 0.04)
	for poly in Geometry2D.intersect_polygons(inner, wave):
		if Geometry2D.is_polygon_clockwise(poly) or Geometry2D.triangulate_polygon(poly).is_empty():
			continue
		draw_colored_polygon(poly, Color(liquid.lerp(Color.WHITE, flash * 0.6), 0.9))
	for b in _bubbles:
		var bp := Vector2(base.x + b.x * r * 0.8, bottom - b.y * (bottom - level))
		if bp.y > level + 5 and Geometry2D.is_point_in_polygon(bp, inner):
			draw_circle(bp, 2.5 + b.z * 4.0, Color(1, 1, 1, 0.35))


func _draw_face(c: Vector2, r: float) -> void:
	var ink := Color(0.06, 0.08, 0.1)
	for side in [-1, 1]:
		var e := c + Vector2(side * r * 0.24, 0)
		draw_circle(e, r * 0.09, ink)
		draw_circle(e + Vector2(r * 0.03, -r * 0.03), r * 0.035, Color.WHITE)
		if form >= 4:
			draw_arc(e, r * 0.14, PI * 1.1, PI * 1.9, 8, Color(0.4, 0.9, 1.0, 0.8), 2.0, true)
	if ratio > 0.4:
		draw_arc(c + Vector2(0, r * 0.1), r * 0.14, PI * 0.15, PI * 0.85, 12, ink, 3.0, true)
	else:
		draw_arc(c + Vector2(0, r * 0.28), r * 0.14, PI * 1.15, PI * 1.85, 12, ink, 3.0, true)
	draw_circle(c + Vector2(-r * 0.4, r * 0.08), r * 0.06, Color(1.0, 0.5, 0.55, 0.45))
	draw_circle(c + Vector2(r * 0.4, r * 0.08), r * 0.06, Color(1.0, 0.5, 0.55, 0.45))


## Lv3+：铁架台
func _draw_stand(base: Vector2, r: float) -> void:
	var metal := Color(0.55, 0.62, 0.7)
	draw_line(base + Vector2(r * 1.55, 0), base + Vector2(r * 1.55, -r * 2.8), metal, 5.0, true)
	draw_line(base + Vector2(r * 1.1, 0), base + Vector2(r * 2.0, 0), metal, 7.0, true)
	draw_line(base + Vector2(r * 0.3, -r * 2.2), base + Vector2(r * 1.55, -r * 2.2), metal, 4.0, true)


## Lv3+：侧管与小烧杯
func _draw_side_tube(base: Vector2, r: float, glass: Color, liquid: Color) -> void:
	var from := base + Vector2(-r * 0.3, -r * 2.0)
	var mid := base + Vector2(-r * 1.3, -r * 1.7)
	var to := base + Vector2(-r * 1.5, -r * 0.6)
	draw_polyline(PackedVector2Array([from, mid, to]), glass, 3.0, true)
	var cup := Rect2(base + Vector2(-r * 1.85, -r * 0.6), Vector2(r * 0.7, r * 0.6))
	draw_rect(Rect2(cup.position + Vector2(0, cup.size.y * 0.4), Vector2(cup.size.x, cup.size.y * 0.6)), Color(liquid, 0.8))
	draw_rect(cup, glass, false, 3.0)
	var t := fmod(_time * 0.8, 1.0)
	draw_circle(from.lerp(mid, t) if t < 0.5 else mid.lerp(to, (t - 0.5) * 2.0), 3.0, liquid.lightened(0.3))


## Lv4+：两只机械臂
func _draw_arms(base: Vector2, r: float) -> void:
	var metal := Color(0.7, 0.78, 0.86)
	for side in [-1, 1]:
		var shoulder := base + Vector2(side * r * 1.15, -r * 0.4)
		var swing := 0.25 * sin(_time * 2.0 + side)
		var elbow := shoulder + Vector2(side * r * 0.5, -r * 0.7).rotated(swing * side)
		var hand := elbow + Vector2(-side * r * 0.25, -r * 0.6).rotated(-swing * side)
		draw_line(shoulder, elbow, metal, 7.0, true)
		draw_line(elbow, hand, metal, 6.0, true)
		draw_circle(shoulder, 7.0, metal.darkened(0.3))
		draw_circle(elbow, 6.0, metal.darkened(0.3))
		draw_line(hand, hand + Vector2(-side * 8, -8), Color(0.4, 0.9, 1.0), 3.0, true)
		draw_line(hand, hand + Vector2(side * 4, -12), Color(0.4, 0.9, 1.0), 3.0, true)


## Lv5：头顶光环 + 环绕分子
func _draw_halo(base: Vector2, r: float) -> void:
	var c := base + Vector2(0, -r * 2.9)
	_ellipse_line(c, Vector2(r * 0.7, r * 0.18), Color(1.0, 0.85, 0.4, 0.9), 4.0)
	for i in 4:
		var a := _time * 1.2 + i * TAU / 4.0
		var p := base + Vector2(0, -r * 1.2) + Vector2(cos(a) * r * 1.8, sin(a) * r * 0.5)
		draw_circle(p, 6.0, [Color(0.45, 0.75, 1.0), Color(0.6, 0.48, 0.95), Color(0.95, 0.75, 0.35), GREEN][i])
		draw_circle(p, 10.0, Color(1, 1, 1, 0.1))


func _ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)


func _ellipse_line(center: Vector2, radii: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(pts, col, width, true)
