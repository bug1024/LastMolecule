class_name ModalPanel
extends Control
## 模态面板基类：半透明遮罩 + 居中面板 + 标题栏（含返回按钮），Esc 关闭。
## 标题栏：圆形图标徽章（icon_name）+ 标题 + 副标题（subtitle_key）+ 返回；下方一条强调色渐隐线。
## 面板背景：角落里淡淡的六边形纹理与强调色光晕（accent），让各个面板有统一但各有颜色的「封面感」。
## 子类在 _build(content) 中往 content 里添加内容；open()/close() 带淡入淡出。

signal closed()

var title_key := ""
var subtitle_key := ""
var icon_name := ""
var accent := UIKit.ACCENT
var panel_width := 720.0
var _content: VBoxContainer
var _panel: PanelContainer
var _built := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func open() -> void:
	if not _built:
		_construct()
	_refresh()
	visible = true
	modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.96, 0.96)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.16)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	GameAudio.sfx("open")


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## 语言切换等需要重建内容时调用
func rebuild() -> void:
	if not _built:
		return
	for child in _content.get_children():
		child.queue_free()
	_build(_content)


func _construct() -> void:
	_built = true
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(panel_width, 0)
	_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.08, 0.11, 0.98), Color(accent, 0.45), 18))
	center.add_child(_panel)
	var decor := Control.new()
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor.clip_contents = true
	decor.draw.connect(_draw_decor.bind(decor))
	decor.resized.connect(decor.queue_redraw)
	_panel.add_child(decor)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	if not icon_name.is_empty():
		var badge := Control.new()
		badge.custom_minimum_size = Vector2(46, 46)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tex := UIKit.icon(icon_name)
		badge.draw.connect(func() -> void:
			var c := badge.size * 0.5
			badge.draw_circle(c, 23, Color(accent, 0.16))
			badge.draw_arc(c, 22, 0, TAU, 48, Color(accent, 0.8), 2.0, true)
			if tex:
				badge.draw_texture_rect(tex, Rect2(c - Vector2(13, 13), Vector2(26, 26)), false, accent.lightened(0.25)))
		bar.add_child(badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UIKit.header(tr(title_key), 26)
	title.set_meta("title", true)
	names.add_child(title)
	if not subtitle_key.is_empty():
		names.add_child(UIKit.label(tr(subtitle_key), Color(accent.lightened(0.2), 0.8), 14))
	bar.add_child(names)
	var back := UIKit.button(tr("ui.back"), "ui_back", "normal", Vector2(110, 40))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	bar.add_child(back)
	outer.add_child(bar)
	var line := Control.new()
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void:   # 从左到右渐隐的一条线（顶点着色，没有分段接缝）
		var w := line.size.x
		line.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 2), Vector2(0, 2)]),
			PackedColorArray([Color(accent, 0.8), Color(accent, 0.0), Color(accent, 0.0), Color(accent, 0.8)])))
	outer.add_child(line)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	outer.add_child(_content)
	_build(_content)


## 面板背景装饰：右上角强调色光晕 + 淡淡的六边形纹理
func _draw_decor(decor: Control) -> void:
	var w := decor.size.x
	var corner := Vector2(w - 60, 40)
	for i in 8:
		decor.draw_circle(corner, 170.0 - i * 18.0, Color(accent, 0.02))
	var r := 18.0
	for row in 5:
		for col in 7:
			var center := Vector2(w - 30 - col * r * 1.732 - (r * 0.866 if row % 2 else 0.0), 20 + row * r * 1.5)
			var pts := PackedVector2Array()
			for k in 7:
				var a := PI / 6 + k * TAU / 6
				pts.append(center + Vector2(cos(a), sin(a)) * r)
			decor.draw_polyline(pts, Color(accent, 0.08 * (1.0 - (col + row) / 10.0)), 1.0, true)


## 子类实现：构建内容
func _build(_box: VBoxContainer) -> void:
	pass


## 子类可选实现：每次打开时刷新数据
func _refresh() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
