class_name UIKit
extends RefCounted
## 界面小工具：图标、按钮、标题、颜色常量，供各页面共用，保持统一风格。

const ICON_DIR := "res://assets/icons/"

const ACCENT := Color(0.31, 0.78, 0.56)
const ACCENT_BLUE := Color(0.45, 0.75, 1.0)
const GOLD := Color(0.95, 0.8, 0.4)
const DANGER := Color(0.93, 0.42, 0.42)
const TEXT := Color(0.86, 0.9, 0.94)
const TEXT_DIM := Color(0.58, 0.64, 0.72)

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


## kind："normal" / "primary"（主操作，绿色）/ "danger"（危险操作，红色）
static func button(text: String, icon_name := "", kind := "normal", min_size := Vector2(0, 44)) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not icon_name.is_empty():
		btn.icon = icon(icon_name)
	if kind != "normal":
		var color := ACCENT if kind == "primary" else DANGER
		btn.add_theme_stylebox_override("normal", filled(color.darkened(0.45), color.darkened(0.1)))
		btn.add_theme_stylebox_override("hover", filled(color.darkened(0.3), color.lightened(0.2)))
		btn.add_theme_stylebox_override("pressed", filled(color.darkened(0.55), color))
		btn.add_theme_color_override("icon_normal_color", Color(1, 1, 1))
	return btn


static func filled(bg: Color, border: Color, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func panel_style(bg := Color(0.085, 0.105, 0.145, 0.88), border := Color(0.22, 0.29, 0.37), radius := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(14)
	return sb


static func header(text: String, size := 24, color := Color(0.93, 0.96, 0.98)) -> Label:
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
