class_name ProjectTypes
extends RefCounted
## 项目类型（data/projects.json）：每类项目在 project.json 基础上改变起始牌组、终审要求与战斗规则，
## 让不同项目需要不同打法。文案键：project.type.<id>（名称）/ .tag（一句话打法）/ .desc（规则说明）。

const PATH := "res://data/projects.json"


static func config() -> Dictionary:
	return JsonData.load_dict(PATH)


static func all() -> Array:
	return config().get("types", [])


static func default_id() -> String:
	return String(config().get("default", "standard"))


## 找不到时返回默认类型
static func find(type_id: String) -> Dictionary:
	var types := all()
	for t in types:
		if String(t.get("id", "")) == type_id:
			return t
	for t in types:
		if String(t.get("id", "")) == default_id():
			return t
	return {"id": "standard"}


## 普通项目编号：LM-001 留给主线最终分子，第 n 个项目为 LM-(n+1)
static func code_for_run(run_index: int) -> String:
	var cfg := config()
	return String(cfg.get("code_format", "LM-%03d")) % (int(cfg.get("code_start", 2)) + run_index)


## 把类型的 overrides 合并进项目配置（字典逐层合并，其它值直接覆盖）
static func apply_overrides(project: Dictionary, type_cfg: Dictionary) -> Dictionary:
	var merged := project.duplicate(true)
	_merge(merged, type_cfg.get("overrides", {}))
	return merged


static func _merge(into: Dictionary, from: Dictionary) -> void:
	for key in from:
		if into.get(key) is Dictionary and from[key] is Dictionary:
			_merge(into[key], from[key])
		else:
			into[key] = from[key]
