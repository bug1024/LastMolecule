class_name JsonData
extends RefCounted
## 读取 data/*.json 的公共工具


static func load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("数据文件不存在: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法打开数据文件: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("JSON 解析失败或结构不正确: %s" % path)
		return {}
	return parsed


## 加权随机下标（条目的 weight 字段，缺省为 1）
static func weighted_index(pool: Array, rng: RandomNumberGenerator = null) -> int:
	var total := 0
	for entry in pool:
		total += int(entry.get("weight", 1))
	var roll := (rng.randi_range(1, maxi(total, 1)) if rng != null else randi_range(1, maxi(total, 1)))
	for i in pool.size():
		roll -= int(pool[i].get("weight", 1))
		if roll <= 0:
			return i
	return pool.size() - 1
