class_name ArchivePanel
extends ModalPanel
## 公司档案：跨局积累的数据、流程等级、开局 AI 档位与最近项目记录。

var _body: VBoxContainer


func _init() -> void:
	super._init()
	title_key = "archive.title"
	panel_width = 820


func _build(box: VBoxContainer) -> void:
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	box.add_child(_body)


func _refresh() -> void:
	for child in _body.get_children():
		child.queue_free()
	var company := Company.new()
	company.load_save()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var rate := 0 if company.runs == 0 else roundi(100.0 * company.approvals / company.runs)
	grid.add_child(_stat("ui_archive", tr("archive.runs"), str(company.runs), UIKit.TEXT))
	grid.add_child(_stat("outcome_approved", tr("archive.approvals"), "%d (%d%%)" % [company.approvals, rate], UIKit.ACCENT))
	grid.add_child(_stat("stat_year", tr("archive.best"), tr("archive.best_value") % company.best_years if company.best_years > 0 else "—", UIKit.GOLD))
	grid.add_child(_stat("stat_data", tr("archive.data"), str(company.data), UIKit.ACCENT_BLUE))
	_body.add_child(grid)

	var level := company.process_level()
	var next := company.next_level_threshold()
	var level_box := VBoxContainer.new()
	level_box.add_child(UIKit.label(tr("archive.level") % level + ("" if next < 0 else tr("archive.level_next") % [company.data, next]), UIKit.TEXT, 16))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 18)
	bar.show_percentage = false
	bar.max_value = maxf(next, 1) if next > 0 else 1
	bar.value = company.data if next > 0 else 1
	level_box.add_child(bar)
	var tier := company.tier_for(company.effective_data(0, 0))
	level_box.add_child(UIKit.label(tr("archive.ai_start") % [company.effective_data(0, 0), tr("tier." + String(tier.id)), int(tier.deviation)],
		UIKit.ACCENT_BLUE, 14, true))
	if company.start_funding_bonus > 0:
		level_box.add_child(UIKit.label(tr("ui.run_carry").strip_edges() % company.start_funding_bonus, UIKit.GOLD, 14))
	_body.add_child(level_box)

	_body.add_child(HSeparator.new())
	_body.add_child(UIKit.header(tr("archive.history"), 18))
	if company.history.is_empty():
		_body.add_child(UIKit.label(tr("archive.empty"), UIKit.TEXT_DIM, 15, true))
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for entry in company.history:
		list.add_child(_history_row(entry))
	_body.add_child(scroll)


func _stat(icon_name: String, key: String, value: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 0)
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.1, 0.13, 0.17, 0.9), Color(color, 0.35), 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UIKit.icon_rect(icon_name, 30, color))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.add_child(UIKit.label(key, UIKit.TEXT_DIM, 13))
	col.add_child(UIKit.header(value, 20, color))
	row.add_child(col)
	panel.add_child(row)
	return panel


func _history_row(entry: Dictionary) -> HBoxContainer:
	var outcome := String(entry.get("outcome", "failed"))
	var color: Color = {"approved": UIKit.ACCENT, "terminated": UIKit.GOLD}.get(outcome, UIKit.DANGER)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UIKit.icon_rect("outcome_" + outcome, 22, color))
	var code := String(entry.get("project_code", ""))
	var run_name := tr("project.title") % [code, tr("project.type." + String(entry.get("project_type", "standard")))] \
		if not code.is_empty() else tr("archive.run_no") % int(entry.get("index", 0))
	row.add_child(UIKit.label(run_name, UIKit.TEXT_DIM, 14))
	var outcome_label := UIKit.label(tr("ending." + outcome), color, 15)
	outcome_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(outcome_label)
	var detail := UIKit.label(tr("archive.run_detail") % [tr("stage." + String(entry.get("stage", ""))), int(entry.get("year", 0)),
		int(entry.get("efficacy", 0)), int(entry.get("safety_risk", 0)), int(entry.get("data_saved", 0))], UIKit.TEXT, 14)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	return row
