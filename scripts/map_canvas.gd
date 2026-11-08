class_name MapCanvas
extends Control
## 研发旅程：路网仍按研发层推进（杀戮尖塔式的节点选择），但读起来是一段探索——
## 每个阶段有自己的地貌、色调和路线起伏；走过的路变成一条踩出来的亮色小径，没选的岔路褪去；
## 前方被迷雾笼罩，越远越看不清；分子本人站在当前位置上。

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
var stage_index := 0
const TERRAIN_PROFILES := [
	[0.2, 0.5, -0.35, -0.8, -0.1, 0.4],
	[0.5, -0.3, 0.1, -0.55, 0.2, -0.6],
	[-0.4, -0.55, -0.2, 0.55, 0.45, 0.2],
	[0.35, -0.15, 0.45, 0.25, -0.4, -0.7],
	[0.45, 0.6, -0.4, -0.45, 0.35, -0.4],
]
var _layers: Array = []
var _path: Array = []
var _choices: Array = []
var _enabled := false
var _boss_title := ""
var _boss_id := ""
## 每个阶段的地貌色调：迷雾颜色与已探索区域的光
const BIOME_TINT := [
	Color(0.35, 0.55, 0.75), Color(0.45, 0.65, 0.4), Color(0.75, 0.35, 0.4), Color(0.7, 0.6, 0.35), Color(0.45, 0.5, 0.8),
]
var _nodes: Array = []     # 每层的 MapNode 列表
var _time := 0.0


func set_map(layers: Array, path: Array, choices: Array, enabled: bool, boss_title: String, boss_id := "") -> void:
	_layers = layers
	_path = path
	_choices = choices
	_enabled = enabled
	_boss_title = boss_title
	_boss_id = boss_id
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
	view.boss_id = _boss_id
	view.fogged = layer > _path.size() + 1   # 前方两层以外在迷雾里
	if reachable:
		view.pressed.connect(func() -> void: node_pressed.emit(index))
	return view


## 节点沿地貌起伏，同时保持同一层的目标间距。
func _place() -> void:
	var cols := _layers.size()
	if cols == 0:
		return
	var w := size.x
	var h := maxf(size.y, 420.0)
	var profile: Array = TERRAIN_PROFILES[clampi(stage_index, 0, TERRAIN_PROFILES.size() - 1)]
	for i in cols:
		var nodes: Array = _nodes[i]
		var travel := float(i) / maxf(1, cols - 1)
		var x := lerpf(60.0, w - 74.0, travel)
		var elevation := float(profile[roundi(travel * (profile.size() - 1))])
		var spacing := minf(108.0, (h - 112.0) / maxf(1, nodes.size() - 1))
		for j in nodes.size():
			var view: MapNode = nodes[j]
			var lane := j - (nodes.size() - 1) * 0.5
			var y := h * 0.49 + lane * spacing + elevation * (55.0 if nodes.size() < 3 else 18.0)
			var stagger := clampf(lane * 9.0 * (-1.0 if i % 2 else 1.0), -16.0, 16.0)
			view.position.x = x + stagger - view.size.x * 0.5
			view.position.y = y - view.radius() - 4
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	_draw_landscape()
	if _nodes.is_empty():
		return
	var frontier := _path.size()   # 下一步要选的那一层
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
					_trail(from, to)
				elif open:
					_curve(from, to, UIKit.GOLD, 3.0, true)
				elif i + 1 < frontier:
					_curve(from, to, Color(0.6, 0.64, 0.66, 0.12), 1.2, false)   # 没选的岔路：已经褪色
				else:
					var distance := float(i + 1 - frontier)
					_curve(from, to, Color(0.72, 0.76, 0.76, 0.42 * clampf(1.0 - distance * 0.22, 0.12, 1.0)), 1.6, false)
	_draw_fog(frontier)
	# 当前位置：分子本人站在这里
	if not _path.is_empty():
		var current: MapNode = _nodes[_path.size() - 1][int(_path.back())]
		_draw_hero(current.hex_center() - Vector2(0, current.radius() + 6))


## 走过的路：一条被踩出来的骨白小径，墨色描边，上面一串足迹般的亮点
func _trail(from: Vector2, to: Vector2) -> void:
	var pts := _bezier(from, to)
	draw_polyline(pts, Color(0.03, 0.04, 0.07, 0.75), 10.0, true)
	draw_polyline(pts, Color(0.93, 0.86, 0.66, 0.9), 6.0, true)
	draw_polyline(pts, Color(UIKit.ACCENT, 0.55), 2.0, true)
	for k in range(2, pts.size() - 1, 4):
		draw_circle(pts[k], 2.2, Color(1.0, 0.97, 0.85, 0.9))


func _bezier(from: Vector2, to: Vector2) -> PackedVector2Array:
	var c1 := from + Vector2((to.x - from.x) * 0.5, 0)
	var c2 := to - Vector2((to.x - from.x) * 0.5, 0)
	var pts := PackedVector2Array()
	for k in 25:
		var t := k / 24.0
		var u := 1.0 - t
		pts.append(from * u * u * u + c1 * 3 * u * u * t + c2 * 3 * u * t * t + to * t * t * t)
	return pts


## 前方的迷雾：从下一步那一列往右越来越浓，几团雾气缓慢飘动；已经走过的区域留一层暖光
func _draw_fog(frontier: int) -> void:
	if frontier >= _nodes.size() or (_nodes[frontier] as Array).is_empty():
		return
	var tint: Color = BIOME_TINT[clampi(stage_index, 0, BIOME_TINT.size() - 1)]
	var edge := (_nodes[frontier][0] as MapNode).hex_center().x + 70.0
	var mist := Color(0.03, 0.04, 0.08).lerp(tint.darkened(0.7), 0.35)
	var band := 200.0
	var steps := 10
	for k in steps:
		var x0 := edge + band * k / steps
		var x1 := edge + band * (k + 1) / steps
		draw_rect(Rect2(x0, 0, x1 - x0, size.y), Color(mist, 0.068 * (k + 1)))
	if edge + band < size.x:
		draw_rect(Rect2(edge + band, 0, size.x - edge - band, size.y), Color(mist, 0.68))
	for i in 7:   # 飘动的雾团
		var drift := fmod(_time * (6.0 + i) + i * 97.0, size.x - edge + 200.0)
		var p := Vector2(edge + drift - 100.0, size.y * (0.15 + 0.12 * i) + sin(_time * 0.4 + i) * 12.0)
		Shading.glow(self, p, 90.0 + 20.0 * (i % 3), Color(tint.lightened(0.3), 0.06))
	if frontier > 0:
		var lit := (_nodes[frontier - 1][0] as MapNode).hex_center().x
		Shading.glow(self, Vector2(lit, size.y * 0.5), size.y * 0.55, Color(1.0, 0.86, 0.6, 0.06))


## 当前位置上的分子：和战斗里同一个角色形象的缩影，轻轻起伏
func _draw_hero(foot: Vector2) -> void:
	var texture := UIKit.art(MoleculeCharacter.CORE)
	var bob := 2.5 * sin(_time * 2.2)
	Shading.glow(self, foot + Vector2(0, -18), 34.0, Color(UIKit.ACCENT, 0.35))
	if texture == null:
		draw_circle(foot + Vector2(0, -16 + bob), 12, UIKit.ACCENT)
		return
	var source := MoleculeCharacter.CORE_SOURCE
	var w := 92.0
	var h := w * source.size.y / source.size.x
	draw_texture_rect_region(texture, Rect2(foot + Vector2(-w * 0.5, -h + bob), Vector2(w, h)), source)


## 两节点间的缓 S 形曲线；dashed 时为向前流动的虚线
func _curve(from: Vector2, to: Vector2, color: Color, width: float, dashed: bool) -> void:
	var pts := _bezier(from, to)
	draw_polyline(pts, Color(0.045, 0.06, 0.10, 0.62 * color.a), width + 4, true)
	if not dashed:
		draw_polyline(pts, color, width, true)
		return
	var phase := int(_time * 8.0) % 4
	for k in range(phase, pts.size() - 1, 4):
		draw_line(pts[k], pts[mini(k + 2, pts.size() - 1)], color, width, true)


func _draw_landscape() -> void:
	var area := Rect2(Vector2.ZERO, size)
	PaintedArt.stage_world(self, area, stage_index, 0.3)
	var tint: Color = BIOME_TINT[clampi(stage_index, 0, BIOME_TINT.size() - 1)]
	draw_rect(area, Color(tint.darkened(0.4), 0.16))   # 每个阶段的地貌色调
	UIKit.inset(self, area, 12.0)
	# 区域铭牌：这一段旅程的地名
	var key := "map.biome.%d" % stage_index
	var font := get_theme_default_font()
	var title := tr(key)
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var plate := Rect2(12, 10, w + 34, 32)
	draw_style_box(UIKit.panel_style(Color(0.05, 0.06, 0.1, 0.82), Color(tint.lightened(0.3), 0.7), 6), plate)
	draw_rect(Rect2(plate.position + Vector2(8, 9), Vector2(4, 14)), tint.lightened(0.3))
	draw_string(font, plate.position + Vector2(20, 22), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.PAPER)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not _layers.is_empty():
		_place()
