class_name ResearchMap
extends RefCounted
## 研发地图数据模型：每个研发阶段生成一张分层分支地图（data/maps.json）。
## 结构：第一层全是战斗 → 若干随机层（精英从指定层开始出现）→ 最后一层全是平台建设（休整）
##   → Boss 层（1 个节点）→ 里程碑层（1 个节点）。
## 节点 {type, next: [下一层可达下标]}；玩家每次在可达节点中选择一个。
## 纯数据 + 游标，不含 UI 与业务流转（流转由 game.gd 驱动）。

const MAPS_PATH := "res://data/maps.json"

var _config: Dictionary = {}
var _stage := ""
var _layers: Array = []   # Array[Array[Dictionary]]
var _layer := -1          # 当前所在层（-1 为尚未进入）
var _pos := -1            # 当前所在层中的节点下标
var path: Array = []      # 已走过的节点下标（按层）


func _init() -> void:
	_config = JsonData.load_dict(MAPS_PATH)


func generate(stage: String, rng: RandomNumberGenerator) -> void:
	_stage = stage
	_layers.clear()
	_layer = -1
	_pos = -1
	path.clear()
	var width: Array = _config.get("width", [2, 4])
	var weights: Dictionary = (_config.get("weights", {"fight": 1}) as Dictionary).duplicate()
	var overrides: Dictionary = _config.get("stage_weights", {}).get(stage, {})
	for type in overrides:
		weights[type] = int(overrides[type])
	var layer_count := int(_config.get("layers", 5))
	var elite_from := int(_config.get("elite_from_layer", 2))
	for i in layer_count:
		var layer: Array = []
		var forced := ""
		if i == 0:
			forced = String(_config.get("first_layer", "fight"))
		elif i == layer_count - 1:
			forced = String(_config.get("last_layer", "platform"))
		var pool: Array = []
		for type in weights:
			if int(weights[type]) > 0 and not (type == "elite" and i < elite_from):
				pool.append({"type": type, "weight": int(weights[type])})
		var used_special := {}
		for j in rng.randi_range(int(width[0]), int(width[1])):
			var type := forced
			if type.is_empty():
				type = String(pool[JsonData.weighted_index(pool, rng)].type)
				# 同层不重复出现精英 / 加速通道 / 合作 / 平台节点
				var guard := 0
				while type not in ["fight", "research", "event"] and used_special.has(type) and guard < 20:
					type = String(pool[JsonData.weighted_index(pool, rng)].type)
					guard += 1
				used_special[type] = true
			layer.append({"type": type, "next": []})
		_layers.append(layer)
	_layers.append([{"type": "boss", "next": []}])
	_layers.append([{"type": "milestone", "next": []}])
	_connect_layers()


## 相邻层按相对位置连线：每个节点连向下一层位置最近的 1–2 个节点，并保证下一层每个节点都有入边
func _connect_layers() -> void:
	for i in _layers.size() - 1:
		var current: Array = _layers[i]
		var following: Array = _layers[i + 1]
		var has_incoming := {}
		for j in current.size():
			var center := (float(j) + 0.5) / current.size() * following.size() - 0.5
			var targets := {}
			targets[clampi(int(floor(center)), 0, following.size() - 1)] = true
			targets[clampi(int(ceil(center)), 0, following.size() - 1)] = true
			for t in targets:
				current[j].next.append(int(t))
				has_incoming[int(t)] = true
		for k in following.size():
			if not has_incoming.has(k):
				var nearest := clampi(roundi((float(k) + 0.5) / following.size() * current.size() - 0.5), 0, current.size() - 1)
				current[nearest].next.append(k)
		for node in current:
			node.next.sort()


func to_dict() -> Dictionary:
	return {"stage": _stage, "layers": _layers.duplicate(true), "layer": _layer, "pos": _pos, "path": path.duplicate()}


## 读档：JSON 里的数字都是浮点，节点连线下标要转回整数
func load_dict(d: Dictionary) -> void:
	_stage = String(d.get("stage", ""))
	_layers.clear()
	for layer in d.get("layers", []):
		var nodes: Array = []
		for node in layer:
			var next: Array = []
			for k in node.get("next", []):
				next.append(int(k))
			nodes.append({"type": String(node.get("type", "fight")), "next": next})
		_layers.append(nodes)
	_layer = int(d.get("layer", -1))
	_pos = int(d.get("pos", -1))
	path.clear()
	for k in d.get("path", []):
		path.append(int(k))


func get_stage() -> String:
	return _stage


func get_layers() -> Array:
	return _layers


func get_layer_index() -> int:
	return _layer


func get_position() -> int:
	return _pos


func get_current_node() -> Dictionary:
	if _layer < 0 or _layer >= _layers.size():
		return {}
	return _layers[_layer][_pos]


## 下一层中可前往的节点下标
func get_choices() -> Array:
	if _layers.is_empty() or _layer >= _layers.size() - 1:
		return []
	if _layer < 0:
		return range(_layers[0].size())
	return _layers[_layer][_pos].next


func choose(index: int) -> bool:
	if not get_choices().has(index):
		return false
	_layer += 1
	_pos = index
	path.append(index)
	return true


func is_at_last_layer() -> bool:
	return _layer == _layers.size() - 1
