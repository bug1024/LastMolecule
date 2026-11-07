class_name MoleculeEditor
extends ModalPanel
## 分子设计 / 修饰界面。操作只有一件事：点分子上的位置，再点下面的片段。
## 片段库只列能放进这个位置的；鼠标停在片段上，分子和右边的属性都会先试装给你看。
## 右边只说现在的结果，阈值规则放在悬停提示里。
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
var _target: Label               # 靶点口袋：变体名 + 它的故事（口袋热点直接画在骨架位点上）
var _lineage_btn: Button
var lineage_sites := {}          # 分子谱系里上一代的结构（有就显示「沿用上一代」）
var _preview: Callable        # 修饰模式：func(placement) -> {kind, efficacy}
var _baseline := {}           # 修饰模式：改动前的属性，用来对比
var _prop_delta := {}         # 这次操作让每项属性变了多少（只在刷新后闪一下）
var _toasts: HBoxContainer
var _step: Label              # 告诉玩家这一步该做什么
var _trial: Molecule = null   # 悬停试装：只用来显示，不影响工作副本
var _stage := "候选化合物发现"
var _card_box: VBoxContainer  # 片段决定卡组：右下角展示这个位置给你的那张牌


func _init() -> void:
	super._init()
	title_key = "mol.title"
	icon_name = "type_molecular"
	accent = Color(0.7, 0.55, 1.0)
	panel_width = 1140


## 打开编辑器；molecule 是游戏里的分子（不会被直接修改）
func edit(molecule: Molecule, edit_mode: String, preview: Callable = Callable(), stage := "候选化合物发现") -> void:
	mode = edit_mode
	_stage = stage
	_trial = null
	_preview = preview
	_work = Molecule.from_dict(molecule.to_dict())
	_baseline = _work.properties() if edit_mode == "modify" else {}
	_prop_delta.clear()
	open()
	_view.molecule = _work
	_view.selected = "L1"
	_presets.visible = mode == "initial"
	_lineage_btn.visible = not lineage_sites.is_empty()
	_target.visible = not molecule.disease.is_empty()
	if _target.visible:
		var vid := Molecule.variant_id(molecule.disease, molecule.variant)
		_target.text = tr("mol.pocket_title") % tr("variant." + vid)
		_target.tooltip_text = tr("variant.%s.desc" % vid)
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
	_target = UIKit.label("", Color(0.82, 0.72, 1.0), 14)
	_target.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_target)
	_view = MoleculeView.new()
	_view.interactive = true
	_view.custom_minimum_size = Vector2(0, 300)
	_view.site_clicked.connect(_on_site)
	left.add_child(_view)
	# 播报排在分子下方的空处，绝不盖住正在响应的结构
	_toasts = HBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_CENTER
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toasts.offset_top = -30
	_toasts.offset_bottom = -2
	_view.add_child(_toasts)
	_step = UIKit.header("", 16, accent.lightened(0.25))
	left.add_child(_step)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 156)
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
			var before := _snapshot()
			_work.apply_preset(preset)
			_after_change(before))
		_presets.add_child(b)
	_lineage_btn = UIKit.button(tr("mol.preset.lineage"), "", "normal", Vector2(0, 32))
	_lineage_btn.add_theme_font_size_override("font_size", 14)
	_lineage_btn.pressed.connect(func() -> void:
		var before := _snapshot()
		_work.apply_sites(lineage_sites)
		_after_change(before))
	_presets.add_child(_lineage_btn)
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
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 4)
	right.add_child(_card_box)
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
	var before := _snapshot()
	if _view.selected == site_id and _work.sites.has(site_id):
		# 再点一次已放片段的选中位点：取下片段
		var placement := _work.sites.duplicate()
		placement.erase(site_id)
		_work.apply_layout(placement)
	_view.selected = site_id
	_after_change(before)


func _place(fragment_id: String, chip: Control = null) -> void:
	var site := _view.selected
	if site.is_empty() or not Molecule.can_place(fragment_id, site):
		GameAudio.sfx("error")
		return
	var before := _snapshot()
	var from := Vector2.INF
	if chip != null:
		from = chip.global_position + chip.size * 0.5 - _view.global_position
	var placement := _work.sites.duplicate()
	placement[site] = fragment_id
	if _work.apply_layout(placement):
		_view.snap(site, from)
		# 自动跳到下一个空位点，减少点击
		for s in Molecule.config().get("sites", []):
			if not _work.sites.has(String(s.id)):
				_view.selected = String(s.id)
				break
	_after_change(before)


func _snapshot() -> Dictionary:
	var combos: Array = _work.active_combos().map(func(c: Dictionary) -> String: return String(c.id))
	return {"props": _work.properties(), "combos": combos, "alerts": _work.alerts.keys(), "sites": _work.sites.duplicate()}


## 一次改动之后：属性闪动、结构响应，新组合和新警示各有自己的表现
func _after_change(before: Dictionary) -> void:
	if before.sites != _work.sites:
		GameAudio.sfx("molecule_modify")
	var props := _work.properties()
	_prop_delta.clear()
	for p in Molecule.PROPS:
		var change := int(props[p]) - int(before.props[p])
		if change != 0:
			_prop_delta[p] = change
	for id in _work.sites:   # 方案一次换多个片段时，每个变化的位点都吸附一下
		if String(before.sites.get(id, "")) != String(_work.sites[id]) and not _view._snap.has(id):
			_view.snap(String(id))
	_refresh_all()
	_prop_delta.clear()
	for combo in _work.active_combos():
		if not (before.combos as Array).has(String(combo.id)):
			_announce_combo(combo)
	for id in _work.alerts:
		if not (before.alerts as Array).has(id):
			_announce_alert(String(id))


func _announce_combo(combo: Dictionary) -> void:
	var links := _work.combo_links(combo)
	var bad := combo.has("alert")
	var color := UIKit.DANGER if bad else UIKit.GOLD
	_view.link_glow(links.pairs, color)
	_view.flash_sites(links.sites, color)
	if bad:
		return   # 带警示的组合由警示本身播报
	GameAudio.sfx("buff")
	# 右栏已写全效果，这里只报名字
	var short_name := tr("combo." + String(combo.id)).get_slice("：", 0).get_slice(":", 0)
	_toast(tr("mol.toast.combo") % short_name, UIKit.GOLD)


func _announce_alert(id: String) -> void:
	GameAudio.sfx("debuff")
	var hit_sites: Array = []
	for site_id in _work.sites:
		if String(Molecule.fragment(String(_work.sites[site_id])).get("alert", "")) == id:
			hit_sites.append(site_id)
	_view.flash_sites(hit_sites, UIKit.DANGER)
	_view.hit(0.3)
	_toast(tr("mol.toast.alert") % tr("alert." + id), UIKit.DANGER.lightened(0.2))


func _toast(text: String, color: Color) -> void:
	var plate := PanelContainer.new()
	var skin := UIKit.panel_style(Color(0.07, 0.08, 0.14, 0.96), color, 8)
	skin.content_margin_left = 10
	skin.content_margin_right = 10
	skin.content_margin_top = 3
	skin.content_margin_bottom = 4
	plate.add_theme_stylebox_override("panel", skin)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UIKit.header(text, 14, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(label)
	_toasts.add_child(plate)
	plate.pivot_offset = plate.get_combined_minimum_size() * 0.5
	plate.scale = Vector2(1.25, 1.25)
	var tween := plate.create_tween()
	tween.tween_property(plate, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.6)
	tween.tween_property(plate, "modulate:a", 0.0, 0.3)
	tween.tween_callback(plate.queue_free)


func _refresh_all() -> void:
	_trial = null
	_view.preview_frag = ""
	_view.queue_redraw()
	_fill_step()
	_fill_inventory()
	_fill_props()
	_fill_extras()
	_show_card(String(_work.sites.get(_view.selected, "")), false)


## 这一步要做什么：一句话，随选中的位置变化
func _fill_step() -> void:
	var site := _view.selected
	if site.is_empty():
		_step.text = tr("mol.step.select")
		return
	var site_name := tr("site." + Molecule.site_type(site)).split(" ")[0]
	if _work.sites.has(site):
		_step.text = tr("mol.step.replace") % [site_name, tr("frag." + String(_work.sites[site]))]
	else:
		_step.text = tr("mol.step.pick") % site_name


func _fill_inventory() -> void:
	for child in _inventory.get_children():
		child.queue_free()
	var counts := {}
	for id in _work.inventory:
		if Molecule.can_place(String(id), _view.selected):   # 放不进去的不列出来，不用玩家自己筛
			counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()
	for id in ids:
		_inventory.add_child(_fragment_chip(String(id), int(counts[id])))
	if ids.is_empty():
		_inventory.add_child(UIKit.label(tr("mol.inventory_empty"), UIKit.TEXT_DIM, 14))


## 鼠标停在片段上：分子和属性先按试装后的样子显示
func _hover_chip(id: String, on: bool) -> void:
	_trial = null
	_view.preview_frag = ""
	if on and not _view.selected.is_empty():
		var trial := Molecule.from_dict(_work.to_dict())
		var placement := trial.sites.duplicate()
		placement[_view.selected] = id
		if trial.apply_layout(placement):
			_trial = trial
			_view.preview_frag = id
	_fill_props()
	_fill_extras()
	_show_card(id if _trial != null else String(_work.sites.get(_view.selected, "")), _trial != null)


## 右下角：这个位置现在给的牌，或悬停片段装上后会变成的牌
func _show_card(frag_id: String, trying: bool) -> void:
	for child in _card_box.get_children():
		child.queue_free()
	var data := _site_card(frag_id)
	if data.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var card := ResearchCard.from_dict(data)
	card.type_name = tr("mol.fragment_tag_synergy" if data.has("synergy_with") else "mol.fragment_tag")
	var face := CardFace.create(card, 0.6)
	face.detail_enabled = false
	row.add_child(face)
	var caption_text := tr("mol.card_try" if trying else "mol.card_now")
	if data.has("synergy_with"):
		caption_text += "\n" + tr("mol.synergy_with") % tr("frag." + String(data.synergy_with))
	var caption := UIKit.label(caption_text, UIKit.GOLD if trying else UIKit.TEXT_DIM, 13, true)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_card_box.add_child(row)


## 片段放进选中位置后的牌（算上和相邻片段的联动）
func _site_card(frag_id: String) -> Dictionary:
	if frag_id.is_empty() or _view.selected.is_empty():
		return {}
	var m := Molecule.from_dict(_work.to_dict())
	m.sites[_view.selected] = frag_id   # 只为算牌面，不检查库存
	return m.site_card(_view.selected)


## 片段卡的一行摘要：「1 费 · 11 伤害 · -2 自伤」
static func card_summary(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	var card := ResearchCard.from_dict(data)
	var parts: Array[String] = [TranslationServer.translate("mol.card_cost") % card.cost]
	for row in card.effect_rows():
		parts.append("%s %s" % [row.number, row.text])
	return " · ".join(parts)


## 片段小卡：结构图 + 名称 + 收益 / 代价；这个位置的口袋喜欢或讨厌它时直接标出来
func _fragment_chip(id: String, count: int) -> Control:
	var frag := Molecule.fragment(id)
	var col := Color.from_string(String(frag.get("color", "#9fb4c8")), Color.GRAY)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(212, 48)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := UIKit.panel_style(Color(0.07, 0.09, 0.12, 0.85), Color(col, 0.55), 10)
	for state_name in ["normal", "focus"]:
		btn.add_theme_stylebox_override(state_name, sb)
	var hover := sb.duplicate() as PaintedStyle
	hover.bg_color = Color(col.darkened(0.45), 0.95)
	hover.border_color = col
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.pressed.connect(_place.bind(id, btn))
	btn.mouse_entered.connect(_hover_chip.bind(id, true))
	btn.mouse_exited.connect(_hover_chip.bind(id, false))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.add_theme_constant_override("separation", 6)
	btn.add_child(row)
	var art := Control.new()
	art.custom_minimum_size = Vector2(38, 0)
	art.draw.connect(func() -> void: MoleculeSpecimen.draw_fragment(art, id, art.size * 0.5, 19.0))
	row.add_child(art)
	var col_box := VBoxContainer.new()
	col_box.alignment = BoxContainer.ALIGNMENT_CENTER
	col_box.add_theme_constant_override("separation", 0)
	row.add_child(col_box)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 5)
	name_row.add_child(UIKit.header(tr("frag." + id) + ("  ×%d" % count if count > 1 else ""), 14, Color.WHITE))
	if not String(frag.get("alert", "")).is_empty():
		name_row.add_child(UIKit.label("⚠", UIKit.GOLD, 13))
	var fit := _pocket_note(frag)
	if not fit.is_empty():
		name_row.add_child(UIKit.label(String(fit.text), fit.color, 12))
	col_box.add_child(name_row)
	# 第二行写它给的牌——这才是装上它的意义；属性变化悬停时在右边属性条上试给你看
	var site_data := _site_card(id)
	if site_data.has("synergy_with"):
		name_row.add_child(UIKit.label("✦ " + tr("mol.synergy"), UIKit.GOLD, 12))
	col_box.add_child(UIKit.label(card_summary(site_data), Color(1.0, 0.86, 0.62), 12))
	btn.tooltip_text = Molecule.fx_text(frag.get("fx", {}))
	for node in btn.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return btn


## 片段放进当前位置后和靶点口袋的关系：✓ 要芳环 / ✗ 忌大基团；没关系就不写
func _pocket_note(frag: Dictionary) -> Dictionary:
	var tags: Array = frag.get("tags", [])
	for spot in _work.pocket():
		if String(spot.get("site", "")) != _view.selected:
			continue
		if spot.has("want") and tags.has(String(spot.want)):
			return {"text": "✓ " + tr("pocket.want." + String(spot.want)), "color": UIKit.ACCENT}
		if spot.has("avoid") and tags.has(String(spot.avoid)):
			return {"text": "✗ " + tr("pocket.avoid." + String(spot.avoid)), "color": UIKit.DANGER.lightened(0.2)}
	return {}


## 当前显示的分子：悬停试装时是试装品，否则是工作副本
func _shown() -> Molecule:
	return _trial if _trial != null else _work


func _fill_props() -> void:
	for child in _props.get_children():
		child.queue_free()
	var shown := _shown()
	var props := shown.properties()
	var now := _work.properties()
	var hi := int(Molecule.config().get("range", [0, 6])[1])
	var effect_lines: Array = shown.effects(_stage).lines
	for p in Molecule.PROPS:
		var v := int(props[p])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.tooltip_text = tr("prop.%s.tip" % p)
		var name_label := UIKit.label(tr("prop." + p), UIKit.TEXT, 14)
		name_label.custom_minimum_size = Vector2(56, 0)
		row.add_child(name_label)
		var pips := Control.new()
		pips.custom_minimum_size = Vector2(hi * 18, 16)
		var good := v >= 4
		var bad := v <= 1
		var trying := _trial != null
		var change := v - int(now[p]) if trying else int(_prop_delta.get(p, 0))
		var was := v - change
		var base := int(_baseline.get(p, -1))
		var pulse := [(0.55 if trying else 1.0) if change != 0 else 0.0]
		pips.draw.connect(func() -> void:
			var t: float = pulse[0]
			for i in hi:
				var r := Rect2(i * 18, 3, 14, 10)
				var on := i < v
				var c: Color = (UIKit.ACCENT if good else (UIKit.DANGER if bad else UIKit.ACCENT_BLUE)) if on else Color(0.2, 0.24, 0.3)
				if t > 0.0 and i >= mini(v, was) and i < maxi(v, was):   # 这次变化的格子：涨的亮起，跌的烧红后熄灭
					if on:
						r = r.grow(1.5 * t)
						c = c.lerp(Color.WHITE, t)
					else:
						c = c.lerp(UIKit.DANGER, t)
				pips.draw_rect(r, c)
			if base >= 0 and base != v:   # 修饰前的位置
				pips.draw_line(Vector2(base * 18 - 2, 0), Vector2(base * 18 - 2, 16), UIKit.GOLD, 2.0))
		if change != 0 and not trying:
			var pulse_tween := pips.create_tween()
			pulse_tween.tween_method(func(t: float) -> void:
				pulse[0] = t
				pips.queue_redraw(), 1.0, 0.0, 0.7)
		row.add_child(pips)
		row.add_child(UIKit.header(str(v), 15, UIKit.ACCENT if good else (UIKit.DANGER.lightened(0.2) if bad else UIKit.TEXT)))
		if base >= 0 and base != v:
			row.add_child(UIKit.label(tr("mol.prop_from") % base, UIKit.GOLD, 12))
		if change != 0:
			var delta := UIKit.header("%+d" % change, 16, UIKit.ACCENT if change > 0 else UIKit.DANGER.lightened(0.2))
			row.add_child(delta)
			if not trying:
				var delta_tween := delta.create_tween()
				delta_tween.tween_interval(0.8)
				delta_tween.tween_property(delta, "modulate:a", 0.0, 0.4)
		_props.add_child(row)
		# 只写现在真正生效的效果；所有阈值放在这一行的悬停提示里
		for line in effect_lines:
			if String(line.get("prop", "")) != p:
				continue
			var args: Array = line.get("args", [])
			var text := tr(String(line.key)) % args if not args.is_empty() else tr(String(line.key))
			var harmful := String(line.key) in ["mol.fx.weak", "mol.fx.offtarget", "mol.fx.poison_down", "mol.fx.clinical_cost", "mol.fx.unstable_strength"]
			_props.add_child(UIKit.label(text, UIKit.DANGER.lightened(0.25) if harmful else UIKit.ACCENT, 12, true))


func _fill_extras() -> void:
	var shown := _shown()
	var counts := {}
	for c in shown.active_combos():
		counts[String(c.id)] = int(counts.get(String(c.id), 0)) + 1
	var full: Array = counts.keys().map(func(id: String) -> String: return tr("combo." + id))
	var short: Array = full.map(func(text: String) -> String: return text.get_slice("：", 0).get_slice(":", 0))
	_combos.visible = not short.is_empty()
	_combos.text = tr("mol.combos") + "：" + "、".join(short)
	_combos.tooltip_text = "\n".join(full)
	for child in _alerts.get_children():
		child.queue_free()
	for id in shown.alerts:
		var state := String(shown.alerts[id])
		var color: Color = {"cleared": UIKit.ACCENT, "confirmed": UIKit.DANGER}.get(state, UIKit.GOLD)
		_alerts.add_child(UIKit.label("⚠ %s（%s）" % [tr("alert." + String(id)), tr("alert.state." + state)], color, 13, true))
	# 阶段考验：过的只打勾，没过的才写差多少——玩家要看的就是这一条
	for child in _exams.get_children():
		child.queue_free()
	var marks: Array[String] = []
	var failures: Array[String] = []
	var details: Array[String] = []
	for stage in Molecule.config().get("exams", {}):
		var exam := shown.exam_result(String(stage))
		var ok := bool(exam.passed)
		var short_stage := tr("stage_short." + String(stage))
		marks.append(("✓ " if ok else "✗ ") + short_stage)
		details.append("%s %s　%s" % ["✓" if ok else "✗", short_stage, Molecule.exam_label(exam)])
		if not ok:
			failures.append("✗ %s　%s" % [short_stage, Molecule.exam_label(exam)])
	var summary := UIKit.label(tr("mol.exam.title") + "　" + "　".join(marks), accent.lightened(0.2), 13)
	summary.mouse_filter = Control.MOUSE_FILTER_PASS
	summary.tooltip_text = "\n".join(details)
	_exams.add_child(summary)
	for line in failures:
		_exams.add_child(UIKit.label(line, UIKit.DANGER.lightened(0.25), 12))
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
				_cost.text = ""
	else:
		_cost.text = ""
