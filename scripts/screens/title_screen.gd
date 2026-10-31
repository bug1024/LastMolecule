extends Control
## 标题界面：右侧大半屏是 LM-001 主视觉（TitleHero），左侧标题 + 统一风格的半透明菜单按钮（主按钮绿色描边、轻微呼吸光），
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
	_hero.offset_left = 510
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
	_logo.self_modulate = UIKit.TEAL
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = Vector2(92, 92)
	brand.add_child(_logo)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	var title := UIKit.header(tr("ui.title"), 48, Color(0.93, 0.98, 0.96))
	title.add_theme_constant_override("outline_size", 0)
	title.add_theme_color_override("font_outline_color", UIKit.PAPER)
	names.add_child(title)
	names.add_child(UIKit.label(tr("title.english"), UIKit.ACCENT, 18))
	brand.add_child(names)
	left.add_child(brand)
	left.add_child(UIKit.label(tr("ui.subtitle"), UIKit.TEXT_DIM, 17))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26 if RunSave.exists() else 40)
	left.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 8)
	_menu.custom_minimum_size = Vector2(320, 0)
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(_menu)
	var saved := RunSave.summary()
	if not saved.is_empty():
		_menu_button("title.continue", "ui_play", _on_continue, true)
		var project := tr("project.title") % [String(saved.project_code), tr("project.type." + String(saved.project_type))]
		var line := UIKit.label(tr("title.continue_line") % [project, tr("stage." + String(saved.stage)), int(saved.year), int(saved.funding)], UIKit.ACCENT, 14)
		_menu.add_child(line)
		_menu_button("title.start", "ui_plus", _on_start)
	else:
		_menu_button("title.start", "ui_play", _on_start, true)
	_menu_button("title.archive", "ui_archive", func() -> void: _archive.open())
	_menu_button("title.help", "ui_help", func() -> void: _help.open())
	_menu_button("title.settings", "type_process", func() -> void: _settings.open())
	_menu_button("title.credits", "ui_music", func() -> void: _credits.open())
	if OS.get_name() != "Web":
		_menu_button("title.quit", "ui_power", func() -> void: get_tree().quit())

	var version := UIKit.label(tr("title.version"), Color(UIKit.TEXT_DIM, 0.6), 13)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_left = 96
	version.offset_bottom = -42
	add_child(version)
	_company_box = VBoxContainer.new()
	_company_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_company_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_company_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_company_box.offset_right = -48
	_company_box.offset_bottom = -42
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


## 菜单按钮：统一的半透明「玻璃」胶囊，同尺寸、同样的小图标与悬停光晕；
## 主按钮（开始 / 继续）只用绿色描边和淡绿底区分，不再是一整块实心绿
func _menu_button(key: String, icon_name: String, action: Callable, primary := false) -> void:
	var btn := Button.new()
	btn.text = tr(key)
	btn.icon = UIKit.icon(icon_name)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_constant_override("icon_max_width", 20)
	btn.add_theme_constant_override("h_separation", 12)
	btn.custom_minimum_size = Vector2(300, 48)
	btn.add_theme_font_size_override("font_size", 20 if primary else 19)
	var accent: Color = UIKit.ACCENT if primary else UIKit.BRASS
	var text_color := UIKit.PAPER_LIGHT if primary else UIKit.INK
	for state_name in ["font_color", "font_focus_color"]:
		btn.add_theme_color_override(state_name, text_color)
	btn.add_theme_color_override("font_hover_color", UIKit.PAPER_LIGHT if primary else UIKit.TEAL)
	btn.add_theme_color_override("font_pressed_color", UIKit.PAPER_LIGHT if primary else UIKit.TEAL)
	btn.add_theme_color_override("icon_normal_color", UIKit.PAPER_LIGHT if primary else UIKit.TEXT_DIM)
	btn.add_theme_color_override("icon_hover_color", UIKit.PAPER_LIGHT if primary else UIKit.TEAL)
	btn.add_theme_color_override("icon_focus_color", accent.lightened(0.1))
	btn.add_theme_stylebox_override("normal", _menu_style(accent, primary, false))
	btn.add_theme_stylebox_override("focus", _menu_style(accent, primary, false))
	btn.add_theme_stylebox_override("hover", _menu_style(accent, primary, true))
	btn.add_theme_stylebox_override("pressed", _menu_style(accent.darkened(0.2), primary, true))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.mouse_entered.connect(func() -> void: GameAudio.sfx("hover"))
	btn.pressed.connect(func() -> void:
		GameAudio.sfx("click")
		action.call())
	_menu.add_child(btn)
	if primary:
		_primary = btn


func _menu_style(accent: Color, primary: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = (UIKit.TEAL.lightened(0.08) if hover else UIKit.TEAL) if primary else (UIKit.PAPER_LIGHT if hover else Color(UIKit.PAPER, 0.9))
	sb.border_color = Color(accent, 0.95 if hover else (0.75 if primary else 0.28))
	sb.set_border_width_all(2 if hover or primary else 1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.anti_aliasing = true
	if hover:
		sb.shadow_color = Color(accent, 0.3)
		sb.shadow_size = 10
	return sb


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


## 主按钮轻微呼吸光：提示「从这里开始」
func _process(_delta: float) -> void:
	if _primary and is_instance_valid(_primary):
		_primary.modulate = Color(1, 1, 1).lerp(Color(1.06, 1.1, 1.06), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 600.0))


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

