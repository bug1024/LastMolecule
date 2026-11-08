class_name MapNode
extends Control
## 研发地图上的一个地点。每类地点有自己的轮廓，不再都是同一个六边形：
##   实验难题＝分子环六边形 / 精英＝带刺的冠状六边形 / 研究＝透镜圆加轨道 / 事件＝菱形 /
##   平台建设＝立在地上的方形站台 / 合作＝双环 / 快速通道＝箭头 / 里程碑＝旗帜 / Boss＝敌人本体的肖像。
## 地点站在地面上（脚下有阴影）；名字只写在能去的地点和鼠标停留的地点上，其余靠轮廓和提示。
## 状态：reachable 可前往 / current 当前位置 / visited 走过 / locked 还没到；fogged 表示在前方的迷雾里。

signal pressed()

const HEX_R := 24.0
const BOSS_R := 34.0

var type := "fight"
var color := Color.WHITE
var state := "locked"
var label_text := ""
var fogged := false
var boss_id := ""
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
	custom_minimum_size = Vector2(150, 104) if type == "boss" else Vector2(104, 78)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hover = true
		if state == "reachable":
			GameAudio.sfx("hover")
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	if state == "reachable":
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				GameAudio.sfx("node")
				pressed.emit())


## 徽章中心（画布连线用）
func hex_center() -> Vector2:
	return position + Vector2(size.x * 0.5, radius() + 4)


func radius() -> float:
	return BOSS_R if type == "boss" else HEX_R


func _process(delta: float) -> void:
	if state == "reachable" or state == "current" or type == "boss":
		_time += delta
		queue_redraw()


## 每类地点的轮廓
func outline(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match type:
		"elite":   # 带刺的冠：强敌
			for i in 13:
				var a := -PI / 2 + i * TAU / 12.0
				pts.append(c + Vector2.from_angle(a) * r * (1.18 if i % 2 == 0 else 0.9))
		"research", "partner", "boss":
			for i in 29:
				pts.append(c + Vector2.from_angle(i * TAU / 28.0) * r)
		"event":   # 菱形：未知
			for a in [-PI / 2, 0.0, PI / 2, PI, -PI / 2]:
				pts.append(c + Vector2.from_angle(a) * r * 1.15)
		"platform":   # 方形站台
			var h := r * 0.86
			pts = PackedVector2Array([c + Vector2(-h, -h * 0.8), c + Vector2(h, -h * 0.8), c + Vector2(h * 1.08, h), c + Vector2(-h * 1.08, h), c + Vector2(-h, -h * 0.8)])
		"fast_track":   # 向前的箭头
			pts = PackedVector2Array([c + Vector2(-r, -r * 0.7), c + Vector2(r * 0.2, -r * 0.7), c + Vector2(r * 1.1, 0), c + Vector2(r * 0.2, r * 0.7),
				c + Vector2(-r, r * 0.7), c + Vector2(-r * 0.45, 0), c + Vector2(-r, -r * 0.7)])
		"milestone":   # 旗帜
			pts = PackedVector2Array([c + Vector2(-r * 0.7, -r), c + Vector2(r * 0.95, -r * 0.6), c + Vector2(r * 0.55, -r * 0.1), c + Vector2(r * 0.95, r * 0.4),
				c + Vector2(-r * 0.7, r * 0.5), c + Vector2(-r * 0.7, -r)])
		_:   # 实验难题：分子环
			for i in 7:
				pts.append(c + Vector2.from_angle(PI / 6 + i * TAU / 6) * r)
	return pts


func _draw() -> void:
	var r := radius() * (1.08 if _hover and state == "reachable" else 1.0)
	var c := Vector2(size.x * 0.5, radius() + 4)
	var fade := 0.55 if fogged else 1.0
	# 地点站在地面上：脚下一块椭圆阴影
	var ground := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		ground.append(c + Vector2(cos(a) * r * 1.05, r * 0.95 + sin(a) * r * 0.22))
	draw_colored_polygon(ground, Color(0.01, 0.02, 0.04, 0.45 * fade))
	var fill: Color
	var border: Color
	var icon_tint: Color
	match state:
		"reachable":
			var pulse := 0.5 + 0.5 * sin(_time * 4.0)
			Shading.glow(self, c, r * (1.9 + 0.2 * pulse), Color(color, 0.32))
			fill = color.lerp(Color(0.08, 0.1, 0.14), 0.3)
			border = UIKit.GOLD
			icon_tint = UIKit.PAPER
		"current", "visited":
			fill = color.lerp(Color(0.08, 0.1, 0.14), 0.62)
			border = color.lerp(Color.WHITE, 0.2) if state == "current" else Color(color, 0.7)
			icon_tint = Color(1, 1, 1, 0.85)
		_:
			fill = color.lerp(Color(0.07, 0.09, 0.12), 0.8)
			border = Color(color, 0.45)
			icon_tint = Color(color.lightened(0.2), 0.6)
	fill.a *= fade
	border.a *= fade
	icon_tint.a *= fade
	if type == "boss":
		_draw_boss(c, r, fade)
		border = Color(UIKit.DANGER.lightened(0.15), fade)
	var pts := outline(c, r)
	if type == "platform":   # 站台的立柱
		draw_line(c + Vector2(0, r * 0.86), c + Vector2(0, r * 1.1), Color(UIKit.INK, fade), 5.0, true)
	if type == "partner":
		draw_arc(c + Vector2(r * 0.35, 0), r * 0.82, 0, TAU, 28, Color(border, 0.6 * fade), 1.5, true)
	if type == "research":   # 透镜外的一条轨道
		draw_arc(c, r * 1.25, -0.6 + _time * 0.6, 1.6 + _time * 0.6, 20, Color(color, 0.6 * fade), 1.5, true)
	if type != "boss":
		draw_colored_polygon(pts.slice(0, pts.size() - 1), fill)   # 轮廓首尾重合，填充时去掉重复点
	draw_polyline(pts, Color(UIKit.INK, fade), 6.0, true)
	draw_polyline(pts, border, 3.0 if state == "reachable" or state == "current" else 1.5, true)
	if _icon and type != "boss":
		var s := r * (0.9 if type in ["event", "fast_track", "milestone"] else 1.0)
		draw_texture_rect(_icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, icon_tint)
	if state == "visited":   # 走过：右下角小勾
		var tick := c + Vector2(r * 0.62, r * 0.55)
		draw_circle(tick, 7, Color(0.05, 0.07, 0.1))
		draw_polyline(PackedVector2Array([tick + Vector2(-3.5, 0), tick + Vector2(-1, 3), tick + Vector2(4, -3)]), UIKit.ACCENT, 2.0, true)
	if not _shows_label():
		return
	var font := get_theme_default_font()
	var fs := 14 if type == "boss" else 13
	var text_color: Color = Color.WHITE if state == "reachable" or _hover else Color(1, 1, 1, 0.85)
	var lines := label_text.split("\n")
	for i in lines.size():
		var y := c.y + r * 1.18 + 6 + fs + i * (fs + 2)
		var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(c.x - w * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(c.x - w * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)


## 名字只写在要做选择的地方：能去的、鼠标停着的、Boss 和里程碑这两个路标
func _shows_label() -> bool:
	return state == "reachable" or _hover or type == "boss" or (type == "milestone" and not fogged)


## Boss：圆框里是它本体的肖像，外圈一层缓慢搏动的危险光
func _draw_boss(c: Vector2, r: float, fade: float) -> void:
	var throb := 0.5 + 0.5 * sin(_time * 2.2)
	Shading.glow(self, c, r * (1.7 + 0.15 * throb), Color(UIKit.DANGER, 0.38 * fade))
	draw_circle(c, r, Color(0.12, 0.04, 0.06, 0.95 * fade))
	for sheet in CreatureView.GEOMETRIC_PORTRAITS:
		var entries: Dictionary = CreatureView.GEOMETRIC_PORTRAITS[sheet]
		var texture := UIKit.art(sheet)
		if entries.has(boss_id) and texture != null:
			var source: Rect2 = entries[boss_id]
			var k := (r * 1.7) / maxf(source.size.x, source.size.y)
			var extent := source.size * k
			draw_texture_rect_region(texture, Rect2(c - extent * 0.5 + Vector2(0, r * 0.08), extent), source, Color(1, 1, 1, fade))
			return
	if _icon:
		draw_texture_rect(_icon, Rect2(c - Vector2(r, r) * 0.5, Vector2(r, r)), false, Color(1, 0.85, 0.8, fade))
