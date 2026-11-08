class_name GameAudio
extends Node
## 音乐与音效（自动加载为 /root/Sound）。
## 其他脚本通过静态方法 GameAudio.play("MAP") / GameAudio.sfx("click") 调用；
## 自动加载不存在时（如部分测试环境）静默跳过。
## 所有按钮自动获得点击与悬停音效；按钮设置 meta "sfx" 可替换点击音效，设为 "" 则静音。
##
## 背景音乐按逻辑 ID 集中注册（MUSIC 表）：TITLE / MAP / LAB / EVENT / BATTLE / BOSS / ENDING。
## 各页面只说「现在是哪种场景」，不写文件路径。曲目文件、循环点和节拍由 tools/import_suno_music.py
## 写进 MusicTracks；文件缺失时退回旧的程序合成曲（fallback）并只警告一次。
##
## 两个音乐播放器做等功率交叉淡化，同一时刻最多两层背景音乐加一段短乐句。
## 同一个 ID 重复请求不会重播；地图、实验室这类页面离开后两分钟内回来，从离开时的位置接着播。
## 战斗结束在下一拍收掉战斗曲，接独立的收束乐句。关键音效出现时音乐让出几分贝。
## 旧的程序合成战斗曲有三层分轨（基础 / 紧张 / 高潮），作为兜底时仍按小节线换层。

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"

## 背景音乐注册表。gain_db 叠在导入时统一到 −16 LUFS 的文件上；fade 是切入这首时的交叉淡化秒数；
## resume 表示短时间内回到这个页面时从离开的位置接着播；fallback 是新曲缺失时用的旧曲。
const MUSIC := {
	"TITLE": {"track": "title", "gain_db": -3.0, "fade": 1.2, "resume": true, "fallback": "title", "fallback_db": -6.5},
	"MAP": {"track": "map", "gain_db": -3.5, "fade": 1.0, "resume": true, "fallback": "lab", "fallback_db": -6.5},
	"LAB": {"track": "lab", "gain_db": -4.0, "fade": 1.0, "resume": true, "fallback": "lab", "fallback_db": -6.5},
	"EVENT": {"track": "event", "gain_db": -3.5, "fade": 0.8, "resume": true, "fallback": "lab", "fallback_db": -6.5},
	"BATTLE": {"track": "battle", "gain_db": -4.0, "fade": 0.6, "resume": false, "fallback": "battle", "fallback_db": -1.0},
	"BOSS": {"track": "boss", "gain_db": -3.0, "fade": 1.2, "resume": false, "fallback": "boss", "fallback_db": -1.0},
	"ENDING": {"track": "ending", "gain_db": -2.5, "fade": 1.5, "resume": false, "fallback": "campaign_approved", "fallback_db": -4.0},
}
const LEGACY_IDS := {"title": "TITLE", "lab": "LAB", "map": "MAP", "event": "EVENT", "battle": "BATTLE", "boss": "BOSS", "ending": "ENDING"}
const RESUME_WINDOW_MS := 120000
const STOP_FADE := 0.8
## 各战况下三层的目标音量（线性）：基础、紧张、高潮。只对带分轨的兜底战斗曲生效。
const MOOD_LEVELS := {
	"normal": [1.0, 0.0, 0.0],
	"tension": [1.0, 1.0, 0.0],
	"climax": [1.0, 0.45, 1.0],
}
const LAYER_DB := [0.0, -5.0, -7.0]
const PAUSE_FADE := 0.2
## 这些音效出现时，音乐短暂让出几分贝，保证关键反馈听得清；普通出牌、悬停不在其中
const KEY_SFX := ["hit_heavy", "boss_warn", "boss_hurt", "boss_die", "boss_threat", "shield_form", "ai_scan", "ai_fail", "synergy", "mol_release"]
const SILENT_DB := -60.0
const SFX_VOICES := 8
const SFX_SAME_GAP_MS := 40       # 同一个音效 40 ms 内重复触发只响一次，避免叠加过载
const QUARTER_BEATS := [0.0, 0.25, 0.5, 0.75]
const BUS_RATE := 5.0             # 音量条与静音：总线音量每秒最多变化的线性幅度

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _sfx_last_ms := {}
var _current := ""                # 当前背景音乐的逻辑 ID（旧接口的曲目名会换成 ID）
var _active_music: AudioStreamPlayer
var _voice := {}                  # 播放器 → {id, amp, target, rate, gain, stop, mode, gap}
var _resume := {}                 # 逻辑 ID → {pos, ms}
var _restart_left := -1.0
var _warned := {}
var _duck_db := 0.0
var _duck_tween: Tween
var _cache := {}
var _last_hover_ms := 0
var _layers: AudioStreamSynchronized = null   # 兜底战斗曲的分层流（其余曲目为空）
var _bar := 2.0                  # 当前曲目一小节的秒数
var _accents: Array = QUARTER_BEATS
var _clock := 0.0                # 当前曲目已播放的秒数（暂停时停走）
var _last_bar := -1
var mood := "normal"             # 已生效的战况
var _pending_mood := ""          # 等待下一个小节线生效的战况
var _level := [1.0, 0.0, 0.0]    # 三层当前音量（线性）
var _ending := ""                # 等待下一拍收尾后要播放的乐句
var _paused := false
var _pause_db := 0.0
var _sfx_duck_db := 0.0
var _bus_targets := {}           # 总线名 → 目标线性音量
var tracks: Dictionary = MusicTracks.DATA   # 曲目元数据；测试可换成空表来验证旧曲兜底


## 切到某个场景的背景音乐（TITLE / MAP / LAB / EVENT / BATTLE / BOSS / ENDING）；
## 同一个 ID 正在播放时什么都不做。fade < 0 时用注册表里的淡化时长
static func play(id: String, fade := -1.0) -> void:
	var node := _instance()
	if node:
		node.play_music(id, fade)


## 淡出并停止背景音乐（例如 Boss 登场前先让场景安静下来）
static func stop_music(fade := STOP_FADE) -> void:
	var node := _instance()
	if node:
		node.play_music("", fade)


## 旧接口：music("title") / music("lab") / music("") 仍然可用，内部换成逻辑 ID
static func music(track: String) -> void:
	play(String(LEGACY_IDS.get(track, track)))


## 战斗配乐：普通战斗 BATTLE，Boss 战（含最终 Boss）BOSS
static func battle_theme(_stage: int, boss: bool, _final_boss: bool) -> void:
	play("BOSS" if boss else "BATTLE")


## 播放一段不循环的短乐句（胜负），期间背景乐压低
static func sting(track: String) -> void:
	var node := _instance()
	if node:
		node.play_sting(track)


static func finish_sting(track: String) -> void:
	var node := _instance()
	if node:
		node.fade_sting(track)


## 战况：normal 普通 / tension 紧张 / climax 高潮。在下一个小节线生效；
## 单轨的新曲目没有分轨可换，请求会被记下但不改变音乐，也绝不会让曲子重播
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


## 当前背景音乐的逻辑 ID（没有音乐时为空）
static func current() -> String:
	var node := _instance()
	return node._current if node else ""


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
	for player in [_music_a, _music_b]:
		player.finished.connect(_on_music_finished.bind(player))
	_sting = _make_player("Music")
	for i in SFX_VOICES:
		_sfx_players.append(_make_player("SFX"))
	GameSettings.apply()   # 启动时直接到位，不做渐变
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


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	_cache[path] = stream
	return stream


## 音量条与静音：总线音量平滑地走向目标，拖动或静音时不会爆音
func set_bus_target(bus_name: String, linear: float) -> void:
	_bus_targets[bus_name] = clampf(linear, 0.0, 1.0)


func _step_buses(delta: float) -> void:
	for bus_name in _bus_targets:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			continue
		var target := float(_bus_targets[bus_name])
		var now := 0.0 if AudioServer.is_bus_mute(index) else db_to_linear(AudioServer.get_bus_volume_db(index))
		now = move_toward(now, target, delta * BUS_RATE)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(now, 0.0001)))
		AudioServer.set_bus_mute(index, now <= 0.0005 and target <= 0.0005)


# ---------- 背景音乐 ----------

## 曲目解析：注册表 → 生成的曲目元数据 → 新曲缺失时的旧曲兜底
func _resolve(id: String) -> Dictionary:
	var entry: Dictionary = MUSIC.get(id, {})
	if entry.is_empty():
		push_warning("GameAudio: 未注册的音乐 ID %s" % id)
		return {}
	var info: Dictionary = tracks.get(String(entry.track), {})
	var stream: AudioStream = _load(String(info.file)) if not info.is_empty() else null
	if stream != null:
		return {"stream": stream, "gain": float(entry.gain_db), "mode": String(info.mode), "offset": float(info.loop_offset),
			"bar": float(info.bar), "gap": float(info.get("gap", 1.0)), "legacy": ""}
	var legacy := String(entry.fallback)
	if not _warned.has(id):
		_warned[id] = true
		push_warning("GameAudio: %s 的曲目文件缺失，改用旧曲 %s" % [id, legacy])
	stream = _load(MUSIC_DIR + legacy + ".ogg")
	if stream == null:
		return {}
	return {"stream": stream, "gain": float(entry.fallback_db), "mode": "loop", "offset": 0.0,
		"bar": float(MusicMeta.BAR.get(legacy, 2.0)), "gap": 1.0, "legacy": legacy}


func play_music(id: String, fade := -1.0) -> void:
	if id == _current:
		return
	_current = id
	_ending = ""
	_restart_left = -1.0
	_paused = false   # 从暂停菜单直接离开（如退回标题）时，新曲目不能继承暂停的静音
	_pause_db = 0.0
	_layers = null
	_reset_clock(2.0, QUARTER_BEATS)
	var outgoing := _active_music
	var seconds := fade if fade >= 0.0 else (float(MUSIC[id].fade) if MUSIC.has(id) else STOP_FADE)
	# 快速来回切换（A → B → A）：A 还在淡出，直接把它拉回来，不重播
	var other := _music_b if outgoing == _music_a else _music_a
	if not id.is_empty() and _voice.has(other) and String(_voice[other].id) == id and other.playing:
		_retarget(other, 1.0, seconds, false)
		if outgoing != null:
			_retarget(outgoing, 0.0, seconds, true)
		_active_music = other
		_reset_clock(float(_voice[other].bar), QUARTER_BEATS)
		return
	if outgoing != null:
		_retarget(outgoing, 0.0, seconds, true)
	_active_music = null
	if id.is_empty():
		return
	var track := _resolve(id)
	if track.is_empty():
		return
	var incoming := other
	if incoming.playing:   # 第三首插进来：仍在淡出的那首直接停掉，同时最多两层背景音乐
		_release(incoming)
	var stream: AudioStream = track.stream
	if String(track.legacy) != "" and MusicMeta.BAR.has(String(track.legacy)):
		stream = _legacy_layers(String(track.legacy), stream)
	elif stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = String(track.mode) == "loop"
		ogg.loop_offset = float(track.offset)
	_reset_clock(float(track.bar), MusicMeta.ACCENTS.get(String(track.legacy), QUARTER_BEATS))
	incoming.stream = stream
	incoming.stream_paused = false
	_voice[incoming] = {"id": id, "amp": 0.0, "target": 1.0, "rate": 1.0 / maxf(seconds, 0.01), "gain": float(track.gain),
		"stop": false, "mode": String(track.mode), "gap": float(track.gap), "bar": float(track.bar)}
	var start := 0.0
	var memory: Dictionary = _resume.get(id, {})
	if bool(MUSIC[id].resume) and not memory.is_empty() and Time.get_ticks_msec() - int(memory.ms) < RESUME_WINDOW_MS:
		start = float(memory.pos)
	incoming.volume_db = SILENT_DB
	incoming.play(start)
	_active_music = incoming
	_apply_voice(incoming)


func _reset_clock(bar: float, accents: Array) -> void:
	_bar = bar
	_accents = accents
	_clock = 0.0
	_last_bar = -1
	mood = "normal"
	_pending_mood = ""
	_level = [1.0, 0.0, 0.0]


func _retarget(player: AudioStreamPlayer, target: float, seconds: float, stop: bool) -> void:
	if not _voice.has(player):
		return
	var v: Dictionary = _voice[player]
	v.target = target
	v.rate = 1.0 / maxf(seconds, 0.01)
	v.stop = stop


## 停掉一个播放器；可续播的曲目记下位置
func _release(player: AudioStreamPlayer) -> void:
	if _voice.has(player):
		var id := String(_voice[player].id)
		if MUSIC.has(id) and bool(MUSIC[id].resume) and player.playing:
			_resume[id] = {"pos": player.get_playback_position(), "ms": Time.get_ticks_msec()}
		_voice.erase(player)
	player.stop()
	player.stream_paused = false


func _apply_voice(player: AudioStreamPlayer) -> void:
	var v: Dictionary = _voice[player]
	var shaped := sin(clampf(float(v.amp), 0.0, 1.0) * PI * 0.5)   # 等功率：交叉时总响度不塌陷
	player.volume_db = float(v.gain) + linear_to_db(maxf(shaped, 0.0001)) + _duck_db + _pause_db + _sfx_duck_db


func _step_voices(delta: float) -> void:
	for player: AudioStreamPlayer in _voice.keys():
		var v: Dictionary = _voice[player]
		if not player.stream_paused:
			v.amp = move_toward(float(v.amp), float(v.target), delta * float(v.rate))
		if bool(v.stop) and float(v.amp) <= 0.0:
			_release(player)
			continue
		_apply_voice(player)
	if _restart_left >= 0.0 and not _paused:
		_restart_left -= delta
		if _restart_left < 0.0 and _active_music != null and _voice.has(_active_music):
			var v: Dictionary = _voice[_active_music]
			v.amp = 0.0
			v.target = 1.0
			v.rate = 1.0
			_active_music.play(0.0)
			_clock = 0.0


## restart 模式：整首播完（结尾已烘焙淡出）后停顿片刻，从头淡入
func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player != _active_music or not _voice.has(player):
		return
	if String(_voice[player].mode) == "restart":
		_restart_left = float(_voice[player].gap)


## 兜底的旧战斗曲有紧张 / 高潮分轨时，装成同步分层流
func _legacy_layers(track: String, main_stream: AudioStream) -> AudioStream:
	if main_stream is AudioStreamOggVorbis:
		(main_stream as AudioStreamOggVorbis).loop = true
	var tension := _load(MUSIC_DIR + track + "_tension.ogg")
	var climax := _load(MUSIC_DIR + track + "_climax.ogg")
	if tension == null or climax == null:
		return main_stream
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = 3
	for i in 3:
		var layer: AudioStream = [main_stream, tension, climax][i]
		if layer is AudioStreamOggVorbis:
			(layer as AudioStreamOggVorbis).loop = true
		sync.set_sync_stream(i, layer)
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
	for player: AudioStreamPlayer in _voice.keys():
		player.stream_paused = on   # 停在原位置；继续时仍从这里接上
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
		_retarget(_active_music, 0.0, 0.5, true)
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
	_step_voices(delta)
	_step_buses(delta)


func play_sting(track: String, duck := true) -> void:
	var stream := _load(MUSIC_DIR + track + ".ogg")
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	if _duck_tween != null:
		_duck_tween.kill()
		_duck_tween = null
	_sting.stream = stream
	_sting.volume_db = 0.0
	_sting.play()
	if not duck:
		_duck_db = 0.0
		return
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


# ---------- 音效 ----------

func play_sfx(id: String) -> void:
	if id.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_sfx_last_ms.get(id, -100000)) < SFX_SAME_GAP_MS:
		return
	_sfx_last_ms[id] = now
	var stream := _load(SFX_DIR + id + ".ogg")
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
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
