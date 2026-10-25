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


## state 为 ProjectState；summary 为 Company.settle_run 的返回值
func show_ending(outcome: String, reason_key: String, summary: Dictionary, state: ProjectState) -> void:
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
	var icon := UIKit.icon_rect("logo" if not campaign.is_empty() else "outcome_" + outcome, 84, color)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(icon)
	if not campaign.is_empty():
		var badge := UIKit.label(tr("campaign.badge"), UIKit.GOLD, 15)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(badge)
	var title := UIKit.header(tr("campaign.%s.title" % campaign) if not campaign.is_empty() else tr("ending." + outcome + ".title"), 36, color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	var reason := UIKit.label(tr(reason_key), UIKit.TEXT, 16, true)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason.custom_minimum_size = Vector2(560, 0)
	_box.add_child(reason)
	var flavor := UIKit.label(tr("campaign.%s.flavor" % campaign) if not campaign.is_empty() else tr("ending." + outcome + ".flavor"),
		UIKit.TEXT if not campaign.is_empty() else UIKit.TEXT_DIM, 14 if campaign.is_empty() else 16, true)
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.custom_minimum_size = Vector2(560, 0)
	_box.add_child(flavor)
	_box.add_child(HSeparator.new())

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
	_box.add_child(grid)
	_box.add_child(HSeparator.new())

	var settle := tr("ui.run_summary") % [summary.data_saved, summary.level_before, summary.level_after]
	if int(summary.funding_carry) > 0:
		settle += tr("ui.run_carry") % summary.funding_carry
	var settle_label := UIKit.label(settle, UIKit.ACCENT_BLUE, 15, true)
	settle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settle_label.custom_minimum_size = Vector2(560, 0)
	_box.add_child(settle_label)
	if int(summary.level_after) > int(summary.level_before):
		var up := UIKit.header(tr("ending.level_up") % summary.level_after, 18, UIKit.GOLD)
		up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(up)
	_add_evidence(summary)
	if not campaign.is_empty():
		_add_chain()

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
	_panel.pivot_offset = _panel.get_combined_minimum_size() * 0.5
	_panel.scale = Vector2(0.9, 0.9)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.4)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
		_box.add_child(label)


## 主线结局的因果链：每项证据来自哪个项目、那次做过的决策，以及 LM-001 选的路线
func _add_chain() -> void:
	var company := Company.new()
	company.load_save()
	_box.add_child(HSeparator.new())
	var head := UIKit.header(tr("ending.chain_title"), 18, UIKit.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(head)
	for line in chain_lines(company):
		var label := UIKit.label(line, UIKit.TEXT, 15, true)
		label.custom_minimum_size = Vector2(560, 0)
		_box.add_child(label)


static func chain_lines(company: Company) -> Array[String]:
	var t := TranslationServer
	var lines: Array[String] = []
	var ids: Array = company.evidence.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(company.evidence[a].get("run", 0)) < int(company.evidence[b].get("run", 0)))
	for id in ids:
		var src: Dictionary = company.evidence[id]
		lines.append(t.translate("chain.evidence") % [String(src.get("code", "")), t.translate("project.type." + String(src.get("project_type", ""))),
			t.translate("ending." + String(src.get("outcome", ""))), t.translate("evidence." + String(id))])
		for d in src.get("decisions", []):
			if not String(d).begins_with("route:"):
				lines.append(t.translate("chain.decision") % t.translate("milestone.opt." + String(d)))
	var route := String(company.campaign.get("route", ""))
	if not route.is_empty():
		lines.append(t.translate("chain.route") % t.translate("route." + route))
	return lines


func _cell(grid: GridContainer, icon_name: String, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIKit.icon_rect(icon_name, 22, UIKit.TEXT_DIM))
	row.add_child(UIKit.label(key, UIKit.TEXT_DIM, 14))
	row.add_child(UIKit.header(value, 17))
	grid.add_child(row)
