class_name PaintedStyle
extends StyleBox
## Nine-slice painted surfaces retain real typography, states and container margins.
@export var bg_color := Color("1c2336")
@export var border_color := Color("c49a5b")
@export var draw_center := true
@export var surface_kind := -1 # automatic: ink, jade, bone, secondary
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
static var _texture: Texture2D
static var _regions := {}


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
	if _texture == null and ResourceLoader.exists("res://assets/art/painted-ui.png"):
		_texture = load("res://assets/art/painted-ui.png")
	var kind := surface_kind
	if kind < 0:
		kind = 1 if bg_color.g > bg_color.r * 1.18 and bg_color.g > bg_color.b * 0.95 else (2 if bg_color.get_luminance() > 0.45 else 3)
	if _texture and kind != 4:
		_draw_skin(canvas, rect, kind)
	else:
		var points := _contour(rect, 9)
		if draw_center:
			RenderingServer.canvas_item_add_polygon(canvas, points, PackedColorArray([bg_color]))
		points.append(points[0])
		RenderingServer.canvas_item_add_polyline(canvas, points, PackedColorArray([border_color]), 2.0, true)


func _draw_skin(canvas: RID, rect: Rect2, kind: int) -> void:
	if not _regions.has(kind):
		var tile_size := _texture.get_size() * 0.5
		var tile := Rect2i(Vector2(kind % 2, kind / 2) * tile_size, tile_size)
		var used := _texture.get_image().get_region(tile).get_used_rect()
		_regions[kind] = Rect2(tile.position + used.position, used.size)
	var source: Rect2 = _regions[kind]
	var sx := source.size.x * 0.17
	var sy := source.size.y * 0.17
	var dx := minf(20.0, rect.size.x * 0.18)
	var dy := minf(20.0, rect.size.y * 0.28)
	var xs := [0.0, sx, source.size.x - sx, source.size.x]
	var ys := [0.0, sy, source.size.y - sy, source.size.y]
	var xd := [0.0, dx, rect.size.x - dx, rect.size.x]
	var yd := [0.0, dy, rect.size.y - dy, rect.size.y]
	var level := clampf(bg_color.v * 1.8 + 0.4, 0.75, 1.10)
	var tint := Color(level, level, level)
	tint.a = bg_color.a if draw_center else 1.0
	for row in 3:
		for col in 3:
			if row == 1 and col == 1 and not draw_center:
				continue
			var src := Rect2(source.position + Vector2(xs[col], ys[row]), Vector2(xs[col + 1] - xs[col], ys[row + 1] - ys[row]))
			var dst := Rect2(rect.position + Vector2(xd[col], yd[row]), Vector2(xd[col + 1] - xd[col], yd[row + 1] - yd[row]))
			RenderingServer.canvas_item_add_texture_rect_region(canvas, dst, _texture.get_rid(), src, tint)
	# State/selection colors remain live, expressed as a restrained inner ink line.
	if border_color.a > 0.6 and border_color.s > 0.35:
		var edge := _contour(rect.grow(-3), 8)
		edge.append(edge[0])
		RenderingServer.canvas_item_add_polyline(canvas, edge, PackedColorArray([Color(border_color, 0.65)]), 1.0, true)


static func _contour(rect: Rect2, cut := 9.0) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.25)
	return PackedVector2Array([a + Vector2(c, 0), Vector2(b.x - c, a.y),
		Vector2(b.x, a.y + c), b - Vector2(0, c), b - Vector2(c, 0),
		Vector2(a.x + c, b.y), Vector2(a.x, b.y - c), a + Vector2(0, c)])
