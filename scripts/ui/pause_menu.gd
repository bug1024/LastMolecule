class_name PauseMenu
extends ModalPanel
## 游戏内菜单（Esc / 右上角「菜单」）：继续、玩法说明、设置、放弃本局返回标题。

signal help_requested()
signal settings_requested()

var _confirm: ConfirmDialog


func _init() -> void:
	super._init()
	title_key = "pause.title"
	panel_width = 420


func _build(box: VBoxContainer) -> void:
	box.add_theme_constant_override("separation", 10)
	var resume := UIKit.button(tr("pause.resume"), "ui_play", "primary", Vector2(0, 48))
	resume.pressed.connect(close)
	box.add_child(resume)
	var help := UIKit.button(tr("title.help"), "ui_help", "normal", Vector2(0, 46))
	help.pressed.connect(func() -> void: help_requested.emit())
	box.add_child(help)
	var settings := UIKit.button(tr("title.settings"), "type_process", "normal", Vector2(0, 46))
	settings.pressed.connect(func() -> void: settings_requested.emit())
	box.add_child(settings)
	var quit := UIKit.button(tr("pause.quit"), "ui_back", "normal", Vector2(0, 46))
	quit.pressed.connect(func() -> void: SceneRouter.goto(SceneRouter.TITLE))
	box.add_child(quit)
	box.add_child(UIKit.label(tr("pause.quit_hint"), UIKit.TEXT_DIM, 13, true))
