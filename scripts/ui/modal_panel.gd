class_name ModalPanel
extends Control
## 模态面板基类：半透明遮罩 + 居中面板 + 标题栏（含返回按钮），Esc 关闭。
## 子类在 _build(content) 中往 content 里添加内容；open()/close() 带淡入淡出。

signal closed()

var title_key := ""
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
	_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.075, 0.095, 0.13, 0.98), Color(0.27, 0.36, 0.45), 16))
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)
	var bar := HBoxContainer.new()
	var title := UIKit.header(tr(title_key), 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.set_meta("title", true)
	bar.add_child(title)
	var back := UIKit.button(tr("ui.back"), "ui_back", "normal", Vector2(110, 40))
	back.pressed.connect(close)
	bar.add_child(back)
	outer.add_child(bar)
	outer.add_child(HSeparator.new())
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	outer.add_child(_content)
	_build(_content)


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
