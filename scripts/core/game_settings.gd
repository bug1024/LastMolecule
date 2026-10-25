class_name GameSettings
extends RefCounted
## 玩家设置（音量、全屏、语言），存于 user://settings.cfg。
## 全部为静态成员，任何脚本都可直接读写；修改后调用 save() 落盘、apply() 生效。

const DEFAULT_SAVE_PATH := "user://settings.cfg"
const LOCALES := ["zh_CN", "en"]

static var save_path := DEFAULT_SAVE_PATH  # 测试可改为空串以禁用读写
static var master_volume := 0.8
static var music_volume := 0.6
static var sfx_volume := 0.8
static var fullscreen := false
static var locale := "zh_CN"
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	var saved_locale := String(cfg.get_value("general", "locale", locale))
	locale = saved_locale if LOCALES.has(saved_locale) else "zh_CN"


static func save() -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("general", "locale", locale)
	cfg.save(save_path)


## 把设置应用到音频总线、窗口与语言
static func apply() -> void:
	apply_audio()
	TranslationServer.set_locale(locale)
	apply_display()


## 只改音量：拖动音量条时调用，不碰窗口
static func apply_audio() -> void:
	ensure_loaded()
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)


## 只在「全屏 / 非全屏」真的不一致时切换窗口模式；
## 玩家自己最大化或缩放的窗口保持原样（以前每次拖音量都会把最大化窗口强制还原，窗口来回缩放）。
static func apply_display() -> void:
	ensure_loaded()
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


static func _set_bus(bus_name: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(index, volume <= 0.001)
