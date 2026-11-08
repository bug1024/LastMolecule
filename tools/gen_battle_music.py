#!/usr/bin/env python3
"""按段落编曲的分层战斗配乐与战斗音效，纯程序合成，可随时重跑。

  · 普通战斗：134–148 BPM，以底鼓、反拍军鼓、短音低音带出从第一小节就能听到的律动。
    32 小节分为建立节拍、展开主题、全奏和短暂回落后重新起势。
  · Boss：保留分组拍号，用切分鼓点、短促铜管和上行旋律制造压力。
  · 每首战斗曲三层同长同拍：基础层（Normal）、紧张层（Tension）、高潮层（Climax），游戏按战况在小节边界开关。
  · 短乐句：Boss 登场、Boss 死亡收束、普通战斗胜利。
  · 战斗音效：分子攻击的预备 / 释放、命中余韵、护盾形成、片段联动、AI 激活与失误、Boss 预警 / 受击 / 死亡。

运行：~/.local/bin/uv run --with numpy python tools/gen_battle_music.py [--music] [--sfx] [--only=名称]
输出：assets/audio/music/<曲名>.ogg、<曲名>_tension.ogg、<曲名>_climax.ogg、music_meta.json；assets/audio/sfx/*.ogg
"""
import functools
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402

import gen_audio  # noqa: E402
from gen_audio import (ROOT, SR, KICK, SNARE, HAT, SHAKER, TAIKO, THEME, Mix, bell, click, crunch, fade,  # noqa: E402
                       highpass, layer, lowpass, metal, mf, punch, sfx, to_major, ts)


def write(x, path, peak=0.8):
    # 战斗曲较长、分三层：基础层 q4；紧张层与高潮层只做叠加，用更低码率控制体积
    quality = 2 if path.endswith("_tension.ogg") else (3 if path.endswith("_climax.ogg") else 4)
    gen_audio.write(x, path, peak, quality=quality)

MUSIC = os.path.join(ROOT, "music")
R = np.random.default_rng(2026)
TAU = 2 * np.pi
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MIXOLYDIAN = [0, 2, 4, 5, 7, 9, 10]
DORIAN = [0, 2, 3, 5, 7, 9, 10]


# ---------- 乐器 ----------

@functools.lru_cache(maxsize=None)
def saw(m, dur, bright=1.0, decay=6.0, sustain=0.25, attack=0.004, voices=3, detune=0.08, release=0.06, harm=28):
    """失谐锯齿合奏；高次谐波衰减更快，相当于一个随音符关闭的滤波包络"""
    f = mf(m)
    n = int((dur + release) * SR)
    t = ts(n)
    out = np.zeros(n)
    rng = np.random.default_rng(int(m * 1000 + dur * 977) % 100000)
    for v in range(voices):
        fv = f * 2 ** ((v - (voices - 1) / 2) * detune / 12)
        ph = rng.uniform(0, TAU)
        for k in range(1, harm + 1):
            if fv * k > SR / 2.3:
                break
            env = sustain + (1 - sustain) * np.exp(-t * decay * k / (bright * 4))
            out += (1 / k) * np.sin(TAU * fv * k * t + ph * k) * env
    amp = np.ones(n)
    a = max(1, int(attack * SR))
    amp[:a] = np.linspace(0, 1, a)
    r0 = int(dur * SR)
    if r0 < n:
        amp[r0:] *= np.exp(-(t[r0:] - dur) / max(release * 0.35, 0.005))
    return out * amp / voices


def spiccato(m, vel=1.0):
    """短促的弦乐跳弓：快速起音，一下就收"""
    return saw(m, 0.085, 1.3, 11.0, 0.0, 0.003, 3, 0.07, 0.05) * vel


def tbass(m, dur):
    """战术低音：带滤波包络的锯齿 + 正弦次低音"""
    body = saw(m, dur, 0.7, 9.0, 0.1, 0.004, 2, 0.04, 0.05, 18)
    t = ts(len(body))
    sub = np.sin(TAU * mf(m) * t) * np.minimum(1, t / 0.004) * np.exp(-t / max(dur * 1.4, 0.08))
    return body * 0.8 + sub * 0.9


def strings(m, dur, attack=0.25):
    return saw(m, dur, 0.55, 2.0, 0.7, attack, 4, 0.11, 0.5, 20)


@functools.lru_cache(maxsize=None)
def brass(m, dur, vel=1.0):
    """铜管：起音时音色逐渐变亮（谐波随时间展开），持续段饱满"""
    f = mf(m)
    n = int((dur + 0.18) * SR)
    t = ts(n)
    open_ = 1 - np.exp(-t / 0.07)
    out = np.zeros(n)
    for det in (-0.06, 0.06):
        fv = f * 2 ** (det / 12)
        for k in range(1, 26):
            if fv * k > SR / 2.3:
                break
            out += (1 / k) * np.exp(-k / (2.5 + 9 * open_)) * np.sin(TAU * fv * k * t)
    amp = np.minimum(1, t / 0.03)
    r0 = int(dur * SR)
    amp[r0:] *= np.exp(-(t[r0:] - dur) / 0.06)
    return out * amp * vel / 2


@functools.lru_cache(maxsize=None)
def soft_pluck(m, dur=0.16):
    return saw(m, dur, 0.6, 14.0, 0.0, 0.002, 2, 0.05, 0.12, 14)


@functools.lru_cache(maxsize=None)
def bubble(f0):
    n = int(0.05 * SR)
    t = ts(n)
    return np.sin(np.cumsum(TAU * f0 * (1 + 1.6 * t / 0.05) / SR)) * np.exp(-t / 0.012) * np.minimum(1, t / 0.002)


@functools.lru_cache(maxsize=None)
def squelch(m):
    """湿润的生物「啵」：FM 下滑短音"""
    f = mf(m)
    n = int(0.14 * SR)
    t = ts(n)
    freq = f * (1 - 0.35 * t / 0.14)
    mod = np.sin(np.cumsum(TAU * freq * 1.5 / SR)) * 3 * np.exp(-t / 0.03)
    return np.sin(np.cumsum(TAU * freq / SR) + mod) * np.exp(-t / 0.05) * np.minimum(1, t / 0.003)


TICK = metal((4200, 6100, 7900), 0.04, 0.009)


def tom(f, tau=0.14):
    n = int(0.45 * SR)
    t = ts(n)
    body = np.sin(np.cumsum(TAU * (f + f * 1.2 * np.exp(-t / 0.03)) / SR)) * np.exp(-t / tau)
    skin = lowpass(R.standard_normal(n), 1600) * np.exp(-t / 0.02)
    return fade(body + 0.35 * skin, 0.0008, 0.03)


TOMS = [tom(f) for f in (150, 118, 92, 72)]


def _clap():
    n = int(0.25 * SR)
    t = ts(n)
    noise = highpass(highpass(R.standard_normal(n)))
    env = sum(np.where(t >= d, np.exp(-(t - d) / 0.008), 0) for d in (0.0, 0.011, 0.022)) + np.where(t > 0.03, 0.6 * np.exp(-(t - 0.03) / 0.07), 0)
    return noise * env * 0.6


CLAP = _clap()
RIM = metal((1800, 2650), 0.05, 0.012)
CRASH = highpass(R.standard_normal(int(2.2 * SR))) * np.exp(-ts(int(2.2 * SR)) / 0.7) * 0.35


def riser(dur, f0=300, f1=7000):
    """噪声上扫：音量与亮度一起升高，落在下一小节的强拍前"""
    n = int(dur * SR)
    t = ts(n)
    noise = R.standard_normal(n)
    out = np.zeros(n)
    seg = 1024
    for i in range(0, n, seg):
        frac = i / n
        out[i:i + seg] = lowpass(noise[i:i + seg], f0 + (f1 - f0) * frac ** 2)
    return out * (t / dur) ** 2


def impact(depth=1.0):
    return layer((punch(1.4, 110, 30, 0.5 * depth), 1.2, 0), (crunch(0.6, 1800, 0.12, 4.0), 0.5, 0), (CRASH, 0.4, 0.01))


DRIVE_KICK = KICK * np.exp(-ts(len(KICK)) / 0.095)
DRIVE_SNARE = SNARE * np.exp(-ts(len(SNARE)) / 0.075)
DRIVE_TAIKO = TAIKO * np.exp(-ts(len(TAIKO)) / 0.15)


# ---------- 和声 ----------

def degree(root, scale, d, raise7=False):
    octave, idx = divmod(d, 7)
    return root + 12 * octave + scale[idx] + (1 if raise7 and idx == 6 else 0)


def triad(root, scale, chord_degree, raise7):
    return [degree(root, scale, chord_degree + k, raise7) for k in (0, 2, 4)]


# ---------- 普通战斗 ----------
# motif：两小节（32 个十六分音符）的 (位置, 相对和弦根音的音级, 长度)，按和弦级数做调内模进，节奏型就是辨识度
MOTIFS = {
    "hook": [(0, 0, 2), (3, 0, 2), (6, 4, 2), (8, 2, 1), (10, 1, 1), (11, 2, 1), (12, 4, 2), (14, 6, 2),
             (16, 7, 3), (19, 6, 1), (20, 4, 2), (22, 2, 2), (24, 3, 2), (26, 2, 2), (28, 1, 2), (30, -1, 2)],
    "gallop": [(0, 0, 1), (1, 0, 1), (2, 2, 2), (4, 4, 1), (5, 4, 1), (6, 5, 2), (8, 4, 2), (10, 2, 2), (12, 1, 1), (13, 2, 1),
               (14, 0, 2), (16, 0, 1), (17, 0, 1), (18, 2, 2), (20, 4, 1), (21, 5, 1), (22, 7, 2), (24, 6, 3), (27, 4, 1), (28, 5, 2), (30, 4, 2)],
    "syncope": [(0, 0, 3), (3, 2, 3), (6, 4, 2), (10, 3, 2), (12, 2, 4), (16, 0, 3), (19, 2, 3), (22, 5, 2), (24, 4, 2), (26, 3, 2), (28, 1, 4)],
    "call": [(0, 4, 2), (2, 2, 2), (4, 0, 4), (8, 1, 2), (10, 2, 2), (12, 4, 4), (16, 5, 2), (18, 4, 2), (20, 2, 4), (24, 1, 2), (26, 0, 2), (28, -1, 4)],
    "engine": [(0, 0, 1), (1, 4, 1), (2, 7, 1), (3, 4, 1), (4, 0, 1), (5, 4, 1), (6, 8, 2), (8, 7, 1), (9, 4, 1), (10, 6, 1), (11, 4, 1), (12, 2, 2),
               (14, 4, 2), (16, 0, 1), (17, 4, 1), (18, 7, 1), (19, 4, 1), (20, 0, 1), (21, 4, 1), (22, 9, 2), (24, 8, 2), (26, 7, 2), (28, 6, 2), (30, 4, 2)],
}

# 每个研发阶段一首：调、速度、和弦级数、主题、主奏音色、低音律动与生物纹理都不同
BATTLES = {
    "battle": dict(bpm=138, root=40, scale=MAJOR, chords=[0, 5, 3, 4], motif="hook", lead="spiccato",
                   kick=[0, 6, 10], bass=[0, 3, 6, 8, 11, 14], texture="bubble"),
    "preclinical": dict(bpm=134, root=38, scale=DORIAN, chords=[0, 3, 6, 4], motif="gallop", lead="pluck",
                        kick=[0, 7, 10], bass=[0, 2, 4, 7, 8, 10, 12, 14], texture="squelch"),
    "phase1": dict(bpm=142, root=36, scale=MIXOLYDIAN, chords=[0, 6, 3, 4], motif="syncope", lead="brass",
                   kick=[0, 3, 8, 11], bass=[0, 3, 6, 8, 10, 14], texture="tick"),
    "phase2": dict(bpm=140, root=42, scale=MAJOR, chords=[0, 3, 1, 4], motif="call", lead="bell",
                   kick=[0, 6, 8, 13], bass=[0, 4, 6, 8, 12, 14], texture="breath"),
    "phase3": dict(bpm=148, root=35, scale=MAJOR, chords=[0, 3, 5, 4], motif="engine", lead="strings",
                   kick=[0, 6, 10, 12], bass=[0, 2, 3, 6, 8, 10, 11, 14], texture="heart"),
}


def combine(*sigs):
    out = np.zeros(max(len(x) for x in sigs))
    for x in sigs:
        out[:len(x)] += x
    return out


def lead_voice(kind, m, length_s):
    if kind == "pluck":
        return soft_pluck(m, max(0.1, length_s * 0.8)) * 1.1
    if kind == "brass":
        return brass(m, max(0.09, length_s * 0.7), 0.9)
    if kind == "bell":
        return combine(bell(m + 12, 0.8, 1.2, 3.01, 1.6) * 0.7, spiccato(m, 0.6))
    if kind == "strings":
        return saw(m, max(0.08, length_s * 0.9), 1.0, 5.0, 0.4, 0.004, 4, 0.1, 0.06, 22)
    return spiccato(m)


def texture(mix, kind, start, bar, density, root):
    """生物质感纹理：气泡、湿润的啵声、细胞钟表、呼吸、心跳。只放在弱拍上，不抢节奏"""
    steps = bar / 16
    for s in range(16):
        if s % 4 == 0 or R.random() > density * 0.45:
            continue
        at = start + s * steps
        pan = R.uniform(-0.8, 0.8)
        if kind == "bubble":
            mix.add(at, bubble(R.uniform(500, 1400)), 0.09, pan, 0.6)
        elif kind == "squelch":
            mix.add(at, squelch(root + 24 + int(R.integers(0, 12))), 0.07, pan, 0.5)
        elif kind == "tick":
            mix.add(at, TICK, 0.05, pan, 0.3)
        elif kind == "breath" and s % 8 == 6:
            mix.add(at, lowpass(R.standard_normal(int(0.6 * SR)), 900) * np.sin(np.pi * ts(int(0.6 * SR)) / 0.6), 0.05, pan, 0.6)
        elif kind == "heart" and s in (6, 14):
            mix.add(at, bubble(R.uniform(300, 600)), 0.06, pan, 0.5)


def battle_score(name, spec):
    bpm = spec["bpm"]
    beat = 60 / bpm
    bar = beat * 4
    step = beat / 4
    root, scale = spec["root"], spec["scale"]
    motif = MOTIFS[spec["motif"]]
    bars = 32
    base, tension, climax = Mix(bar * bars), Mix(bar * bars), Mix(bar * bars)

    def chord_at(b):
        d = spec["chords"][(b // 2) % 4]
        return d, d % 7 == 4 and scale[6] == 10

    for b in range(bars):
        section = b // 8   # 0 A 起 / 1 B 推进 / 2 C 全奏 / 3 D 收束与回升
        t0 = b * bar
        d, raise7 = chord_at(b)
        chord = triad(root + 12, scale, d, raise7)
        bass_root = degree(root, scale, d, raise7)
        build = section == 3 and b >= 30
        # --- 打击乐 ---
        kicks = sorted(set(spec["kick"] + [8]))
        if section == 2:
            kicks = sorted(set(kicks + [3, 14]))
        if section == 3 and not build:
            kicks = [0, 8]
        if build:
            kicks = [0, 4, 8, 12]
        for s in kicks:
            base.add(t0 + s * step, DRIVE_KICK, 1.0 if s == 0 else (0.82 if s == 8 else 0.61), 0, 0.02)
        for s in ((8,) if section == 3 and not build else (4, 12)):
            base.add(t0 + s * step, DRIVE_SNARE, 0.62, 0.05, 0.12)
            base.add(t0 + s * step, CLAP, 0.28, -0.08, 0.15)
        if section == 2:
            for s in (7, 15):
                base.add(t0 + s * step, DRIVE_SNARE, 0.12, 0.12, 0.08)
        if build:   # 回升：军鼓从八分到十六分越来越密
            density = 2 if b == 30 else 1
            for s in range(0, 16, density):
                base.add(t0 + s * step, SNARE, 0.08 + 0.22 * (s / 16 + (b - 30)) / 2, 0.05, 0.2)
        hats = {0: range(0, 16, 2), 1: range(0, 16, 2), 2: range(16), 3: range(2, 16, 4)}[section]
        if build:
            hats = range(0, 16, 2)
        for s in hats:
            base.add(t0 + s * step, HAT, 0.25 if s % 4 == 2 else 0.095, 0.34, 0.05)
        if section == 0:
            for s in range(0, 16, 2):
                base.add(t0 + s * step, SHAKER, 0.05, -0.4, 0.1)
        if section == 1 and b % 2:
            for i, s in enumerate((9, 11, 13, 15)):
                base.add(t0 + s * step, spiccato(chord[i % 3] + 24), 0.18, 0.38, 0.16)
        if section == 3 and not build:
            base.add(t0 + 10 * step, RIM, 0.25, 0, 0.14)
        if b in (7, 15, 23, 31):   # 每 8 小节一个过门
            for k, s in enumerate((12, 13, 14, 15)):
                base.add(t0 + s * step, TOMS[k], 0.45, -0.4 + k * 0.27, 0.25)
        if b in (15, 23, 31):
            base.add(t0, riser(bar), 0.16, 0, 0.4)
        if b in (0, 16):
            base.add(t0, impact(0.8 if b == 0 else 1.0), 0.34 if b == 0 else 0.42, 0, 0.5)
        # --- 低音律动 ---
        pattern = (0, 6, 10) if section == 3 and not build else spec["bass"]
        for i, s in enumerate(pattern):
            note = bass_root + (12 if i % 3 == 2 else 0)
            base.add(t0 + s * step, tbass(note, step * 0.95), 0.31 if s == 0 else 0.24, 0, 0.03)
        for s in (2, 10) if section == 3 and not build else (2, 6, 10, 14):
            for n in chord[1:]:
                base.add(t0 + s * step, spiccato(n), 0.13, -0.28, 0.12)
        # --- 主题动机 ---
        phrase_bar = b % 2
        for pos, deg, length in motif:
            if pos // 16 != phrase_bar or (section == 3 and not build and pos % 16 >= 8):
                continue
            note = degree(root + 24, scale, d + deg, raise7)
            at = t0 + (pos % 16) * step
            if section == 3 and not build:
                base.add(at, bell(note + 12, 0.7, 1.6, 2.01, 1.0), 0.12, 0.3, 0.6)
            else:
                base.add(at, lead_voice(spec["lead"], note, length * step), 0.19 if section == 0 else 0.28, 0.2 if pos % 2 else -0.2, 0.22)
                if section == 2:
                    base.add(at, lead_voice(spec["lead"], note + 12, length * step), 0.1, -0.3, 0.35)
        if section == 2 and b % 2 == 0:   # 全奏段的对位：长音弦乐唱一条反向的线
            top = degree(root + 36, scale, d + (2 if b % 4 == 0 else 4), raise7)
            base.add(t0, strings(top, bar * 2, 0.3), 0.1, 0.4, 0.5)
        texture(base, spec["texture"], t0, bar, [0.6, 0.4, 0.3, 0.7][section], root)

        # --- 紧张层：交错的短弓、踩镲和鬼音，往下一重拍推进 ---
        for i, s in enumerate((1, 3, 6, 9, 11, 14, 15)):
            tension.add(t0 + s * step, TICK if i % 2 else HAT, 0.21 if s in (3, 11, 15) else 0.12, 0.42, 0.1)
            tension.add(t0 + s * step, spiccato(chord[i % 3] + 12), 0.17, -0.34, 0.12)
        for s in (7, 15):
            tension.add(t0 + s * step, DRIVE_SNARE, 0.19, 0.15, 0.08)

        # --- 高潮层：铜管齐奏、抬高八度的回应和小节末鼓花 ---
        for s in (0, 6, 8, 14):
            for n in chord:
                climax.add(t0 + s * step, brass(n + 12, step * 1.35, 0.85), 0.12, 0, 0.18)
            climax.add(t0 + s * step, DRIVE_TAIKO, 0.25 if s in (0, 8) else 0.15, -0.2, 0.12)
        for i, s in enumerate((11, 13, 15) if b % 2 else (5, 13)):
            climax.add(t0 + s * step, TOMS[i], 0.2, 0.28, 0.12)
        if b % 4 == 0:
            climax.add(t0, CRASH, 0.25, 0.3, 0.4)

    write(base.render(wet_gain=0.3, rt=1.15), os.path.join(MUSIC, name + ".ogg"), 0.8)
    write(tension.render(wet_gain=0.28, rt=1.0), os.path.join(MUSIC, name + "_tension.ogg"), 0.43)
    write(climax.render(wet_gain=0.32, rt=1.2), os.path.join(MUSIC, name + "_climax.ogg"), 0.55)
    return {"bpm": bpm, "bar": bar, "bars": bars}


# ---------- Boss ----------
# groups：每小节的八分音符分组（2+2+3 = 7/8 等），不规则拍号就是 Boss 的「异常」
BOSSES = {
    "boss": dict(bpm=150, root=38, scale=MIXOLYDIAN, groups=[2, 2, 3], chords=[0, 3, 6, 4],
                 motif=[(0, 0, 2), (2, 0, 2), (4, 4, 3), (8, 2, 2), (10, 7, 3)]),
    "preclinical_boss": dict(bpm=146, root=36, scale=DORIAN, groups=[3, 3, 2, 2], chords=[0, 3, 6, 4],
                             motif=[(0, 0, 3), (3, 2, 3), (6, 4, 2), (12, 5, 2), (14, 7, 4)]),
    "phase1_boss": dict(bpm=152, root=41, scale=MIXOLYDIAN, groups=[2, 2, 3], chords=[0, 6, 3, 4],
                        motif=[(0, 0, 1), (1, 2, 1), (2, 0, 2), (4, 4, 2), (8, 5, 3), (11, 4, 3)]),
    "phase2_boss": dict(bpm=150, root=39, scale=MAJOR, groups=[3, 2, 2, 3], chords=[0, 5, 3, 4],
                        motif=[(0, 0, 4), (4, 1, 2), (6, 3, 2), (10, 1, 2), (14, 0, 4)]),
    "phase3_boss": dict(bpm=158, root=37, scale=MIXOLYDIAN, groups=[2, 3, 2], chords=[0, 6, 3, 4],
                        motif=[(0, 0, 2), (2, 4, 2), (4, 1, 3), (8, 0, 2), (10, 4, 2), (12, 5, 2)]),
}


def boss_score(name, spec, theme=None):
    bpm = spec["bpm"]
    eighth = 60 / bpm / 2
    step = eighth / 2
    groups = spec["groups"]
    bar_steps = sum(groups) * 2
    bar = bar_steps * step
    accents = [sum(groups[:i]) * 2 for i in range(len(groups))]
    root, scale = spec["root"], spec["scale"]
    bars = 32
    base, tension, climax = Mix(bar * bars), Mix(bar * bars), Mix(bar * bars)
    theme_events = []
    if theme:   # 最终 Boss：LM-001 主题塞进不规则拍号里
        pos = 0
        for note, beats in theme:
            theme_events.append((pos, to_major(note), beats * 4))
            pos += int(beats * 4)
    for b in range(bars):
        section = b // 8   # A 宣战 / B 展开 / C 全奏 / D 半拍换气与回升
        t0 = b * bar
        d = spec["chords"][(b // 2) % 4]
        raise7 = d % 7 == 4 and scale[6] == 10
        chord = triad(root + 12, scale, d, raise7)
        low = degree(root, scale, d, raise7)
        build = section == 3 and b >= 30
        # --- 打击乐 ---
        accents_now = (0, accents[-1]) if section == 3 and not build else accents
        for s in accents_now:
            base.add(t0 + s * step, DRIVE_KICK, 0.98 if s == 0 else 0.62, 0, 0.02)
            base.add(t0 + s * step, DRIVE_TAIKO, 0.32 if s == 0 else 0.19, 0, 0.12)
        for s in accents_now[1::2]:
            base.add(t0 + s * step, DRIVE_SNARE, 0.66, 0.05, 0.12)
            base.add(t0 + s * step, CLAP, 0.28, -0.1, 0.12)
        for s in range(0, bar_steps, 2):
            base.add(t0 + s * step, HAT, 0.09 if s in accents else 0.23, 0.34, 0.05)
        if section == 2:
            for s in (bar_steps // 2 - 1, bar_steps - 2):
                base.add(t0 + s * step, DRIVE_KICK, 0.48, 0, 0.03)
        if build:
            for s in range(0, bar_steps, 1 if b == 31 else 2):
                base.add(t0 + s * step, SNARE, 0.1 + 0.2 * s / bar_steps, 0.05, 0.2)
        if b in (7, 15, 23, 31):
            for k in range(4):
                base.add(t0 + (bar_steps - 4 + k) * step, TOMS[k], 0.5, -0.4 + k * 0.27, 0.25)
        if b in (15, 23, 31):
            base.add(t0, riser(bar), 0.18, 0, 0.4)
        if b in (0, 16):
            base.add(t0, impact(1.2), 0.5, 0, 0.5)
        # --- 短低音踩重拍，短弓从反拍回答 ---
        for i, s in enumerate(accents_now):
            base.add(t0 + s * step, tbass(low, step * 1.5), 0.32, 0, 0.03)
            base.add(t0 + (s + 2) * step, tbass(low + (12 if i % 2 else 7), step), 0.22, 0, 0.03)
            for n in chord[1:]:
                base.add(t0 + (s + 2) * step, spiccato(n + (12 if section == 2 else 0)), 0.18, -0.28, 0.16)
        # --- Boss 主题动机：短促的铜管宣战，全奏抬高八度 ---
        if theme_events:
            for pos, note, length in theme_events:
                rel = pos - (b % 8) * bar_steps
                if 0 <= rel < bar_steps:
                    at = t0 + rel * step
                    base.add(at, brass(note - 12 + (12 if section == 2 else 0), min(step * 4, length * step)), 0.24, 0, 0.22)
        elif section != 3 or build:
            for pos, deg, length in spec["motif"]:
                if b % 2 and pos < accents[-1]:
                    continue
                note = degree(root + 24, scale, d + deg, raise7) + (12 if section == 2 else 0)
                base.add(t0 + pos * step, brass(note, length * step * 0.75), 0.29, 0, 0.18)
                if section == 2:
                    base.add(t0 + pos * step, spiccato(note + 12), 0.11, 0.3, 0.17)

        # --- 紧张层：分组末尾的军鼓、分解短弓与切分踩镲 ---
        for i, s in enumerate(accents):
            tension.add(t0 + (s + 1) * step, spiccato(chord[i % 3] + 12), 0.22, -0.38, 0.12)
            tension.add(t0 + (s + 2) * step, HAT, 0.18, 0.4, 0.1)
            tension.add(t0 + (s + groups[i] * 2 - 1) * step, DRIVE_SNARE, 0.2, 0.16, 0.1)

        # --- 高潮层：成组的铜管与太鼓重音，穿插高音反句 ---
        for i, s in enumerate(accents):
            for n in chord:
                climax.add(t0 + s * step, brass(n + 12, step * 1.6, 1.0), 0.13, 0, 0.2)
            climax.add(t0 + s * step, DRIVE_TAIKO, 0.28, 0, 0.15)
            climax.add(t0 + (s + groups[i] * 2 - 1) * step, TOMS[i], 0.23, 0.28 if i % 2 else -0.28, 0.12)
        if b % 2:
            for pos, deg, length in spec["motif"]:
                note = degree(root + 36, scale, d + deg, raise7)
                climax.add(t0 + pos * step, lead_voice("strings", note, length * step), 0.13, 0.4, 0.18)
        if b % 4 == 0:
            climax.add(t0, CRASH, 0.3, -0.3, 0.4)

    write(base.render(wet_gain=0.28, rt=1.15), os.path.join(MUSIC, name + ".ogg"), 0.8)
    write(tension.render(wet_gain=0.26, rt=1.0), os.path.join(MUSIC, name + "_tension.ogg"), 0.43)
    write(climax.render(wet_gain=0.3, rt=1.2), os.path.join(MUSIC, name + "_climax.ogg"), 0.55)
    return {"bpm": bpm, "bar": bar, "bars": bars}


FINAL_BOSS = dict(bpm=154, root=33, scale=MAJOR, groups=[3, 3, 2], chords=[0, 3, 5, 4],
                  motif=[(0, 0, 3), (3, 2, 3), (6, 4, 2), (8, 3, 3), (11, 2, 3), (14, 1, 2)])


# ---------- 短乐句 ----------

def sting_write(name, mix, peak=0.78):
    write(mix.render(loop=False, wet_gain=0.65, rt=2.2), os.path.join(MUSIC, name + ".ogg"), peak)


def boss_intro():
    """短鼓组与上行铜管，1.35 秒的重拍对应 Boss 亮相。"""
    mix = Mix(0.1, tail=2.4)
    for at, note in ((0.0, 50), (0.32, 57), (0.59, 62), (0.86, 64), (1.11, 66)):
        mix.add(at, DRIVE_TAIKO, 0.45, 0, 0.16)
        mix.add(at, brass(note, 0.16), 0.52, 0, 0.2)
    for i, at in enumerate((0.9, 1.04, 1.16, 1.26)):
        mix.add(at, DRIVE_SNARE, 0.22 + i * 0.09, 0.1, 0.15)
    mix.add(1.35, DRIVE_KICK, 0.84, 0, 0.1)
    mix.add(1.35, CRASH, 0.22, 0, 0.18)
    for note in (55, 62, 67, 71):
        mix.add(1.35, brass(note, 0.47), 0.29, 0.0, 0.24)
    sting_write("boss_intro", mix, 0.64)


def boss_death():
    """战斗结束的铜管短句，上行落到明亮的大三和弦。"""
    mix = Mix(0.1, tail=3.2)
    for at, note in ((0.0, 57), (0.22, 62), (0.44, 66), (0.66, 69)):
        mix.add(at, DRIVE_TAIKO, 0.5, 0.0, 0.18)
        mix.add(at, brass(note, 0.17), 0.48, 0.0, 0.24)
    mix.add(0.92, DRIVE_KICK, 0.74, 0.0, 0.08)
    for n in (50, 57, 66, 74):
        mix.add(0.92, brass(n, 0.6), 0.25, 0.0, 0.27)
        mix.add(0.92, strings(n, 0.7, 0.08), 0.13, 0.0, 0.32)
    mix.add(1.12, bell(86, 0.7, 1.5, 2.01, 1.1), 0.15, 0.25, 0.3)
    sting_write("boss_death", mix, 0.7)


def battle_win():
    """普通战斗胜利：主题节奏（3-3-2）短短一句，结尾转大调"""
    mix = Mix(0.1, tail=5.0)
    step = 60 / 124 / 4
    for i, (pos, note) in enumerate(((0, 64), (3, 64), (6, 71), (8, 68), (10, 71), (12, 76))):
        mix.add(pos * step, spiccato(note, 1.0), 0.4, 0.2, 0.35)
        mix.add(pos * step, soft_pluck(note + 12), 0.15, -0.2, 0.4)
    mix.add(0, KICK, 0.6, 0, 0.1)
    mix.add(6 * step, KICK, 0.5, 0, 0.1)
    mix.add(12 * step, impact(0.6), 0.35, 0, 0.5)
    for n in (64, 68, 71, 76):
        mix.add(12 * step, strings(n - 12, 1.6, 0.05), 0.14, 0, 0.6)
        mix.add(12 * step, bell(n + 12, 0.7, 2.2, 2.01, 1.0), 0.12, 0.3, 0.7)
    sting_write("win", mix)


# ---------- 战斗音效（分层：预备 / 释放 / 命中 / 余韵） ----------

def _sweep_up(dur, f0, f1):
    n = int(dur * SR)
    t = ts(n)
    noise = R.standard_normal(n)
    out = np.zeros(n)
    for i in range(0, n, 512):
        out[i:i + 512] = lowpass(noise[i:i + 512], f0 + (f1 - f0) * (i / n) ** 1.5)
    return out * (t / dur) ** 1.5


def combat_sfx():
    # 分子蓄力：骨架绷紧的上扫 + 生物质感的低频「吸气」
    n = int(0.16 * SR)
    t = ts(n)
    inhale = np.sin(np.cumsum(TAU * (90 + 160 * t / 0.16) / SR)) * (t / 0.16) ** 1.2
    sfx("mol_charge", layer((_sweep_up(0.16, 300, 2600), 0.6, 0), (inhale, 0.6, 0), (squelch(55), 0.3, 0.02)), 0.45)
    # 分子释放：短促风切 + 一点金属亮边
    n = int(0.14 * SR)
    t = ts(n)
    whip = np.zeros(n)
    noise = R.standard_normal(n)
    for i in range(0, n, 256):
        whip[i:i + 256] = lowpass(noise[i:i + 256], 6500 - 4800 * i / n)
    whip *= np.exp(-t / 0.05) * np.minimum(1, t / 0.006)
    sfx("mol_release", layer((whip, 1.0, 0), (metal([2900, 4300], 0.1, 0.025), 0.25, 0.01)), 0.5)
    # 命中：瞬态 → 冲击 → 颗粒 → 余韵（低频的短暂回荡）
    tail = punch(0.5, 70, 50, 0.18) * 0.4
    sfx("hit", layer((click(), 0.9, 0), (punch(0.22, 260, 70, 0.06), 1.0, 0), (crunch(0.15, 3500, 0.03), 0.6, 0.003),
                     (tail, 1.0, 0.05)), 0.8)
    sfx("hit_heavy", layer((click(0.012), 1.0, 0), (punch(0.6, 210, 40, 0.16), 1.3, 0), (crunch(0.35, 2200, 0.07, 5.0), 0.9, 0.004),
                           (metal([310, 787, 1290], 0.7, 0.2), 0.25, 0.01), (punch(1.0, 60, 36, 0.4), 0.6, 0.08)), 0.95)
    # 护盾形成：膜被撑开的低频「嗡」+ 晶格一片片亮起的上行亮音
    hum = np.sin(TAU * 140 * ts(int(0.5 * SR))) * np.sin(np.pi * ts(int(0.5 * SR)) / 0.5) * 0.6
    chimes = [(metal([1320 * 2 ** (k / 12), 2100 * 2 ** (k / 12)], 0.3, 0.08), 0.35, 0.05 + k * 0.03) for k in (0, 3, 7, 10)]
    sfx("shield_form", layer((hum, 1.0, 0), (_sweep_up(0.2, 500, 4000), 0.25, 0), *chimes), 0.55)
    # 片段联动：两个片段依次亮起——五度两音 + 一道连接的亮光
    sfx("synergy", layer((bell(76, 0.9, 0.8, 2.01, 1.2), 0.5, 0), (bell(83, 0.9, 1.0, 2.01, 1.2), 0.55, 0.09),
                         (_sweep_up(0.12, 1500, 7000), 0.12, 0.05)), 0.5)
    # AI 激活：几何扫描（快速上行的方波琶音）+ 锁定确认的双音
    n = int(0.3 * SR)
    t = ts(n)
    arp = np.zeros(n)
    for k, f in enumerate((660, 990, 1320, 1980)):
        st = int(k * 0.035 * SR)
        seg = ts(int(0.05 * SR))
        tone = np.sign(np.sin(TAU * f * seg)) * np.exp(-seg / 0.02) * 0.4
        arp[st:st + len(tone)] += tone[:n - st]
    lock = layer((np.sin(TAU * 1760 * ts(int(0.06 * SR))) * 0.5, 1.0, 0), (np.sin(TAU * 2640 * ts(int(0.08 * SR))) * 0.5, 1.0, 0.06))
    sfx("ai_scan", layer((arp, 1.0, 0), (lock, 0.6, 0.16)), 0.42)
    # AI 失误：断续的故障声——采样率压缩的下滑方波，中间被切成碎片
    n = int(0.42 * SR)
    t = ts(n)
    sq = np.sign(np.sin(np.cumsum(TAU * (900 * np.exp(-t / 0.18) + 80) / SR)))
    gate = (np.floor(t / 0.028) % 3 != 1).astype(float)
    sq = np.repeat(sq[::8], 8)[:n] * gate * np.exp(-t / 0.2)
    sfx("ai_fail", layer((sq, 0.5, 0), (crunch(0.2, 5000, 0.04, 6.0), 0.3, 0.12)), 0.42)
    # Boss 攻击预警：低音铜管一声长鸣涨起 + 三全音的高音
    n = int(0.75 * SR)
    t = ts(n)
    swell = np.minimum(1, (t / 0.6) ** 2)
    horn = brass(38, 0.6, 1.0)[:n] * swell
    sfx("boss_warn", layer((horn, 1.0, 0), (brass(44, 0.6, 1.0)[:n] * swell, 0.5, 0), (_sweep_up(0.7, 200, 1800), 0.25, 0)), 0.6)
    # Boss 受击：深沉的共鸣撞击 + 一声闷吼
    growl = np.tanh(lowpass(np.sign(np.sin(np.cumsum(TAU * (70 + 20 * np.sin(TAU * 9 * ts(int(0.4 * SR)))) / SR))), 700) * 2) \
        * np.exp(-ts(int(0.4 * SR)) / 0.15)
    sfx("boss_hurt", layer((punch(0.7, 150, 38, 0.22), 1.2, 0), (crunch(0.3, 1400, 0.08, 4.0), 0.6, 0), (growl, 0.45, 0.03)), 0.85)
    # Boss 死亡：崩塌的长吼 + 碎落 + 低频收尾
    n = int(2.2 * SR)
    t = ts(n)
    f = 60 * np.exp(-t / 1.4) + 28
    roar = np.tanh(lowpass(2 * (np.cumsum(f / SR) % 1.0) - 1, 900) * 2) * np.minimum(1, t / 0.05) * np.exp(-t / 0.8)
    debris = np.zeros(n)
    for k in range(14):
        st = int(R.uniform(0.15, 1.6) * SR)
        bit = metal([R.uniform(900, 3000)], 0.12, 0.03)
        debris[st:st + len(bit)] += bit[:n - st] * R.uniform(0.3, 0.8)
    sfx("boss_die", layer((roar, 0.8, 0), (impact(1.3), 0.8, 0), (debris, 0.35, 0)), 0.95)


# ---------- 入口 ----------

def main():
    args = sys.argv[1:]
    only = next((a.split("=", 1)[1] for a in args if a.startswith("--only=")), "")
    do_music = "--sfx" not in args or "--music" in args
    do_sfx = "--music" not in args or "--sfx" in args
    meta_path = os.path.join(MUSIC, "music_meta.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    if do_music:
        for name, spec in BATTLES.items():
            if not only or only == name:
                meta[name] = battle_score(name, spec)
        for name, spec in BOSSES.items():
            if not only or only == name:
                meta[name] = boss_score(name, spec)
        if not only or only == "boss_final":
            meta["boss_final"] = boss_score("boss_final", FINAL_BOSS, THEME)
        if not only or only == "stings":
            boss_intro()
            boss_death()
            battle_win()
        with open(meta_path, "w") as fh:
            json.dump(meta, fh, indent=1, sort_keys=True)
        # 导出包里不一定带 JSON：同一份小节长度再写成 GDScript 常量，GameAudio 直接读
        script = os.path.join(ROOT, "..", "..", "scripts", "core", "music_meta.gd")
        with open(script, "w") as fh:
            fh.write("class_name MusicMeta\nextends RefCounted\n## 由 tools/gen_battle_music.py 生成：分层战斗曲的一小节秒数，GameAudio 用它把战况切换对齐到小节线。\n\n")
            fh.write("const BAR := {\n")
            for name in sorted(meta):
                fh.write('\t"%s": %.6f,\n' % (name, meta[name]["bar"]))
            fh.write("}\n")
            fh.write("\n## Boss 每组重拍在小节中的相对位置。\nconst ACCENTS := {\n")
            for name, spec in sorted({**BOSSES, "boss_final": FINAL_BOSS}.items()):
                groups = spec["groups"]
                offsets = ", ".join(f"{sum(groups[:i]) / sum(groups):.6f}" for i in range(len(groups)))
                fh.write(f'\t"{name}": [{offsets}],\n')
            fh.write("}\n")
    if do_sfx:
        combat_sfx()


if __name__ == "__main__":
    main()
