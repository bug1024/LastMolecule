class_name PipelineView
extends Control
## 研发管线进度条：六个阶段节点（发现 → 上市）横向排列，已完成打勾、当前阶段发光。

var stages: Array = []      # 阶段 id 列表
var current := 0
var _time := 0.0

const DONE := UIKit.TEAL
const NOW := UIKit.GOLD
const TODO := UIKit.TEXT_DIM


func set_stages(stage_ids: Array, current_index: int) -> void:
	stages = stage_ids
	current = current_index
	custom_minimum_size = Vector2(0, 74)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	if stages.is_empty():
		return
	var font := get_theme_default_font()
	var n := stages.size()
	var margin := 70.0
	var y := 24.0
	var step := (size.x - margin * 2) / maxf(n - 1, 1)
	for i in n - 1:
		var a := Vector2(margin + step * i, y)
		var b := Vector2(margin + step * (i + 1), y)
		draw_line(a, b, TODO, 3.0, true)
		if i < current:
			draw_line(a, b, DONE, 3.0, true)
		elif i == current:
			var t := fmod(_time * 0.5, 1.0)
			draw_line(a, a.lerp(b, t), Color(NOW, 0.6 * (1.0 - t)), 3.0, true)
	for i in n:
		var p := Vector2(margin + step * i, y)
		var color := DONE if i < current else (NOW if i == current else TODO)
		if i == current:
			var pulse := 0.5 + 0.5 * sin(_time * 3.0)
			draw_circle(p, 18 + 4 * pulse, Color(NOW, 0.12))
		draw_circle(p, 12, UIKit.PAPER)
		draw_arc(p, 12, 0, TAU, 32, color, 3.0, true)
		if i < current:
			draw_polyline(PackedVector2Array([p + Vector2(-5, 0), p + Vector2(-1, 4), p + Vector2(6, -4)]), color, 2.5, true)
		elif i == current:
			draw_circle(p, 5, color)
		var text := tr("stage_short." + String(stages[i]))
		var fs := 14
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, Vector2(p.x - w * 0.5, y + 38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			UIKit.INK if i == current else (DONE if i < current else TODO))
