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
	var plate := Rect2(Vector2(8, -6), Vector2(size.x + 8, size.y + 12))
	draw_style_box(UIKit.action_style(UIKit.TEAL.darkened(0.6)), plate)
	draw_rect(plate.grow(-3), Color(UIKit.BRASS, 0.8), false, 1)
	draw_rect(rect, Color(0.10, 0.12, 0.10))
	var trail_w := rect.size.x * clampf(_trail / max_value, 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(trail_w, rect.size.y)), Color(1, 0.95, 0.8, 0.8))
	var fill_w := rect.size.x * clampf(_shown / max_value, 0.0, 1.0)
	var fill := Color(0.30, 0.65, 0.57) if is_player else Color(0.65, 0.26, 0.22)
	draw_rect(Rect2(rect.position, Vector2(fill_w, rect.size.y)), fill)
	draw_rect(Rect2(rect.position, Vector2(fill_w, rect.size.y * 0.4)), Color(1, 1, 1, 0.15))
	draw_rect(rect, Color(0, 0, 0, 0.8), false, 2.0)
	var font := get_theme_default_font()
	var text := "%d/%d" % [value, max_value]
	var fs := 15
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(rect.get_center().x - w * 0.5, rect.get_center().y + fs * 0.35)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if block > 0:
		var c := Vector2(14, size.y * 0.5)
		var s := 1.0 + _block_pop * 0.5
		var shield := PackedVector2Array([c + Vector2(0, -13) * s, c + Vector2(11, -8) * s, c + Vector2(10, 4) * s,
			c + Vector2(0, 13) * s, c + Vector2(-10, 4) * s, c + Vector2(-11, -8) * s])
		draw_colored_polygon(shield, UIKit.TEAL)
		shield.append(shield[0])
		draw_polyline(shield, UIKit.BRASS, 2.0, true)
		var bt := str(block)
		var bw := font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string_outline(font, c + Vector2(-bw * 0.5, 5), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
		draw_string(font, c + Vector2(-bw * 0.5, 5), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
