class_name PaintedArt
extends RefCounted
## Live ink-and-bone frames; no text or changing state is baked into artwork.
const INK := Color("1c2336")
const PAPER := Color("ddd0ac")
const JADE := Color("397b68")
const GOLD := Color("c49a5b")


static func contour(rect: Rect2, cut := 9.0) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.25)
	return PackedVector2Array([a + Vector2(c, 0), Vector2(b.x - c * 0.8, a.y + 1),
		Vector2(b.x, a.y + c), b - Vector2(1, c), b - Vector2(c, 0),
		Vector2(a.x + c * 0.7, b.y - 1), Vector2(a.x, b.y - c), a + Vector2(1, c)])


static func frame(ci: CanvasItem, rect: Rect2, fill: Color, edge := GOLD, width := 2.0) -> void:
	var skin := PaintedStyle.new()
	skin.bg_color = fill
	skin.border_color = edge
	skin.draw_center = fill.a > 0.01
	skin.draw(ci.get_canvas_item(), rect)


static func atlas_region(name: String, cell: int, columns := 3, rows := 2) -> Rect2:
	var texture := UIKit.art(name)
	if texture == null:
		return Rect2()
	var cell_size := texture.get_size() / Vector2(columns, rows)
	return Rect2(Vector2(cell % columns, cell / columns) * cell_size, cell_size)


static var _sprite_regions := {}


static func sprite(ci: CanvasItem, name: String, cell: int, area: Rect2, tint := Color.WHITE, bottom_align := false) -> bool:
	var texture := UIKit.art(name)
	if texture == null:
		return false
	var key := name + str(cell)
	if not _sprite_regions.has(key):
		var tile := Rect2i(atlas_region(name, cell))
		if name == "painted-enemies":
			# Alpha-separated exported subjects have deliberately unequal gutter widths.
			var cuts := [0.0, 0.3125, 0.6628, 1.0] if cell < 3 else [0.0, 0.36, 0.65, 1.0]
			var y := 0 if cell < 3 else roundi(texture.get_height() * 0.5078)
			var end_y := roundi(texture.get_height() * 0.5078) if cell < 3 else texture.get_height()
			var left := roundi(texture.get_width() * float(cuts[cell % 3]))
			var right := roundi(texture.get_width() * float(cuts[cell % 3 + 1]))
			tile = Rect2i(left, y, right - left, end_y - y)
		var image := texture.get_image().get_region(tile)
		var used := image.get_used_rect()
		_sprite_regions[key] = Rect2(tile.position + used.position, used.size)
	var source: Rect2 = _sprite_regions[key]
	if not source.has_area():
		return false
	var factor := minf(area.size.x / source.size.x, area.size.y / source.size.y)
	var extent := source.size * factor
	var origin := area.get_center() - extent * 0.5
	if bottom_align:
		origin.y = area.end.y - extent.y
	ci.draw_texture_rect_region(texture, Rect2(origin, extent), source, tint)
	return true


static func world(ci: CanvasItem, area: Rect2, shade := 0.0) -> void:
	var texture := UIKit.art("painted-world")
	ci.draw_rect(area, INK)
	if texture:
		var factor := maxf(area.size.x / texture.get_width(), area.size.y / texture.get_height())
		var visible := area.size / factor
		var source := Rect2((texture.get_size() - visible) * 0.5, visible)
		ci.draw_texture_rect_region(texture, area, source)
	if shade > 0:
		ci.draw_rect(area, Color(0.06, 0.08, 0.14, shade))
