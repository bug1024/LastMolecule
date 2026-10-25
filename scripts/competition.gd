class_name Competition
extends RefCounted
## 竞争格局：若干竞品管线随年份推进，并改变审评门槛与融资环境（data/competitors.json）。
##   竞品获批 → 终审疗效门槛提高、之后的 Boss 获得效力（评审标准更严）
##   竞品二期读出积极 → 融资收益下降
##   竞品失败 → 融资收益上升
##   新机制出现 → 终审疗效门槛提高、融资收益下降
## 竞品阶段下标：0 发现 … 4 三期，5 已获批。

const APPROVED_STAGE := 5

var competitors: Array = []   # [{name_key, stage, status, chance}]
var efficacy_bar_bonus := 0
var boss_strength_bonus := 0
var finance_mod := 0
var intel_revealed := false   # 打出过「AI 竞品情报」：显示各竞品的预计上市年数
var news: Array = []          # 最新在前 [{key, args}]

var _config: Dictionary = {}
var _new_mechanism := false


func _init() -> void:
	_config = JsonData.load_dict("res://data/competitors.json")


func setup(rng: RandomNumberGenerator) -> void:
	competitors.clear()
	news.clear()
	var names: Array = _config.get("names", []).duplicate()
	var count_range: Array = _config.get("count", [2, 3])
	var stage_range: Array = _config.get("start_stage", [0, 2])
	var chance_range: Array = _config.get("advance_chance", [18, 30])
	for i in mini(rng.randi_range(int(count_range[0]), int(count_range[1])), names.size()):
		competitors.append({
			"name_key": String(names[i]),
			"stage": rng.randi_range(int(stage_range[0]), int(stage_range[1])),
			"status": "active",
			"chance": rng.randi_range(int(chance_range[0]), int(chance_range[1])),
		})


func to_dict() -> Dictionary:
	return {"competitors": competitors.duplicate(true), "efficacy_bar_bonus": efficacy_bar_bonus,
		"boss_strength_bonus": boss_strength_bonus, "finance_mod": finance_mod, "intel_revealed": intel_revealed,
		"news": news.duplicate(true), "new_mechanism": _new_mechanism}


func load_dict(d: Dictionary) -> void:
	competitors.clear()
	for c in d.get("competitors", []):
		competitors.append({"name_key": String(c.get("name_key", "")), "stage": int(c.get("stage", 0)),
			"status": String(c.get("status", "active")), "chance": int(c.get("chance", 20))})
	efficacy_bar_bonus = int(d.get("efficacy_bar_bonus", 0))
	boss_strength_bonus = int(d.get("boss_strength_bonus", 0))
	finance_mod = int(d.get("finance_mod", 0))
	intel_revealed = bool(d.get("intel_revealed", false))
	news = (d.get("news", []) as Array).duplicate(true)
	_new_mechanism = bool(d.get("new_mechanism", false))


## 推进一年，返回本年新闻
func tick_year(rng: RandomNumberGenerator) -> Array:
	var fresh: Array = []
	for c in competitors:
		if String(c.status) != "active":
			continue
		if rng.randi_range(1, 100) <= int(_config.get("fail_chance", 6)):
			c.status = "failed"
			finance_mod += int(_config.get("fail_finance", 1))
			fresh.append({"key": "news.competitor_failed", "args": [c.name_key]})
			continue
		if rng.randi_range(1, 100) > int(c.chance):
			continue
		c.stage = int(c.stage) + 1
		if int(c.stage) == 4:
			finance_mod += int(_config.get("readout_finance", -1))
			fresh.append({"key": "news.competitor_readout", "args": [c.name_key]})
		elif int(c.stage) >= APPROVED_STAGE:
			c.status = "approved"
			efficacy_bar_bonus += int(_config.get("approval_efficacy_bar", 10))
			boss_strength_bonus += int(_config.get("approval_boss_strength", 1))
			fresh.append({"key": "news.competitor_approved", "args": [c.name_key, int(_config.get("approval_efficacy_bar", 10))]})
		else:
			fresh.append({"key": "news.competitor_advanced", "args": [c.name_key, "stage_index." + str(c.stage)]})
	if not _new_mechanism and rng.randi_range(1, 100) <= int(_config.get("new_mechanism_chance", 4)):
		_new_mechanism = true
		efficacy_bar_bonus += int(_config.get("new_mechanism_efficacy_bar", 5))
		finance_mod += int(_config.get("new_mechanism_finance", -1))
		fresh.append({"key": "news.new_mechanism", "args": [int(_config.get("new_mechanism_efficacy_bar", 5))]})
	for item in fresh:
		news.push_front(item)
	if news.size() > 6:
		news.resize(6)
	return fresh


## 预计还需几年上市（情报可见时显示）
func forecast_years(c: Dictionary) -> int:
	if String(c.status) != "active":
		return -1
	var remaining := APPROVED_STAGE - int(c.stage)
	return int(ceil(remaining * 100.0 / maxi(int(c.chance), 1)))
