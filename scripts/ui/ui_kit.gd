class_name UIKit
extends RefCounted
## 界面小工具：图标、按钮、标题、颜色常量，供各页面共用，保持统一风格。

const ICON_DIR := "res://assets/icons/"

# Research archive palette. Paper surfaces use ink; solid actions use ivory.
const PAPER := Color("eadbc0")
const PAPER_LIGHT := Color("f4e9d3")
const PAPER_DARK := Color("d5c3a2")
const INK := Color("302d27")
const TEAL := Color("245951")
const BRASS := Color("95713d")
const ACCENT := TEAL
const ACCENT_BLUE := Color("3c626c")
const GOLD := Color("87602c")
const DANGER := Color("a34235")
const TEXT := INK
const TEXT_DIM := Color("5e5341")   # 次要文字：在米色纸上仍要读得清（对比度约 5:1）

# Keep legacy callers legible on paper while preserving their semantic hue.
static func ink(color: Color) -> Color:
	if color.get_luminance() > 0.42:
		var toned := color.darkened(0.55)
		return Color(toned, color.a)
	return color

static var _icons := {}
static var _art := {}


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
		var c := btn.size * 0.5
		var r := minf(btn.size.x, btn.size.y) * 0.5 - 1.0
		btn.draw_circle(c, r, Color(accent, 0.24 if hover else 0.06))
		btn.draw_arc(c, r, 0, TAU, 40, Color(accent, 0.9) if hover else Color(0.6, 0.68, 0.76, 0.35), 1.5, true)
		var k := r * 0.36
		var ink := TEAL if hover else TEXT_DIM
		btn.draw_line(c + Vector2(-k, -k), c + Vector2(k, k), ink, 2.0, true)
		btn.draw_line(c + Vector2(-k, k), c + Vector2(k, -k), ink, 2.0, true))


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
		btn.add_theme_stylebox_override("normal", action_style(color))
		btn.add_theme_stylebox_override("hover", action_style(color.lightened(0.1)))
		btn.add_theme_stylebox_override("pressed", action_style(color.darkened(0.15)))
		for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color"]:
			btn.add_theme_color_override(state_name, PAPER_LIGHT)
	return btn


static func filled(bg: Color, border: Color, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
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


static func panel_style(bg := PAPER, border := Color(BRASS, 0.6), radius := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER if bg.get_luminance() < 0.08 else bg
	sb.border_color = Color(ink(border), maxf(border.a, 0.45))
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(mini(radius, 4))
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0.22, 0.13, 0.05, 0.22)   # 纸叠在纸上：一层暖色投影把面板托起来
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func header(text: String, size := 24, color := INK) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"HeaderLabel"
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink(color))
	return l


static func label(text: String, color := TEXT, size := 16, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ink(color))
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


static func action_style(color: Color) -> StyleBoxFlat:
	var sb := filled(PAPER, BRASS, 4)
	sb.bg_color = color
	return sb


## Fine engraved rules and corner brackets on the research folio.
static func folio(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_style_box(panel_style(), rect)
	paper(ci, rect.grow(-2), 0.7)
	var inner := rect.grow(-7)
	ci.draw_rect(inner, Color(BRASS, 0.35), false, 1.0)
	for corner in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		ci.draw_circle(corner, 2, BRASS)


static func art(name: String) -> Texture2D:
	if not _art.has(name):
		var path := "res://assets/art/" + name + ".png"
		_art[name] = load(path) if ResourceLoader.exists(path) else null
	return _art[name]


static func paper(ci: CanvasItem, rect: Rect2, opacity := 1.0) -> void:
	var tex := art("archive-desk")
	if tex:
		ci.draw_texture_rect_region(tex, rect, Rect2(Vector2(160, 100), Vector2(1320, 710)), Color(1, 1, 1, opacity))


static func atlas(ci: CanvasItem, name: String, cell: int, rect: Rect2, tint := Color.WHITE) -> bool:
	var tex := art(name)
	if not tex:
		return false
	var cell_size := tex.get_size() / Vector2(3, 2)
	ci.draw_texture_rect_region(tex, rect, Rect2(Vector2(cell % 3, cell / 3) * cell_size, cell_size), tint)
	return true


## Physical paper grain is shared by scene-owned sheets and generated dialogs.
static func decorate_panel(panel: PanelContainer) -> void:
	if panel.has_meta("archive_paper"):
		return
	panel.set_meta("archive_paper", true)
	var decor := Control.new()
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor.clip_contents = true
	decor.draw.connect(func() -> void:
		paper(decor, Rect2(Vector2.ZERO, decor.size), 0.38 if decor.size.y < 150 else 0.75)
		if decor.size.y >= 150:
			decor.draw_rect(Rect2(Vector2(4, 4), decor.size - Vector2(8, 8)), Color(BRASS, 0.4), false, 1))
	decor.resized.connect(decor.queue_redraw)
	panel.add_child(decor)
	panel.move_child(decor, 0)
