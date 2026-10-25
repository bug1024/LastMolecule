class_name ConfirmDialog
extends ModalPanel
## 二次确认弹窗：ask(title, message, on_yes)。

var _message: Label
var _on_yes := Callable()


func _init() -> void:
	super._init()
	title_key = ""
	panel_width = 480


func ask(title: String, message: String, on_yes: Callable) -> void:
	_on_yes = on_yes
	open()
	for node in find_children("*", "Label", true, false):
		if node.has_meta("title"):
			(node as Label).text = title
	_message.text = message


func _build(box: VBoxContainer) -> void:
	_message = UIKit.label("", UIKit.TEXT, 16, true)
	_message.custom_minimum_size = Vector2(420, 0)
	box.add_child(_message)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	var no := UIKit.button(tr("ui.cancel"), "", "normal", Vector2(120, 42))
	no.pressed.connect(close)
	var yes := UIKit.button(tr("ui.confirm"), "", "danger", Vector2(120, 42))
	yes.pressed.connect(func() -> void:
		close()
		if _on_yes.is_valid():
			_on_yes.call())
	row.add_child(no)
	row.add_child(yes)
	box.add_child(row)
