class_name StatusRow
extends HBoxContainer
## 状态图标行：图标 + 层数，悬停显示名称与说明。新增状态时图标弹跳一下。

const BUFF_COLOR := Color(0.45, 0.9, 0.6)
const DEBUFF_COLOR := Color(0.95, 0.45, 0.45)

var _shown := {}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_statuses(statuses: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	var fresh := {}
	for id in statuses:
		var amount := int(statuses[id])
		if amount <= 0:
			continue
		fresh[id] = amount
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.tooltip_text = "%s：%s" % [tr("status." + String(id)), tr("status." + String(id) + ".desc")]
		var color := DEBUFF_COLOR if Combatant.DEBUFFS.has(id) else BUFF_COLOR
		var icon := UIKit.icon_rect("status_" + String(id), 22, color)
		box.add_child(icon)
		var count := UIKit.label(str(amount), Color.WHITE, 13)
		count.add_theme_constant_override("outline_size", 4)
		count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(count)
		add_child(box)
		if int(_shown.get(id, 0)) != amount:
			icon.pivot_offset = Vector2(11, 11)
			icon.scale = Vector2(1.6, 1.6)
			icon.create_tween().tween_property(icon, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shown = fresh
