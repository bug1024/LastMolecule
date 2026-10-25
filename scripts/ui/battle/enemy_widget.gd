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
var danger := false           # 本回合伤害很高：意图数字放大并闪烁
const DANGER_DAMAGE := 15
var _intent_box: HBoxContainer
var _intent_icons: HBoxContainer
var _intent_label: Label
var _name: Label
var _time := 0.0
var _hover := false


func setup(enemy: Enemy, enemy_index: int) -> void:
	index = enemy_index
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_intent_box = HBoxContainer.new()
	_intent_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_intent_box.position = Vector2(0, 0)
	_intent_box.size = Vector2(SIZE.x, 40)
	_intent_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_intent_icons = HBoxContainer.new()
	_intent_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intent_box.add_child(_intent_icons)
	_intent_label = UIKit.label("", Color.WHITE, 22)
	_intent_label.add_theme_constant_override("outline_size", 6)
	_intent_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_intent_box.add_child(_intent_label)
	add_child(_intent_box)
	creature = CreatureView.new()
	creature.setup(enemy.data, enemy.is_boss, enemy.is_elite)
	var cs := creature.custom_minimum_size
	creature.size = cs
	creature.position = Vector2((SIZE.x - cs.x) * 0.5, 250 - cs.y)
	add_child(creature)
	move_child(_intent_box, -1)
	_name = UIKit.label(tr(enemy.name_key), Color(1, 0.9, 0.85) if enemy.is_boss else Color.WHITE, 15)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.position = Vector2(0, 252)
	_name.size = Vector2(SIZE.x, 22)
	_name.add_theme_constant_override("outline_size", 5)
	_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_name)
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


func show_intent(enemy: Enemy, damage: int) -> void:
	for child in _intent_icons.get_children():
		child.queue_free()
	if not enemy.is_alive() or enemy.intent.is_empty():
		_intent_box.visible = false
		return
	_intent_box.visible = true
	var kind := String(enemy.intent.get("intent", "attack"))
	var parts := kind.split("_")
	for part in parts:
		var color: Color = INTENT_COLOR.get(part, Color.WHITE)
		_intent_icons.add_child(UIKit.icon_rect("intent_" + part, 32, color))
	var hits := enemy.intent_hits()
	_intent_label.text = "" if damage <= 0 else (str(damage) if hits == 1 else "%d×%d" % [damage, hits])
	danger = damage * hits >= DANGER_DAMAGE
	_intent_label.add_theme_font_size_override("font_size", 30 if danger else 24)
	_intent_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2) if danger else (INTENT_COLOR.attack.lightened(0.3) if damage > 0 else Color.WHITE))
	_intent_box.tooltip_text = _intent_tooltip(enemy, damage)


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
	statuses.set_statuses(enemy.statuses)


func _process(delta: float) -> void:
	_time += delta
	if _intent_box and _intent_box.visible:
		_intent_box.position.y = 4.0 * sin(_time * 2.5)
		var s := 1.0 + (0.12 * absf(sin(_time * 6.0)) if danger else 0.0)
		_intent_box.pivot_offset = _intent_box.size * 0.5
		_intent_box.scale = Vector2(s, s)
	queue_redraw()


func _draw() -> void:
	if targetable and creature and creature.dying <= 0.0:
		var c := creature.position + creature.size * Vector2(0.5, 0.55)
		var r := creature.radius * 1.35
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		var color := Color(1, 0.85, 0.3, 0.5 + 0.4 * pulse) if _hover else Color(1, 1, 1, 0.18)
		draw_arc(c, r, 0, TAU, 64, color, 3.0 if _hover else 2.0, true)
		if _hover:
			for i in 4:
				var a := _time * 1.5 + i * TAU / 4.0
				draw_line(c + Vector2(cos(a), sin(a)) * (r + 4), c + Vector2(cos(a), sin(a)) * (r + 18), color, 3.0, true)
