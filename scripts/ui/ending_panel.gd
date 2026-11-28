class_name EndingPanel
extends Control
## 一局结束的结局画面：结局图标与标题、原因、项目数据、公司结算、研究证据，以及「再来一局 / 返回标题」。
## 最终项目 LM-001 的主线结局会换成战役标题与文案，并列出因果链：哪些项目带来了哪些证据、做过哪些决策、选了哪条路线。

signal restart_requested()

const OUTCOME_COLOR := {
	"approved": Color(0.35, 0.85, 0.6),
	"terminated": Color(0.95, 0.8, 0.4),
	"failed": Color(0.93, 0.42, 0.42),
}

var _panel: PanelContainer
var _box: VBoxContainer
var _mid: VBoxContainer          # 统计 / 结算 / 证据 / 因果链：内容多时在这里滚动，标题与按钮固定
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_box)


## state 为 ProjectState；summary 为 Company.settle_run 的返回值；molecule 为本局玩家亲手打造的分子
func show_ending(outcome: String, reason_key: String, summary: Dictionary, state: ProjectState, molecule: Molecule = null, mol_form := 1) -> void:
	for child in _box.get_children():
		child.queue_free()
	var color: Color = OUTCOME_COLOR.get(outcome, OUTCOME_COLOR.failed)
	var style := UIKit.panel_style(Color(0.07, 0.09, 0.12, 0.98), color, 18)
	style.set_content_margin_all(28)
	style.shadow_color = Color(color, 0.25)
	style.shadow_size = 24
	_panel.add_theme_stylebox_override("panel", style)
	var campaign := String(summary.get("campaign_ending", ""))
	if not campaign.is_empty():
		color = UIKit.GOLD
		style.border_color = color
		style.shadow_color = Color(color, 0.3)
	var title_text := tr("campaign.%s.title" % campaign) if not campaign.is_empty() else tr("ending." + outcome + ".title")
	var flavor_text := tr("campaign.%s.flavor" % campaign) if not campaign.is_empty() else tr("ending." + outcome + ".flavor")
	if molecule != null:
		# 结局主角展示横幅：左侧是玩家亲手打造的终态分子角色，右侧是结局徽标、标题与叙事，兼顾仪式感与 720p 紧凑高度
		var hero_row := HBoxContainer.new()
		hero_row.add_theme_constant_override("separation", 20)
		hero_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_box.add_child(hero_row)
		hero_row.add_child(_molecule_showcase(molecule, mol_form, outcome, color))
		var meta := VBoxContainer.new()
		meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meta.add_theme_constant_override("separation", 6)
		hero_row.add_child(meta)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.alignment = BoxContainer.ALIGNMENT_BEGIN
		head.add_child(UIKit.icon_rect("logo" if not campaign.is_empty() else "outcome_" + outcome, 36, color))
		var title_col := VBoxContainer.new()
		title_col.add_theme_constant_override("separation", 0)
		if not campaign.is_empty():
			title_col.add_child(UIKit.label(tr("campaign.badge"), UIKit.GOLD, 13))
		title_col.add_child(UIKit.header(title_text, 30, color))
		head.add_child(title_col)
		meta.add_child(head)
		var reason := UIKit.label(tr(reason_key), UIKit.TEXT, 15, true)
		reason.custom_minimum_size = Vector2(340, 0)
		meta.add_child(reason)
		if tr(reason_key) != flavor_text:
			var flavor := UIKit.label(flavor_text, UIKit.TEXT if not campaign.is_empty() else UIKit.TEXT_DIM, 13 if campaign.is_empty() else 15, true)
			flavor.custom_minimum_size = Vector2(340, 0)
			meta.add_child(flavor)
	else:
		var icon := UIKit.icon_rect("logo" if not campaign.is_empty() else "outcome_" + outcome, 84, color)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_box.add_child(icon)
		if not campaign.is_empty():
			var badge := UIKit.label(tr("campaign.badge"), UIKit.GOLD, 15)
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_box.add_child(badge)
		var title := UIKit.header(title_text, 36, color)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(title)
		var reason := UIKit.label(tr(reason_key), UIKit.TEXT, 16, true)
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reason.custom_minimum_size = Vector2(560, 0)
		_box.add_child(reason)
		if tr(reason_key) != flavor_text:
			var flavor := UIKit.label(flavor_text,
				UIKit.TEXT if not campaign.is_empty() else UIKit.TEXT_DIM, 14 if campaign.is_empty() else 16, true)
			flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			flavor.custom_minimum_size = Vector2(560, 0)
			_box.add_child(flavor)
	_box.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_scroll)
	_mid = VBoxContainer.new()
	_mid.add_theme_constant_override("separation", 12)
	_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_mid)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cell(grid, "stat_progress", tr("ending.stage"), tr("stage." + state.stage))
	_cell(grid, "stat_year", tr("ending.years"), str(state.year))
	_cell(grid, "stat_funding", tr("ending.funding"), str(state.funding))
	_cell(grid, "stat_efficacy", tr("ending.efficacy"), str(state.efficacy))
	_cell(grid, "stat_safety", tr("ending.safety"), str(state.safety_risk))
	_cell(grid, "stat_data", tr("ending.data"), str(state.data))
	_mid.add_child(grid)
	_mid.add_child(HSeparator.new())

	var settle := tr("ui.run_summary") % [summary.data_saved, summary.level_before, summary.level_after]
	if int(summary.funding_carry) > 0:
		settle += tr("ui.run_carry") % summary.funding_carry
	var settle_label := UIKit.label(settle, UIKit.ACCENT_BLUE, 15, true)
	settle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settle_label.custom_minimum_size = Vector2(560, 0)
	_mid.add_child(settle_label)
	if int(summary.get("patients", 0)) > 0:
		# 这一代药物帮助的患者；疾病被攻克（战役结局）或进化出耐药（下一代要重新设计）
		var lines: Array[String] = [tr("ending.patients") % [Company.format_people(int(summary.patients)),
			Company.format_people(int(summary.get("patients_total", 0)))]]
		var disease_name := tr("disease." + String(summary.get("disease", "")))
		if not campaign.is_empty() and outcome == "approved":
			lines.append(tr("ending.conquered") % disease_name)
		elif not String(summary.get("next_variant", "")).is_empty():
			lines.append(tr("ending.resistance") % tr("variant." + String(summary.next_variant)))
		var mission := UIKit.label("\n".join(lines), Color(0.82, 0.72, 1.0), 15, true)
		mission.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mission.custom_minimum_size = Vector2(560, 0)
		_mid.add_child(mission)
		var strip := ArchivePanel.lineage_strip(summary.get("lineage", []))
		strip.alignment = BoxContainer.ALIGNMENT_CENTER
		_mid.add_child(strip)
	if int(summary.level_after) > int(summary.level_before):
		var up := UIKit.header(tr("ending.level_up") % summary.level_after, 18, UIKit.GOLD)
		up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_mid.add_child(up)
	_add_evidence(summary)
	if not campaign.is_empty():
		_add_chain(String(summary.get("route", "")), summary.get("decisions", []))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var again := UIKit.button(tr("ending.again"), "ui_play", "primary", Vector2(200, 50))
	again.pressed.connect(func() -> void: restart_requested.emit())
	var title_btn := UIKit.button(tr("ending.to_title"), "ui_back", "normal", Vector2(200, 50))
	title_btn.pressed.connect(func() -> void: SceneRouter.goto(SceneRouter.TITLE))
	row.add_child(again)
	row.add_child(title_btn)
	_box.add_child(row)

	visible = true
	modulate.a = 0.0
	_fit_scroll()
	_fit_scroll.call_deferred()   # 自动换行的文字要排版一帧后高度才准
	_panel.pivot_offset = _panel.get_combined_minimum_size() * 0.5
	_panel.scale = Vector2(0.9, 0.9)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.4)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 中间区域尽量完整显示；整个面板会超出窗口时，只让中间区域滚动
func _fit_scroll() -> void:
	_scroll.custom_minimum_size.y = 0
	var content := _mid.get_combined_minimum_size().y
	var without := _panel.get_combined_minimum_size().y
	var room := get_viewport_rect().size.y - 24.0 - without
	_scroll.custom_minimum_size.y = clampf(room, 120.0, content)


## 研究证据与本局统计；还没解锁 LM-001 时显示进度
func _add_evidence(summary: Dictionary) -> void:
	var company := Company.new()
	company.load_save()
	var lines: Array = []   # [文字, 颜色]
	var evidence := String(summary.get("evidence", ""))
	if not evidence.is_empty():
		var fresh := bool(summary.get("evidence_new", false))
		lines.append([tr("ending.evidence_new" if fresh else "ending.evidence_have") % tr("evidence." + evidence), UIKit.ACCENT_BLUE if fresh else UIKit.TEXT_DIM])
	if String(summary.get("campaign_ending", "")).is_empty():
		var need := int(ProjectTypes.config().get("final_unlock_evidence", 2))
		lines.append([tr("ending.final_unlocked") % need, UIKit.GOLD] if company.final_unlocked() \
			else [tr("ending.final_progress") % [company.evidence.size(), need], UIKit.TEXT_DIM])
	var stats: Dictionary = company.history[0].get("stats", {}) if not company.history.is_empty() else {}
	if int(stats.get("attacks", 0)) > 0:
		lines.append([tr("ending.stats") % [int(stats.attacks), int(stats.get("precise", 0)), int(stats.get("backfires", 0))], UIKit.TEXT_DIM])
	for line in lines:
		var label := UIKit.label(String(line[0]), line[1], 15, true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(560, 0)
		_mid.add_child(label)


## 主线结局的因果链：每项证据来自哪个项目、那次做过的决策，以及本次 LM-001 的路线与决策
func _add_chain(run_route: String, run_decisions: Array) -> void:
	var company := Company.new()
	company.load_save()
	_mid.add_child(HSeparator.new())
	var head := UIKit.header(tr("ending.chain_title"), 18, UIKit.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mid.add_child(head)
	for line in chain_lines(company, run_route, run_decisions):
		var label := UIKit.label(line, UIKit.TEXT, 15, true)
		label.custom_minimum_size = Vector2(560, 0)
		_mid.add_child(label)


## run_route / run_decisions 是本次 LM-001 的路线与决策（重复通关时以本次为准）；
## 本次路线用到的那项证据标上「★」
static func chain_lines(company: Company, run_route: String, run_decisions: Array) -> Array[String]:
	var used := ""
	for r in ProjectTypes.find("final").get("routes", []):
		if String(r.get("id", "")) == run_route:
			used = String(r.get("requires", ""))
	var t := TranslationServer
	var lines: Array[String] = []
	var ids: Array = company.evidence.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(company.evidence[a].get("run", 0)) < int(company.evidence[b].get("run", 0)))
	for id in ids:
		var src: Dictionary = company.evidence[id]
		lines.append(("★ " if String(id) == used else "") + t.translate("chain.evidence") % [String(src.get("code", "")),
			t.translate("project.type." + String(src.get("project_type", ""))),
			t.translate("ending." + String(src.get("outcome", ""))), t.translate("evidence." + String(id))])
		for d in src.get("decisions", []):
			if not String(d).begins_with("route:"):
				lines.append(t.translate("chain.decision") % t.translate("milestone.opt." + String(d)))
	if not run_route.is_empty():
		lines.append(t.translate("chain.route") % t.translate("route." + run_route))
	for d in run_decisions:
		if not String(d).begins_with("route:"):
			lines.append(t.translate("chain.final_decision") % t.translate("milestone.opt." + String(d)))
	return lines


## 结局主角标本展台：把玩家一路进化到终态的分子放进纪念框里
func _molecule_showcase(molecule: Molecule, mol_form: int, outcome: String, accent: Color) -> Control:
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(216, 134)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(func() -> void:
		var area := Rect2(Vector2.ZERO, frame.size)
		var bg := PaintedStyle.new()
		bg.surface_kind = 3
		bg.bg_color = Color(0.055, 0.072, 0.125, 0.96)
		bg.border_color = Color(accent, 0.65)
		bg.draw(frame.get_canvas_item(), area)
		var c := Vector2(frame.size.x * 0.5, frame.size.y * 0.52)
		Shading.glow(frame, c, frame.size.x * 0.44, Color(accent, 0.24 if outcome == "approved" else 0.14))
		# 纪念台座底面与脚影
		var foot_y := frame.size.y - 16.0
		var dais := PackedVector2Array([
			Vector2(c.x - 62, foot_y - 4), Vector2(c.x + 62, foot_y - 4),
			Vector2(c.x + 76, foot_y + 5), Vector2(c.x - 76, foot_y + 5)])
		frame.draw_colored_polygon(dais, Color(0.11, 0.14, 0.22, 0.9))
		frame.draw_line(dais[0], dais[1], Color(UIKit.PAPER, 0.35), 1.2, true)
		var shadow := PackedVector2Array()
		for i in 18:
			var a := i * TAU / 18.0
			shadow.append(Vector2(c.x + cos(a) * 46.0, foot_y - 2.0 + sin(a) * 3.5))
		frame.draw_colored_polygon(shadow, Color(0.015, 0.02, 0.05, 0.55))
		UIKit.inset(frame, area.grow(-2.0), 8.0))
	var view := MoleculeView.new()
	view.character = true
	view.form = clampi(mol_form, 1, 5)
	view.set_molecule(molecule)
	view.position = Vector2(8, 12)
	view.size = Vector2(200, 108)
	if outcome == "approved":
		view.cheer()
	elif outcome != "approved":
		view.modulate = Color(0.76, 0.74, 0.82)
	frame.add_child(view)
	return frame


func _cell(grid: GridContainer, icon_name: String, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIKit.icon_rect(icon_name, 22, UIKit.TEXT_DIM))
	row.add_child(UIKit.label(key, UIKit.TEXT_DIM, 14))
	row.add_child(UIKit.header(value, 17))
	grid.add_child(row)
