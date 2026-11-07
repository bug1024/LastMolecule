class_name PaintedStyle
extends StyleBox
## 控件的「实体材质」：每块面板都是现画的一块手工切割的厚板，而不是拉伸一张相框图。
## 轮廓略有手工起伏；笔触颗粒按固定比例取样，大小控件的笔触尺度一致；
## 明暗、亮边和投影都按场景同一束左上方来的光计算，所以控件和世界共用一个光源。
## 文字、图标和状态色仍是实时绘制，不烘焙进皮肤。
@export var bg_color := Color("1c2336")
@export var border_color := Color("c49a5b")
@export var draw_center := true
@export var surface_kind := -1 # 自动：0 墨 / 1 青绿 / 2 骨白 / 3 次级 / 4 只画线
@export var border_width_left := 1
@export var border_width_top := 1
@export var border_width_right := 1
@export var border_width_bottom := 1
@export var corner_radius_top_left := 3
@export var corner_radius_top_right := 3
@export var corner_radius_bottom_left := 3
@export var corner_radius_bottom_right := 3
@export var shadow_color := Color.TRANSPARENT
@export var shadow_size := 0
@export var shadow_offset := Vector2.ZERO
@export var anti_aliasing := true
@export var expand_margin_left := 0.0
@export var expand_margin_right := 0.0
@export var expand_margin_top := 0.0
@export var expand_margin_bottom := 0.0

const LIGHT := Vector2(-0.6, -0.8)                 # 和场景一致：光从左上方来
const INK_EDGE := Color(0.035, 0.04, 0.085)        # 所有实体共用的墨色外轮廓
const SURFACE := {
	0: Color(0.15, 0.17, 0.27),   # 墨：和膜世界同一组灰紫蓝
	1: Color(0.13, 0.36, 0.30),   # 青绿：主操作
	2: Color(1.0, 0.98, 0.9),     # 骨白：阅读面（贴图本身偏暖，这里不再加黄）
	3: Color(0.13, 0.15, 0.24),   # 次级
}
const GRAIN_PIXELS := 340.0     # 笔触贴图可用的边长（源像素）；屏幕 1px 对应 1 源像素

static var _texture: Texture2D
static var _grain := Rect2()


func set_border_width_all(value: int) -> void:
	border_width_left = value
	border_width_top = value
	border_width_right = value
	border_width_bottom = value


func set_corner_radius_all(value: int) -> void:
	corner_radius_top_left = value
	corner_radius_top_right = value
	corner_radius_bottom_left = value
	corner_radius_bottom_right = value


func _draw(canvas: RID, rect: Rect2) -> void:
	if rect.size.x < 3.0 or rect.size.y < 3.0 or (bg_color.a <= 0.01 and border_color.a <= 0.01):
		return
	var kind := surface_kind
	if kind < 0:
		kind = 1 if bg_color.g > bg_color.r * 1.18 and bg_color.g > bg_color.b * 0.95 else (2 if bg_color.get_luminance() > 0.45 else 3)
	var points := _silhouette(rect)
	if kind == 4:
		_draw_meter(canvas, points, rect)
		return
	if draw_center:
		_draw_shadow(canvas, points, rect)
	# 墨色外轮廓：比本体略大一圈，粗细随手工起伏自然变化
	if draw_center:
		RenderingServer.canvas_item_add_polygon(canvas, _offset_from_center(points, rect, 1.6), PackedColorArray([Color(INK_EDGE, bg_color.a)]))
		_draw_body(canvas, points, rect, kind)
	_draw_rim(canvas, points, rect, kind)


## 进度条、滑块这类细控件：只有语义色的液面 / 凹槽，没有厚度和投影。上亮下暗，光向一致
func _draw_meter(canvas: RID, points: PackedVector2Array, rect: Rect2) -> void:
	if draw_center:
		var colors := PackedColorArray()
		for p in points:
			var t := (p.y - rect.position.y) / maxf(rect.size.y, 1.0)
			colors.append(bg_color.lerp(bg_color.lightened(0.22), 1.0 - t).darkened(t * 0.25))
		RenderingServer.canvas_item_add_polygon(canvas, points, colors)
	if border_color.a > 0.0 and border_color != bg_color:
		var line := points.duplicate()
		line.append(points[0])
		RenderingServer.canvas_item_add_polyline(canvas, line, PackedColorArray([Color(border_color, border_color.a * 0.55)]), 1.0, true)


## 手工切割的轮廓：缺角 + 每隔一段有一点起伏。种子只取决于尺寸，移动时形状不抖
static func _silhouette(rect: Rect2) -> PackedVector2Array:
	var cut := minf(clampf(minf(rect.size.x, rect.size.y) * 0.2, 3.0, 9.0), minf(rect.size.x, rect.size.y) * 0.4)
	var a := rect.position
	var b := rect.end
	var corners: Array[Vector2] = [a + Vector2(cut, 0), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut), b - Vector2(0, cut),
		b - Vector2(cut, 0), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut), a + Vector2(0, cut)]
	var amp := clampf(minf(rect.size.x, rect.size.y) * 0.012, 0.3, 1.1)
	var seed_value := int(rect.size.x) * 31 + int(rect.size.y) * 17
	var out := PackedVector2Array()
	for i in corners.size():
		var from := corners[i]
		var to := corners[(i + 1) % corners.size()]
		out.append(from)
		var length := from.distance_to(to)
		var steps := int(length / 34.0)
		if steps < 2:
			continue
		var normal := (to - from).normalized().orthogonal()
		for s in range(1, steps):
			var wave := sin(float(seed_value + i * 7 + s) * 12.9898) * 43758.5453
			out.append(from.lerp(to, float(s) / steps) + normal * (wave - floorf(wave) - 0.5) * 2.0 * amp)
	return out


static func _offset_from_center(points: PackedVector2Array, rect: Rect2, amount: float) -> PackedVector2Array:
	var center := rect.get_center()
	var half := rect.size * 0.5
	var out := PackedVector2Array()
	for p in points:
		var d := p - center
		out.append(p + Vector2(amount * signf(d.x) * minf(1.0, absf(d.x) / maxf(half.x, 1.0)),
			amount * signf(d.y) * minf(1.0, absf(d.y) / maxf(half.y, 1.0))))
	return out


## 投影落在右下方，只有几层很淡的偏移，让板子贴着场景而不是浮在上面
func _draw_shadow(canvas: RID, points: PackedVector2Array, rect: Rect2) -> void:
	var lift := clampf(minf(rect.size.x, rect.size.y) * 0.05, 1.5, 5.0)
	for i in 3:
		var step := float(i + 1) * lift
		var shifted := PackedVector2Array()
		for p in points:
			shifted.append(p - LIGHT * step)
		RenderingServer.canvas_item_add_polygon(canvas, shifted, PackedColorArray([Color(0.01, 0.015, 0.04, 0.13 * bg_color.a)]))


## 本体：笔触颗粒 × 材质色 × 按光线方向的整体明暗
func _draw_body(canvas: RID, points: PackedVector2Array, rect: Rect2, kind: int) -> void:
	var base: Color = SURFACE.get(kind, SURFACE[3])
	# 调用方给的颜色（危险红、选中态等）优先；它只决定色相明度，材质由这里统一
	if kind != 2 and bg_color.s > 0.42 and bg_color.v > 0.25:
		base = Color(bg_color, 1.0)
	if kind == 1:   # 青绿再亮也是一块矿物，不是发光的塑料
		base.v = minf(base.v, 0.46)
	var alpha := clampf(bg_color.a, 0.0, 1.0)
	var center := rect.get_center()
	var reach := maxf(rect.size.length() * 0.5, 1.0)
	var colors := PackedColorArray()
	for p in points:
		var lit := (p - center).dot(LIGHT.normalized()) / reach     # 朝光 +1，背光 -1
		var shade := 1.0 + lit * (0.16 if kind == 2 else 0.34)
		colors.append(Color(base.r * shade, base.g * shade, base.b * shade, alpha))
	var texture := _grain_texture()
	if texture == null:
		RenderingServer.canvas_item_add_polygon(canvas, points, colors)
		return
	var uvs := PackedVector2Array()
	# 贴图不够大时等比放大，只改变笔触的整体尺度，绝不单向拉伸
	var fit := minf(1.0, GRAIN_PIXELS / maxf(rect.size.x, rect.size.y))
	var image_size := texture.get_size()
	for p in points:
		uvs.append((_grain.position + (p - rect.position) * fit) / image_size)
	RenderingServer.canvas_item_add_polygon(canvas, points, colors, uvs, texture.get_rid())


## 亮边与暗边：朝光的边缘亮、背光的边缘暗，形成厚度；状态色（选中、悬停）叠在亮边上
func _draw_rim(canvas: RID, points: PackedVector2Array, rect: Rect2, kind: int) -> void:
	var inner := _offset_from_center(points, rect, -1.2)
	inner.append(inner[0])
	var center := rect.get_center()
	var state := border_color.a > 0.6 and border_color.s > 0.35
	var warm := Color(1.0, 0.9, 0.68) if kind != 2 else Color(1.0, 0.98, 0.9)
	var colors := PackedColorArray()
	for p in inner:
		var facing := (p - center).normalized().dot(LIGHT.normalized())
		if state:
			colors.append(Color(border_color, 0.22 + 0.68 * maxf(facing, 0.0)))   # 状态色也顺着光：亮面明显，背光面收住，不成一整圈框
		elif facing > 0.0:
			colors.append(Color(warm, facing * (0.5 if kind == 2 else 0.3)))
		else:
			colors.append(Color(0.0, 0.0, 0.03, -facing * 0.4))
	RenderingServer.canvas_item_add_polyline(canvas, inner, colors, 1.5 if state else 1.2, true)


static func _grain_texture() -> Texture2D:
	if _texture == null and ResourceLoader.exists("res://assets/art/painted-ui.png"):
		_texture = load("res://assets/art/painted-ui.png")
		# 只用骨白格中央的干净笔触当颗粒：它接近中性，乘上材质色后不会带出别的颜色
		var size := _texture.get_size()
		_grain = Rect2(size * Vector2(0.105, 0.615), Vector2(GRAIN_PIXELS, GRAIN_PIXELS))
	return _texture
