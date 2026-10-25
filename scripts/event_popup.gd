class_name EventPopup
extends Control
## 事件 / 节点决策 / 里程碑弹窗（纯 UI 层）
## 内容完全来自 game 组装的事件数据；玩家选择后通过 choice_selected 信号回传。
## 支持 desc_args / label_args（字符串参数会先经 tr() 翻译）与选项的 tag_key、desc_key。

signal choice_selected(event_id: String, choice_index: int)

@onready var _tag: Label = %TagLabel
@onready var _title: Label = %TitleLabel
@onready var _desc: Label = %DescLabel
@onready var _choices_box: VBoxContainer = %ChoicesBox

var _event_id: String = ""


func show_event(event: Dictionary, is_gate: bool, state: ProjectState) -> void:
	_event_id = String(event.get("id", ""))
	_title.text = tr(String(event.get("title_key", "event.default_title")))
	_tag.text = tr(String(event.get("tag_key", "ui.gate_tag" if is_gate else "ui.event_tag")))
	_tag.add_theme_color_override("font_color", Color(0.45, 0.85, 0.95) if is_gate else Color(0.95, 0.72, 0.30))
	_desc.text = _format(String(event.get("desc_key", "")), event.get("desc_args", []))
	for child in _choices_box.get_children():
		child.queue_free()
	var choices: Array = event.get("choices", [])
	for i in choices.size():
		_choices_box.add_child(_build_choice(choices[i], i, state))
	visible = true


func _format(key: String, args: Array) -> String:
	if key.is_empty():
		return ""
	if args.is_empty():
		return tr(key)
	var translated: Array = []
	for a in args:
		translated.append(tr(a) if a is String else a)
	return tr(key) % translated


func _build_choice(choice: Dictionary, index: int, state: ProjectState) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", 16)
	var title := _format(String(choice.get("label_key", "ui.choose_default")), choice.get("label_args", []))
	if choice.has("tag_key"):
		title = "【%s】%s" % [tr(String(choice.tag_key)), title]
	var lines: Array[String] = [title]
	var desc_key := String(choice.get("desc_key", ""))
	if desc_key != "" and tr(desc_key) != desc_key:
		lines.append(tr(desc_key))
	var effects_text := ProjectState.format_effects(choice.get("effects", {}))
	if effects_text != tr("fx.none"):
		lines.append(tr("ui.effect_prefix") % effects_text)
	var requires: Dictionary = choice.get("requires", {})
	if state != null and not state.can_meet(requires):
		btn.disabled = true
		lines.append(_requires_text(requires))
	btn.text = "\n".join(lines)
	btn.pressed.connect(_on_choice_pressed.bind(index))
	return btn


func _requires_text(requires: Dictionary) -> String:
	var parts: Array[String] = []
	if requires.has("funding_min"):
		parts.append(tr("req.funding_min") % int(requires.funding_min))
	if requires.has("efficacy_min"):
		parts.append(tr("req.efficacy_min") % int(requires.efficacy_min))
	if requires.has("safety_risk_below"):
		parts.append(tr("req.safety_risk_below") % int(requires.safety_risk_below))
	if requires.has("data_min"):
		parts.append(tr("req.data_min") % int(requires.data_min))
	if bool(requires.get("battle_won", false)):
		parts.append(tr("req.battle_won"))
	return tr("ui.requires") % "，".join(parts)


func _on_choice_pressed(index: int) -> void:
	visible = false
	choice_selected.emit(_event_id, index)
