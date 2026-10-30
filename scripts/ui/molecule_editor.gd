class_name MoleculeEditor
extends ModalPanel
## 分子设计 / 修饰界面。左边是分子结构图（点位点选中）和片段库（点片段放进选中的位点），
## 右边是实时的属性条（每项写清楚现在会带来什么效果）、触发的组合、毒性警示、快速方案与确认按钮。
## initial：开局设计，不能取消；modify：里程碑修饰，显示这次改动的代价（局部 / 核心），可以取消。

signal submitted(placement: Dictionary)
signal cancelled()

var mode := "initial"
var _work: Molecule          # 工作副本：所有改动先作用在它上面，确认后才提交
var _view: MoleculeView
var _inventory: HFlowContainer
var _props: VBoxContainer
var _combos: Label
var _alerts: VBoxContainer
var _exams: VBoxContainer
var _cost: Label
var _confirm: Button
var _cancel: Button
var _presets: HBoxContainer
var _preview: Callable        # 修饰模式：func(placement) -> {kind, efficacy}


func _init() -> void:
	super._init()
	title_key = "mol.title"
	subtitle_key = "mol.subtitle"
	icon_name = "type_molecular"
	accent = Color(0.7, 0.55, 1.0)
	panel_width = 1140


## 打开编辑器；molecule 是游戏里的分子（不会被直接修改）
func edit(molecule: Molecule, edit_mode: String, preview: Callable = Callable()) -> void:
	mode = edit_mode
	_preview = preview
	_work = Molecule.from_dict(molecule.to_dict())
	open()
	_view.molecule = _work
	_view.selected = "L1"
	_presets.visible = mode == "initial"
	_cancel.visible = mode == "modify"
	_confirm.text = tr("mol.confirm" if mode == "initial" else "mol.confirm_modify")
	_title_text(tr("mol.title" if mode == "initial" else "mol.modify_title"))
	for node in find_children("*", "Button", true, false):
		if node.has_meta("close"):
			(node as Button).visible = mode != "initial"   # 开局设计不能关掉
	_refresh_all()


func _title_text(text: String) -> void:
	for label in find_children("*", "Label", true, false):
		if (label as Label).has_meta("title"):
			(label as Label).text = text


## 开局设计时 Esc 交给研发界面打开暂停菜单（设计不能取消，但可以退出到标题）
func _unhandled_input(event: InputEvent) -> void:
	if mode != "initial":
		super._unhandled_input(event)


func close() -> void:
	if mode == "initial" and visible:
		return   # 开局设计必须完成
	super.close()
	cancelled.emit()


func _build(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_view = MoleculeView.new()
	_view.interactive = true
	_view.custom_minimum_size = Vector2(0, 280)
	_view.site_clicked.connect(_on_site)
	left.add_child(_view)
	left.add_child(UIKit.label(tr("mol.hint"), UIKit.TEXT_DIM, 13, true))
	left.add_child(UIKit.header(tr("mol.inventory"), 15, accent.lightened(0.2)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_inventory = HFlowContainer.new()
	_inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory.add_theme_constant_override("h_separation", 8)
	_inventory.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_inventory)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(390, 0)
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	_presets = HBoxContainer.new()
	_presets.add_theme_constant_override("separation", 6)
	_presets.add_child(UIKit.label(tr("mol.presets"), UIKit.TEXT_DIM, 13))
	for preset in ["potent", "balanced", "selective"]:
		var b := UIKit.button(tr("mol.preset." + preset), "", "normal", Vector2(0, 32))
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void:
			_work.apply_preset(preset)
			_refresh_all())
		_presets.add_child(b)
	right.add_child(_presets)
	right.add_child(UIKit.header(tr("mol.properties"), 16, accent.lightened(0.2)))
	_props = VBoxContainer.new()
	_props.add_theme_constant_override("separation", 4)
	right.add_child(_props)
	_combos = UIKit.label("", Color(0.75, 0.85, 1.0), 13, true)
	right.add_child(_combos)
	_alerts = VBoxContainer.new()
	right.add_child(_alerts)
	_exams = VBoxContainer.new()
	_exams.add_theme_constant_override("separation", 0)
	right.add_child(_exams)
	_cost = UIKit.label("", UIKit.GOLD, 14, true)
	right.add_child(_cost)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_cancel = UIKit.button(tr("mol.cancel"), "", "normal", Vector2(110, 46))
	_cancel.pressed.connect(func() -> void:
		visible = false
		cancelled.emit())
	buttons.add_child(_cancel)
	_confirm = UIKit.button(tr("mol.confirm"), "outcome_approved", "primary", Vector2(0, 46))
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(func() -> void:
		visible = false
		submitted.emit(_work.sites.duplicate()))
	buttons.add_child(_confirm)
	right.add_child(buttons)


func _on_site(site_id: String) -> void:
	if _view.selected == site_id and _work.sites.has(site_id):
		# 再点一次已放片段的选中位点：取下片段
		var placement := _work.sites.duplicate()
		placement.erase(site_id)
		_work.apply_layout(placement)
	_view.selected = site_id
	_refresh_all()


func _place(fragment_id: String) -> void:
	var site := _view.selected
	if site.is_empty() or not Molecule.can_place(fragment_id, site):
		GameAudio.sfx("error")
		return
	var placement := _work.sites.duplicate()
	placement[site] = fragment_id
	if _work.apply_layout(placement):
		GameAudio.sfx("card_play")
		# 自动跳到下一个空位点，减少点击
		for s in Molecule.config().get("sites", []):
			if not _work.sites.has(String(s.id)):
				_view.selected = String(s.id)
				break
	_refresh_all()


func _refresh_all() -> void:
	_view.queue_redraw()
	_fill_inventory()
	_fill_props()
	_fill_extras()


func _fill_inventory() -> void:
	for child in _inventory.get_children():
		child.queue_free()
	var counts := {}
	for id in _work.inventory:
		counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()
	for id in ids:
		_inventory.add_child(_fragment_chip(String(id), int(counts[id])))


## 片段小卡：颜色点 + 名称（×数量）+ 能放的位点 + 收益 / 代价
func _fragment_chip(id: String, count: int) -> Control:
	var frag := Molecule.fragment(id)
	var col := Color.from_string(String(frag.get("color", "#9fb4c8")), Color.GRAY)
	var fits := not _view.selected.is_empty() and Molecule.can_place(id, _view.selected)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(212, 58)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := UIKit.panel_style(Color(col, 0.12) if fits else Color(0.07, 0.09, 0.12, 0.8), Color(col, 0.7) if fits else Color(0.3, 0.34, 0.4, 0.5), 10)
	for state_name in ["normal", "focus"]:
		btn.add_theme_stylebox_override(state_name, sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(col, 0.25)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.pressed.connect(_place.bind(id))
	var col_box := VBoxContainer.new()
	col_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col_box.offset_left = 10
	col_box.offset_top = 5
	col_box.add_theme_constant_override("separation", 0)
	col_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col_box)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(dot)
	name_row.add_child(UIKit.header(" " + tr("frag." + id) + ("  ×%d" % count if count > 1 else ""), 14, Color.WHITE if fits else UIKit.TEXT_DIM))
	if not String(frag.get("alert", "")).is_empty():
		name_row.add_child(UIKit.label(" ⚠", UIKit.GOLD, 13))
	col_box.add_child(name_row)
	col_box.add_child(UIKit.label(Molecule.fx_text(frag.get("fx", {})), Color(0.8, 0.86, 0.92) if fits else Color(0.55, 0.6, 0.66), 12))
	var site_names: Array = (frag.get("sites", []) as Array).map(func(t: String) -> String: return tr("site." + t).split(" ")[0])
	col_box.add_child(UIKit.label(" / ".join(site_names), Color(0.55, 0.62, 0.7), 11))
	for node in col_box.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.disabled = not fits
	return btn


func _fill_props() -> void:
	for child in _props.get_children():
		child.queue_free()
	var props := _work.properties()
	var hi := int(Molecule.config().get("range", [0, 6])[1])
	for p in Molecule.PROPS:
		var v := int(props[p])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := UIKit.label(tr("prop." + p), UIKit.TEXT, 14)
		name_label.custom_minimum_size = Vector2(56, 0)
		row.add_child(name_label)
		var pips := Control.new()
		pips.custom_minimum_size = Vector2(hi * 18, 16)
		var good := v >= 4
		var bad := v <= 1
		pips.draw.connect(func() -> void:
			for i in hi:
				var r := Rect2(i * 18, 3, 14, 10)
				var on := i < v
				var c: Color = (UIKit.ACCENT if good else (UIKit.DANGER if bad else UIKit.ACCENT_BLUE)) if on else Color(0.2, 0.24, 0.3)
				pips.draw_rect(r, c))
		row.add_child(pips)
		row.add_child(UIKit.header(str(v), 15, UIKit.ACCENT if good else (UIKit.DANGER.lightened(0.2) if bad else UIKit.TEXT)))
		_props.add_child(row)
		var tip := UIKit.label(tr("prop.%s.tip" % p), UIKit.ACCENT if good else (UIKit.DANGER.lightened(0.25) if bad else UIKit.TEXT_DIM), 12, true)
		_props.add_child(tip)


func _fill_extras() -> void:
	var counts := {}
	for c in _work.active_combos():
		counts[String(c.id)] = int(counts.get(String(c.id), 0)) + 1
	var combos: Array = counts.keys().map(func(id: String) -> String:
		return "· " + tr("combo." + id) + ("  ×%d" % counts[id] if counts[id] > 1 else ""))
	_combos.text = tr("mol.combos") + "：" + ("\n" + "\n".join(combos) if not combos.is_empty() else tr("mol.combos_none"))
	for child in _alerts.get_children():
		child.queue_free()
	if _work.alerts.is_empty():
		_alerts.add_child(UIKit.label("✓ " + tr("mol.alerts_none"), UIKit.ACCENT, 13))
	for id in _work.alerts:
		var state := String(_work.alerts[id])
		var color: Color = {"cleared": UIKit.ACCENT, "confirmed": UIKit.DANGER}.get(state, UIKit.GOLD)
		_alerts.add_child(UIKit.label("⚠ %s（%s）" % [tr("alert." + String(id)), tr("alert.state." + state)], color, 13, true))
	# 各阶段 Boss 的分子考验：设计时就能看到这个分子会在哪一关吃亏
	for child in _exams.get_children():
		child.queue_free()
	_exams.add_child(UIKit.label(tr("mol.exam.title"), accent.lightened(0.2), 13))
	for stage in Molecule.config().get("exams", {}):
		var exam := _work.exam_result(String(stage))
		var ok := bool(exam.passed)
		_exams.add_child(UIKit.label("%s %s　%s" % ["✓" if ok else "✗", tr("stage_short." + String(stage)), Molecule.exam_label(exam)],
			UIKit.ACCENT if ok else UIKit.DANGER.lightened(0.25), 12))
	_confirm.disabled = false
	_cost.add_theme_color_override("font_color", UIKit.GOLD)
	if mode == "modify" and _preview.is_valid():
		var info: Dictionary = _preview.call(_work.sites)
		match String(info.get("kind", "none")):
			"core" when bool(info.get("core_used", false)):
				_cost.text = tr("mol.cost.core_used")
				_cost.add_theme_color_override("font_color", UIKit.DANGER.lightened(0.25))
				_confirm.disabled = true
			"core":
				_cost.text = tr("mol.cost.core") % int(info.get("efficacy", -8))
			"local":
				_cost.text = tr("mol.cost.local")
			_:
				_cost.text = tr("mol.cost.none")
	else:
		_cost.text = ""
