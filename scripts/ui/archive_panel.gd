class_name ArchivePanel
extends ModalPanel
## 公司档案：左栏是公司的「身份卡」（随获批进化的烧瓶、流程等级环、下个项目的开局 AI），
## 右栏依次是四个关键数字、研究证据勋章（已获得 / 未获得）与主线进度、公司使命与分子谱系、最近项目时间线。

const EVIDENCE := ["foundation", "selectivity", "long_safety"]
const OUTCOME_COLOR := {"approved": Color(0.31, 0.78, 0.56), "terminated": Color(0.95, 0.8, 0.4), "failed": Color(0.93, 0.42, 0.42)}

var _body: HBoxContainer


func _init() -> void:
	super._init()
	title_key = "archive.title"
	subtitle_key = "archive.subtitle"
	icon_name = "ui_archive"
	accent = UIKit.ACCENT_BLUE
	panel_width = 940


func _build(box: VBoxContainer) -> void:
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	box.add_child(_body)


func _refresh() -> void:
	for child in _body.get_children():
		child.queue_free()
	var company := Company.new()
	company.load_save()
	_body.add_child(_identity(company))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	_body.add_child(right)
	right.add_child(_stats_row(company))
	right.add_child(_section("archive.evidence", "outcome_approved"))
	right.add_child(_evidence_row(company))
	right.add_child(_campaign_line(company))
	right.add_child(_section("archive.lineage", "type_molecular"))
	right.add_child(_mission_line(company))
	if not company.lineage.is_empty():
		right.add_child(lineage_strip(company.lineage))
	right.add_child(_section("archive.history", "stat_year"))
	right.add_child(_timeline(company))


## 左栏身份卡：烧瓶形象（1 + 获批数级）、流程等级环形进度、开局 AI 档位
func _identity(company: Company) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 0)
	var sb := UIKit.panel_style(Color(0.05, 0.08, 0.11, 0.9), Color(accent, 0.3), 14)
	sb.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	var avatar := PlayerAvatar.new()
	col.add_child(avatar)
	avatar.custom_minimum_size = Vector2(200, 150)   # 高一些的形态带铁架台和机械臂，按高度缩放以免超出卡片
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar.form = 1 + company.approvals
	var level := company.process_level()
	var next := company.next_level_threshold()
	var ring := Control.new()
	ring.custom_minimum_size = Vector2(0, 96)
	var ratio := 1.0 if next < 0 else clampf(float(company.data) / maxf(next, 1.0), 0.0, 1.0)
	ring.draw.connect(func() -> void:
		var c := Vector2(ring.size.x * 0.5, 48)
		ring.draw_arc(c, 40, 0, TAU, 64, Color(0.2, 0.26, 0.32), 8.0, true)
		ring.draw_arc(c, 40, -PI / 2, -PI / 2 + TAU * ratio, 64, UIKit.ACCENT, 8.0, true)
		var font := ring.get_theme_default_font()
		var text := "Lv%d" % level
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		ring.draw_string(font, c + Vector2(-w * 0.5, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.92, 0.98, 0.95)))
	col.add_child(ring)
	var level_text := UIKit.label(tr("archive.level_short") + (tr("archive.level_next") % [company.data, next] if next > 0 else ""), UIKit.TEXT_DIM, 13, true)
	level_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(level_text)
	var tier := company.tier_for(company.effective_data(0, 0))
	var ai := UIKit.label(tr("archive.ai_short") % [tr("tier." + String(tier.id)), int(tier.deviation)], UIKit.ACCENT_BLUE, 14, true)
	ai.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ai.tooltip_text = tr("archive.ai_start") % [company.effective_data(0, 0), tr("tier." + String(tier.id)), int(tier.deviation)]
	ai.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(ai)
	if company.start_funding_bonus > 0:
		var carry := UIKit.label(tr("ui.run_carry").strip_edges() % company.start_funding_bonus, UIKit.GOLD, 13, true)
		carry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(carry)
	return card


## 四个关键数字：大号数字 + 小标签，竖线分隔
func _stats_row(company: Company) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var rate := 0 if company.runs == 0 else roundi(100.0 * company.approvals / company.runs)
	var stats := [
		[str(company.runs), tr("archive.runs_short"), UIKit.TEXT],
		[str(company.approvals), tr("archive.approved_short") % rate, UIKit.ACCENT],
		[tr("archive.best_value") % company.best_years if company.best_years > 0 else "—", tr("archive.best"), UIKit.GOLD],
		[str(company.data), tr("archive.data"), UIKit.ACCENT_BLUE],
	]
	for i in stats.size():
		if i > 0:
			var sep := ColorRect.new()
			sep.color = Color(0.3, 0.38, 0.45, 0.4)
			sep.custom_minimum_size = Vector2(1, 46)
			row.add_child(sep)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		var big := UIKit.header(String(stats[i][0]), 30, stats[i][2])
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(big)
		var small := UIKit.label(String(stats[i][1]), UIKit.TEXT_DIM, 13)
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(small)
		row.add_child(col)
	return row


## 小节标题：强调色短竖条 + 图标 + 文字
func _section(key: String, icon: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(UIKit.icon_rect(icon, 18, accent.lightened(0.2)))
	row.add_child(UIKit.header(tr(key), 17))
	return row


## 研究证据勋章：已获得的发光并写来源，未获得的灰色带问号
func _evidence_row(company: Company) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for id in EVIDENCE:
		var got := company.has_evidence(id)
		var color: Color = {"foundation": UIKit.ACCENT, "selectivity": Color(0.75, 0.55, 1.0), "long_safety": UIKit.ACCENT_BLUE}[id]
		var medal := PanelContainer.new()
		medal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := UIKit.panel_style(Color(color, 0.12) if got else Color(0.08, 0.1, 0.13, 0.8), Color(color, 0.7) if got else Color(0.3, 0.34, 0.4, 0.4), 12)
		sb.set_content_margin_all(10)
		medal.add_theme_stylebox_override("panel", sb)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		medal.add_child(line)
		var hex := Control.new()
		hex.custom_minimum_size = Vector2(34, 34)
		hex.draw.connect(func() -> void:
			var c := hex.size * 0.5
			var pts := PackedVector2Array()
			for k in 7:
				var a := PI / 6 + k * TAU / 6
				pts.append(c + Vector2(cos(a), sin(a)) * 16)
			hex.draw_colored_polygon(pts, Color(color, 0.35) if got else Color(0.2, 0.22, 0.26))
			hex.draw_polyline(pts, color if got else Color(0.4, 0.44, 0.5), 2.0, true)
			var font := hex.get_theme_default_font()
			var mark := "✓" if got else "?"
			hex.draw_string(font, c + Vector2(-6, 7), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE if got else Color(0.55, 0.6, 0.66)))
		line.add_child(hex)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.add_child(UIKit.label(tr("evidence." + id), color.lightened(0.2) if got else UIKit.TEXT_DIM, 14))
		var src: Dictionary = company.evidence.get(id, {})
		text.add_child(UIKit.label(String(src.get("code", "")) + " · " + tr("ending." + String(src.get("outcome", ""))) if got else tr("archive.evidence_locked"),
			UIKit.TEXT_DIM, 12))
		line.add_child(text)
		row.add_child(medal)
	return row


func _campaign_line(company: Company) -> Control:
	var need := int(ProjectTypes.config().get("final_unlock_evidence", 2))
	var text: String
	if company.is_campaign_done():
		text = tr("archive.campaign_done") % tr("campaign.%s.title" % String(company.campaign.get("ending", "")))
	elif company.final_unlocked():
		text = tr("ending.final_unlocked") % need
	else:
		text = tr("ending.final_progress") % [company.evidence.size(), need]
	return UIKit.label("◆ " + text, UIKit.GOLD, 14, true)


func _mission_line(company: Company) -> Control:
	if company.disease.is_empty():
		return UIKit.label(tr("archive.mission_none"), UIKit.TEXT_DIM, 14, true)
	var text := tr("archive.mission") % [tr("disease." + company.disease), Company.format_people(company.patients)]
	if company.lineage.is_empty():
		text += "\n" + tr("archive.lineage_empty")
	return UIKit.label(text, Color(0.82, 0.72, 1.0), 14, true)


## 分子谱系：每一代获批分子的小结构图，下面写第几代、面对的靶点变体、编号与帮助的患者（最近 max_items 代）
static func lineage_strip(lineage: Array, max_items := 5) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for i in range(maxi(0, lineage.size() - max_items), lineage.size()):
		var entry: Dictionary = lineage[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		var view := MoleculeView.new()
		view.compact = true
		view.custom_minimum_size = Vector2(124, 70)
		var m := Molecule.new()
		for k in entry.get("sites", {}):
			m.sites[String(k)] = String(entry.sites[k])
		view.molecule = m
		col.add_child(view)
		var vid := Molecule.variant_id(String(entry.get("disease", "")), int(entry.get("variant", 0)))
		var head := UIKit.label(TranslationServer.translate("archive.gen") % [i + 1, TranslationServer.translate("variant." + vid)],
			Color(0.82, 0.72, 1.0), 12)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		var detail := UIKit.label(TranslationServer.translate("archive.gen_detail") % [String(entry.get("code", "")),
			Company.format_people(int(entry.get("patients", 0)))], UIKit.TEXT_DIM, 11)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(detail)
		row.add_child(col)
	return row


## 最近项目时间线：左侧竖线串起结果色圆点，每项是「编号 · 类型 + 结果胶囊」和一行数据
func _timeline(company: Company) -> Control:
	if company.history.is_empty():
		return UIKit.label(tr("archive.empty"), UIKit.TEXT_DIM, 14, true)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)
	for i in company.history.size():
		list.add_child(_history_row(company.history[i], i == 0, i == company.history.size() - 1))
	return scroll


func _history_row(entry: Dictionary, first: bool, last: bool) -> Control:
	var outcome := String(entry.get("outcome", "failed"))
	var color: Color = OUTCOME_COLOR.get(outcome, OUTCOME_COLOR.failed)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var rail := Control.new()
	rail.custom_minimum_size = Vector2(24, 52)
	rail.draw.connect(func() -> void:
		var x := 12.0
		var mid := rail.size.y * 0.5
		if not first:
			rail.draw_line(Vector2(x, 0), Vector2(x, mid), Color(0.3, 0.38, 0.45, 0.6), 2.0)
		if not last:
			rail.draw_line(Vector2(x, mid), Vector2(x, rail.size.y), Color(0.3, 0.38, 0.45, 0.6), 2.0)
		rail.draw_circle(Vector2(x, mid), 7, Color(0.05, 0.07, 0.1))
		rail.draw_circle(Vector2(x, mid), 5, color))
	row.add_child(rail)
	var code := String(entry.get("project_code", ""))
	var run_name := tr("project.title") % [code, tr("project.type." + String(entry.get("project_type", "standard")))] \
		if not code.is_empty() else tr("archive.run_no") % int(entry.get("index", 0))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(UIKit.header(run_name, 15))
	var pill := PanelContainer.new()
	var psb := UIKit.filled(Color(color, 0.16), Color(color, 0.6), 8)
	psb.content_margin_left = 8
	psb.content_margin_right = 8
	pill.add_theme_stylebox_override("panel", psb)
	pill.add_child(UIKit.label(tr("ending." + outcome), color.lightened(0.2), 12))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pill)
	col.add_child(top)
	col.add_child(UIKit.label(tr("archive.run_detail") % [tr("stage." + String(entry.get("stage", ""))), int(entry.get("year", 0)),
		int(entry.get("efficacy", 0)), int(entry.get("safety_risk", 0)), int(entry.get("data_saved", 0))], UIKit.TEXT_DIM, 13))
	row.add_child(col)
	return row
