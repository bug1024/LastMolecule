class_name SceneRouter
extends CanvasLayer
## 场景切换（自动加载为 /root/Router）：黑幕淡出 → 换场景 → 淡入。
## 通过静态方法 SceneRouter.goto(path) / SceneRouter.restart_scene() 调用；自动加载不存在时直接切换。

const TITLE := "res://title.tscn"
const GAME := "res://main.tscn"
const DURATION := 0.28

var _curtain: ColorRect
var _busy := false


static func goto(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var router := tree.root.get_node_or_null("Router") as SceneRouter
	if router:
		router._transition(func() -> void: tree.change_scene_to_file(path))
	else:
		tree.change_scene_to_file(path)


static func restart_scene() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var router := tree.root.get_node_or_null("Router") as SceneRouter
	if router:
		router._transition(func() -> void: tree.reload_current_scene())
	else:
		tree.reload_current_scene()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_curtain = ColorRect.new()
	_curtain.color = Color(0.02, 0.03, 0.05, 0.0)
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_curtain)


func _transition(change: Callable) -> void:
	if _busy:
		return
	_busy = true
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_curtain, "color:a", 1.0, DURATION)
	await tween.finished
	get_tree().paused = false
	change.call()
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_curtain, "color:a", 0.0, DURATION)
	await back.finished
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
