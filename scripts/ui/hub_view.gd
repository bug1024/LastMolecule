class_name HubView
extends Control
## 研发总览的观察室：世界背景由 MoleculeBackground 的 lab 模式画，这里画分子脚下的观察台。
##   主体：候选分子悬浮在观察台的光柱里，是整屏最大的东西；
##   左上：RPG 式状态栏（生命条 + 资金 / 年份 / 疗效 / 前期研究）；
##   右上：AI / 研发能力 / 竞争格局三张可展开卡片，默认只显示一行摘要；
##   实验台正面：团队铭牌、消息条、「进入研发地图 / 查看牌库」按钮。
## 只负责展示；rd_ui 调 refresh(game) 刷新，并用这里的控件做飘字锚点。

var stage_label: Label
var molecule_art: MoleculeArt
var mol_view: MoleculeView        # 设计了分子的项目：显示玩家自己的分子结构（代替装饰分子）
var _mol_line: Label
var _exam_line: Label   # 本阶段 Boss 的分子考验：通过 / 未通过
var avatar: PlayerAvatar
var hp_label: Label
var hp_bar: ProgressBar
var funding_label: Label
var year_label: Label
var efficacy_label: Label
var efficacy_bar: ProgressBar
var progress_label: Label
var progress_bar: ProgressBar
var event_label: Label
var advance_button: Button
var challenge_button: Button
var goal_card: InfoCard
var ai_card: InfoCard
var abilities_card: InfoCard
var competition_card: InfoCard

var _team_label: Label
var _xp_bar: ProgressBar
var _bonus_label: Label
var _status_panel: PanelContainer
var _cards: VBoxContainer
var _bench_panel: Control
var _tint := Color(0.35, 0.28, 0.6)
var _time := 0.0
var _stage_index := 0
var _growth := 0.0
var _target_growth := 0.0
var _scan := 0.0
var _project_code := ""
var _observed_sites := {}

const BENCH_FROM_BOTTOM := 176.0
const STATUS_W := 330.0
const CARDS_W := 300.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_build()
	resized.connect(_layout)


func _build() -> void:
	stage_label = UIKit.header("", 28, Color(0.75, 0.95, 1.0))
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.add_theme_constant_override("outline_size", 8)
	stage_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(stage_label)

	molecule_art = MoleculeArt.new()
	add_child(molecule_art)
	mol_view = MoleculeView.new()
	mol_view.character = true
	mol_view.visible = false
	add_child(mol_view)
	_mol_line = UIKit.label("", Color(0.82, 0.75, 1.0), 14)
	_mol_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mol_line.add_theme_constant_override("outline_size", 5)
	_mol_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_mol_line)
	_exam_line = UIKit.label("", UIKit.ACCENT, 14)
	_exam_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exam_line.add_theme_constant_override("outline_size", 5)
	_exam_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_exam_line)
	avatar = PlayerAvatar.new()
	add_child(avatar)
	avatar.custom_minimum_size = Vector2(170, 204)

	_status_panel = _glass_panel()
	add_child(_status_panel)
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 6)
	_status_panel.add_child(status)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	hp_row.tooltip_text = tr("ui.hp_tip")
	hp_row.mouse_filter = Control.MOUSE_FILTER_PASS
	hp_row.add_child(UIKit.icon_rect("ui_heart", 22, UIKit.DANGER))
	hp_bar = _bar(170, 16)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(hp_bar)
	hp_label = UIKit.header("", 17)
	hp_row.add_child(hp_label)
	status.add_child(hp_row)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	status.add_child(grid)
	funding_label = _chip(grid, "stat_funding", UIKit.GOLD, "")
	year_label = _chip(grid, "stat_year", UIKit.TEXT, "")
	var eff := _bar_chip(grid, "stat_efficacy", UIKit.ACCENT)
	efficacy_label = eff[0]
	efficacy_bar = eff[1]
	var prog := _bar_chip(grid, "stat_progress", UIKit.ACCENT_BLUE)
	progress_label = prog[0]
	progress_bar = prog[1]

	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 6)
	add_child(_cards)
	goal_card = InfoCard.new("outcome_approved", "goal.title", UIKit.ACCENT)
	goal_card.pin()
	_cards.add_child(goal_card)
	ai_card = InfoCard.new("type_ai", "ui.hub_ai", UIKit.ACCENT_BLUE)
	abilities_card = InfoCard.new("role_power", "ui.hub_abilities", Color(0.75, 0.55, 1.0))
	competition_card = InfoCard.new("node_event", "ui.competition_title", UIKit.GOLD)
	for card in [ai_card, abilities_card, competition_card]:
		_cards.add_child(card)

	# 实验台正面：左边团队铭牌，中间消息，下面按钮
	_bench_panel = Control.new()
	_bench_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_bench_panel)
	var plate := VBoxContainer.new()
	plate.name = "Plate"
	plate.add_theme_constant_override("separation", 3)
	_bench_panel.add_child(plate)
	_team_label = UIKit.header("", 15, PlayerAvatar.GREEN)
	plate.add_child(_team_label)
	_xp_bar = _bar(200, 10)
	plate.add_child(_xp_bar)
	_bonus_label = UIKit.label("", UIKit.TEXT_DIM, 12, true)
	_bonus_label.custom_minimum_size = Vector2(220, 0)
	plate.add_child(_bonus_label)
	# 消息条：放进 CenterContainer，由容器按最小尺寸居中排版（自动换行的 Label 自己定尺寸不可靠）
	var msg := CenterContainer.new()
	msg.name = "Message"
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bench_panel.add_child(msg)
	event_label = UIKit.label("", UIKit.TEXT, 15, true)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_child(event_label)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_bench_panel.add_child(buttons)
	advance_button = UIKit.button(tr("ui.enter_map"), "node_research", "primary", Vector2(260, 52))
	advance_button.add_theme_font_size_override("font_size", 20)
	advance_button.set_meta("sfx", "open")
	buttons.add_child(advance_button)
	challenge_button = UIKit.button(tr("ui.view_deck"), "ui_deck", "normal", Vector2(170, 52))
	challenge_button.add_theme_font_size_override("font_size", 17)
	buttons.add_child(challenge_button)


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w < 600 or h < 300:
		return   # 尚未排版到真实尺寸：零宽度时自动换行文字会撑出很高的最小尺寸，之后缩不回来
	var bench_y := h - BENCH_FROM_BOTTOM
	stage_label.position = Vector2(STATUS_W + 20, 14)
	stage_label.size = Vector2(w - STATUS_W - CARDS_W - 40, 40)
	_status_panel.position = Vector2(14, 14)
	_status_panel.size = Vector2(STATUS_W, 0)
	_cards.position = Vector2(w - CARDS_W - 14, 14)
	_cards.size = Vector2(CARDS_W, 0)
	avatar.size = avatar.custom_minimum_size
	avatar.position = Vector2(w * 0.3 - avatar.size.x * 0.5, bench_y - avatar.size.y + 12)
	var mol := Vector2(minf(300, w * 0.26), minf(240, bench_y - 70))
	molecule_art.size = mol
	molecule_art.position = Vector2(w * 0.56 - mol.x * 0.5, bench_y - 58 - mol.y)
	mol_view.size = Vector2(minf(570, w - STATUS_W - CARDS_W - 60), bench_y - 62)
	mol_view.position = Vector2((STATUS_W + w - CARDS_W) * 0.5 - mol_view.size.x * 0.5, 68)
	_mol_line.position = Vector2(STATUS_W + 20, 50)
	_mol_line.size = Vector2(w - STATUS_W - CARDS_W - 40, 22)
	_exam_line.size = Vector2(460, 22)
	_exam_line.position = Vector2((STATUS_W + w - CARDS_W) * 0.5 - 230, bench_y - 1)   # 写在观察台下方
	_bench_panel.position = Vector2(0, bench_y + 14)
	_bench_panel.size = Vector2(w, h - bench_y - 14)
	var plate: Control = _bench_panel.get_node("Plate")
	plate.position = Vector2(w * 0.3 - 110, 6)
	plate.size = Vector2(220, 0)
	var msg_w := (w - CARDS_W - 28) - (w * 0.3 + 130)   # 右侧卡片列可能伸到台面，消息不压到它
	var msg: Control = _bench_panel.get_node("Message")
	event_label.custom_minimum_size = Vector2(msg_w, 0)
	msg.position = Vector2(w * 0.3 + 130, 4)
	# 文字最小高度要等定宽后下一帧才更新；立即设尺寸会被旧的（零宽度时的）最小高度撑大
	msg.set_deferred("size", Vector2(msg_w, 64))
	var buttons: Control = _bench_panel.get_node("Buttons")
	buttons.size = Vector2(w, 52)
	buttons.position = Vector2(0, _bench_panel.size.y - 64)
	queue_redraw()


## 终审目标卡：每个条件一行，达标打勾、不达标写差多少；标题后汇总「n/m 达标」
static func fill_goal_card(card: InfoCard, items: Array) -> void:
	var t := TranslationServer
	var lines: Array[String] = []
	var met := 0
	for item in items:
		var ok := bool(item.ok)
		met += 1 if ok else 0
		var need := ("< %d" % int(item.need)) if item.id == "safety" else str(int(item.need))
		var mark := "[color=#5ad99a]✓[/color]" if ok else "[color=#ff8a80]%s[/color]" % (t.translate("goal.gap") % int(item.gap))
		lines.append("%s　[b]%d[/b] / %s　%s" % [t.translate("goal." + String(item.id)), int(item.current), need, mark])
	card.set_title_suffix(t.translate("goal.summary") % [met, items.size()])
	card.set_content("", "\n".join(lines))


## 状态全部从 game 读：rd_ui 在状态同步时调用（竞争格局的摘要与全文由地图界面生成后传入）
func refresh(game, competition_summary: String, competition_text: String) -> void:
	var state: ProjectState = game.get_state()
	stage_label.text = tr("stage." + state.stage)
	_tint = BattleView.STAGE_TINT.get(state.stage, Color(0.2, 0.5, 0.5))
	var stages: Array = game.get_stages()
	var new_stage := maxi(stages.find(state.stage), 0)
	var same_project: bool = _project_code == game.project_code
	var mol: Molecule = game.molecule
	var sites: Dictionary = mol.sites if mol != null else {}
	_target_growth = clampf((new_stage + minf(1.0, float(state.research_progress) / maxf(1, game.get_progress_gate()))) / 5.0, 0.0, 1.0)
	if not same_project:
		_growth = _target_growth
		_scan = 0.0
	elif new_stage != _stage_index or sites != _observed_sites:
		_scan = 1.0
	_stage_index = new_stage
	_project_code = game.project_code
	_observed_sites = sites.duplicate()
	molecule_art.stage_index = _stage_index
	molecule_art.visible = mol == null
	mol_view.visible = mol != null
	_mol_line.visible = mol != null
	if mol != null:
		mol_view.set_molecule(mol)
		var props := mol.properties()
		var parts: Array[String] = []
		for p in Molecule.PROPS:
			parts.append("%s %d" % [tr("prop." + p), int(props[p])])
		parts.append("%s %d" % [tr("prop.alerts"), mol.open_alerts()])
		if not mol.disease.is_empty():   # 先写这一代面对的靶点（耐药变体）
			parts.push_front(tr("variant." + Molecule.variant_id(mol.disease, mol.variant)))
		_mol_line.text = " · ".join(parts)
		var exam: Dictionary = game.get_exam(state.stage)
		_exam_line.visible = bool(exam.get("has", false))
		if _exam_line.visible:
			var ok := bool(exam.passed)
			_exam_line.text = tr("mol.exam.hub_pass" if ok else "mol.exam.hub_fail") % Molecule.exam_label(exam)
			_exam_line.add_theme_color_override("font_color", UIKit.ACCENT if ok else UIKit.DANGER.lightened(0.25))
	else:
		_exam_line.visible = false
	molecule_art.health = clampf(0.5 + (state.efficacy - state.safety_risk) / 120.0, 0.0, 1.0)
	var hp := maxi(0, 100 - state.safety_risk)
	hp_bar.value = hp
	hp_label.text = tr("ui.hp_value") % hp
	var hp_color: Color = UIKit.ACCENT if hp > 60 else (UIKit.GOLD if hp > 30 else UIKit.DANGER)
	_style_bar(hp_bar, hp_color)
	hp_label.add_theme_color_override("font_color", hp_color.lightened(0.2))
	hp_label.get_parent().tooltip_text = tr("ui.hp_tip") + "\n" + tr("hub.safety_tip") % [state.safety_risk, game.get_final_safety_limit()]
	funding_label.text = tr("hub.funding") % state.funding
	year_label.text = tr("ui.year") % state.year
	var bar := game.get_final_efficacy_bar() as int
	efficacy_label.text = tr("hub.efficacy") % [state.efficacy, bar]
	efficacy_bar.max_value = maxi(bar, 1)
	efficacy_bar.value = mini(state.efficacy, bar)
	efficacy_label.get_parent().get_parent().tooltip_text = tr("hub.efficacy_tip") % bar
	var gate := game.get_progress_gate() as int
	progress_label.text = tr("hub.research") % [mini(state.research_progress, gate), gate]
	progress_bar.max_value = maxi(gate, 1)
	progress_bar.value = mini(state.research_progress, gate)
	progress_label.get_parent().get_parent().tooltip_text = tr("hub.research_tip") % gate
	# 团队铭牌
	var level: int = game.get_player_level()
	avatar.form = level
	avatar.ratio = float(hp) / 100.0
	var next: int = game.get_next_level_xp()
	_team_label.text = tr("player.tag_team") % [level, tr("mol.level.%d" % level)] if game.molecule != null \
		else tr("player.tag") % [level, tr("player.level.%d" % level)]
	mol_view.form = level
	mol_view.ratio = float(hp) / 100.0
	avatar.visible = game.molecule == null   # 有分子时它就是主角，卡通烧瓶不再出场
	queue_redraw()
	_xp_bar.max_value = maxi(next, 1) if next > 0 else 1
	_xp_bar.value = game.player_xp if next > 0 else 1
	_xp_bar.tooltip_text = tr("player.xp") % [game.player_xp, next] if next > 0 else tr("player.max")
	_bonus_label.text = PlayerHud.bonus_text(game.get_player_bonus())
	# 右侧三张卡片
	var ai: Dictionary = game.get_ai_info()
	ai_card.set_content(tr("hub.ai_summary") % [tr("tier." + String(ai.tier)), ai.multiplier, ai.deviation],
		tr("ui.hub_ai_detail") % [ai.effective, tr("tier." + String(ai.tier)), ai.multiplier, ai.deviation,
			ai.run_data, ai.company_data, ai.level] + "\n" + BattleView.ai_next_text(ai))
	var names: Array[String] = []
	for ability_id in state.abilities:
		names.append("· " + tr(String(game.get_ability_by_id(String(ability_id)).get("name_key", String(ability_id)))))
	abilities_card.set_content(tr("hub.abilities_summary") % names.size() if not names.is_empty() else tr("hub.abilities_empty"),
		"\n".join(names) if not names.is_empty() else tr("ui.hub_abilities_none"))
	competition_card.set_content(competition_summary, competition_text)
	fill_goal_card(goal_card, game.get_final_checklist())
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		_growth = move_toward(_growth, _target_growth, delta * 0.45)
		_scan = maxf(0.0, _scan - delta * 0.7)
		var base_unit := minf(mol_view.size.x / 8.85, mol_view.size.y / 6.25)
		mol_view.unit = base_unit * lerpf(0.78, 1.04, _growth)
		queue_redraw()


func _draw() -> void:
	if mol_view == null or not mol_view.visible:
		return
	# 标本观察龛：取消硬切矩形写实视窗与科幻全息圆盘，改用几何膜岩底座 + 柔和阶段柔光 + 极克制的刻度弧
	var alcove := Rect2(Vector2(STATUS_W + 24, 77),
		Vector2(size.x - STATUS_W - CARDS_W - 48, size.y - BENCH_FROM_BOTTOM - 82))
	var bounds := mol_view.visual_bounds()
	var center := mol_view.position + bounds.get_center()
	var feet := mol_view.support_points()
	var foot := Vector2(center.x, mol_view.position.y + bounds.end.y + 4.0)
	if feet.size() >= 2:
		foot = mol_view.position + (feet[0] + feet[1]) * 0.5
	var radius := bounds.size.x * 0.56
	var light := _tint.lightened(0.35)
	if alcove.has_area():
		# 柔和的八角形暗角框架 + 左上方阶段主光束，与整体几何膜世界融为一体
		var frame_pts := PaintedArt.contour(alcove, 16.0)
		draw_colored_polygon(frame_pts, Color(0.035, 0.045, 0.085, 0.34))
		frame_pts.append(frame_pts[0])
		draw_polyline(frame_pts, Color(light, 0.24), 1.4, true)
		var beam_src := Vector2(alcove.position.x + alcove.size.x * 0.16, alcove.position.y)
		var beam := PackedVector2Array([
			beam_src, beam_src + Vector2(alcove.size.x * 0.28, 0),
			Vector2(foot.x + radius * 0.82, foot.y + 6.0), Vector2(foot.x - radius * 0.72, foot.y + 6.0)])
		var warm_light := Color(1.0, 0.90, 0.72).lerp(light, 0.45)
		draw_polygon(beam, PackedColorArray([Color(warm_light, 0.11), Color(warm_light, 0.06), Color(warm_light, 0.0), Color(warm_light, 0.02)]))
		# 四角细金标本标尺折线
		var arm := 16.0
		var corner_col := Color(UIKit.GOLD, 0.45)
		for corner: Vector2 in [alcove.position + Vector2(8, 8), Vector2(alcove.end.x - 8, alcove.position.y + 8),
				alcove.end - Vector2(8, 8), Vector2(alcove.position.x + 8, alcove.end.y - 8)]:
			var inward: Vector2 = (alcove.get_center() - corner).sign()
			draw_polyline(PackedVector2Array([corner + Vector2(inward.x * arm, 0), corner, corner + Vector2(0, inward.y * arm)]), corner_col, 1.5, true)
	# 克制的标本刻度弧（不再铺黑底圆盘挡住背景）
	var ring_height := minf(0.62, alcove.size.y * 0.37 / maxf(1.0, radius * 1.06))
	draw_set_transform(center, 0.0, Vector2(1.0, ring_height))
	draw_arc(Vector2.ZERO, radius * 0.86, -PI * 0.86, -PI * 0.14, 48, Color(light, 0.28), 1.4, true)
	draw_arc(Vector2.ZERO, radius * 0.86, PI * 0.14, PI * 0.86, 48, Color(light, 0.18), 1.2, true)
	for ring in _stage_index:
		var start := -PI * 0.88 + ring * 0.18
		draw_arc(Vector2.ZERO, radius * (0.91 + ring * 0.04), start, start + PI * 0.85,
			36, Color(UIKit.GOLD.lerp(light, 0.5), 0.38 - ring * 0.04), 1.8, true)
	for i in 24:
		var a := i * TAU / 24.0 + _time * 0.025
		var inner := radius * (0.82 if i % 3 == 0 else 0.845)
		draw_line(Vector2.from_angle(a) * inner, Vector2.from_angle(a) * radius * 0.86, Color(UIKit.PAPER, 0.22), 1.0, true)
	draw_set_transform(Vector2.ZERO)
	if _scan > 0.0:
		var y := center.y + lerpf(-radius * 0.72, radius * 0.72, 1.0 - _scan) * ring_height
		draw_line(Vector2(center.x - radius * 0.82, y), Vector2(center.x + radius * 0.82, y),
			Color(UIKit.PAPER, sin(_scan * PI) * 0.65), 2.0, true)
	# 几何厚涂切面石台底座：替代原来的扁平椭圆科幻圆盘，左上受光、右下厚暗面
	var hw := radius * 0.94
	var hh := 16.0
	var thick := 13.0
	var top_poly := PackedVector2Array([
		foot + Vector2(-hw * 0.76, -hh), foot + Vector2(hw * 0.68, -hh * 0.92),
		foot + Vector2(hw, 0.0), foot + Vector2(hw * 0.72, hh),
		foot + Vector2(-hw * 0.72, hh * 0.95), foot + Vector2(-hw, 0.0)])
	var drop_poly := PackedVector2Array()
	for p in top_poly:
		drop_poly.append(p + Vector2(6.0, thick + 6.0))
	draw_colored_polygon(drop_poly, Color(0.012, 0.016, 0.04, 0.65))
	# 台座正面三个受光不同的厚切面
	var f0 := top_poly[5]
	var f1 := top_poly[4]
	var f2 := top_poly[3]
	var f3 := top_poly[2]
	draw_colored_polygon(PackedVector2Array([f0, f1, f1 + Vector2(0, thick), f0 + Vector2(0, thick * 0.85)]), Color(0.14, 0.17, 0.27))
	draw_colored_polygon(PackedVector2Array([f1, f2, f2 + Vector2(0, thick), f1 + Vector2(0, thick)]), Color(0.095, 0.115, 0.19))
	draw_colored_polygon(PackedVector2Array([f2, f3, f3 + Vector2(0, thick * 0.85), f2 + Vector2(0, thick)]), Color(0.06, 0.075, 0.135))
	# 顶面按左上主光做渐变明暗
	var top_colors := PackedColorArray()
	var ldir := PaintedStyle.LIGHT.normalized()
	for p in top_poly:
		var lit := clampf(((p - foot).dot(ldir) / maxf(hw, 1.0)) * 0.5 + 0.5, 0.0, 1.0)
		var base := Color(0.13, 0.16, 0.26).lerp(light.darkened(0.35), 0.25)
		top_colors.append(base.lerp(Color(0.32, 0.36, 0.47).lerp(UIKit.PAPER, 0.14), lit * 0.75))
	draw_polygon(top_poly, top_colors)
	# 顶面斜切受光面 + 正面折线棱边，增强手绘切面石台的体块感
	draw_colored_polygon(PackedVector2Array([top_poly[5], top_poly[0], top_poly[1], foot + Vector2(-hw * 0.12, hh * 0.2)]),
		Color(UIKit.PAPER, 0.07))
	draw_polyline(PackedVector2Array([top_poly[5], top_poly[0], top_poly[1]]), Color(UIKit.PAPER, 0.58), 1.8, true)
	var rim := top_poly.duplicate()
	rim.append(top_poly[0])
	draw_polyline(rim, Color(0.035, 0.04, 0.085, 0.9), 1.6, true)
	draw_line(f1, f1 + Vector2(0, thick), Color(UIKit.PAPER, 0.18), 1.2, true)
	draw_line(f2, f2 + Vector2(0, thick), Color(0.025, 0.03, 0.065, 0.75), 1.2, true)
	draw_line(f1 + Vector2(0, thick), f2 + Vector2(0, thick), Color(0.025, 0.03, 0.065, 0.9), 1.6, true)
	# 角色双足贴台接触阴影
	if feet.size() >= 2:
		for fp in feet:
			var sp := mol_view.position + fp
			var s_pts := PackedVector2Array()
			for k in 18:
				var a := k * TAU / 18.0
				s_pts.append(sp + Vector2(cos(a) * 28.0 + 2.0, sin(a) * 5.0 + 1.5))
			draw_colored_polygon(s_pts, Color(0.015, 0.02, 0.05, 0.55))


func _glass_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0.04, 0.06, 0.09, 0.78), Color(0.3, 0.4, 0.46, 0.6), 12)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _bar(width: float, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(width, height)
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_bar(b, UIKit.ACCENT)
	return b


func _style_bar(b: ProgressBar, color: Color) -> void:
	b.add_theme_stylebox_override("fill", UIKit.meter_style(color, color, 4))
	b.add_theme_stylebox_override("background", UIKit.meter_style(Color(0.1, 0.12, 0.16), Color(0.25, 0.3, 0.36), 4))


func _chip(grid: GridContainer, icon_name: String, color: Color, text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(UIKit.icon_rect(icon_name, 18, color))
	var label := UIKit.label(text, color.lightened(0.15), 15)
	row.add_child(label)
	grid.add_child(row)
	return label


## 带小进度条的指标（疗效对终审门槛、前期研究对 Boss 削弱上限）
func _bar_chip(grid: GridContainer, icon_name: String, color: Color) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(UIKit.icon_rect(icon_name, 18, color))
	var label := UIKit.label("", color.lightened(0.15), 14)
	row.add_child(label)
	col.add_child(row)
	var b := _bar(140, 6)
	_style_bar(b, color)
	col.add_child(b)
	grid.add_child(col)
	return [label, b]
