class_name MusicMeta
extends RefCounted
## 由 tools/gen_battle_music.py 生成：分层战斗曲的一小节秒数，GameAudio 用它把战况切换对齐到小节线。

const BAR := {
	"battle": 1.739130,
	"boss": 1.400000,
	"boss_final": 1.558442,
	"phase1": 1.690141,
	"phase1_boss": 1.381579,
	"phase2": 1.714286,
	"phase2_boss": 2.000000,
	"phase3": 1.621622,
	"phase3_boss": 1.329114,
	"preclinical": 1.791045,
	"preclinical_boss": 2.054795,
}

## Boss 每组重拍在小节中的相对位置。
const ACCENTS := {
	"boss": [0.000000, 0.285714, 0.571429],
	"boss_final": [0.000000, 0.375000, 0.750000],
	"phase1_boss": [0.000000, 0.285714, 0.571429],
	"phase2_boss": [0.000000, 0.300000, 0.500000, 0.700000],
	"phase3_boss": [0.000000, 0.285714, 0.714286],
	"preclinical_boss": [0.000000, 0.300000, 0.600000, 0.800000],
}
