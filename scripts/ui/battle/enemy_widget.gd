class_name EnemyWidget
extends Control
## 单个敌人：头顶意图、生物形象、名称、血条与状态。可被点击选为目标。

signal pressed(index: int)
signal hovered(index: int, on: bool)

const SIZE := Vector2(250, 330)
const INTENT_COLOR := {
	"attack": Color(1.0, 0.45, 0.4),
	"defend": Color(0.45, 0.7, 1.0),
	"buff": Color(0.5, 0.95, 0.6),
	"debuff": Color(0.8, 0.55, 1.0),
}

var index := 0
var creature: CreatureView
var bar: HealthBar
var statuses: StatusRow
var targetable := false
var danger := false           # 本回合伤害很高：意图底板强调，生物蓄力
const DANGER_DAMAGE := 15
var _intent_box: PanelContainer
var _intent_icons: HBoxContainer
var _name: Label
var _hover := false
var _base_radius := 80.0
var _boss := false
var _intent_width := 240.0


func setup(enemy: Enemy, enemy_index: int) -> void:
	index = enemy_index
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_intent_box = PanelContainer.new()
	_intent_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_intent_box.add_theme_stylebox_override("panel", _intent_style(false))
	_intent_icons = HBoxContainer.new()
	_intent_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intent_box.add_child(_intent_icons)
	_intent_icons.add_theme_constant_override("separation", 8)
	add_child(_intent_box)
	creature = CreatureView.new()
	creature.setup(enemy.data, enemy.is_boss, enemy.is_elite)
	_base_radius = clampf(creature.radius * 1.2, 70, 92)
	_boss = enemy.is_boss
	creature.radius = _base_radius
	creature.custom_minimum_size = Vector2(creature.radius * 2.8, creature.radius * 2.6)
	var cs := creature.custom_minimum_size
	creature.size = cs
	creature.position = Vector2((SIZE.x - cs.x) * 0.5, 250 - cs.y)
	add_child(creature)
	move_child(_intent_box, -1)
	_name = UIKit.label(tr(enemy.name_key), Color(1, 0.9, 0.85) if enemy.is_boss else Color.WHITE, 15)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.tooltip_text = tr(enemy.name_key)
	_name.position = Vector2(25, 252)
	_name.size = Vector2(200, 22)
	_name.add_theme_constant_override("outline_size", 5)
	_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_name)
	UIKit.identity_plate(_name)
	bar = HealthBar.new()
	bar.position = Vector2(30, 276)
	bar.size = Vector2(SIZE.x - 60, 22)
	add_child(bar)
	bar.set_values(enemy.hp, enemy.max_hp, enemy.block, true)
	statuses = StatusRow.new()
	statuses.position = Vector2(34, 300)
	statuses.size = Vector2(SIZE.x - 60, 26)
	add_child(statuses)
	mouse_entered.connect(func() -> void:
		_hover = true
		hovered.emit(index, true))
	mouse_exited.connect(func() -> void:
		_hover = false
		hovered.emit(index, false))
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(index))


func show_intent(enemy: Enemy, damage: int, exploit := {}) -> void:
	for child in _intent_icons.get_children():
		_intent_icons.remove_child(child)
		child.queue_free()
	if not enemy.is_alive() or enemy.intent.is_empty():
		_intent_box.visible = false
		return
	_intent_box.visible = true
	var move := enemy.intent
	var kind := String(move.get("intent", "attack"))
	var hits := enemy.intent_hits()
	danger = damage * hits >= DANGER_DAMAGE
	_intent_box.add_theme_stylebox_override("panel", _intent_style(danger))
	if kind.split("_").has("attack"):
		_add_intent("intent_attack", str(damage) if hits == 1 else "%d×%d" % [damage, hits], INTENT_COLOR.attack)
	for field in ["block", "ally_block"]:
		if int(move.get(field, 0)) > 0:
			_add_intent("intent_defend", str(int(move[field])), INTENT_COLOR.defend)
	for field in ["status", "self_status", "ally_status"]:
		for id in move.get(field, {}):
			var debuff: bool = field == "status"
			_add_intent("status_" + String(id) if debuff else "intent_buff", str(int(move[field][id])), INTENT_COLOR.debuff if debuff else INTENT_COLOR.buff)
	if move.has("add_card"):
		_add_intent("intent_debuff", str(int(move.add_card.get("value", 1))), INTENT_COLOR.debuff)
	if _intent_icons.get_child_count() == 0:
		_add_intent("intent_" + kind, "", INTENT_COLOR.get(kind, Color.WHITE))
	_intent_box.tooltip_text = _intent_tooltip(enemy, damage)
	# 这一击会专攻分子的哪个片段：提前一回合写出来，玩家可以先打出相关牌或准备修复
	var names := str(exploit.get("names", ""))   # 已翻译、用顿号连接的片段名
	if int(exploit.get("bonus", 0)) > 0 and kind.split("_").has("attack") and not names.is_empty():
		_add_intent("type_molecular", "", Color(1.0, 0.55, 0.45))
		_intent_box.tooltip_text += "\n" + tr("intent.tip.exploit") % names
	_intent_box.reset_size()


func _intent_style(high_risk: bool) -> StyleBoxFlat:
	var background := Color("2d151c") if high_risk else Color("121928")
	var edge := Color("d97063") if high_risk else Color("556077")
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	style.shadow_color = Color(0, 0, 0, 0.52)
	style.shadow_size = 4
	return style


func _add_intent(icon_name: String, amount: String, color: Color) -> void:
	var item := HBoxContainer.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_constant_override("separation", 3)
	item.add_child(UIKit.icon_rect(icon_name, 20, color))
	if not amount.is_empty():
		var number := UIKit.label(amount, UIKit.PAPER.lightened(0.55), 24)
		number.theme_type_variation = &"NumberLabel"
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number.add_theme_constant_override("outline_size", 3)
		number.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		item.add_child(number)
	_intent_icons.add_child(item)


func _intent_tooltip(enemy: Enemy, damage: int) -> String:
	var move := enemy.intent
	var lines: Array[String] = ["【%s】" % tr("move." + String(move.get("id", "")))]
	if damage > 0:
		lines.append(tr("intent.tip.attack") % [damage, enemy.intent_hits()] if enemy.intent_hits() > 1 else tr("intent.tip.attack_once") % damage)
	if int(move.get("block", 0)) > 0:
		lines.append(tr("intent.tip.block") % int(move.block))
	for id in move.get("status", {}):
		lines.append(tr("intent.tip.debuff") % [int(move.status[id]), tr("status." + String(id))])
	for id in move.get("self_status", {}):
		lines.append(tr("intent.tip.buff") % [int(move.self_status[id]), tr("status." + String(id))])
	for id in move.get("ally_status", {}):
		lines.append(tr("intent.tip.ally_buff") % [int(move.ally_status[id]), tr("status." + String(id))])
	if int(move.get("ally_block", 0)) > 0:
		lines.append(tr("intent.tip.ally_block") % int(move.ally_block))
	if move.has("add_card"):
		lines.append(tr("intent.tip.add_card") % [int(move.add_card.get("value", 1)), tr("card." + String(move.add_card.id))])
	return "\n".join(lines)


func refresh(enemy: Enemy) -> void:
	bar.set_values(enemy.hp, enemy.max_hp, enemy.block)
	creature.hp_ratio = float(enemy.hp) / maxf(1.0, enemy.max_hp)
	statuses.set_statuses(enemy.statuses)


func _process(_delta: float) -> void:
	if _intent_box and _intent_box.visible:
		var body := creature.visible_body_rect()
		# 预留鼓胀、摇摆的空间，底板与身体各自保持稳定。
		var top := creature.position.y + body.position.y - body.size.y * creature.strain * 0.20
		var scale_factor := minf(1.0, _intent_width / maxf(1.0, _intent_box.size.x))
		_intent_box.scale = Vector2.ONE * scale_factor
		var extent := _intent_box.size * scale_factor
		_intent_box.position = Vector2((SIZE.x - extent.x) * 0.5, maxf(top - extent.y - 8, 55.0 - position.y))
	if creature:
		creature.windup = danger and _intent_box != null and _intent_box.visible
	queue_redraw()


func _draw() -> void:
	if targetable and creature and creature.dying <= 0:
		var area := creature.visible_body_rect()
		area.position += creature.position
		var edge := PaintedArt.contour(area.grow(6),12)
		edge.append(edge[0])
		draw_polyline(edge,UIKit.GOLD if _hover else Color(UIKit.PAPER,0.3),2 if _hover else 1,true)


## A single boss can own the stage; groups retain separate target silhouettes.
func set_stage_pose(body_size: Vector2, meta_width: float) -> void:
	creature.size = body_size
	creature.position = Vector2(SIZE.x * 0.5 - body_size.x * 0.5, -body_size.y)
	_name.position = Vector2((SIZE.x - meta_width) * 0.5, 14)
	_name.size = Vector2(meta_width, 24)
	bar.position = Vector2((SIZE.x - meta_width) * 0.5, 42)
	bar.size = Vector2(meta_width, 24)
	statuses.position = Vector2((SIZE.x - meta_width) * 0.5 + 8, 67)
	_intent_width = meta_width


## 登场演出时先藏起名字、血条和意图，只留下身体
func set_meta_alpha(alpha: float) -> void:
	for node: Control in [_intent_box, _name, bar, statuses]:
		node.modulate.a = alpha


func contact_point() -> Vector2:
	return position + creature.position + creature.action_contact()


func _has_point(point: Vector2) -> bool:
	return Rect2(creature.position,creature.size).grow(8).has_point(point) or Rect2(Vector2(0,18),Vector2(SIZE.x,90)).has_point(point)
