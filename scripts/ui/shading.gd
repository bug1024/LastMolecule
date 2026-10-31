class_name Shading
extends RefCounted
## 程序绘制的立体感：用运行时生成的径向渐变贴图，给圆和任意多边形加上「左上来光」的球面明暗、
## 高光和柔光。分子（MoleculeView）和敌人（CreatureView）共用，让画面从扁平卡通变成科学插画质感。

static var _sphere: Texture2D
static var _glow: Texture2D


## 球面明暗：亮点偏左上，边缘压暗（白色贴图，用颜色调制）
static func sphere_tex() -> Texture2D:
	if _sphere == null:
		var tex := GradientTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.36, 0.32)
		tex.fill_to = Vector2(1.02, 0.86)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
		g.colors = PackedColorArray([Color(1.25, 1.25, 1.25), Color(0.95, 0.95, 0.95), Color(0.55, 0.55, 0.6), Color(0.28, 0.28, 0.34)])
		tex.gradient = g
		_sphere = tex
	return _sphere


## 柔光：中心白、向外透明
static func glow_tex() -> Texture2D:
	if _glow == null:
		var tex := GradientTexture2D.new()
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		tex.gradient = g
		_glow = tex
	return _glow


static func _circle(c: Vector2, r: float, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## 任意多边形套上球面明暗（uv 以 center / radius 为参照）
static func shaded_polygon(ci: CanvasItem, pts: PackedVector2Array, center: Vector2, radius: float, col: Color) -> void:
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(Vector2(0.5, 0.5) + (p - center) / (radius * 2.0))
	ci.draw_colored_polygon(pts, col, uvs, sphere_tex())


## 立体小球：明暗 + 高光 + 右下的反光边
static func sphere(ci: CanvasItem, c: Vector2, r: float, col: Color, specular := 1.0) -> void:
	shaded_polygon(ci, _circle(c, r), c, r, col)
	if specular > 0:
		glow(ci, c + Vector2(-r * 0.36, -r * 0.4), r * 0.42, Color(1, 1, 1, 0.55 * specular * col.a))
	ci.draw_arc(c, r * 0.94, 0.15, 1.45, 12, Color(col.lightened(0.45), 0.35 * col.a), maxf(1.0, r * 0.08), true)


## 柔光斑
static func glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(glow_tex(), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


## 圆柱状的键：深色底 + 偏上的高光线
static func bond(ci: CanvasItem, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var n := (b - a).normalized().orthogonal()
	ci.draw_line(a, b, Color(col.darkened(0.55), col.a), width, true)
	ci.draw_line(a, b, Color(col, col.a * 0.9), width * 0.62, true)
	ci.draw_line(a - n * width * 0.18, b - n * width * 0.18, Color(1, 1, 1, 0.35 * col.a), maxf(1.0, width * 0.18), true)
