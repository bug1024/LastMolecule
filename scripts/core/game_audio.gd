class_name GameAudio
extends Node
## 音乐与音效（自动加载为 /root/Sound）。
## 其他脚本通过静态方法 GameAudio.music("lab") / GameAudio.sfx("click") 调用；
## 自动加载不存在时（如部分测试环境）静默跳过。
## 所有按钮自动获得点击与悬停音效；按钮设置 meta "sfx" 可替换点击音效，设为 "" 则静音。

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const LOOPS := ["title", "lab", "battle"]
const FADE := 0.8
const SFX_VOICES := 8

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _current := ""
var _cache := {}
var _last_hover_ms := 0


static func music(track: String) -> void:
	var node := _instance()
	if node:
		node.play_music(track)


## 播放一段不循环的短乐句（胜负、结局），期间背景乐压低
static func sting(track: String) -> void:
	var node := _instance()
	if node:
		node.play_sting(track)


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


func play_music(track: String) -> void:
	if track == _current:
		return
	_current = track
	var stream := _load(MUSIC_DIR + track + ".ogg", true) if not track.is_empty() else null
	var outgoing := _music_a if _music_a.playing else _music_b
	var incoming := _music_b if outgoing == _music_a else _music_a
	_fade_out(outgoing)
	if stream == null:
		return
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	var tween := create_tween()
	tween.tween_property(incoming, "volume_db", 0.0, FADE)


func play_sting(track: String) -> void:
	var stream := _load(MUSIC_DIR + track + ".ogg", false)
	if stream == null:
		return
	for player in [_music_a, _music_b]:
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -18.0, 0.3)
			tween.tween_interval(maxf(stream.get_length() - 1.0, 0.5))
			tween.tween_property(player, "volume_db", 0.0, 1.2)
	_sting.stream = stream
	_sting.play()


func _fade_out(player: AudioStreamPlayer) -> void:
	if not player.playing:
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -40.0, FADE)
	tween.tween_callback(player.stop)


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
