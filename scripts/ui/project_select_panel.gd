class_name ProjectSelectPanel
extends ModalPanel
## 立项选择：列出 data/projects.json 的项目类型（名称、难度、一句话打法、规则说明），点选后「立项」。
## 最终项目 LM-001 在研究证据不足时显示为锁定。

signal project_chosen(type_id: String)

var _list: VBoxContainer
var _desc: Label
var _start: Button
var _hint: Label
var _picked := ""
var _rows := {}   # type id → PanelContainer
var _evidence: Label


func _init() -> void:
	super._init()
	title_key = "project.select.title"
	icon_name = "node_research"
	accent = UIKit.ACCENT
	subtitle_key = "project.select.subtitle"
	panel_width = 860


func _build(box: VBoxContainer) -> void:
	_hint = UIKit.label("", UIKit.TEXT_DIM, 15, true)
	box.add_child(_hint)
	_evidence = UIKit.label("", UIKit.ACCENT_BLUE, 14, true)
	box.add_child(_evidence)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size = Vector2(380, 0)
	row.add_child(_list)
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UIKit.panel_style(Color(UIKit.PAPER, 0.9), Color(0.22, 0.29, 0.37), 12))
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size = Vector2(0, 240)
	row.add_child(detail)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	detail.add_child(margin)
	_desc = UIKit.label("", UIKit.TEXT, 16, true)
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	margin.add_child(_desc)
	_start = UIKit.button("", "ui_play", "primary", Vector2(0, 50))
	_start.add_theme_font_size_override("font_size", 19)
	_start.pressed.connect(func() -> void:
		close()
		project_chosen.emit(_picked))
	box.add_child(_start)


func _refresh() -> void:
	var company := Company.new()
	company.load_save()
	_hint.text = tr("project.select.hint") % ProjectTypes.code_for_run(company.runs)
	var names: Array = company.evidence.keys().map(func(id: String) -> String: return tr("evidence." + id))
	_evidence.text = tr("project.select.evidence") % "、".join(names) if not names.is_empty() else tr("project.select.evidence_none")
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()
	var unlocked := company.final_unlocked()
	for t in ProjectTypes.all():
		var id := String(t.get("id", ""))
		var locked := bool(t.get("final", false)) and not unlocked
		var panel := _type_row(t, company.runs == 0 and id == ProjectTypes.default_id(), locked, company)
		if not locked:
			_rows[id] = panel
		_list.add_child(panel)
	_select("final" if unlocked and not company.is_campaign_done() and _rows.has("final") else ProjectTypes.default_id())


func _type_row(t: Dictionary, recommended: bool, locked: bool, company: Company) -> PanelContainer:
	var id := String(t.get("id", ""))
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if locked:
		panel.modulate = Color(1, 1, 1, 0.55)
		panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(UIKit.PAPER, 0.9), Color(0.2, 0.22, 0.26), 12))
	else:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				GameAudio.sfx("click")
				_select(id))
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var is_final := bool(t.get("final", false))
	row.add_child(UIKit.icon_rect(String(t.get("icon", "type_molecular")), 34, UIKit.GOLD if is_final else UIKit.ACCENT_BLUE))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(UIKit.header(("%s · " % String(t.get("code", "")) if is_final else "") + tr("project.type." + id), 20, UIKit.GOLD if is_final else UIKit.INK))
	var stars := "★".repeat(int(t.get("difficulty", 1))) + "☆".repeat(maxi(0, 3 - int(t.get("difficulty", 1))))
	name_row.add_child(UIKit.label(stars, UIKit.GOLD, 14))
	if recommended:
		name_row.add_child(UIKit.label(tr("project.recommended"), UIKit.ACCENT, 14))
	text.add_child(name_row)
	var need := int(ProjectTypes.config().get("final_unlock_evidence", 2))
	text.add_child(UIKit.label(tr("project.locked") % [need, company.evidence.size()] if locked else tr("project.type.%s.tag" % id),
		UIKit.TEXT_DIM, 15, true))
	for child in text.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for sub in child.get_children():
			sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _select(id: String) -> void:
	_picked = id
	for type_id in _rows:
		var on: bool = type_id == id
		var sb := UIKit.panel_style(Color(UIKit.PAPER, 0.95) if on else Color(UIKit.PAPER, 0.9),
			UIKit.ACCENT if on else Color(0.22, 0.29, 0.37), 12)
		sb.set_border_width_all(3 if on else 1)
		(_rows[type_id] as PanelContainer).add_theme_stylebox_override("panel", sb)
	_desc.text = tr("project.type.%s.desc" % id)
	_start.text = tr("project.select.start") % tr("project.type." + id)
