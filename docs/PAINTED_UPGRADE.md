# 新视觉素材与控件实现

本轮将《ART_DIRECTION.md》的方向接入运行界面。素材使用内置 image_gen 生成并作为可拆分图集使用；实时文字、卡牌效果、血条、状态、点击区域和换装逻辑继续由 Godot 渲染。

## 项目内素材

| 文件 | 用途 |
| --- | --- |
| assets/art/painted-world.png | 无角色、无 UI 的膜结构场景，标题、总览与战斗共用；阅读页面增加墨色罩层 |
| assets/art/painted-enemies.png | 六种具有不同机制剪影的敌人／主视觉，独立透明主体 |
| assets/art/painted-fragments.png | 12 种分子片段、开放环核心与辅助连接部件 |
| assets/art/painted-cards.png | 六种手绘卡牌机制插画，独立裁切与边界保护 |
| assets/art/painted-ui.png | 主面板、青绿主按钮、骨白卡面、次级 HUD 四类手绘框体 |

## 控件系统

`PaintedStyle` 是共用 StyleBox 实现：把手绘框体拆成九块绘制，源纹理边距与屏幕边距独立，避免长按钮的角部被拉伸。容器内容边距仍由实时布局管理。可读文字与图标不烘焙入皮肤。主按钮、次按钮、关闭入口、主弹窗、奖励／事件／地图场景内覆盖样式和默认主题均使用同一系统。

悬停与按下通过实时描边和明暗变化区分，禁用保持输入禁用与字体／表面减弱，键盘焦点保留轮廓提示。细进度条、滑块与滚动条保留语义颜色，避免将它们渲染成装饰性面板。卡牌标题和作用区保持清晰的骨白阅读面与角色配色。

敌人与分子图集根据透明边界取景，导出的不等宽留白由归一化裁切表吸收。单体 Boss 与多目标群体使用不同展示尺度，固定受光与作用朝向。场景与主体常态不烘焙攻击爆光。

当前六种敌人剪影仍通过既有 shape 分类分配，尚非每个敌人 ID 的独立立绘；各研发阶段也尚未拥有独立背景整套素材。后续扩展须继续遵循机制造型规则。

## 验证

`sh tests/run.sh` 运行逻辑与界面回归。`tools/capture_ui.gd` 覆盖标题、项目选择、档案、分子编辑、总览、地图、战斗、多敌人、剂量操作、卡牌详情／选择、奖励、事件、设置、帮助、暂停与结局。截图位于 `.godot/painted-final/`，不纳入版本控制。截图脚本禁用持久化与真实输入，避免改动玩家存档。

## 素材初始提示词

以下为内置 image_gen 的初始制作提示词。敌人及片段另进行过透明背景与分格留白修正，UI 框体按相同参考图单独制作。

### world

The supplied image is STYLE REFERENCE ONLY. Create production GAME ART matching its thick painted gouache brushwork, indigo contours, expressive angular silhouettes, slate blue/bruise-purple biological world, jade and bone-white molecular structures and sparse warm ochre highlights. Authored 2D/2.5D painted biological fantasy. NO photoreal PBR, metal, glass, toy balls, gradients masquerading as paint, laboratory apparatus, faces, eyes, text, numbers, UI, cards, labels, watermarks or framing. Stable calm planning state, NO gold attack blasts or permanent glow. ONE wide 16:9 EMPTY BATTLE ENVIRONMENT. Remove ALL characters, monsters, molecular protagonists and UI. Painted microscopic membrane gorge, phospholipid bridges receding in the blue haze, broad layered violet-gray membrane ground at 57% image height, open unobstructed left and right staging positions, calm quiet central corridor, distant low-contrast gray-blue folded tissue. Lower 35% very dark indigo broad organic folds, QUIET behind future hand of cards; near corners organic stalks crop into frame but do not reach staging positions. No centerpiece creature, no glowing energy source, no text. Readable painterly broad masses, selective drybrush edges. Upper corners and side edges rich, central battlefield quiet. Very sparse subdued warm directional light upper-left. Edge-to-edge background only.

### enemies

The supplied image is STYLE REFERENCE ONLY. Create production GAME ART matching its thick painted gouache brushwork, indigo contours, expressive angular silhouettes, slate blue/bruise-purple biological world, jade and bone-white molecular structures and sparse warm ochre highlights. Authored 2D/2.5D painted biological fantasy. NO photoreal PBR, metal, glass, toy balls, gradients masquerading as paint, laboratory apparatus, faces, eyes, text, numbers, UI, cards, labels, watermarks or framing. Stable calm planning state, NO gold attack blasts or permanent glow. ONE TRANSPARENT sprite atlas, EXACT equal 3 columns by 2 rows, each of 6 subjects fully isolated with 15% transparent margin, NO overlap, NO drop shadows, NO background. Consistent three-quarter side-facing view, all organisms face LEFT, common top-left painted light. Each object must look like a strongly designed biological adversary, not a scientific render or generic monster. Row1 col1 enzyme: compact irregular plum shell with two asymmetric interlocking cleavage plates and one dark off-center processing slit. Row1 col2 cell: broad flattened oval membrane organism, ribbed dark blue-purple shell, jade nucleus partly enclosed inside, rhythmically repeating membrane edges, no eyes. Row1 col3 BINDING POCKET BOSS: huge dramatic folded violet membrane shell curving around a clearly visible deep KEY-SHAPED central cavity opening toward LEFT, broad overlapping angular plates, matte bone/ochre lip accents, dark empty interior, no teeth or eye; match the reference boss silhouette. Row2 col1 folding protein: twisted low horizontal organism, three interlocking mauve ribbon folds and a dark tunnel; recognizable irregular silhouette, not a cloud. Row2 col2 ion channel: stout blue-violet organism with concentric stacked membrane plates, a vertical open central channel and sharp finlike side plates, no technological metal. Row2 col3 rival molecular entity: open hexagonal ring with asymmetric branching polygonal links and nested ring, ivory-jade darkened to violet-green, readable empty center, NO face. Keep each subject large within its own cell, transparent gutters, all brush textures share same scale. True alpha background.

### fragments

The supplied image is STYLE REFERENCE ONLY. Create production GAME ART matching its thick painted gouache brushwork, indigo contours, expressive angular silhouettes, slate blue/bruise-purple biological world, jade and bone-white molecular structures and sparse warm ochre highlights. Authored 2D/2.5D painted biological fantasy. NO photoreal PBR, metal, glass, toy balls, gradients masquerading as paint, laboratory apparatus, faces, eyes, text, numbers, UI, cards, labels, watermarks or framing. Stable calm planning state, NO gold attack blasts or permanent glow. ONE TRANSPARENT molecular-building-kit sprite atlas, EXACTLY 4 columns x4 rows equal cells. Each of 16 objects centered fully inside its own cell with generous transparent gutters, no overlap, no shadow. The protagonist's geometric molecular fragments must be thick irregular jade polygonal bond bars with bone-white top planes and near-black indigo undersides, drybrush painted edges and occasional muted gold functional tips. NOT shiny atomic ball-stick models, NOT faceted crystals. Every RING HAS OPEN NEGATIVE SPACE. Every chemical motif uses same slightly tilted frontal viewpoint and light from upper-left, no perspective rotation per cell. Row-major exact objects: 1 fluorine substituent as single cut-corner small ochre polygon with tiny jade attachment stub; 2 methyl as compact 3-branch jade/ivory node; 3 hydroxyl as small hook ending in pale jade rounded polygon; 4 phenyl as open hexagonal ring of thick jade-and-ivory bars with one attachment stub. Row2: 5 morpholine as rounded open hexagonal ring with two notched jade nodes and asymmetric small branch; 6 nitro as small Y-shaped branching motif with two ochre polygon tips; 7 amide as SHORT angular jade linker with one upward ivory-gold branch, left-right connection stubs; 8 sulfonamide as short 3-pronged jade linker with two small gold tips and left/right stubs. Row3: 9 tert-butyl compact three thick branches around short central node; 10 pyridine open hexagonal ring with one ochre notched vertex, jade-ivory bars; 11 cyclopropyl small OPEN triangular jade ring; 12 acid as small asymmetric two-branch group ending in pale green/ivory tips. Row4: 13 CENTRAL CORE open six-sided aromatic ring, thick bone-white top faces and jade side faces, SIX short attachment stubs, empty center NO disk; 14 small jade irregular polygon connector node; 15 tiny ivory polygon cap; 16 short jagged two-segment jade-ivory linker. ALL shapes painted not perfectly vector, distinctive silhouettes for each fragment. Real alpha transparency.

### cards

The supplied image is STYLE REFERENCE ONLY. Create production GAME ART matching its thick painted gouache brushwork, indigo contours, expressive angular silhouettes, slate blue/bruise-purple biological world, jade and bone-white molecular structures and sparse warm ochre highlights. Authored 2D/2.5D painted biological fantasy. NO photoreal PBR, metal, glass, toy balls, gradients masquerading as paint, laboratory apparatus, faces, eyes, text, numbers, UI, cards, labels, watermarks or framing. Stable calm planning state, NO gold attack blasts or permanent glow. ONE production card-illustration atlas, EXACTLY 3 columns x2 rows equal rectangular tiles, each independent miniature hand-painted illustration with full-bleed dark slate/ivory ground and broad readable shapes. NO card borders, NO text or numeric effects, no icons superimposed. Motifs in row-major order: 1 jade angular molecular branch entering an irregular purple biological cavity, small ochre contact; 2 bone-and-dusty-blue protective shield silhouette sheltering a tiny jade structure, sparse hand-drawn assay trace in background; 3 clear thick jade open aromatic-ring structure, small gold substituent and curved painted substitution arrow; 4 three simplified matte ivory-and-blue assay tubes with jade contents, orderly broad silhouettes; 5 paired rounded control flasks drawn in gouache, one jade and one muted ochre, quiet comparison; 6 asymmetric branching inference network made from polygon nodes and dark jade links, a single ochre decision node, no gears or machinery. Same brushwork and ink contours as reference game, no photo collage or glow. Crisp silhouettes, low detail, preserve tile boundaries and no subject bleeding between tiles.

### UI 框体

以已选定厚涂生物奇幻战斗图为风格参考，制作 2×2 透明 UI 皮肤图集：墨蓝主面板、青绿主按钮、骨白阅读面、简化次级 HUD。仅绘制完整闭合框体，无文字、符号、数字。窄边缘使用紫色膜折层与克制暖金笔触，中心保留安静不透明阅读面；四边与角部适合九宫格缩放。保留透明分隔，避免任何框体跨格，不使用金属镜面、玻璃或通用科幻倒角。
