class_name MapCanvas
extends Control
## 分层分支地图画布（纯 UI）：按层排布节点按钮并绘制连线。
## 可前往的节点高亮可点，已走过的路径加粗。

signal node_pressed(index: int)

const NODE_SIZE := Vector2(128, 38)
const ROW_GAP := 60.0

const NODE_META := {
	"fight": {"label": "map.type.fight", "color": Color(0.85, 0.55, 0.45)},
	"elite": {"label": "map.type.elite", "color": Color(0.98, 0.72, 0.25)},
	"boss": {"label": "map.type.boss", "color": Color(0.93, 0.35, 0.4)},
	"research": {"label": "map.type.research", "color": Color(0.35, 0.68, 0.95)},
	"event": {"label": "map.type.event", "color": Color(0.95, 0.72, 0.3)},
	"partner": {"label": "map.type.partner", "color": Color(0.4, 0.82, 0.55)},
	"platform": {"label": "map.type.platform", "color": Color(0.45, 0.8, 0.75)},
	"fast_track": {"label": "map.type.fast_track", "color": Color(0.95, 0.5, 0.8)},
	"milestone": {"label": "map.type.milestone", "color": Color(0.45, 0.85, 0.95)},
}

var rest_heal := 25   # 平台建设「安全评估」能回多少血（由地图界面按项目类型设置，显示在节点提示里）
var _layers: Array = []
var _path: Array = []
var _choices: Array = []
var _enabled := false
var _centers: Array = []   # 每层每个节点的中心点


func set_map(layers: Array, path: Array, choices: Array, enabled: bool, boss_title: String) -> void:
	_layers = layers
	_path = path
	_choices = choices
	_enabled = enabled
	custom_minimum_size = Vector2(0, maxf(ROW_GAP * layers.size(), 120.0))
	for child in get_children():
		child.queue_free()
	_centers.clear()
	var width := maxf(size.x, 600.0)
	for i in layers.size():
		var row: Array = layers[i]
		var centers: Array = []
		for j in row.size():
			var center := Vector2(width * (j + 1) / (row.size() + 1), ROW_GAP * i + NODE_SIZE.y * 0.5 + 6)
			centers.append(center)
			add_child(_build_node(row[j], i, j, center, boss_title))
		_centers.append(centers)
	queue_redraw()


func _build_node(node: Dictionary, layer: int, index: int, center: Vector2, boss_title: String) -> Button:
	var type := String(node.get("type", "research"))
	var meta: Dictionary = NODE_META.get(type, NODE_META["research"])
	var color: Color = meta.color
	var visited: bool = layer < _path.size() and int(_path[layer]) == index
	var current := visited and layer == _path.size() - 1
	var reachable: bool = _enabled and layer == _path.size() and _choices.has(index)
	var btn := Button.new()
	btn.position = center - NODE_SIZE * 0.5
	btn.size = NODE_SIZE
	btn.text = tr(String(meta.label)) if type != "boss" else "BOSS · " + boss_title
	if type == "boss":
		btn.size = Vector2(NODE_SIZE.x + 70, NODE_SIZE.y + 8)
		btn.position = center - btn.size * 0.5
	btn.tooltip_text = tr(String(meta.label) + ".tip") % [rest_heal, rest_heal] if type == "platform" else tr(String(meta.label) + ".tip")
	btn.icon = UIKit.icon("node_" + type)
	btn.add_theme_constant_override("icon_max_width", 20)
	btn.set_meta("sfx", "node")
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(1, 1, 1) if reachable or visited else color.lightened(0.2))
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.85) if visited else color.darkened(0.15))
	btn.add_theme_color_override("icon_normal_color", Color(1, 1, 1) if reachable else color.lightened(0.2))
	btn.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.85) if visited else color.darkened(0.15))
	var fill := color.lerp(Color(0.1, 0.12, 0.17), 0.35 if reachable else (0.55 if visited else 0.82))
	btn.add_theme_stylebox_override("normal", _style(fill, color, reachable or current))
	btn.add_theme_stylebox_override("hover", _style(fill.lightened(0.15), Color(1, 1, 1), true))
	btn.add_theme_stylebox_override("pressed", _style(fill.darkened(0.1), Color(1, 1, 1), true))
	btn.add_theme_stylebox_override("disabled", _style(fill, color.darkened(0.3), current))
	btn.disabled = not reachable
	if reachable:
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(func() -> void: node_pressed.emit(index))
	return btn


func _style(fill: Color, border: Color, strong: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(3 if strong else 1)
	sb.border_color = border
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	if strong:
		sb.shadow_color = Color(border, 0.3)
		sb.shadow_size = 8
	return sb


func _draw() -> void:
	for i in _layers.size() - 1:
		for j in _layers[i].size():
			for t in _layers[i][j].next:
				var on_path: bool = i + 1 < _path.size() and int(_path[i]) == j and int(_path[i + 1]) == int(t)
				var from: Vector2 = _centers[i][j] + Vector2(0, NODE_SIZE.y * 0.5)
				var to: Vector2 = _centers[i + 1][t] - Vector2(0, NODE_SIZE.y * 0.5)
				draw_line(from, to, Color(0.95, 0.8, 0.4, 0.9) if on_path else Color(0.5, 0.56, 0.66, 0.45), 3.0 if on_path else 1.5, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not _layers.is_empty():
		var width := size.x
		for i in _centers.size():
			for j in _centers[i].size():
				_centers[i][j].x = width * (j + 1) / (_layers[i].size() + 1)
		var k := 0
		for i in _centers.size():
			for j in _centers[i].size():
				if k < get_child_count():
					get_child(k).position = _centers[i][j] - NODE_SIZE * 0.5
				k += 1
		queue_redraw()
