class_name GameAudio
extends Node
## 音乐与音效（自动加载为 /root/Sound）。
## 其他脚本通过静态方法 GameAudio.music("lab") / GameAudio.sfx("click") 调用；
## 自动加载不存在时（如部分测试环境）静默跳过。
## 所有按钮自动获得点击与悬停音效；按钮设置 meta "sfx" 可替换点击音效，设为 "" 则静音。
##
## 战斗音乐是三层同长同拍的分轨（基础 / 紧张 / 高潮），装进一个 AudioStreamSynchronized 里同步播放，
## 战况（Normal / Tension / Climax）只改各层音量，并且只在下一个小节线生效，不会突然切断或来回淡入淡出。
## 胜利与 Boss 死亡在下一拍收掉战斗曲，接独立的收束乐句。关键音效出现时音乐让出几分贝。

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const STAGE_TRACKS := ["", "preclinical", "phase1", "phase2", "phase3"]
const BATTLE_DB := -5.0
## 各战况下三层的目标音量（线性）：基础、紧张、高潮
const MOOD_LEVELS := {
	"normal": [1.0, 0.0, 0.0],
	"tension": [1.0, 1.0, 0.0],
	"climax": [1.0, 0.45, 1.0],
}
const LAYER_DB := [0.0, -2.0, -1.0]   # 各层的音量上限，给主旋律和出牌音效留空间
const PAUSE_FADE := 0.2
## 这些音效出现时，音乐短暂让出几分贝，保证关键反馈听得清
const KEY_SFX := ["hit_heavy", "boss_warn", "boss_hurt", "boss_die", "shield_form", "ai_scan", "ai_fail", "synergy", "mol_release"]
const SILENT_DB := -60.0
const FADE := 0.8
const SFX_VOICES := 8
const QUARTER_BEATS := [0.0, 0.25, 0.5, 0.75]

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
var _layers: AudioStreamSynchronized = null   # 当前战斗曲的分层流（非分层曲目为空）
var _bar := 2.0                  # 当前战斗曲一小节的秒数
var _accents: Array = QUARTER_BEATS
var _clock := 0.0                # 当前战斗曲已播放的秒数（暂停时停走）
var _last_bar := -1
var mood := "normal"             # 已生效的战况
var _pending_mood := ""          # 等待下一个小节线生效的战况
var _level := [1.0, 0.0, 0.0]    # 三层当前音量（线性）
var _ending := ""                # 等待下一拍收尾后要播放的乐句
var _paused := false
var _pause_db := 0.0
var _sfx_duck_db := 0.0


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


static func finish_sting(track: String) -> void:
	var node := _instance()
	if node:
		node.fade_sting(track)


## 战况：normal 普通 / tension 紧张（生命低、敌人蓄力、危险机制）/ climax 高潮（Boss 关键阶段、终局）。
## 在下一个小节线生效
static func set_mood(state: String) -> void:
	var node := _instance()
	if node:
		node.request_mood(state)


## 战斗结束：在下一拍收掉战斗曲，再播放收束乐句（win / lose / boss_death）
static func end_battle(phrase: String) -> void:
	var node := _instance()
	if node:
		node.request_end(phrase)


## 暂停菜单打开 / 关闭：音乐在原位置停住，继续时从同一处接上
static func set_paused(on: bool) -> void:
	var node := _instance()
	if node:
		node.pause_music(on)


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


func play_music(track: String, _layer_theme := "", gain_db := 0.0) -> void:
	if track == _current:
		return
	_current = track
	_base_gain_db = gain_db
	_ending = ""
	_paused = false   # 从暂停菜单直接离开（如退回标题）时，新曲目不能继承暂停的静音
	_pause_db = 0.0
	var stream := _music_stream(track) if not track.is_empty() else null
	var outgoing := _active_music
	var incoming := _music_b if outgoing == _music_a else _music_a
	_fade_out(outgoing)
	_active_music = incoming if stream != null else null
	if stream != null:
		_cancel_music_tween(incoming)
		incoming.stream = stream
		incoming.stream_paused = false
		incoming.volume_db = -40.0
		incoming.play()
		_fade_music(incoming, gain_db + _duck_db, FADE)


## 有紧张 / 高潮分轨的曲目装成同步分层流；其余曲目照常单轨循环
func _music_stream(track: String) -> AudioStream:
	var main_stream := _load(MUSIC_DIR + track + ".ogg", true)
	_layers = null
	_bar = float(MusicMeta.BAR.get(track, 2.0))
	_accents = MusicMeta.ACCENTS.get(track, QUARTER_BEATS)
	_clock = 0.0
	_last_bar = -1
	mood = "normal"
	_pending_mood = ""
	_level = [1.0, 0.0, 0.0]
	if main_stream == null:
		return null
	var tension := _load(MUSIC_DIR + track + "_tension.ogg", true)
	var climax := _load(MUSIC_DIR + track + "_climax.ogg", true)
	if tension == null or climax == null:
		return main_stream
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = 3
	for i in 3:
		sync.set_sync_stream(i, [main_stream, tension, climax][i])
	_layers = sync
	_apply_layers()
	return sync


func request_mood(state: String) -> void:
	if not MOOD_LEVELS.has(state):
		return
	_pending_mood = "" if state == mood else state


func request_end(phrase: String) -> void:
	if _active_music == null or not _active_music.playing:
		play_sting(phrase)
		return
	_ending = phrase


func pause_music(on: bool) -> void:
	if on == _paused:
		return
	_paused = on
	var player := _active_music
	if player == null:
		return
	player.stream_paused = on   # 停在原位置；三层在同一个流里，继续时仍然对齐
	if on:
		_pause_db = -30.0
	else:
		create_tween().tween_property(self, "_pause_db", 0.0, PAUSE_FADE * 2.0)   # 继续时轻轻淡入，不突兀


func _apply_layers() -> void:
	if _layers == null:
		return
	for i in 3:
		_layers.set_sync_stream_volume(i, LAYER_DB[i] + linear_to_db(maxf(float(_level[i]), 0.0001)))


## 节拍时钟：战况在小节线生效，收尾在下一拍发生
func _advance_clock(delta: float) -> void:
	if _active_music == null or not _active_music.playing or _active_music.stream_paused:
		return
	var beat := _bar / _accents.size()
	var before := _clock
	_clock += delta
	if not _ending.is_empty() and _beat_index(_clock) != _beat_index(before):
		var phrase := _ending
		_ending = ""
		_fade_music(_active_music, -40.0, 0.5, true)
		_active_music = null
		_current = ""
		_layers = null
		play_sting(phrase, false)
		return
	var bar_index := int(floorf(_clock / _bar))
	if bar_index != _last_bar:
		_last_bar = bar_index
		if not _pending_mood.is_empty():
			mood = _pending_mood
			_pending_mood = ""
	if _layers != null:
		var goal: Array = MOOD_LEVELS[mood]
		for i in 3:
			# 进入一拍内到位，退出用两小节慢慢收
			var rate := 1.0 / beat if float(goal[i]) > float(_level[i]) else 0.5 / _bar
			_level[i] = move_toward(float(_level[i]), float(goal[i]), delta * rate)
		_apply_layers()


func _beat_index(seconds: float) -> int:
	var bars := seconds / _bar
	var index := int(bars) * _accents.size()
	var phase := fposmod(bars, 1.0)
	for i in range(1, _accents.size()):
		if phase < float(_accents[i]):
			break
		index += 1
	return index


func _process(delta: float) -> void:
	_advance_clock(delta)
	_sfx_duck_db = move_toward(_sfx_duck_db, 0.0, delta * 8.0)
	if _active_music != null and not _music_tweens.has(_active_music):
		_active_music.volume_db = _base_gain_db + _duck_db + _pause_db + _sfx_duck_db


func play_sting(track: String, duck := true) -> void:
	var stream := _load(MUSIC_DIR + track + ".ogg", false)
	if stream == null:
		return
	if _duck_tween != null:
		_duck_tween.kill()
		_duck_tween = null
	_sting.stream = stream
	_sting.volume_db = 0.0
	_sting.play()
	if not duck:
		_duck_db = 0.0
		return
	if _active_music != null and _music_tweens.has(_active_music):
		_duck_db = minf(_duck_db, _active_music.volume_db - _base_gain_db - _pause_db - _sfx_duck_db)
		_cancel_music_tween(_active_music)
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_duck_db", -18.0, 0.3)
	_duck_tween.tween_interval(maxf(stream.get_length() - 1.0, 0.5))
	_duck_tween.tween_property(self, "_duck_db", 0.0, 1.2)


func fade_sting(track: String) -> void:
	if _sting.stream == null or _sting.stream.resource_path != MUSIC_DIR + track + ".ogg":
		return
	if _duck_tween != null:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_duck_db", 0.0, 0.18)
	_duck_tween.parallel().tween_property(_sting, "volume_db", SILENT_DB, 0.18)
	_duck_tween.tween_callback(_sting.stop)


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
	if KEY_SFX.has(id):
		_sfx_duck_db = minf(_sfx_duck_db, -3.0)


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
