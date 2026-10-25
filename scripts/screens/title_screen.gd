extends Control
## 标题界面：Logo、主菜单（开始 / 公司档案 / 玩法说明 / 设置 / 制作名单 / 退出）与公司概况。

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


func _ready() -> void:
	GameSettings.apply()
	var bg := MoleculeBackground.new()
	bg.molecule_count = 26
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build()
	GameAudio.music("title")


func _build() -> void:
	for child in get_children():
		if not child is MoleculeBackground:
			child.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 36 if RunSave.exists() else 56)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 20)
	_logo = TextureRect.new()
	_logo.texture = UIKit.icon("logo")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = Vector2(120, 120)
	brand.add_child(_logo)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UIKit.header(tr("ui.title"), 60, Color(0.93, 0.98, 0.96))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.35, 0.28, 0.6))
	names.add_child(title)
	names.add_child(UIKit.label(tr("title.english"), UIKit.ACCENT, 18))
	brand.add_child(names)
	left.add_child(brand)
	left.add_child(UIKit.label(tr("ui.subtitle"), UIKit.TEXT_DIM, 17))
	var tagline := UIKit.label(tr("title.tagline"), UIKit.TEXT, 15, true)
	tagline.custom_minimum_size = Vector2(520, 0)
	left.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4 if RunSave.exists() else 18)
	left.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 7 if RunSave.exists() else 10)
	_menu.custom_minimum_size = Vector2(320, 0)
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(_menu)
	var saved := RunSave.summary()
	if not saved.is_empty():
		_menu_button("title.continue", "ui_play", "primary", _on_continue)
		var project := tr("project.title") % [String(saved.project_code), tr("project.type." + String(saved.project_type))]
		var line := UIKit.label(tr("title.continue_line") % [project, tr("stage." + String(saved.stage)), int(saved.year), int(saved.funding)], UIKit.ACCENT, 14)
		_menu.add_child(line)
	_menu_button("title.start", "ui_plus" if not saved.is_empty() else "ui_play", "normal" if not saved.is_empty() else "primary", _on_start)
	_menu_button("title.archive", "ui_archive", "normal", func() -> void: _archive.open())
	_menu_button("title.help", "ui_help", "normal", func() -> void: _help.open())
	_menu_button("title.settings", "type_process", "normal", func() -> void: _settings.open())
	_menu_button("title.credits", "ui_music", "normal", func() -> void: _credits.open())
	if OS.get_name() != "Web":
		_menu_button("title.quit", "ui_power", "normal", func() -> void: get_tree().quit())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(UIKit.label(tr("title.version"), Color(UIKit.TEXT_DIM, 0.7), 13))

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(right)
	_hero = TitleHero.new()
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_hero)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.07, 0.09, 0.13, 0.82), Color(0.27, 0.4, 0.45), 14))
	_company_box = VBoxContainer.new()
	_company_box.add_theme_constant_override("separation", 6)
	card.add_child(_company_box)
	right.add_child(card)
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


func _menu_button(key: String, icon_name: String, kind: String, action: Callable) -> void:
	var btn := UIKit.button(tr(key), icon_name, kind, Vector2(320, 44 if RunSave.exists() else 50))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 19)
	btn.pressed.connect(action)
	_menu.add_child(btn)


func _fill_company() -> void:
	if _company_box == null:
		return
	for child in _company_box.get_children():
		child.queue_free()
	var company := Company.new()
	company.load_save()
	_company_box.add_child(UIKit.header(tr("title.company"), 18, UIKit.ACCENT))
	if company.runs == 0:
		_company_box.add_child(UIKit.label(tr("title.company_new"), UIKit.TEXT, 14, true))
		return
	var tier := company.tier_for(company.effective_data(0, 0))
	_company_box.add_child(UIKit.label(tr("title.company_line") % [company.runs, company.approvals, company.process_level(), company.data], UIKit.TEXT, 15, true))
	_company_box.add_child(UIKit.label(tr("title.company_ai") % tr("tier." + String(tier.id)), UIKit.ACCENT_BLUE, 14, true))


func _intro() -> void:
	_menu.modulate.a = 0.0
	_logo.pivot_offset = Vector2(60, 60)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_menu, "modulate:a", 1.0, 0.6).set_delay(0.25)
	tween.tween_property(_logo, "rotation", TAU / 6, 1.2).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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

