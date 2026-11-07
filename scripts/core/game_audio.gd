class_name GameAudio
extends Node
## 音乐与音效（自动加载为 /root/Sound）。
## 其他脚本通过静态方法 GameAudio.music("lab") / GameAudio.sfx("click") 调用；
## 自动加载不存在时（如部分测试环境）静默跳过。
## 所有按钮自动获得点击与悬停音效；按钮设置 meta "sfx" 可替换点击音效，设为 "" 则静音。

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const STAGE_TRACKS := ["", "preclinical", "phase1", "phase2", "phase3"]
const DRIVE_DB := -12.0
const DANGER_DB := -9.0
const BATTLE_DB := -5.0
const SILENT_DB := -60.0
const FADE := 0.8
const SFX_VOICES := 8

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _current := ""
var _active_music: AudioStreamPlayer
var _music_tweens := {}
var _base_gain_db := 0.0
var _duck_db := 0.0
var _duck_tween: Tween
var _cache := {}
var _last_hover_ms := 0
var _drive: AudioStreamPlayer
var _danger: AudioStreamPlayer
var _want_drive := 0.0
var _want_danger := 0.0
var _level_drive := 0.0
var _level_danger := 0.0


static func music(track: String) -> void:
	var node := _instance()
	if node:
		node.play_music(track)


static func battle_theme(stage: int, boss: bool, final_boss: bool) -> void:
	var node := _instance()
	if node == null:
		return
	var theme := String(STAGE_TRACKS[stage]) if stage >= 0 and stage < STAGE_TRACKS.size() else ""
	var track := "boss" if boss else "battle"
	if final_boss:
		node.play_music("boss_final", "", BATTLE_DB)
	elif theme.is_empty():
		node.play_music(track, track, BATTLE_DB)
	else:
		node.play_music(theme + ("_boss" if boss else ""), theme, BATTLE_DB)


## 播放一段不循环的短乐句（胜负、结局），期间背景乐压低
static func sting(track: String) -> void:
	var node := _instance()
	if node:
		node.play_sting(track)


## 战况强度 0–1：drive 推进层（紧迫）、danger 危险层（垂危 / 失控）。由战斗界面在重要节点设定，平滑过渡
static func intensity(drive: float, danger: float) -> void:
	var node := _instance()
	if node:
		node._want_drive = clampf(drive, 0.0, 1.0)
		node._want_danger = clampf(danger, 0.0, 1.0)


static func sfx(id: String) -> void:
	var node := _instance()
	if node:
		node.play_sfx(id)


static func _instance() -> GameAudio:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Sound") as GameAudio


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_sting = _make_player("Music")
	_drive = _make_player("Music")
	_danger = _make_player("Music")
	for i in SFX_VOICES:
		_sfx_players.append(_make_player("SFX"))
	GameSettings.apply()
	get_tree().node_added.connect(_on_node_added)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func _make_player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _load(path: String, loop: bool) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	_cache[path] = stream
	return stream


func play_music(track: String, layer_theme := "", gain_db := 0.0) -> void:
	if track == _current:
		return
	_current = track
	_base_gain_db = gain_db
	var stream := _load(MUSIC_DIR + track + ".ogg", true) if not track.is_empty() else null
	var outgoing := _active_music
	var incoming := _music_b if outgoing == _music_a else _music_a
	_fade_out(outgoing)
	_active_music = incoming if stream != null else null
	if stream != null:
		_cancel_music_tween(incoming)
		incoming.stream = stream
		incoming.volume_db = -40.0
		incoming.play()
		_fade_music(incoming, gain_db + _duck_db, FADE)
	_start_layers(layer_theme if stream != null else "")


## 主曲与两层在同一帧起播。Boss 编曲与普通战斗共用同调同拍的阶段分轨。
func _start_layers(theme: String) -> void:
	_want_drive = 0.0
	_want_danger = 0.0
	_level_drive = 0.0
	_level_danger = 0.0
	for pair in [[_drive, "_drive"], [_danger, "_danger"]]:
		var player: AudioStreamPlayer = pair[0]
		player.stop()
		var layer := _load(MUSIC_DIR + theme + String(pair[1]) + ".ogg", true) if not theme.is_empty() else null
		player.stream = layer
		if layer != null:
			player.volume_db = SILENT_DB
			player.play()


func _process(delta: float) -> void:
	if _drive == null:
		return
	# 进来快、退得慢。独立的音量上限给主旋律和出牌反馈留出空间。
	_level_drive = move_toward(_level_drive, _want_drive, delta * (0.8 if _want_drive > _level_drive else 0.25))
	_level_danger = move_toward(_level_danger, _want_danger, delta * (0.9 if _want_danger > _level_danger else 0.3))
	if _drive.playing:
		_drive.volume_db = DRIVE_DB + _duck_db + linear_to_db(maxf(_level_drive, 0.001))
	if _danger.playing:
		_danger.volume_db = DANGER_DB + _duck_db + linear_to_db(maxf(_level_danger, 0.001))
	if _active_music != null and not _music_tweens.has(_active_music):
		_active_music.volume_db = _base_gain_db + _duck_db


func play_sting(track: String) -> void:
	var stream := _load(MUSIC_DIR + track + ".ogg", false)
	if stream == null:
		return
	if _duck_tween != null:
		_duck_tween.kill()
	if _active_music != null:
		_cancel_music_tween(_active_music)
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_duck_db", -18.0, 0.3)
	_duck_tween.tween_interval(maxf(stream.get_length() - 1.0, 0.5))
	_duck_tween.tween_property(self, "_duck_db", 0.0, 1.2)
	_sting.stream = stream
	_sting.play()


func _cancel_music_tween(player: AudioStreamPlayer) -> void:
	if _music_tweens.has(player):
		(_music_tweens[player] as Tween).kill()
		_music_tweens.erase(player)


func _fade_music(player: AudioStreamPlayer, db: float, duration: float, stop := false) -> void:
	_cancel_music_tween(player)
	var tween := create_tween()
	_music_tweens[player] = tween
	tween.tween_property(player, "volume_db", db, duration)
	tween.tween_callback(func() -> void:
		if stop:
			player.stop()
		_music_tweens.erase(player))


func _fade_out(player: AudioStreamPlayer) -> void:
	if player != null and player.playing:
		_fade_music(player, -40.0, FADE, true)


func play_sfx(id: String) -> void:
	if id.is_empty():
		return
	var stream := _load(SFX_DIR + id + ".ogg", false)
	if stream == null:
		return
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = stream
	player.pitch_scale = randf_range(0.97, 1.03)
	player.play()


## 自动给所有按钮挂上悬停与点击音效
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_hover(button: BaseButton) -> void:
	if button.disabled or Time.get_ticks_msec() - _last_hover_ms < 60:
		return
	_last_hover_ms = Time.get_ticks_msec()
	play_sfx("hover")


func _on_button_pressed(button: BaseButton) -> void:
	play_sfx(String(button.get_meta("sfx", "click")))
