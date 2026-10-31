class_name MapNode
extends Control
## 研发地图上的一个节点：六边形徽章（呼应分子主题）+ 中间图标 + 下方名称。
## 状态：reachable 可前往（亮色、脉动光圈、可点）/ visited 已走过（暗色实心）/ current 当前位置 / locked 未到达（暗淡）。

signal pressed()

const HEX_R := 24.0
const BOSS_R := 32.0

var type := "fight"
var color := Color.WHITE
var state := "locked"
var label_text := ""
var _icon: Texture2D
var _hover := false
var _time := 0.0


func setup(node_type: String, node_color: Color, node_state: String, text: String, tip: String) -> void:
	type = node_type
	color = node_color
	state = node_state
	label_text = text
	tooltip_text = tip
	_icon = UIKit.icon("node_" + node_type)
	custom_minimum_size = Vector2(150, 96) if type == "boss" else Vector2(104, 78)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	if state == "reachable":
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			_hover = true
			GameAudio.sfx("hover"))
		mouse_exited.connect(func() -> void: _hover = false)
		gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				GameAudio.sfx("node")
				pressed.emit())


## 六边形中心（画布连线用）
func hex_center() -> Vector2:
	return position + Vector2(size.x * 0.5, radius() + 4)


func radius() -> float:
	return BOSS_R if type == "boss" else HEX_R


func _process(delta: float) -> void:
	if state == "reachable" or state == "current":
		_time += delta
		queue_redraw()


func _draw() -> void:
	var r := radius() * (1.08 if _hover else 1.0)
	var c := Vector2(size.x * 0.5, radius() + 4)
	var pts := PackedVector2Array()
	for i in 7:
		var a := PI / 6 + i * TAU / 6
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var fill: Color
	var border: Color
	var icon_tint: Color
	match state:
		"reachable":
			var pulse := 0.5 + 0.5 * sin(_time * 4.0)
			for k in 3:
				draw_circle(c, r + 6 + k * 4 + pulse * 3, Color(color, 0.10 - k * 0.025))
			fill = color.lerp(UIKit.PAPER, 0.3)
			border = UIKit.TEAL
			icon_tint = UIKit.INK
		"current", "visited":
			fill = color.lerp(UIKit.PAPER, 0.62)
			border = color.lerp(Color.WHITE, 0.2) if state == "current" else Color(color, 0.7)
			icon_tint = UIKit.INK
		_:
			fill = color.lerp(UIKit.PAPER, 0.85)
			border = Color(color, 0.35)
			icon_tint = Color(color.lightened(0.2), 0.55)
	draw_colored_polygon(pts, fill)
	draw_polyline(pts, border, 3.0 if state == "reachable" or state == "current" else 1.5, true)
	if _icon:
		var s := r * 1.0
		draw_texture_rect(_icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, icon_tint)
	if state == "visited":
		# 已完成：右下角小勾
		var tick := c + Vector2(r * 0.62, r * 0.55)
		draw_circle(tick, 7, UIKit.PAPER)
		draw_polyline(PackedVector2Array([tick + Vector2(-3.5, 0), tick + Vector2(-1, 3), tick + Vector2(4, -3)]), UIKit.ACCENT, 2.0, true)
	var font := get_theme_default_font()
	var fs := 14 if type == "boss" else 13
	var text_color: Color = UIKit.INK if state != "locked" else UIKit.TEXT_DIM
	var lines := label_text.split("\n")
	for i in lines.size():
		var y := c.y + r + 8 + fs + i * (fs + 2)
		var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(c.x - w * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 0, UIKit.PAPER)
		draw_string(font, Vector2(c.x - w * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
