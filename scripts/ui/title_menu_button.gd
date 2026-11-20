class_name TitleMenuButton
extends Button
## 标题菜单项。主项（开始 / 继续）是一块玉绿厚板；其余是没有底板的文字行，
## 选中时左侧长出一段金色刻度、文字右移、一道淡金从左向右晕开。
## 鼠标悬停即取得焦点，所以键盘和鼠标共用同一个「当前项」。

const REST_MARGIN := 22.0

var primary := false
var _t := 0.0
var _plate: Control
var _box := StyleBoxEmpty.new()


func _init(label: String, icon_texture: Texture2D, is_primary := false) -> void:
	primary = is_primary
	text = label
	icon = icon_texture
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(340, 58 if primary else 44)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 23 if primary else 19)
	add_theme_constant_override("icon_max_width", 22 if primary else 18)
	add_theme_constant_override("h_separation", 14)
	_box.content_margin_left = REST_MARGIN
	_box.content_margin_right = 20
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state_name, _box)
	var rest := Color(0.97, 0.95, 0.86) if primary else Color(0.8, 0.79, 0.74)
	var lit := Color(1.0, 0.98, 0.9)
	add_theme_color_override("font_color", rest)
	for state_name in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(state_name, lit)
	add_theme_color_override("icon_normal_color", UIKit.GOLD.lightened(0.25) if primary else Color(0.62, 0.66, 0.7))
	for state_name in ["icon_hover_color", "icon_focus_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		add_theme_color_override(state_name, UIKit.GOLD.lightened(0.2))
	_plate = Control.new()
	_plate.show_behind_parent = true
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate.draw.connect(_draw_plate)
	add_child(_plate)
	mouse_entered.connect(grab_focus)
	focus_entered.connect(func() -> void: GameAudio.sfx("hover"))


func _process(delta: float) -> void:
	var target := 1.0 if has_focus() or is_hovered() else 0.0
	if not is_equal_approx(_t, target):
		_t = target if GameSettings.reduce_motion else move_toward(_t, target, delta * 7.0)
		_box.content_margin_left = REST_MARGIN + (4.0 if primary else 10.0) * _eased()
		_plate.queue_redraw()
	elif primary and is_visible_in_tree():
		_plate.queue_redraw()   # 主项的呼吸光


func _eased() -> float:
	return 1.0 - pow(1.0 - _t, 3.0)


func _draw_plate() -> void:
	var w := size.x
	var h := size.y
	var e := _eased()
	if primary:
		var skin := PaintedStyle.new()
		skin.surface_kind = 1
		skin.bg_color = Color(0.13, 0.36, 0.3, 0.97)
		skin.border_color = Color(UIKit.GOLD.lightened(0.15 * e), 0.7 + 0.3 * e)
		skin.draw(_plate.get_canvas_item(), Rect2(0, 0, w, h))
		var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 700.0)
		var sheen := Color(1.0, 0.95, 0.8, 0.05 + 0.05 * breath + 0.1 * e)
		_plate.draw_polygon(PackedVector2Array([Vector2(4, 4), Vector2(w * 0.8, 4), Vector2(w * 0.8, h - 4), Vector2(4, h - 4)]),
			PackedColorArray([sheen, Color(sheen, 0.0), Color(sheen, 0.0), sheen]))
		# 右侧的箭头：选中时向右探出
		var tip := Vector2(w - 24.0 + 5.0 * e, h * 0.5)
		var arrow := Color(UIKit.GOLD.lightened(0.25), 0.55 + 0.45 * e)
		_plate.draw_polyline(PackedVector2Array([tip + Vector2(-7, -7), tip, tip + Vector2(-7, 7)]), arrow, 2.0, true)
		return
	var rule := Color(UIKit.PAPER, 0.13)
	_plate.draw_polyline_colors(PackedVector2Array([Vector2(0, h - 0.5), Vector2(w * 0.85, h - 0.5)]),
		PackedColorArray([rule, Color(rule, 0.0)]), 1.0)
	if e <= 0.0:
		return
	var wash := Color(UIKit.GOLD, 0.2 * e)
	var reach := w * (0.5 + 0.5 * e)
	_plate.draw_polygon(PackedVector2Array([Vector2(0, 3), Vector2(reach, 3), Vector2(reach, h - 4), Vector2(0, h - 4)]),
		PackedColorArray([wash, Color(wash, 0.0), Color(wash, 0.0), wash]))
	var tick := (h - 14.0) * e
	_plate.draw_rect(Rect2(0, (h - tick) * 0.5, 3, tick), UIKit.GOLD.lightened(0.15))
