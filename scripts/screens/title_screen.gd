extends Control
## 标题界面：右侧大半屏是 LM-001 主视觉（TitleHero），左侧标题 + 游戏式菜单（一个发光主按钮 + 无边框文字项），
## 公司概况缩成右下角一行。

var _menu: VBoxContainer
var _company_box: VBoxContainer
var _settings: SettingsPanel
var _help: HelpPanel
var _archive: ArchivePanel
var _credits: CreditsPanel
var _logo: TextureRect
var _confirm: ConfirmDialog
var _hero: TitleHero
var _project_select: ProjectSelectPanel
var _primary: Button


func _ready() -> void:
	GameSettings.apply()
	var bg := MoleculeBackground.new()
	bg.molecule_count = 10   # 少量漂浮分子做氛围，太密会像数据关系图
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build()
	GameAudio.music("title")


func _build() -> void:
	for child in get_children():
		if not child is MoleculeBackground:
			child.queue_free()
	# 主视觉占满右侧大半屏，左侧只放标题与菜单，公司信息缩成右下角一行
	_hero = TitleHero.new()
	_hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero.offset_left = 470
	_hero.offset_top = 40
	_hero.offset_right = -40
	_hero.offset_bottom = -56
	add_child(_hero)

	var left := VBoxContainer.new()
	left.position = Vector2(96, 64 if RunSave.exists() else 84)
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 18)
	_logo = TextureRect.new()
	_logo.texture = UIKit.icon("logo")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = Vector2(92, 92)
	brand.add_child(_logo)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	var title := UIKit.header(tr("ui.title"), 64, Color(0.93, 0.98, 0.96))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.4, 0.3, 0.55))
	names.add_child(title)
	names.add_child(UIKit.label(tr("title.english"), UIKit.ACCENT, 18))
	brand.add_child(names)
	left.add_child(brand)
	left.add_child(UIKit.label(tr("ui.subtitle"), UIKit.TEXT_DIM, 17))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26 if RunSave.exists() else 40)
	left.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 4)
	_menu.custom_minimum_size = Vector2(320, 0)
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(_menu)
	var saved := RunSave.summary()
	if not saved.is_empty():
		_primary_button("title.continue", _on_continue)
		var project := tr("project.title") % [String(saved.project_code), tr("project.type." + String(saved.project_type))]
		var line := UIKit.label(tr("title.continue_line") % [project, tr("stage." + String(saved.stage)), int(saved.year), int(saved.funding)], UIKit.ACCENT, 14)
		_menu.add_child(line)
		_menu_item("title.start", _on_start)
	else:
		_primary_button("title.start", _on_start)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	_menu.add_child(gap2)
	_menu_item("title.archive", func() -> void: _archive.open())
	_menu_item("title.help", func() -> void: _help.open())
	_menu_item("title.settings", func() -> void: _settings.open())
	_menu_item("title.credits", func() -> void: _credits.open())
	if OS.get_name() != "Web":
		_menu_item("title.quit", func() -> void: get_tree().quit())

	var version := UIKit.label(tr("title.version"), Color(UIKit.TEXT_DIM, 0.6), 13)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_left = 96
	version.offset_bottom = -24
	add_child(version)
	_company_box = VBoxContainer.new()
	_company_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_company_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_company_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_company_box.offset_right = -48
	_company_box.offset_bottom = -24
	_company_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(_company_box)
	_fill_company()

	_settings = SettingsPanel.new()
	_settings.allow_reset = true
	_settings.locale_changed.connect(func() -> void: _rebuild_after_locale.call_deferred())
	_settings.closed.connect(func() -> void:
		_fill_company()
		_hero.refresh())   # 设置里可能重置了公司档案
	_help = HelpPanel.new()
	_archive = ArchivePanel.new()
	_credits = CreditsPanel.new()
	_project_select = ProjectSelectPanel.new()
	_project_select.project_chosen.connect(_start_new)
	_confirm = null
	for panel in [_settings, _help, _archive, _credits, _project_select]:
		add_child(panel)
	_intro()


## 主按钮：大号发光胶囊
func _primary_button(key: String, action: Callable) -> void:
	var btn := UIKit.button(tr(key), "ui_play", "primary", Vector2(300, 58))
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(action)
	_menu.add_child(btn)
	_primary = btn


## 次级菜单：无边框的文字项，悬停时变亮并在左侧出现箭头
func _menu_item(key: String, action: Callable) -> void:
	var btn := Button.new()
	btn.text = "   " + tr(key)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.custom_minimum_size = Vector2(300, 38)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", UIKit.ACCENT.lightened(0.3))
	btn.add_theme_color_override("font_focus_color", Color(0.72, 0.78, 0.84))
	var empty := StyleBoxEmpty.new()
	for state_name in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state_name, empty)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.mouse_entered.connect(func() -> void:
		btn.text = "▸  " + tr(key)
		GameAudio.sfx("hover"))
	btn.mouse_exited.connect(func() -> void: btn.text = "   " + tr(key))
	btn.pressed.connect(func() -> void:
		GameAudio.sfx("click")
		action.call())
	_menu.add_child(btn)


func _fill_company() -> void:
	if _company_box == null:
		return
	for child in _company_box.get_children():
		child.queue_free()
	var company := Company.new()
	company.load_save()
	var text := tr("title.company_new_short") if company.runs == 0 else tr("title.company_short") % [company.runs, company.approvals,
		company.process_level(), tr("tier." + String(company.tier_for(company.effective_data(0, 0)).id))]
	var label := UIKit.label(text, Color(UIKit.TEXT_DIM, 0.85), 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_company_box.add_child(label)


func _intro() -> void:
	_menu.modulate.a = 0.0
	_hero.modulate.a = 0.0
	_logo.pivot_offset = Vector2(46, 46)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_menu, "modulate:a", 1.0, 0.6).set_delay(0.25)
	tween.tween_property(_hero, "modulate:a", 1.0, 1.2)
	tween.tween_property(_logo, "rotation", TAU / 6, 1.2).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 主按钮呼吸光：提示「从这里开始」
func _process(_delta: float) -> void:
	if _primary and is_instance_valid(_primary):
		_primary.modulate = Color(1, 1, 1).lerp(Color(1.12, 1.18, 1.12), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 500.0))


func _rebuild_after_locale() -> void:
	_build()
	_settings.open()


func _on_start() -> void:
	if RunSave.exists():
		if _confirm == null:
			_confirm = ConfirmDialog.new()
			add_child(_confirm)
		_confirm.ask(tr("title.start"), tr("title.start_overwrite"), _project_select.open)
		return
	_project_select.open()


func _start_new(type_id: String) -> void:
	RunSave.resume_requested = false
	RunSave.new_project_type = type_id
	GameAudio.sfx("stage")
	SceneRouter.goto(SceneRouter.GAME)


func _on_continue() -> void:
	RunSave.resume_requested = true
	GameAudio.sfx("stage")
	SceneRouter.goto(SceneRouter.GAME)

