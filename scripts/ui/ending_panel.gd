class_name EndingPanel
extends Control
## 一局结束的结局画面：结局图标与标题、原因、项目数据、公司结算，以及「再来一局 / 返回标题」。

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
	var icon := UIKit.icon_rect("outcome_" + outcome, 84, color)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(icon)
	var title := UIKit.header(tr("ending." + outcome + ".title"), 36, color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	var reason := UIKit.label(tr(reason_key), UIKit.TEXT, 16, true)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason.custom_minimum_size = Vector2(560, 0)
	_box.add_child(reason)
	var flavor := UIKit.label(tr("ending." + outcome + ".flavor"), UIKit.TEXT_DIM, 14, true)
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


func _cell(grid: GridContainer, icon_name: String, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIKit.icon_rect(icon_name, 22, UIKit.TEXT_DIM))
	row.add_child(UIKit.label(key, UIKit.TEXT_DIM, 14))
	row.add_child(UIKit.header(value, 17))
	grid.add_child(row)
