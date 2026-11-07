class_name CharacterProfiles
extends RefCounted
## 角色的运动性格：每个阶段只写目标姿态和弹簧手感，节奏由 CharacterMotion 的弹簧算出来。
## 待机项格式：[幅度, 频率 Hz, 不规则度 0–1, 相位]；阶段里 k 越大越干脆，z 越小回弹越多。
## 分子以分子单位计位移；敌人以身体高度计位移。

## 主角分子：敏捷、精准、有生命力。重心缓慢游移，骨架有弹性，末端片段和丝带各自滞后跟随
static func molecule() -> Dictionary:
	return {
		"idle": {
			"x": [0.05, 0.19, 0.6], "y": [0.06, 0.31, 0.5],
			"angle": [0.012, 0.16, 0.55], "bend": [0.06, 0.26, 0.6, 1.1],
			"sx": [0.007, 0.31, 0.3, PI], "sy": [0.009, 0.31, 0.3],
			"adjust": {"x": 0.09, "angle": 0.022, "bend": 0.07, "pose": 0.05},
			"adjust_every": [3.0, 6.5],
		},
		"idle_spring": [36.0, 0.9],
		"lag": [55.0, 0.42],
		"trail": [19.0, 0.3],
		# 近身突进：向后收缩蓄力 → 猛地加速冲出 → 命中后带着惯性略微过冲 → 自然回弹
		"anticipation_attack": [{"t": 0.17, "x": -0.5, "y": 0.06, "angle": 0.07, "sx": 1.05, "sy": 0.93, "pose": -0.42, "bend": -0.18, "k": 170, "z": 0.9}],
		"attack": [
			{"t": 0.12, "reach": 1.0, "angle": -0.1, "sx": 1.07, "sy": 0.96, "pose": 1.0, "bend": 0.28, "k": 950, "z": 0.62},
			{"t": 0.09, "reach": 0.95, "angle": -0.07, "pose": 0.9, "bend": 0.12, "k": 320, "z": 0.4, "cue": "impact"},
		],
		# 原地出招：小幅后拉 → 前送释放
		"anticipation_cast": [{"t": 0.1, "x": -0.2, "angle": 0.04, "sx": 1.03, "sy": 0.96, "pose": -0.3, "bend": -0.1, "k": 260, "z": 0.85}],
		"cast": [
			{"t": 0.1, "x": 0.24, "angle": -0.05, "sx": 0.97, "sy": 1.04, "pose": 0.8, "bend": 0.15, "k": 700, "z": 0.5, "cue": "impact"},
			{"t": 0.08, "x": 0.1, "pose": 0.35, "k": 300, "z": 0.5},
		],
		"recovery": [{"t": 0.32, "k": 110, "z": 0.6}],
		"hit": [{"t": 0.13, "x": -0.24, "angle": 0.06, "sx": 1.05, "sy": 0.94, "bend": -0.3, "pose": -0.15, "k": 300, "z": 0.5}],
		"hit_heavy": [
			{"t": 0.1, "x": -0.55, "y": 0.06, "angle": 0.13, "sx": 1.1, "sy": 0.87, "bend": -0.55, "pose": -0.32, "k": 260, "z": 0.45},
			{"t": 0.2, "x": -0.35, "angle": 0.07, "sx": 1.04, "sy": 0.95, "bend": -0.2, "pose": -0.12, "k": 110, "z": 0.6},
		],
		"hit_kick": {"x": 5.0, "angle": 0.8, "sx": 0.8, "sy": -1.0, "bend": -3.0},
		# 护盾：收缩成防御姿态，外层展开保护结构后恢复战斗姿态
		"defend": [
			{"t": 0.14, "x": -0.08, "angle": 0.02, "sx": 0.93, "sy": 0.9, "pose": -0.45, "bend": -0.22, "k": 420, "z": 0.75},
			{"t": 0.3, "sx": 0.97, "sy": 0.96, "pose": -0.22, "k": 200, "z": 0.7},
		],
		"status": [
			{"t": 0.08, "sx": 1.03, "sy": 0.96, "bend": 0.16, "k": 600, "z": 0.2},
			{"t": 0.26, "k": 200, "z": 0.4},
		],
		"death": [
			{"t": 0.25, "x": -0.2, "y": 0.15, "angle": 0.18, "sx": 1.08, "sy": 0.85, "pose": -0.5, "bend": -0.6, "k": 120, "z": 0.7},
			{"t": 0.6, "x": -0.3, "y": 0.35, "angle": 0.3, "sx": 1.1, "sy": 0.72, "pose": -0.6, "bend": -0.8, "k": 40, "z": 0.9},
		],
	}


## 敌人按身份分性格，未列出的按造型推断
const PERSONALITY := {
	"activity_cliff": "pocket", "off_target": "pocket",
	"resistant_clone": "shell", "progression": "shell", "dlt": "shell",
	"placebo": "pulse", "enroll_drag": "pulse", "center_pd": "pulse", "center_drop": "pulse",
	"pk_variance": "pulse", "metabolite": "pulse",
	"herg": "pump", "animal_bias": "pump", "hepatotox": "pump", "last_molecule": "pump",
	"endpoint_miss": "rigid", "safety_signal": "rigid", "genotox": "rigid", "protocol_dev": "rigid",
	"free_radical": "spark",
	"poor_solubility": "ooze", "infusion_reaction": "ooze",
	"tox_storm": "cloud", "cytokine_storm": "cloud", "center_ae": "cloud",
}
const BY_SHAPE := {"cell": "pulse", "blob": "ooze", "crystal": "rigid", "cloud": "cloud", "spiky": "pump", "molecule": "pump"}


static func personality(id: String, shape: String) -> String:
	return String(PERSONALITY.get(id, BY_SHAPE.get(shape, "ooze")))


static func enemy(kind: String) -> Dictionary:
	match kind:
		"pocket":   # 靶点口袋：缓慢张合；攻击前向内收拢，攻击时猛地扩张吞噬再合拢
			return {
				"idle": {"open": [0.38, 0.2, 0.25], "y": [0.006, 0.17, 0.3], "angle": [0.006, 0.12, 0.4]},
				"idle_spring": [30.0, 0.9],
				"anticipation_attack": [{"t": 0.24, "open": -1.0, "x": 0.04, "sx": 0.93, "sy": 0.97, "k": 160, "z": 0.85}],
				"attack": [
					{"t": 0.1, "reach": 1.0, "open": 1.6, "sx": 1.12, "sy": 1.06, "k": 700, "z": 0.5, "cue": "impact"},
					{"t": 0.15, "reach": 0.75, "open": -0.6, "sx": 0.96, "k": 420, "z": 0.5},
				],
				"recovery": [{"t": 0.42, "k": 80, "z": 0.7}],
				"hit": [{"t": 0.14, "x": 0.03, "angle": -0.02, "open": -0.7, "sx": 0.95, "sy": 0.96, "k": 300, "z": 0.55}],
				"hit_kick": {"x": 0.25, "open": -4.0, "angle": -0.2},
				"defend": [{"t": 0.32, "open": -0.9, "sx": 0.94, "sy": 0.94, "k": 200, "z": 0.8}],
				"status": [{"t": 0.3, "open": 0.4, "k": 300, "z": 0.25}],
				"death": [{"t": 0.5, "open": -1.2, "y": 0.03, "sx": 1.05, "sy": 0.7, "k": 60, "z": 0.8}],
			}
		"shell":    # 耐药菌：顽固、沉重；外壳不规则起伏；受击时外壳震颤，随后慢慢恢复
			return {
				"idle": {"y": [0.004, 0.11, 0.5], "angle": [0.004, 0.08, 0.6], "sy": [0.006, 0.13, 0.5]},
				"adjust": {}, "idle_spring": [18.0, 1.0],
				"springs": {"bend": [1800.0, 0.07]},
				"anticipation_attack": [{"t": 0.34, "x": 0.06, "y": 0.02, "angle": 0.05, "sx": 1.05, "sy": 0.92, "k": 70, "z": 0.9}],
				"attack": [
					{"t": 0.16, "reach": 1.0, "angle": -0.06, "sx": 0.98, "sy": 1.03, "k": 500, "z": 0.75, "cue": "impact"},
					{"t": 0.16, "reach": 0.9, "sx": 1.05, "sy": 0.94, "k": 300, "z": 0.6},
				],
				"recovery": [{"t": 0.55, "k": 45, "z": 0.85}],
				"hit": [{"t": 0.2, "x": 0.015, "angle": -0.01, "k": 200, "z": 0.8}],
				"hit_kick": {"x": 0.08, "bend": 9.0, "angle": -0.05},
				"defend": [{"t": 0.36, "y": 0.01, "sx": 1.06, "sy": 0.9, "k": 120, "z": 0.9}],
				"status": [{"t": 0.3, "sy": 0.97, "k": 200, "z": 0.5}],
				"death": [{"t": 0.7, "y": 0.04, "angle": 0.08, "sx": 1.08, "sy": 0.78, "k": 30, "z": 0.9}],
			}
		"pulse":    # 感染细胞：不规则脉动，局部鼓起又缩回；中毒时脉动更乱
			return {
				"idle": {"open": [0.55, 0.55, 0.85], "sx": [0.012, 0.6, 0.8], "sy": [0.012, 0.6, 0.8, 1.7],
					"y": [0.006, 0.4, 0.7], "angle": [0.008, 0.3, 0.7],
					"adjust": {"x": 0.02, "angle": 0.015}, "adjust_every": [1.5, 3.5]},
				"idle_spring": [70.0, 0.6],
				"anticipation_attack": [{"t": 0.2, "open": 1.2, "x": 0.03, "sx": 1.08, "sy": 1.08, "k": 200, "z": 0.5}],
				"attack": [
					{"t": 0.11, "reach": 1.0, "open": -0.6, "sx": 0.92, "sy": 1.1, "k": 650, "z": 0.45, "cue": "impact"},
					{"t": 0.12, "reach": 0.85, "open": 0.8, "sx": 1.06, "sy": 0.95, "k": 300, "z": 0.4},
				],
				"recovery": [{"t": 0.36, "k": 90, "z": 0.45}],
				"hit": [{"t": 0.16, "x": 0.03, "open": -0.5, "sx": 0.9, "sy": 1.08, "k": 250, "z": 0.25}],
				"hit_kick": {"x": 0.35, "sx": -1.5, "sy": 1.5, "open": -3.0},
				"defend": [{"t": 0.3, "open": 0.8, "sx": 1.06, "sy": 1.04, "k": 200, "z": 0.5}],
				"status": [{"t": 0.36, "open": 1.4, "sx": 1.05, "k": 300, "z": 0.2}],
				"death": [
					{"t": 0.18, "open": 2.0, "sx": 1.18, "sy": 1.12, "k": 300, "z": 0.5},
					{"t": 0.4, "open": -1.0, "sx": 0.6, "sy": 0.5, "k": 80, "z": 0.8},
				],
			}
		"pump":     # 通道 / 外排泵：按节律门控开合；攻击是一次强力泵出
			return {
				"idle": {"y": [0.004, 0.25, 0.1], "angle": [0.004, 0.2, 0.2], "adjust": {"angle": 0.008}},
				"idle_spring": [60.0, 0.8],
				"anticipation_attack": [{"t": 0.18, "open": -1.0, "sx": 0.9, "sy": 1.04, "k": 260, "z": 0.8}],
				"attack": [
					{"t": 0.09, "reach": 1.0, "open": 1.4, "sx": 1.1, "sy": 0.95, "k": 900, "z": 0.5, "cue": "impact"},
					{"t": 0.1, "reach": 0.9, "k": 400, "z": 0.6},
				],
				"recovery": [{"t": 0.3, "k": 120, "z": 0.7}],
				"hit": [{"t": 0.12, "x": 0.03, "angle": -0.03, "open": -0.5, "k": 400, "z": 0.5}],
				"hit_kick": {"x": 0.3, "angle": -0.4, "open": -2.0},
				"defend": [{"t": 0.3, "open": -0.8, "sx": 0.93, "k": 250, "z": 0.8}],
				"status": [{"t": 0.3, "open": 0.6, "k": 400, "z": 0.3}],
				"death": [{"t": 0.5, "open": -1.0, "angle": 0.1, "sy": 0.75, "k": 70, "z": 0.8}],
			}
		"rigid":    # 晶体类：几乎静止，偶尔突然抽动换个角度；出手又快又直
			return {
				"idle": {"angle": [0.003, 0.15, 0.2], "y": [0.003, 0.2, 0.2],
					"adjust": {"angle": 0.035, "x": 0.012}, "adjust_every": [2.0, 4.5]},
				"idle_spring": [260.0, 0.55],
				"anticipation_attack": [{"t": 0.16, "x": 0.05, "angle": 0.1, "k": 400, "z": 0.8}],
				"attack": [
					{"t": 0.07, "reach": 1.0, "angle": -0.12, "k": 1400, "z": 0.6, "cue": "impact"},
					{"t": 0.08, "reach": 0.92, "angle": -0.06, "k": 600, "z": 0.5},
				],
				"recovery": [{"t": 0.25, "k": 260, "z": 0.55}],
				"hit": [{"t": 0.1, "x": 0.03, "angle": -0.05, "k": 700, "z": 0.35}],
				"hit_kick": {"x": 0.3, "angle": -0.6},
				"defend": [{"t": 0.25, "angle": 0.03, "sy": 0.97, "k": 500, "z": 0.7}],
				"status": [{"t": 0.25, "angle": 0.02, "k": 900, "z": 0.15}],
				"death": [{"t": 0.4, "y": 0.05, "angle": 0.4, "sy": 0.8, "k": 90, "z": 0.6}],
			}
		"spark":    # 活性氧：躁动不安，到处乱窜
			return {
				"idle": {"x": [0.02, 1.7, 0.9], "y": [0.025, 1.3, 0.9], "angle": [0.03, 1.1, 0.9],
					"adjust": {"x": 0.05, "y": 0.04}, "adjust_every": [0.6, 1.4]},
				"idle_spring": [300.0, 0.5],
				"anticipation_attack": [{"t": 0.12, "x": 0.08, "sx": 0.9, "sy": 0.9, "k": 500, "z": 0.5}],
				"attack": [
					{"t": 0.07, "reach": 1.0, "sx": 1.12, "sy": 0.9, "k": 1400, "z": 0.5, "cue": "impact"},
					{"t": 0.08, "reach": 0.7, "k": 600, "z": 0.4},
				],
				"recovery": [{"t": 0.2, "k": 300, "z": 0.5}],
				"hit": [{"t": 0.1, "x": 0.08, "k": 500, "z": 0.3}],
				"hit_kick": {"x": 0.8, "angle": -1.0},
				"defend": [{"t": 0.2, "sx": 0.9, "sy": 0.9, "k": 500, "z": 0.6}],
				"status": [{"t": 0.2, "k": 800, "z": 0.2}],
				"death": [{"t": 0.3, "sx": 1.3, "sy": 1.3, "k": 200, "z": 0.6}],
			}
		"cloud":    # 毒云：随气流飘移，边缘流动；攻击时先聚拢再涌出、铺开
			return {
				"idle": {"x": [0.02, 0.09, 0.6], "y": [0.03, 0.14, 0.6], "angle": [0.012, 0.1, 0.6],
					"sx": [0.015, 0.2, 0.5], "open": [0.5, 0.25, 0.5],
					"adjust": {"x": 0.03, "y": 0.02}, "adjust_every": [3.0, 6.0]},
				"idle_spring": [12.0, 0.9],
				"anticipation_attack": [{"t": 0.28, "x": 0.03, "open": -0.8, "sx": 0.9, "sy": 0.92, "k": 80, "z": 0.8}],
				"attack": [
					{"t": 0.16, "reach": 1.0, "open": 1.4, "sx": 1.18, "sy": 1.05, "k": 300, "z": 0.6, "cue": "impact"},
					{"t": 0.2, "reach": 0.8, "open": 1.0, "k": 150, "z": 0.6},
				],
				"recovery": [{"t": 0.6, "k": 30, "z": 0.8}],
				"hit": [{"t": 0.2, "x": 0.04, "open": 0.8, "k": 120, "z": 0.5}],
				"hit_kick": {"x": 0.4, "open": 3.0},
				"defend": [{"t": 0.35, "open": -0.6, "sx": 0.9, "sy": 0.9, "k": 100, "z": 0.8}],
				"status": [{"t": 0.4, "open": 1.2, "k": 120, "z": 0.4}],
				"death": [{"t": 0.8, "y": -0.05, "open": 2.5, "sx": 1.5, "sy": 1.3, "k": 20, "z": 0.9}],
			}
	# ooze：胶状聚集体，黏稠地下坠、摊开再聚拢
	return {
		"idle": {"sy": [0.02, 0.18, 0.4], "sx": [0.02, 0.18, 0.4, PI], "open": [0.4, 0.15, 0.4],
			"adjust": {"x": 0.015}, "adjust_every": [3.0, 6.0]},
		"idle_spring": [25.0, 0.7],
		"anticipation_attack": [{"t": 0.3, "open": 1.0, "sx": 1.1, "sy": 0.85, "k": 90, "z": 0.7}],
		"attack": [
			{"t": 0.14, "reach": 1.0, "open": -0.8, "sx": 0.92, "sy": 1.12, "k": 450, "z": 0.45, "cue": "impact"},
			{"t": 0.18, "reach": 0.85, "open": 0.6, "sx": 1.08, "sy": 0.92, "k": 200, "z": 0.35},
		],
		"recovery": [{"t": 0.5, "k": 50, "z": 0.45}],
		"hit": [{"t": 0.2, "x": 0.02, "open": 0.8, "sx": 1.08, "sy": 0.9, "k": 150, "z": 0.3}],
		"hit_kick": {"x": 0.2, "sx": 1.2, "sy": -1.2},
		"defend": [{"t": 0.35, "sx": 1.1, "sy": 0.88, "k": 120, "z": 0.7}],
		"status": [{"t": 0.4, "open": 1.0, "k": 150, "z": 0.3}],
		"death": [{"t": 0.7, "open": 1.5, "sx": 1.35, "sy": 0.4, "k": 40, "z": 0.8}],
	}
