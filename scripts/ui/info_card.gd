class_name InfoCard
extends PanelContainer
## 研发总览右侧的可展开小卡片：平时只显示「图标 + 标题 + 一行摘要」，点一下展开完整说明。
## detail 支持 BBCode（竞争格局里有新闻配色）。
## pinned 模式（终审目标用）：不能折叠，正文常驻显示，标题后可加汇总（如「2/3 达标」）。

var expanded := false
var _summary: Label
var _detail: RichTextLabel
var _arrow: Label
var _accent := UIKit.ACCENT
var _title_key := ""
var _name_label: Label
var _suffix := ""
var pinned := false


## title_key 为标题的翻译键（切换语言后 set_content 会重新翻译）
func _init(icon_name: String, title_key: String, accent: Color) -> void:
	_title_key = title_key
	_accent = accent
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_restyle(false)
	UIKit.decorate_panel(self)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	head.add_child(UIKit.icon_rect(icon_name, 22, accent))
	_name_label = UIKit.header(tr(title_key), 16, accent.lightened(0.2))
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name_label)
	_arrow = UIKit.label("▸", UIKit.TEXT_DIM, 14)
	head.add_child(_arrow)
	_summary = UIKit.label("", UIKit.TEXT, 14, true)
	box.add_child(_summary)
	_detail = UIKit.rich("", 13)
	_detail.fit_content = true
	_detail.visible = false
	box.add_child(_detail)
	for node in [_name_label, _arrow, _summary, _detail]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gui_input.connect(func(event: InputEvent) -> void:
		if not pinned and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			GameAudio.sfx("click")
			set_expanded(not expanded))
	mouse_entered.connect(func() -> void: _restyle(true))
	mouse_exited.connect(func() -> void: _restyle(false))


func set_content(summary: String, detail: String) -> void:
	_name_label.text = tr(_title_key) + (" · " + _suffix if not _suffix.is_empty() else "")
	_summary.text = summary
	_summary.visible = not summary.is_empty()
	_detail.text = detail


## 固定展开的卡片：没有折叠箭头，正文（BBCode）常驻
func pin() -> void:
	pinned = true
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_arrow.visible = false
	set_expanded(true)


func set_title_suffix(text: String) -> void:
	_suffix = text


func set_expanded(on: bool) -> void:
	expanded = on
	_detail.visible = on
	_arrow.text = "▾" if on else "▸"


## 浮动数字的定位锚点（指标变化时飘字）
func anchor() -> Control:
	return _summary


func _restyle(hover: bool) -> void:
	var sb := UIKit.panel_style(Color(0.05, 0.07, 0.1, 0.78 if not hover else 0.9), Color(_accent, 0.35 if not hover else 0.7), 12)
	add_theme_stylebox_override("panel", sb)
