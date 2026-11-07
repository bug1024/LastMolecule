class_name UIKit
extends RefCounted
## 界面小工具：图标、按钮、标题、颜色常量，供各页面共用，保持统一风格。

const ICON_DIR := "res://assets/icons/"

const ACCENT := Color("69aa87")
const ACCENT_BLUE := Color("70adce")
const GOLD := Color("e4ae53")
const DANGER := Color("d96a52")
const TEXT := Color("e8dcbd")
const TEXT_DIM := Color("acaaa6")
const INK := Color("1c2336")
const PAPER := Color("ddd0ac")
const BIO_VIOLET := Color("785a85")

static var _icons := {}


static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var path := ICON_DIR + icon_name + ".svg"
		_icons[icon_name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[icon_name]


static func icon_rect(icon_name: String, size: float, color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = icon(icon_name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(size, size)
	rect.self_modulate = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## 弹窗右上角的圆形「✕」关闭按钮：平时是淡淡的圆圈，悬停时染上面板的强调色（取代原来的「返回」文字按钮）
static func close_button(accent: Color = ACCENT) -> Button:
	var btn := Button.new()
	style_close_button(btn, accent)
	return btn


static func style_close_button(btn: Button, accent: Color = ACCENT) -> void:
	btn.text = ""
	btn.icon = null
	btn.custom_minimum_size = Vector2(38, 38)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.tooltip_text = TranslationServer.translate("ui.back") + "（Esc）"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state_name, empty)
	btn.mouse_entered.connect(btn.queue_redraw)
	btn.mouse_exited.connect(btn.queue_redraw)
	btn.draw.connect(func() -> void:
		var hover := btn.is_hovered()
		var skin := PaintedStyle.new()
		skin.surface_kind = 3
		skin.bg_color = INK
		skin.border_color = GOLD if hover else Color(GOLD, 0.4)
		skin.draw(btn.get_canvas_item(), Rect2(Vector2.ZERO, btn.size))
		var c := btn.size * 0.5
		var ink := PAPER if hover else TEXT_DIM
		btn.draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), ink, 2.0, true)
		btn.draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), ink, 2.0, true))



## kind："normal" / "primary"（主操作，绿色）/ "danger"（危险操作，红色）
static func button(text: String, icon_name := "", kind := "normal", min_size := Vector2(0, 44)) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not icon_name.is_empty():
		btn.icon = icon(icon_name)
	if kind == "normal":
		btn.add_theme_stylebox_override("normal", filled(INK.lightened(0.07), Color("7b7060"), 4))
		btn.add_theme_stylebox_override("hover", filled(INK.lightened(0.15), GOLD, 4))
	if kind != "normal":
		var color := ACCENT if kind == "primary" else DANGER
		btn.add_theme_stylebox_override("normal", filled(color.darkened(0.45), color.darkened(0.1)))
		btn.add_theme_stylebox_override("hover", filled(color.darkened(0.3), color.lightened(0.2)))
		btn.add_theme_stylebox_override("pressed", filled(color.darkened(0.55), color))
		btn.add_theme_color_override("icon_normal_color", Color(1, 1, 1))
	return btn


static func filled(bg: Color, border: Color, radius := 8) -> PaintedStyle:
	var sb := PaintedStyle.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(mini(radius, 4))
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func panel_style(bg := Color(0.11, 0.14, 0.21, 0.97), border := Color(0.49, 0.43, 0.36), radius := 4) -> PaintedStyle:
	var sb := PaintedStyle.new()
	sb.surface_kind = 3
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(mini(radius, 4))
	sb.set_content_margin_all(16)
	sb.content_margin_bottom = 22
	return sb


static func header(text: String, size := 24, color := TEXT) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"HeaderLabel"
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func label(text: String, color := TEXT, size := 16, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func rich(bbcode: String, size := 16) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


# Scientific specimen and experiment art share the original dark-lab palette.
static var _art := {}


static func art(name: String) -> Texture2D:
	if not _art.has(name):
		var path := "res://assets/art/" + name + ".png"
		_art[name] = load(path) if ResourceLoader.exists(path) else null
	return _art[name]


static func atlas(ci: CanvasItem, name: String, cell: int, rect: Rect2, tint := Color.WHITE) -> bool:
	if name == "painted-enemies":
		return PaintedArt.sprite(ci, name, cell, rect, tint)
	var tex := art(name)
	if not tex:
		return false
	var cell_size := tex.get_size() / Vector2(3, 2)
	ci.draw_texture_rect_region(tex, rect, Rect2(Vector2(cell % 3, cell / 3) * cell_size, cell_size), tint)
	return true


## Meters are data, not buttons: preserve exact semantic fill colors.
static func meter_style(bg: Color, border: Color, radius := 3) -> PaintedStyle:
	var skin := filled(bg, border, radius)
	skin.surface_kind = 4
	skin.set_content_margin_all(0)
	return skin


## 嵌入感：内侧墨线 + 顶部和左侧落下的阴影（光从左上来，窗口边缘挡住了光）。area 是窗口自身的范围
static func inset(ci: CanvasItem, area: Rect2, depth: float) -> void:
	var shade := Color(0.03, 0.03, 0.07, 0.55)
	ci.draw_polygon(PackedVector2Array([area.position, Vector2(area.end.x, area.position.y),
		Vector2(area.end.x, area.position.y + depth), area.position + Vector2(0, depth)]),
		PackedColorArray([shade, shade, Color(shade, 0.0), Color(shade, 0.0)]))
	ci.draw_polygon(PackedVector2Array([area.position, area.position + Vector2(depth, 0),
		Vector2(area.position.x + depth, area.end.y), Vector2(area.position.x, area.end.y)]),
		PackedColorArray([shade, Color(shade, 0.0), Color(shade, 0.0), shade]))
	ci.draw_rect(area.grow(-0.5), Color(0.04, 0.04, 0.09, 0.85), false, maxf(1.0, depth * 0.17), true)


## Actor identity is a stable reading plate, independent of the moving body.
static func identity_plate(label_node: Label) -> void:
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.show_behind_parent = true
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var skin := PaintedStyle.new()
	skin.surface_kind = 2
	skin.bg_color = PAPER
	plate.add_theme_stylebox_override("panel",skin)
	label_node.add_child(plate)
	label_node.add_theme_color_override("font_color",INK)
	label_node.add_theme_constant_override("outline_size",0)
