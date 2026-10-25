class_name RunSave
extends RefCounted
## 进行中项目的存档（user://run.json）。
## game.gd 在每个安全点自动写入：地图上、事件 / 选卡 / 奖励弹窗打开时、战斗开始时；
## 项目结束（获批 / 终止 / 失败）时删除。战斗本身不存中间状态，继续游戏时该场战斗从头再打。
## 标题界面的「继续项目」把 resume_requested 置为 true，main 场景据此读档而不是开新局。

const DEFAULT_SAVE_PATH := "user://run.json"
const VERSION := 1

static var save_path := DEFAULT_SAVE_PATH   # 测试可改为空串以禁用读写
static var resume_requested := false


static func exists() -> bool:
	return not save_path.is_empty() and FileAccess.file_exists(save_path)


static func write(data: Dictionary) -> void:
	if save_path.is_empty():
		return
	data["version"] = VERSION
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


static func read() -> Dictionary:
	if not exists():
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION:
		return {}
	return parsed


static func clear() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## 标题界面显示用的概况 {stage, year, funding}；没有存档时为空
static func summary() -> Dictionary:
	var data := read()
	if data.is_empty():
		return {}
	var state: Dictionary = data.get("state", {})
	return {"stage": String(state.get("stage", "")), "year": int(state.get("year", 1)), "funding": int(state.get("funding", 0))}
