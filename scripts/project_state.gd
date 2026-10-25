class_name ProjectState
extends RefCounted
## 项目状态数据模型（纯数据 + 效果结算，无 UI 依赖）
## 所有效果统一通过 effects 字典应用：
##   research_progress / efficacy / safety_risk / funding / year / data / stage

const PROGRESS_MAX := 100
const RATE_MAX := 100

const _FIELD_LABEL := {
	"research_progress": "fx.research_progress",
	"efficacy": "fx.efficacy",
	"safety_risk": "fx.safety_risk",
	"funding": "fx.funding",
	"year": "fx.year",
	"data": "fx.data",
}

## 字段 → [最小值, 最大值]
const _BOUNDS := {
	"research_progress": [0, PROGRESS_MAX],
	"efficacy": [0, RATE_MAX],
	"safety_risk": [0, RATE_MAX],
	"funding": [0, 999999],
	"year": [1, 9999],
	"data": [0, 999999],
}

var research_progress: int = 0
var efficacy: int = 0
var safety_risk: int = 0
var funding: int = 0
var year: int = 1
var data: int = 0            # 本局数据（驱动 AI 卡，局末按比例存入公司数据）
var stage: String = ""
var stage_battle_won := false   # 本阶段的阶段战斗是否已胜利（里程碑「继续」的条件）
var abilities: Array[String] = []  # 本局持有的研发能力 id


static func from_data(project: Dictionary) -> ProjectState:
	var s := ProjectState.new()
	s.research_progress = int(project.get("initial_progress", 0))
	s.efficacy = int(project.get("initial_efficacy", 20))
	s.safety_risk = int(project.get("initial_safety_risk", 20))
	s.funding = int(project.get("initial_funding_billion", 40))
	s.year = int(project.get("start_year", 1))
	var stages: Array = project.get("stages", [])
	s.stage = String(stages[0]) if not stages.is_empty() else ""
	return s


## 应用效果字典，返回实际变化量 {字段: delta}
## 约定：普通数字键为增量；`set_` 前缀键（如 set_research_progress）为绝对值设置
func apply_effects(effects: Dictionary) -> Dictionary:
	var before_values := {}
	for field in _BOUNDS:
		before_values[field] = get(field)
	for key in effects:
		var name := String(key)
		if name.begins_with("set_") and _BOUNDS.has(name.trim_prefix("set_")):
			set(name.trim_prefix("set_"), int(effects[key]))
	for field in _BOUNDS:
		if effects.has(field):
			set(field, int(get(field)) + int(effects[field]))
	# 绝对值与增量一起结算后再钳制，信号报告最终实际变化。
	var deltas := {}
	for field in _BOUNDS:
		var bounds: Array = _BOUNDS[field]
		set(field, clampi(int(get(field)), bounds[0], bounds[1]))
		var actual := int(get(field)) - int(before_values[field])
		if actual != 0:
			deltas[field] = actual
	if effects.has("stage"):
		var next_stage := String(effects["stage"])
		if next_stage != stage:
			deltas["stage"] = next_stage
			stage = next_stage
	return deltas


func to_dict() -> Dictionary:
	return {"research_progress": research_progress, "efficacy": efficacy, "safety_risk": safety_risk, "funding": funding,
		"year": year, "data": data, "stage": stage, "stage_battle_won": stage_battle_won, "abilities": abilities.duplicate()}


func load_dict(d: Dictionary) -> void:
	for field in _BOUNDS:
		set(field, int(d.get(field, get(field))))
	stage = String(d.get("stage", stage))
	stage_battle_won = bool(d.get("stage_battle_won", false))
	abilities.clear()
	for id in d.get("abilities", []):
		abilities.append(String(id))


## 判断当前状态是否满足选项的 requires 条件
func can_meet(requires: Dictionary) -> bool:
	if requires.has("funding_min") and funding < int(requires["funding_min"]):
		return false
	if requires.has("efficacy_min") and efficacy < int(requires["efficacy_min"]):
		return false
	if requires.has("safety_risk_max") and safety_risk > int(requires["safety_risk_max"]):
		return false
	if requires.has("safety_risk_below") and safety_risk >= int(requires["safety_risk_below"]):
		return false
	if requires.has("data_min") and data < int(requires["data_min"]):
		return false
	if bool(requires.get("battle_won", false)) and not stage_battle_won:
		return false
	return true


static func format_effects(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key in effects:
		if String(key).begins_with("set_"):
			var field := String(key).trim_prefix("set_")
			var label: String = _FIELD_LABEL.get(field, field)
			parts.append(TranslationServer.translate("fx.reset") % [TranslationServer.translate(label), int(effects[key])])
	for field in ["research_progress", "efficacy", "safety_risk", "funding", "year", "data"]:
		_append_delta(parts, _FIELD_LABEL[field], int(effects.get(field, 0)))
	if effects.has("stage"):
		parts.append(TranslationServer.translate("fx.enter_stage") % TranslationServer.translate("stage." + String(effects["stage"])))
	if parts.is_empty():
		return TranslationServer.translate("fx.none")
	return "，".join(parts)


static func _append_delta(parts: Array[String], label_key: String, delta: int) -> void:
	if delta > 0:
		parts.append(TranslationServer.translate("fx.plus") % [TranslationServer.translate(label_key), delta])
	elif delta < 0:
		parts.append(TranslationServer.translate("fx.minus") % [TranslationServer.translate(label_key), delta])
