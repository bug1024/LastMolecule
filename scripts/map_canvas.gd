class_name MapCanvas
extends Control
## 分层分支地图画布（纯 UI）：研发路线从左往右推进，每一列是一层，节点是六边形徽章（MapNode）。
## 背景是按阶段着色的淡六边形网格；已走过的路线是绿色粗线，从当前位置出发可走的路线是流动的金色虚线，
## 其余为淡线；当前位置头顶有一个小烧瓶标记。

signal node_pressed(index: int)

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
var tint := Color(0.35, 0.28, 0.6)   # 阶段色（背景网格与光晕）
var _layers: Array = []
var _path: Array = []
var _choices: Array = []
var _enabled := false
var _boss_title := ""
var _nodes: Array = []     # 每层的 MapNode 列表
var _time := 0.0


func set_map(layers: Array, path: Array, choices: Array, enabled: bool, boss_title: String) -> void:
	_layers = layers
	_path = path
	_choices = choices
	_enabled = enabled
	_boss_title = boss_title
	custom_minimum_size = Vector2(0, 420)
	for child in get_children():
		child.queue_free()
	_nodes.clear()
	for i in layers.size():
		var row: Array = layers[i]
		var nodes: Array = []
		for j in row.size():
			var node := _build_node(row[j], i, j)
			add_child(node)
			nodes.append(node)
		_nodes.append(nodes)
	_place()


func _build_node(node: Dictionary, layer: int, index: int) -> MapNode:
	var type := String(node.get("type", "research"))
	var meta: Dictionary = NODE_META.get(type, NODE_META["research"])
	var visited: bool = layer < _path.size() and int(_path[layer]) == index
	var current := visited and layer == _path.size() - 1
	var reachable: bool = _enabled and layer == _path.size() and _choices.has(index)
	var state := "reachable" if reachable else ("current" if current else ("visited" if visited else "locked"))
	var text := tr(String(meta.label)) if type != "boss" else "BOSS\n" + _boss_title
	var tip := tr(String(meta.label) + ".tip") % [rest_heal, rest_heal] if type == "platform" else tr(String(meta.label) + ".tip")
	var view := MapNode.new()
	view.setup(type, meta.color, state, text, tip)
	if reachable:
		view.pressed.connect(func() -> void: node_pressed.emit(index))
	return view


## 按当前尺寸排布：列均分宽度，每列节点在高度上均分
func _place() -> void:
	var cols := _layers.size()
	if cols == 0:
		return
	var w := maxf(size.x, 600.0)
	var h := maxf(size.y, 420.0)
	for i in cols:
		var nodes: Array = _nodes[i]
		var x := w * (i + 0.5) / cols
		for j in nodes.size():
			var view: MapNode = nodes[j]
			var y := h * (j + 0.5) / nodes.size()
			view.position = Vector2(x - view.size.x * 0.5, y - view.radius() - 4)
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree() and _enabled:
		_time += delta
		queue_redraw()


func _draw() -> void:
	_draw_grid()
	if _nodes.is_empty():
		return
	for i in _layers.size() - 1:
		for j in _layers[i].size():
			for t in _layers[i][j].next:
				var a: MapNode = _nodes[i][j]
				var b: MapNode = _nodes[i + 1][int(t)]
				var walked: bool = i + 1 < _path.size() and int(_path[i]) == j and int(_path[i + 1]) == int(t)
				var open: bool = _enabled and i == _path.size() - 1 and int(_path[i]) == j and _choices.has(int(t))
				var from := a.hex_center() + Vector2(a.radius(), 0)
				var to := b.hex_center() - Vector2(b.radius(), 0)
				if walked:
					_curve(from, to, UIKit.ACCENT, 5.0, false)
				elif open:
					_curve(from, to, UIKit.GOLD, 3.0, true)
				else:
					_curve(from, to, Color(0.55, 0.62, 0.72, 0.28), 2.0, false)
	# 当前位置：头顶的小烧瓶
	if not _path.is_empty():
		var current: MapNode = _nodes[_path.size() - 1][int(_path.back())]
		var top := current.hex_center() - Vector2(0, current.radius() + 18 + 3 * sin(_time * 3.0))
		draw_circle(top, 15, Color(0.04, 0.06, 0.09, 0.95))
		draw_arc(top, 15, 0, TAU, 32, PlayerAvatar.GREEN, 2.0, true)
		var flask := UIKit.icon("type_experiment")
		if flask:
			draw_texture_rect(flask, Rect2(top - Vector2(10, 10), Vector2(20, 20)), false, PlayerAvatar.GREEN)


## 两节点间的缓 S 形曲线；dashed 时为向前流动的虚线
func _curve(from: Vector2, to: Vector2, color: Color, width: float, dashed: bool) -> void:
	var c1 := from + Vector2((to.x - from.x) * 0.5, 0)
	var c2 := to - Vector2((to.x - from.x) * 0.5, 0)
	var pts := PackedVector2Array()
	for k in 25:
		var t := k / 24.0
		var u := 1.0 - t
		pts.append(from * u * u * u + c1 * 3 * u * u * t + c2 * 3 * u * t * t + to * t * t * t)
	if not dashed:
		draw_polyline(pts, color, width, true)
		return
	var phase := int(_time * 8.0) % 4
	for k in range(phase, pts.size() - 1, 4):
		draw_line(pts[k], pts[mini(k + 2, pts.size() - 1)], color, width, true)


## 背景：淡淡的六边形网格，按阶段着色
func _draw_grid() -> void:
	var r := 22.0
	var dx := r * sqrt(3.0)
	var dy := r * 1.5
	var color := Color(tint.lightened(0.3), 0.07)
	var row := 0
	var y := 0.0
	while y < size.y + r:
		var x := (dx * 0.5 if row % 2 == 1 else 0.0)
		while x < size.x + r:
			var pts := PackedVector2Array()
			for i in 7:
				var a := PI / 6 + i * TAU / 6
				pts.append(Vector2(x, y) + Vector2(cos(a), sin(a)) * r)
			draw_polyline(pts, color, 1.0)
			x += dx
		y += dy
		row += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not _layers.is_empty():
		_place()
