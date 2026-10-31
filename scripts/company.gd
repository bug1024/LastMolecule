class_name Company
extends RefCounted
## 公司资产（跨局保留）：公司数据、流程等级、历史记录、研究证据与主线战役进度，
## 以及公司的使命：要攻克的疾病、一代代获批分子组成的分子谱系、累计帮助的患者。
## 研究证据：各类项目获批（或高质量终止）时首次获得，记录来源；集齐足够证据后解锁最终项目 LM-001，
## 并决定 LM-001 能选哪些研究路线（见 data/projects.json）。
## 配置来自 data/company.json；存档写入 user://company.json。
## 有效数据 = (本局数据 + min(公司数据 × 迁移率, 上限)) × 数据利用率

const CONFIG_PATH := "res://data/company.json"
const DEFAULT_SAVE_PATH := "user://company.json"

static var default_save_path := DEFAULT_SAVE_PATH  # 测试可改为空串以禁用读写

var save_path := ""
var data := 0               # 累计公司数据
var runs := 0
var approvals := 0
var start_funding_bonus := 0  # 下一局开局资金加成（主动终止时结转）
var history: Array = []       # 最近的项目记录（新的在前），见 settle_run
var best_years := 0           # 最快获批用时（年），0 表示尚未获批
var evidence := {}            # 证据 id → {code, project_type, outcome, run}（同一种只记首次）
var campaign := {}            # 主线战役：{ending, route, code, run}；空表示尚未完成
var disease := ""             # 公司要攻克的疾病（第一次立项时选定，见 data/diseases.json）
var lineage: Array = []       # 分子谱系：每一代获批药物 {code, run, project_type, variant, sites, patients, efficacy}
var patients := 0             # 累计帮助的患者

const HISTORY_LIMIT := 12

var _config: Dictionary = {}


func _init() -> void:
	save_path = default_save_path
	_config = JsonData.load_dict(CONFIG_PATH)


func load_save() -> void:
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return
	var saved := JsonData.load_dict(save_path)
	data = int(saved.get("data", 0))
	runs = int(saved.get("runs", 0))
	approvals = int(saved.get("approvals", 0))
	start_funding_bonus = int(saved.get("start_funding_bonus", 0))
	history = saved.get("history", [])
	best_years = int(saved.get("best_years", 0))
	evidence = saved.get("evidence", {})
	campaign = saved.get("campaign", {})
	disease = String(saved.get("disease", ""))
	lineage = saved.get("lineage", [])
	patients = int(saved.get("patients", 0))


func save() -> void:
	if save_path.is_empty():
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入公司存档: %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"data": data, "runs": runs, "approvals": approvals,
		"start_funding_bonus": start_funding_bonus,
		"history": history, "best_years": best_years,
		"evidence": evidence, "campaign": campaign,
		"disease": disease, "lineage": lineage, "patients": patients,
	}, "  "))


## 流程等级 0–5，由累计公司数据达到阈值自动提升
func process_level() -> int:
	var level := 0
	for threshold in _config.get("level_thresholds", []):
		if data >= int(threshold):
			level += 1
	return level


func next_level_threshold() -> int:
	for threshold in _config.get("level_thresholds", []):
		if data < int(threshold):
			return int(threshold)
	return -1


## 数据利用率（0–1），run_process_bonus 为本局流程卡带来的临时等级
func utilization(run_process_bonus: int) -> float:
	var level := process_level() + run_process_bonus
	return minf(1.0, float(_config.get("base_utilization", 0.4)) + float(_config.get("utilization_per_level", 0.12)) * level)


func effective_data(run_data: int, run_process_bonus: int) -> int:
	var inherited := minf(float(data) * float(_config.get("transfer_rate", 1.0)), float(_config.get("company_data_cap", 40)))
	return int((float(run_data) + inherited) * utilization(run_process_bonus))


## 离下一档还差多少：{next_id, next_multiplier, need_data, process_helps}
## need_data 为本局还需获得的数据（已是最高档时为 -1）；process_helps 表示再 +1 流程即可升档。
func next_tier_step(run_data: int, run_process_bonus: int) -> Dictionary:
	var current := tier_for(effective_data(run_data, run_process_bonus))
	var tiers: Array = _config.get("tiers", [])
	var index := tiers.find(current)
	if index < 0 or index >= tiers.size() - 1:
		return {"next_id": "", "next_multiplier": float(current.get("multiplier", 1.0)), "need_data": -1, "process_helps": false}
	var next: Dictionary = tiers[index + 1]
	var need := 0
	while need < 1000 and effective_data(run_data + need, run_process_bonus) < int(current.get("max", 0)):
		need += 1
	var helps := utilization(run_process_bonus) < 1.0 \
		and effective_data(run_data, run_process_bonus + 1) >= int(current.get("max", 0))
	return {"next_id": String(next.get("id", "")), "next_multiplier": float(next.get("multiplier", 1.0)),
		"need_data": need, "process_helps": helps}


## 有效数据所在档位 {id, multiplier, deviation}
func tier_for(effective: int) -> Dictionary:
	var tiers: Array = _config.get("tiers", [])
	for tier in tiers:
		if effective < int(tier.get("max", 0)):
			return tier
	return tiers.back() if not tiers.is_empty() else {"id": "mid", "multiplier": 1.0, "deviation": 15}


## 一局结束时结算：outcome 为 "approved" / "terminated" / "failed"
## record 为本局概况 {stage, year, efficacy, safety_risk}，写入历史记录
## 返回 {data_saved, funding_carry, level_before, level_after}
func settle_run(run_data: int, outcome: String, funding_left: int, record: Dictionary = {}) -> Dictionary:
	var level_before := process_level()
	var ratio := float(_config.get("data_ratio", {}).get(outcome, 0.3))
	var saved := int(round(run_data * ratio))
	data += saved
	runs += 1
	if outcome == "approved":
		approvals += 1
	start_funding_bonus = 0
	if outcome == "terminated":
		start_funding_bonus = mini(int(round(funding_left * float(_config.get("funding_carry_ratio", 0.3)))),
			int(_config.get("funding_carry_cap", 10)))
	var entry := record.duplicate()
	entry["outcome"] = outcome
	entry["data_saved"] = saved
	entry["index"] = runs
	history.push_front(entry)
	history = history.slice(0, HISTORY_LIMIT)
	var years := int(record.get("year", 0))
	if outcome == "approved" and years > 0 and (best_years == 0 or years < best_years):
		best_years = years
	save()
	return {
		"data_saved": saved,
		"funding_carry": start_funding_bonus,
		"level_before": level_before,
		"level_after": process_level(),
	}


## 清空公司档案（设置页「重置公司档案」）
func reset() -> void:
	data = 0
	runs = 0
	approvals = 0
	start_funding_bonus = 0
	history = []
	best_years = 0
	evidence = {}
	campaign = {}
	disease = ""
	lineage = []
	patients = 0
	save()


## 记录一项研究证据；已经有了返回 false（不重复奖励）
func grant_evidence(id: String, source: Dictionary) -> bool:
	if id.is_empty() or evidence.has(id):
		return false
	evidence[id] = source.duplicate()
	return true


func has_evidence(id: String) -> bool:
	return evidence.has(id)


## 最终项目 LM-001 是否已解锁（持有足够的研究证据）
func final_unlocked() -> bool:
	return evidence.size() >= int(ProjectTypes.config().get("final_unlock_evidence", 2))


func is_campaign_done() -> bool:
	return not campaign.is_empty()


## 下一代药物面对的靶点变体（每获批一代，疾病就进化一次）
func generation() -> int:
	return lineage.size()


## 一代药物获批：记进分子谱系，累计帮助的患者
func record_approval(entry: Dictionary) -> void:
	lineage.append(entry.duplicate(true))
	patients += int(entry.get("patients", 0))


## 患者人数的显示：中文「6.3 万」，英文「63,000」
static func format_people(n: int) -> String:
	if TranslationServer.get_locale().begins_with("zh"):
		if n >= 10000:
			return ("%.1f" % (n / 10000.0)).trim_suffix(".0") + " 万"
		return str(n)
	var digits := str(n)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return digits + out


## 开局领取资金加成（只生效一次）
func take_start_bonus() -> int:
	var bonus := start_funding_bonus
	start_funding_bonus = 0
	return bonus
