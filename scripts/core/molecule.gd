class_name Molecule
extends RefCounted
## 玩家亲手设计的候选分子（原型，只在标准新药项目启用）。「卡组是你的研发能力，分子才是你的角色。」
## 配置见 data/molecule.json：骨架 7 个带类型的位点（连接位 = 核心结构、环上取代位、末端位），片段有收益也有代价，
## 相邻片段按标签触发组合规则；部分片段或组合带「毒性警示」——待验证的风险，可以靠毒理验证排除或确认。
##
## 属性（0–6）如何改变战斗（effects()）：
##   活性      ≥4 开局力量 +1（6 时 +2）；≤1 开局虚弱
##   选择性    ≤1 发现 / 临床前战斗有脱靶规则；≥4 开局坚固 +1、打出的破绽 +1（副作用少）
##   稳定性    ≥4 施加的中毒 +1；≤1 中毒 −1，且活性带来的力量减半（作用难以维持）
##   溶解度    ≤1 临床策略卡费用 +1（给药困难，制剂优化卡可抵消）；≥4 第一回合多抽 1 张
##   毒性警示  未排除或已确认的每一项：临床前战斗敌人力量 +1，终审安全线 −5

const PATH := "res://data/molecule.json"
const PROPS := ["potency", "selectivity", "stability", "solubility"]

var sites := {}        # 位点 id → 片段 id（空位不在字典里）
var inventory: Array = []   # 未使用的片段 id（可重复）
var alerts := {}       # 警示 id → "unknown" / "cleared" / "confirmed"

static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		_cfg = JsonData.load_dict(PATH)
	return _cfg


static func fragment(id: String) -> Dictionary:
	for f in config().get("fragments", []):
		if String(f.get("id", "")) == id:
			return f
	return {}


static func site_type(site_id: String) -> String:
	for s in config().get("sites", []):
		if String(s.get("id", "")) == site_id:
			return String(s.get("type", ""))
	return ""


static func can_place(fragment_id: String, site_id: String) -> bool:
	return (fragment(fragment_id).get("sites", []) as Array).has(site_type(site_id))


## 新分子：拿到起始片段包，位点为空
static func create() -> Molecule:
	var m := Molecule.new()
	m.inventory = (config().get("starter_kit", []) as Array).duplicate()
	return m


## 用 placement（位点 → 片段）整体替换当前结构；片段从「当前结构 + 库存」里取，取不到或位点类型不符则失败
func apply_layout(placement: Dictionary) -> bool:
	var pool: Array = inventory.duplicate()
	for site_id in sites:
		pool.append(sites[site_id])
	for site_id in placement:
		var frag := String(placement[site_id])
		if not can_place(frag, String(site_id)) or not pool.has(frag):
			return false
		pool.erase(frag)
	sites = placement.duplicate()
	inventory = pool
	_sync_alerts()
	return true


## 按预设方案摆放（取不到的片段跳过）
func apply_preset(preset_id: String) -> void:
	var preset: Dictionary = config().get("presets", {}).get(preset_id, {})
	var pool: Array = inventory.duplicate()
	for site_id in sites:
		pool.append(sites[site_id])
	var placement := {}
	for site_id in preset:
		var frag := String(preset[site_id])
		if pool.has(frag) and can_place(frag, String(site_id)):
			placement[site_id] = frag
			pool.erase(frag)
	apply_layout(placement)


## 属性值 {potency, selectivity, stability, solubility}（已含组合效果，限制在 range 内）
func properties() -> Dictionary:
	var cfg := config()
	var props := {}
	for p in PROPS:
		props[p] = int(cfg.get("base", {}).get(p, 1))
	for site_id in sites:
		var fx: Dictionary = fragment(String(sites[site_id])).get("fx", {})
		for p in fx:
			props[p] = int(props.get(p, 0)) + int(fx[p])
	for combo in active_combos():
		var fx: Dictionary = combo.get("fx", {})
		for p in fx:
			props[p] = int(props.get(p, 0)) + int(fx[p])
	var lo := int(cfg.get("range", [0, 6])[0])
	var hi := int(cfg.get("range", [0, 6])[1])
	for p in PROPS:
		props[p] = clampi(int(props[p]), lo, hi)
	return props


## 当前触发的组合规则（相邻标签组合 / 某标签数量达到阈值）
func active_combos() -> Array:
	var out: Array = []
	for combo in config().get("combos", []):
		match String(combo.get("kind", "")):
			"adjacent":
				var need: Array = combo.get("tags", [])
				for pair in config().get("adjacent", []):
					var a := fragment(String(sites.get(pair[0], ""))).get("tags", []) as Array
					var b := fragment(String(sites.get(pair[1], ""))).get("tags", []) as Array
					if (a.has(need[0]) and b.has(need[1])) or (a.has(need[1]) and b.has(need[0])):
						out.append(combo)
			"count":
				var n := 0
				for site_id in sites:
					if (fragment(String(sites[site_id])).get("tags", []) as Array).has(String(combo.get("tag", ""))):
						n += 1
				if n >= int(combo.get("min", 99)):
					out.append(combo)
	return out


## 当前结构带来的警示 id（片段自带 + 组合触发）
func alert_ids() -> Array:
	var ids: Array = []
	for site_id in sites:
		var a := String(fragment(String(sites[site_id])).get("alert", ""))
		if not a.is_empty() and not ids.has(a):
			ids.append(a)
	for combo in active_combos():
		var a := String(combo.get("alert", ""))
		if not a.is_empty() and not ids.has(a):
			ids.append(a)
	return ids


## 结构变化后：新出现的警示为 unknown，不再存在的警示移除；已排除 / 已确认的保留状态
func _sync_alerts() -> void:
	var now := alert_ids()
	for id in alerts.keys():
		if not now.has(id):
			alerts.erase(id)
	for id in now:
		if not alerts.has(id):
			alerts[id] = "unknown"


## 仍有风险的警示数（未验证 + 已确认）
func open_alerts() -> int:
	var n := 0
	for id in alerts:
		if String(alerts[id]) != "cleared":
			n += 1
	return n


func unknown_alerts() -> Array:
	return alerts.keys().filter(func(id: String) -> bool: return String(alerts[id]) == "unknown")


## 属性带来的战斗效果（game 拼进战斗上下文；stage 决定哪些只在特定阶段生效）
## {strength, dexterity, weak, offtarget (bool), vulnerable_bonus, poison_bonus, clinical_cost, first_draw, enemy_strength, lines: [{key,args}]}
func effects(stage: String) -> Dictionary:
	var p := properties()
	var fx := {"strength": 0, "dexterity": 0, "weak": 0, "offtarget": false, "vulnerable_bonus": 0, "poison_bonus": 0,
		"clinical_cost": 0, "first_draw": 0, "enemy_strength": 0, "lines": []}
	var lines: Array = []
	var strength := (int(p.potency) - 2) / 2 if int(p.potency) >= 4 else 0
	if int(p.stability) <= 1 and strength > 0:
		strength = strength / 2
		lines.append({"key": "mol.fx.unstable_strength", "args": [strength]})
	if strength > 0:
		fx.strength = strength
		lines.append({"key": "mol.fx.strength", "args": [strength]})
	if int(p.potency) <= 1:
		fx.weak = 1
		lines.append({"key": "mol.fx.weak", "args": []})
	var early := stage in ["候选化合物发现", "临床前研究"]
	if int(p.selectivity) <= 1 and early:
		fx.offtarget = true
		lines.append({"key": "mol.fx.offtarget", "args": []})
	if int(p.selectivity) >= 4:
		fx.vulnerable_bonus = 1
		fx.dexterity = 1
		lines.append({"key": "mol.fx.vulnerable", "args": []})
	if int(p.stability) >= 4:
		fx.poison_bonus = 1
		lines.append({"key": "mol.fx.poison_up", "args": []})
	elif int(p.stability) <= 1:
		fx.poison_bonus = -1
		lines.append({"key": "mol.fx.poison_down", "args": []})
	if int(p.solubility) <= 1:
		fx.clinical_cost = 1
		lines.append({"key": "mol.fx.clinical_cost", "args": []})
	elif int(p.solubility) >= 4:
		fx.first_draw = 1
		lines.append({"key": "mol.fx.draw", "args": []})
	if open_alerts() > 0 and stage == "临床前研究":
		fx.enemy_strength = open_alerts()
		lines.append({"key": "mol.fx.alerts", "args": [open_alerts(), open_alerts()]})
	fx.lines = lines
	return fx


## 修饰的规模：none（没变）/ local（只换了取代基）/ core（换了连接位 = 核心结构）
func change_kind(new_sites: Dictionary) -> String:
	var changed := false
	for site_id in _all_site_ids():
		if String(sites.get(site_id, "")) != String(new_sites.get(site_id, "")):
			if site_type(site_id) == "linker":
				return "core"
			changed = true
	return "local" if changed else "none"


static func _all_site_ids() -> Array:
	return (config().get("sites", []) as Array).map(func(s: Dictionary) -> String: return String(s.id))


func to_dict() -> Dictionary:
	return {"sites": sites.duplicate(), "inventory": inventory.duplicate(), "alerts": alerts.duplicate()}


static func from_dict(d: Dictionary) -> Molecule:
	var m := Molecule.new()
	for k in d.get("sites", {}):
		m.sites[String(k)] = String(d.sites[k])
	for id in d.get("inventory", []):
		m.inventory.append(String(id))
	for k in d.get("alerts", {}):
		m.alerts[String(k)] = String(d.alerts[k])
	return m
