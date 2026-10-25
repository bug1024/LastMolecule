class_name CreditsPanel
extends ModalPanel
## 制作名单与素材说明。


func _init() -> void:
	super._init()
	title_key = "credits.title"
	panel_width = 600


func _build(box: VBoxContainer) -> void:
	var text := UIKit.rich(tr("credits.body"), 16)
	text.add_theme_constant_override("line_separation", 6)
	box.add_child(text)
