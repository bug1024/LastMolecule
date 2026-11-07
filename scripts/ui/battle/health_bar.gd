class_name HealthBar
extends Control
## 血条：生命条（数值平滑过渡，掉血时留下白色残影）+ 左侧蓝色护盾徽章。
## 玩家的血条是绿色并带爱心，敌人是红色，一眼区分。

var max_value := 100
var value := 100
var block := 0
var is_player := false
var _shown := 100.0
var _trail := 100.0
var _block_pop := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(170, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(hp: int, max_hp: int, block_value: int, instant := false) -> void:
	if block_value > block:
		_block_pop = 1.0
	max_value = maxi(1, max_hp)
	value = hp
	block = block_value
	if instant:
		_shown = hp
		_trail = hp
	queue_redraw()


## 刻进材质的凹槽：墨色底，上沿内侧压暗、下沿外侧有一道受光的亮边，没有外框
func _draw_groove(rect: Rect2) -> void:
	var lip := _bar_shape(rect.grow(1.0), rect.size.x + 2.0)
	draw_colored_polygon(lip, Color(0.035, 0.04, 0.085, 0.95))
	var inside := _bar_shape(rect, rect.size.x)
	var colors := PackedColorArray()
	for p in inside:
		var t := (p.y - rect.position.y) / maxf(rect.size.y, 1.0)
		colors.append(Color(0.03, 0.035, 0.07).lerp(Color(0.1, 0.11, 0.17), t))
	draw_polygon(inside, colors)
	var c := rect.size.y * 0.3
	draw_line(Vector2(rect.position.x + c, rect.end.y + 1.5), Vector2(rect.end.x - c, rect.end.y + 1.5), Color(1.0, 0.92, 0.75, 0.22), 1.0, true)


## 两端缺角的条形；宽度变化时右端缺角跟着走
static func _bar_shape(rect: Rect2, width: float) -> PackedVector2Array:
	if width < 1.0:
		return PackedVector2Array()
	var c := minf(rect.size.y * 0.3, width * 0.45)
	var x := rect.position.x
	var y := rect.position.y
	var h := rect.size.y
	return PackedVector2Array([Vector2(x + c, y), Vector2(x + width - c, y), Vector2(x + width, y + c), Vector2(x + width, y + h - c),
		Vector2(x + width - c, y + h), Vector2(x + c, y + h), Vector2(x, y + h - c), Vector2(x, y + c)])


func _process(delta: float) -> void:
	_shown = move_toward(_shown, value, delta * maxf(30.0, absf(_shown - value) * 6.0))
	if _trail > _shown:
		_trail = move_toward(_trail, _shown, delta * 25.0)
	else:
		_trail = _shown
	_block_pop = maxf(0.0, _block_pop - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(16, 3), Vector2(size.x - 18, size.y - 6))
	_draw_groove(rect)
	var inner := rect.grow(-2.0)
	var trail_w := inner.size.x * clampf(_trail / max_value, 0.0, 1.0)
	draw_colored_polygon(_bar_shape(inner, trail_w), Color(1, 0.95, 0.8, 0.8))
	var fill_w := inner.size.x * clampf(_shown / max_value, 0.0, 1.0)
	var fill := Color(0.2, 0.6, 0.46) if is_player else Color(0.72, 0.27, 0.22)
	var shape := _bar_shape(inner, fill_w)
	if shape.size() >= 3:
		# 液面：上亮下暗，和面板同一束光
		var colors := PackedColorArray()
		for p in shape:
			var t := (p.y - inner.position.y) / maxf(inner.size.y, 1.0)
			colors.append(fill.lerp(fill.lightened(0.28), 1.0 - t).darkened(t * 0.28))
		draw_polygon(shape, colors)
		draw_line(inner.position + Vector2(3, 1), inner.position + Vector2(maxf(3.0, fill_w - 3), 1), Color(1, 1, 1, 0.22), 1.0, true)
	var font := get_theme_default_font()
	var text := "%d/%d" % [value, max_value]
	var fs := 15
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(rect.get_center().x - w * 0.5, rect.get_center().y + fs * 0.35)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.02, 0.03, 0.06, 0.95))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.98, 0.96, 0.9))
	if is_player:
		var heart := UIKit.icon("ui_heart")
		if heart:
			draw_texture_rect(heart, Rect2(Vector2(size.x - 4, size.y * 0.5 - 13), Vector2(26, 26)), false, Color(1.0, 0.45, 0.5))
	if block > 0:
		var c := Vector2(14, size.y * 0.5)
		var s := 1.0 + _block_pop * 0.5
		var shield := PackedVector2Array([c + Vector2(0, -13) * s, c + Vector2(11, -8) * s, c + Vector2(10, 4) * s,
			c + Vector2(0, 13) * s, c + Vector2(-10, 4) * s, c + Vector2(-11, -8) * s])
		draw_colored_polygon(shield, Color(0.3, 0.55, 0.95))
		shield.append(shield[0])
		draw_polyline(shield, Color(0.75, 0.9, 1.0), 2.0, true)
		var bt := str(block)
		var bw := font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string_outline(font, c + Vector2(-bw * 0.5, 5), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
		draw_string(font, c + Vector2(-bw * 0.5, 5), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
