class_name SettingsPanel
extends ModalPanel
## 设置页：主音量 / 音乐 / 音效、全屏、语言；在标题界面还可重置公司档案。

signal locale_changed()

var allow_reset := false
var _confirm: ConfirmDialog


func _init() -> void:
	super._init()
	title_key = "settings.title"
	panel_width = 620
	closed.connect(GameSettings.save)


func _build(box: VBoxContainer) -> void:
	box.add_child(_section("settings.audio"))
	box.add_child(_slider_row("settings.master", GameSettings.master_volume, func(v: float) -> void:
		GameSettings.master_volume = v))
	box.add_child(_slider_row("settings.music", GameSettings.music_volume, func(v: float) -> void:
		GameSettings.music_volume = v))
	box.add_child(_slider_row("settings.sfx", GameSettings.sfx_volume, func(v: float) -> void:
		GameSettings.sfx_volume = v
		GameAudio.sfx("gain")))
	box.add_child(_section("settings.display"))
	var full_row := HBoxContainer.new()
	var full_label := UIKit.label(tr("settings.fullscreen"), UIKit.TEXT, 16)
	full_label.custom_minimum_size = Vector2(140, 0)
	full_row.add_child(full_label)
	var full := UIKit.button("", "", "normal", Vector2(200, 40))
	full.toggle_mode = true
	full.button_pressed = GameSettings.fullscreen
	full.text = tr("settings.on" if full.button_pressed else "settings.off")
	full.toggled.connect(func(on: bool) -> void:
		full.text = tr("settings.on" if on else "settings.off")
		GameSettings.fullscreen = on
		_commit())
	full_row.add_child(full)
	box.add_child(full_row)
	var lang_row := HBoxContainer.new()
	var lang_label := UIKit.label(tr("settings.language"), UIKit.TEXT, 16)
	lang_label.custom_minimum_size = Vector2(140, 0)
	lang_row.add_child(lang_label)
	var lang := OptionButton.new()
	lang.custom_minimum_size = Vector2(200, 40)
	lang.add_item("中文", 0)
	lang.add_item("English", 1)
	lang.selected = GameSettings.LOCALES.find(GameSettings.locale)
	lang.item_selected.connect(func(index: int) -> void:
		GameSettings.locale = GameSettings.LOCALES[index]
		_commit()
		_relabel()
		locale_changed.emit())
	lang_row.add_child(lang)
	box.add_child(lang_row)
	if allow_reset:
		box.add_child(_section("settings.data"))
		var reset := UIKit.button(tr("settings.reset_company"), "", "danger", Vector2(0, 42))
		reset.pressed.connect(_ask_reset)
		box.add_child(reset)
		box.add_child(UIKit.label(tr("settings.reset_hint"), UIKit.TEXT_DIM, 13, true))


func _section(key: String) -> Label:
	return UIKit.header(tr(key), 17, UIKit.ACCENT)


func _slider_row(key: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := UIKit.label(tr(key), UIKit.TEXT, 16)
	name_label.custom_minimum_size = Vector2(140, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = roundf(value * 100)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := UIKit.label("%d%%" % int(slider.value), UIKit.TEXT_DIM, 15)
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%d%%" % int(v)
		on_change.call(v / 100.0)
		GameSettings.apply_audio())
	slider.drag_ended.connect(func(_changed: bool) -> void: GameSettings.save())
	slider.focus_exited.connect(GameSettings.save)
	return row


func _commit() -> void:
	GameSettings.apply()
	GameSettings.save()


## 语言切换后立刻重绘本页
func _relabel() -> void:
	for child in get_children():
		child.queue_free()
	_confirm = null
	_built = false
	_construct.call_deferred()


func _ask_reset() -> void:
	if _confirm == null:
		_confirm = ConfirmDialog.new()
		add_child(_confirm)
	_confirm.ask(tr("settings.reset_company"), tr("settings.reset_confirm"), func() -> void:
		var company := Company.new()
		company.reset()
		GameAudio.sfx("loss"))
