"""把 Suno 生成的原创配乐（WAV）处理成游戏用的循环 OGG，并写出运行时元数据。

用法（WAV 原件不进仓库，默认放在 ~/Documents/musics/LM，处理时只读不改）：
    ~/.local/bin/uv run --with numpy --with soundfile python tools/import_suno_music.py [WAV 目录]

每首做的事：
1. 去掉开头的静音（结尾不动，循环点之后的部分本来就会被裁掉）。
2. 原曲左右声道完全相同（双单声道）时按单声道编码，不伪造立体声；真立体声保持两声道。
3. 响度：用 ffmpeg ebur128 测整首积分响度，按固定增益拉到 TARGET_LUFS，不做压缩或限幅；
   增益后采样峰值超过 PEAK_CEILING 时自动少拉一点，并在输出里提示。
4. 循环：loop 模式的曲目在 [loop_start, loop_end) 之间循环，两点都落在节拍上、间隔是 16 拍（乐句）的整数倍，
   由 tools 下的相似度分析挑选（见 docs/AUDIO.md）。文件只保留到 loop_end，最后一段和 loop_start 前的同长一段
   做等功率交叉淡化，并在 ±20 ms 内按波形相关对齐，播放到文件末尾跳回 loop_offset 时听不出接缝。
   前奏（loop_start 之前）只在第一次进入时播放。
   restart 模式用于找不到可靠循环点的曲目：保留整首，结尾烘焙淡出，运行时播完停顿片刻再从头淡入。
5. 只做一次有损编码：WAV → Vorbis（soundfile / libvorbis）。
"""

import json
import os
import re
import subprocess
import sys

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "music", "bgm")
META_GD = os.path.join(ROOT, "scripts", "core", "music_tracks.gd")
DEFAULT_SRC = os.path.expanduser("~/Documents/musics/LM")
TARGET_LUFS = -16.0
PEAK_CEILING = -1.0      # dBFS，采样峰值
QUALITY = 0.42           # libsndfile compression_level：0 最好，1 最小；0.42 约为 Vorbis q5.8

# loop_start / loop_end 是原曲时间轴上的秒数；bpm 由节拍分析得到；xfade 以拍为单位。
# review=True 表示自动分析把握不高，需要人工试听确认。
TRACKS = {
    "battle": dict(src="LM1.wav", bpm=128.24, mode="loop", loop_start=9.878, loop_end=159.600, xfade=1.0,
                   note="前 10 s 只播一次，之后在 80 小节主体循环；接缝两侧电平差 <1.5 dB"),
    "boss": dict(src="LM2.wav", bpm=138.55, mode="loop", loop_start=45.830, loop_end=142.834, xfade=2.0, review=True,
                 note="后段越来越响，整首循环跳回开头会掉 9 dB；改为前 46 s 只播一次，之后循环中段 56 小节，接缝相似度偏低需试听"),
    "title": dict(src="LM3.wav", bpm=156.84, mode="loop", loop_start=38.163, loop_end=111.612, xfade=1.0,
                  note="前 38 s 的前奏只在第一次播放，之后在主体 48 小节循环"),
    "map": dict(src="LM4.wav", bpm=126.67, mode="loop", loop_start=7.181, loop_end=98.129, xfade=1.0,
                note="循环 48 小节，结尾 24 s 的收束段不进循环"),
    "lab": dict(src="LM5.wav", bpm=148.08, mode="loop", loop_start=35.067, loop_end=86.931, xfade=4.0,
                review=True, note="整首只有 93 s，长循环相似度偏低，用一小节交叉淡化；需人工试听"),
    "event": dict(src="LM6.wav", bpm=85.00, mode="restart", tail_fade=2.0, gap=1.2,
                  review=True, note="找不到可靠循环点：整首播放，结尾淡出，停顿后从头淡入"),
    "ending": dict(src="LM7.wav", bpm=75.72, mode="loop", loop_start=16.814, loop_end=105.561, xfade=1.0,
                   note="前奏只播一次，之后在 28 小节主体循环，结尾的收束段不进循环"),
}


def lufs(path):
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", out)[-1])


def first_sound(x, sr, threshold_db=-50.0):
    level = np.abs(x).max(axis=1) if x.ndim > 1 else np.abs(x)
    idx = np.argmax(level > 10 ** (threshold_db / 20))
    return max(0, idx - int(0.02 * sr))


def align(x, start, end, n, sr):
    """在 ±20 ms 内移动 end，使 end 前 n 个采样与 start 前 n 个采样的波形最相关。"""
    ref = x[start - n:start].mean(axis=1) if x.ndim > 1 else x[start - n:start]
    best, best_shift = -2.0, 0
    for shift in range(-int(0.02 * sr), int(0.02 * sr) + 1, 8):
        seg = x[end + shift - n:end + shift]
        seg = seg.mean(axis=1) if seg.ndim > 1 else seg
        c = float(np.dot(ref, seg) / (np.linalg.norm(ref) * np.linalg.norm(seg) + 1e-9))
        if c > best:
            best, best_shift = c, shift
    return end + best_shift, best


def process(track_id, cfg, src_dir):
    path = os.path.join(src_dir, cfg["src"])
    x, sr = sf.read(path, dtype="float64", always_2d=True)
    stereo = x.shape[1] > 1 and not np.allclose(x[:, 0], x[:, 1], atol=1e-6)
    x = x if stereo else x[:, :1].copy()
    gain_db = TARGET_LUFS - lufs(path)
    beat = 60.0 / cfg["bpm"]
    t0 = first_sound(x, sr)
    info = {"source": cfg["src"], "mode": cfg["mode"], "bpm": cfg["bpm"], "bar": round(beat * 4, 6),
            "channels": x.shape[1], "review": bool(cfg.get("review", False)), "note": cfg["note"]}
    if cfg["mode"] == "loop":
        s = int(round(cfg["loop_start"] * sr))
        e = int(round(cfg["loop_end"] * sr))
        n = int(round(cfg["xfade"] * beat * sr))
        e, corr = align(x, s, e, n, sr)
        body = x[t0:e].copy()
        k = np.linspace(0.0, 1.0, n)[:, None]
        body[-n:] = x[e - n:e] * np.cos(k * np.pi / 2) + x[s - n:s] * np.sin(k * np.pi / 2)
        info["loop_offset"] = round((s - t0) / sr, 6)
        info["seam_correlation"] = round(corr, 3)
        info["xfade"] = round(n / sr, 3)
    else:
        body = x[t0:].copy()
        n = int(cfg["tail_fade"] * sr)
        body[-n:] *= np.cos(np.linspace(0.0, 1.0, n)[:, None] * np.pi / 2)
        info["loop_offset"] = 0.0
        info["gap"] = cfg["gap"]
    peak_db = 20 * np.log10(np.abs(body).max() + 1e-12) + gain_db
    if peak_db > PEAK_CEILING:
        print("  %s: 峰值 %.1f dBFS，增益下调 %.1f dB 以免削波" % (track_id, peak_db, peak_db - PEAK_CEILING))
        gain_db -= peak_db - PEAK_CEILING
    body *= 10 ** (gain_db / 20)
    info["gain_db"] = round(gain_db, 2)
    info["length"] = round(len(body) / sr, 6)
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "bgm_%s.ogg" % track_id)
    # libsndfile 一次写入很长的 Vorbis 数据会崩溃，按块写
    with sf.SoundFile(out, "w", sr, body.shape[1], format="OGG", subtype="VORBIS", compression_level=QUALITY) as f:
        for i in range(0, len(body), sr):
            f.write(body[i:i + sr])
    info["file"] = "res://assets/audio/music/bgm/bgm_%s.ogg" % track_id
    print("wrote %s  %.1fs  %s  gain %+.1f dB  %s" % (os.path.relpath(out, ROOT), info["length"],
          "stereo" if stereo else "mono", gain_db, ("seam r=%.2f" % info["seam_correlation"]) if "seam_correlation" in info else "restart"))
    return info


def write_meta(meta):
    lines = ["class_name MusicTracks", "## 由 tools/import_suno_music.py 生成，请勿手改：每首背景音乐的文件、循环点与节拍。",
             "## loop_offset 是循环段在 OGG 文件里的起点（秒）；mode = loop 循环 / restart 播完停顿后从头淡入。", "",
             "const DATA := {"]
    for track_id, info in meta.items():
        fields = {k: info[k] for k in ("file", "mode", "loop_offset", "length", "bar", "bpm", "channels", "review")}
        if "gap" in info:
            fields["gap"] = info["gap"]
        lines.append('\t"%s": %s,' % (track_id, json.dumps(fields, ensure_ascii=False)))
    lines.append("}")
    with open(META_GD, "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(OUT_DIR, "tracks.json"), "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    meta = {}
    for track_id, cfg in TRACKS.items():
        if not os.path.exists(os.path.join(src_dir, cfg["src"])):
            print("  缺少 %s，%s 将由 GameAudio 用旧曲目兜底" % (cfg["src"], track_id))
            continue
        meta[track_id] = process(track_id, cfg, src_dir)
    write_meta(meta)


if __name__ == "__main__":
    main()
