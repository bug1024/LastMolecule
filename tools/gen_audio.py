#!/usr/bin/env python3
"""生成游戏音乐与音效：纯程序合成，不依赖外部素材，可随时重跑。

运行：/usr/bin/python3 tools/gen_audio.py   （需要 numpy 与带 vorbis 编码器的 ffmpeg）
输出：assets/audio/music/*.ogg（无缝循环）、assets/audio/sfx/*.ogg
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(7)


# ---------- 基础工具 ----------

def mf(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def ts(n):
    return np.arange(n) / SR


def fade(sig, attack, release):
    n = len(sig)
    a = min(n, int(attack * SR))
    if a > 0:
        sig[:a] *= np.linspace(0, 1, a)
    r = min(n - a, int(release * SR))
    if r > 0:
        sig[n - r:] *= np.linspace(1, 0, r)
    return sig


def highpass(x):
    return np.diff(x, prepend=0.0)


def lowpass(x, cutoff):
    """频域一阶低通（只用于短信号）"""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= 1 / np.sqrt(1 + (f / cutoff) ** 2)
    return np.fft.irfft(spec, len(x))


# ---------- 乐器 ----------

def additive(freq, n, amps):
    t = ts(n)
    s = np.zeros(n)
    for k, a in enumerate(amps, 1):
        if freq * k > SR / 2.3:
            break
        s += a * np.sin(2 * np.pi * freq * k * t + rng.uniform(0, 2 * np.pi))
    return s


def pad(midis, dur, attack=1.0, release=1.6, bright=5.0, breathe=0.15):
    n = int((dur + release) * SR)
    out = np.zeros(n)
    amps = [(1 / k) * np.exp(-k / bright) for k in range(1, 14)]
    for m in midis:
        for det in (-0.09, 0.0, 0.09):
            out += additive(mf(m) * 2 ** (det / 12), n, amps)
    t = ts(n)
    e = np.ones(n)
    a = int(attack * SR)
    e[:a] = np.linspace(0, 1, a) ** 1.5
    r = int(release * SR)
    e[n - r:] *= np.linspace(1, 0, r) ** 1.5
    e *= 1 + 0.08 * np.sin(2 * np.pi * breathe * t)
    return out * e / (len(midis) * 3)


def epiano(m, dur, vel=1.0):
    f = mf(m)
    n = int((dur + 1.2) * SR)
    t = ts(n)
    mod = np.sin(2 * np.pi * f * t) * 1.4 * np.exp(-t / 0.22)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 1.4)
    s += 0.2 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.5)
    tail = t > dur
    s[tail] *= np.exp(-(t[tail] - dur) / 0.18)
    return fade(s, 0.004, 0.02) * vel


def bell(m, vel=1.0, length=3.5, ratio=3.5, index=2.0):
    f = mf(m)
    n = int(length * SR)
    t = ts(n)
    mod = np.sin(2 * np.pi * f * ratio * t) * index * np.exp(-t / 0.5)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 1.1)
    s += 0.25 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t / 0.4)
    return fade(s, 0.002, 0.05) * vel


def pluck(m, dur, vel=1.0, bright=1.0):
    f = mf(m)
    n = int((dur + 0.35) * SR)
    t = ts(n)
    s = np.zeros(n)
    for k in range(1, 12):
        if f * k > SR / 2.3:
            break
        s += (1 / k) * np.sin(2 * np.pi * f * k * t) * np.exp(-t * (3 + k * 2.2 / bright))
    tail = t > dur
    s[tail] *= np.exp(-(t[tail] - dur) / 0.06)
    return fade(s, 0.002, 0.01) * vel


def bass(m, dur, vel=1.0):
    f = mf(m)
    n = int((dur + 0.1) * SR)
    t = ts(n)
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.15)
    s += 0.12 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t / 0.08)
    s *= np.exp(-t / 2.0)
    return fade(s, 0.006, 0.08) * vel


def _kick():
    n = int(0.45 * SR)
    t = ts(n)
    phase = np.cumsum(2 * np.pi * (45 + 85 * np.exp(-t / 0.035)) / SR)
    s = np.sin(phase) * np.exp(-t / 0.16)
    s += 0.25 * rng.standard_normal(n) * np.exp(-t / 0.003)
    return fade(s, 0.0005, 0.02)


def _snare():
    n = int(0.3 * SR)
    t = ts(n)
    s = 0.7 * highpass(rng.standard_normal(n)) * np.exp(-t / 0.09)
    s += 0.5 * np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05)
    return fade(s, 0.001, 0.02)


def _hat(length=0.09, tau=0.025):
    n = int(length * SR)
    t = ts(n)
    s = highpass(highpass(rng.standard_normal(n))) * np.exp(-t / tau)
    return fade(s, 0.0005, 0.01) * 0.5


def _taiko():
    n = int(0.7 * SR)
    t = ts(n)
    body = np.sin(np.cumsum(2 * np.pi * (65 + 40 * np.exp(-t / 0.05)) / SR)) * np.exp(-t / 0.25)
    skin = lowpass(rng.standard_normal(n), 700) * np.exp(-t / 0.04)
    return fade(body + skin * 0.6, 0.001, 0.05)


KICK, SNARE, HAT, SHAKER = _kick(), _snare(), _hat(), _hat(0.12, 0.05)
TAIKO = _taiko()


# ---------- 混音 ----------

class Mix:
    """带混响发送的立体声缓冲；length 为循环长度（秒）"""

    def __init__(self, length, tail=6.0):
        self.L = int(length * SR)
        size = self.L + int(tail * SR)
        self.dry = np.zeros((2, size))
        self.wet = np.zeros((2, size))

    def add(self, start, sig, gain=1.0, pan=0.0, send=0.25):
        i = int(start * SR)
        if i >= self.dry.shape[1]:
            return
        n = min(len(sig), self.dry.shape[1] - i)
        theta = (pan + 1) * np.pi / 4
        for ch, w in ((0, np.cos(theta)), (1, np.sin(theta))):
            part = sig[:n] * gain * w
            self.dry[ch, i:i + n] += part
            self.wet[ch, i:i + n] += part * send

    def render(self, loop=True, wet_gain=0.6, rt=2.4):
        out = self.dry + reverb(self.wet, rt) * wet_gain
        if not loop:
            return trim_silence(out)
        body = out[:, :self.L].copy()
        tail = out[:, self.L:]
        m = min(tail.shape[1], self.L)
        body[:, :m] += tail[:, :m]
        return body


def reverb(x, rt):
    n = int(rt * SR)
    t = ts(n)
    out = np.zeros_like(x)
    size = 1 << int(np.ceil(np.log2(x.shape[1] + n)))
    for ch in range(2):
        ir = np.random.default_rng(11 + ch).standard_normal(n) * np.exp(-6.9 * t / rt)
        ir = lowpass(ir, 3500)
        pre = int(0.015 * SR)
        ir[:pre] *= np.linspace(0, 1, pre)
        ir /= np.sqrt(np.sum(ir ** 2))
        out[ch] = np.fft.irfft(np.fft.rfft(x[ch], size) * np.fft.rfft(ir, size), size)[:x.shape[1]]
    return out


def trim_silence(x, threshold=1e-4):
    energy = np.max(np.abs(x), axis=0)
    idx = np.nonzero(energy > threshold)[0]
    end = idx[-1] + int(0.05 * SR) if len(idx) else x.shape[1]
    return fade_stereo(x[:, :end], 0.0, 0.05)


def fade_stereo(x, attack, release):
    for ch in range(2):
        x[ch] = fade(x[ch], attack, release)
    return x


def write(x, path, peak=0.8):
    x = x / max(1e-9, np.max(np.abs(x))) * peak
    x = np.tanh(x * 1.1) / np.tanh(1.1)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16).T.copy()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = tmp.name
    with wave.open(tmp_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", tmp_path,
                    "-c:a", "vorbis", "-strict", "-2", "-q:a", "6", path], check=True)
    os.remove(tmp_path)
    print("wrote", os.path.relpath(path), "%.1fs" % (x.shape[1] / SR))


# ---------- LM-001 主题 ----------
# 一段 8 小节的固定旋律（A 小调），不随机生成：标题、最终 Boss、主线结局都用它，只换配器、速度与调式。
# 每项 (MIDI 音高, 拍数)；每小节 4 拍。
THEME = [
    (69, 2), (72, 1), (76, 1),            # 1  A  C  E
    (74, 3), (72, 1),                     # 2  D— C
    (71, 1), (72, 1), (74, 1), (76, 1),   # 3  B C D E
    (69, 4),                              # 4  A———
    (69, 1), (72, 1), (76, 1), (81, 1),   # 5  A C E A'
    (79, 2), (76, 1), (74, 1),            # 6  G— E D
    (72, 1), (74, 1), (71, 2),            # 7  C D B—
    (69, 4),                              # 8  A———
]
# 每小节的和弦（根音, 和弦音）
THEME_CHORDS = [
    (45, [57, 60, 64]), (50, [57, 62, 65]), (43, [55, 59, 62]), (45, [57, 60, 64]),
    (45, [57, 60, 64]), (40, [55, 59, 64]), (41, [57, 60, 65]), (45, [57, 60, 64]),
]


def to_major(m):
    """A 小调 → A 大调：C→C#、F→F#、G→G#（获批结局用）"""
    return m + 1 if m % 12 in (0, 5, 7) else m


def theme_notes(bars=8, major=False):
    """返回 [(起始拍, 音高, 拍数)]，只取前 bars 小节"""
    out, t = [], 0.0
    for note, beats in THEME:
        if t >= bars * 4:
            break
        out.append((t, to_major(note) if major else note, beats))
        t += beats
    return out


# ---------- 音乐 ----------

def music_title():
    """标题：68 BPM。LM-001 主题第一次出现——缓慢的电钢琴旋律 + 长音铺底，后半段只剩铺底与零星钟声（循环 16 小节）"""
    beat = 60 / 68
    bar = beat * 4
    mix = Mix(bar * 16)
    for rep_i in range(2):
        for i, (root, notes) in enumerate(THEME_CHORDS):
            start = (rep_i * 8 + i) * bar
            mix.add(start, pad(notes, bar, attack=1.2, release=1.8), 0.5, 0.0, 0.5)
            mix.add(start, bass(root, bar - 0.1) * 0.6, 0.32, 0.0, 0.1)
    for t, note, beats in theme_notes():
        mix.add(t * beat, epiano(note, beats * beat * 0.95, 0.85), 0.34, -0.15, 0.55)
        mix.add(t * beat, bell(note + 12, 0.35, 3.0), 0.08, 0.4, 0.8)
    # 后 8 小节：主题的回声，只在每小节第一拍敲一下钟
    for i, (t, note, beats) in enumerate(theme_notes()):
        if t % 4 == 0:
            mix.add(bar * 8 + t * beat + beat, bell(note + 12, 0.45, 4.0, 4.1), 0.16, 0.5 - (i % 2), 0.8)
    write(mix.render(wet_gain=0.85, rt=3.4), os.path.join(ROOT, "music", "title.ogg"))


def music_lab():
    """研发日常（主界面 / 地图）：86 BPM，D 多利亚电钢琴 + 轻鼓"""
    beat = 60 / 86
    bar = beat * 4
    cycle = [
        ([53, 57, 60, 64], 38), ([53, 57, 59, 62], 43), ([53, 57, 58, 62], 34), ([55, 57, 62, 64], 33),
    ]
    mix = Mix(bar * 16)
    swing = 0.07 * beat
    # 编排好的旋律（D 多利亚，八分音符；None 为休止），后 8 小节循环出现
    phrase = [
        [69, None, 72, 74, None, 72, 69, None], [67, None, 69, None, 65, 67, None, None],
        [69, None, 72, 74, 77, None, 74, 72], [74, None, None, 72, 69, None, None, None],
        [65, 67, 69, None, 72, None, 69, None], [67, None, 65, None, 62, 65, None, None],
        [69, 72, None, 74, None, 72, 74, 77], [74, None, None, None, None, None, None, None],
    ]
    for b in range(16):
        notes, root = cycle[b % 4]
        start = b * bar
        for off, length, vel in ((0, 1.4, 0.9), (2.5, 1.2, 0.7)):
            for k, n in enumerate(notes):
                mix.add(start + off * beat + k * 0.012, epiano(n, length * beat, vel), 0.16, -0.25 + k * 0.17, 0.35)
        for off, note, length in ((0, root, 1.5), (1.75, root + 12, 0.25), (2, root + 7, 1.4), (3.5, root + 5, 0.45)):
            mix.add(start + off * beat, bass(note, length * beat), 0.42, 0.0, 0.05)
        mix.add(start, KICK, 0.55, 0, 0.05)
        mix.add(start + 2.5 * beat, KICK, 0.35, 0, 0.05)
        for off in (1, 3):
            mix.add(start + off * beat, SNARE, 0.18, 0.1, 0.25)
        for e in range(8):
            mix.add(start + e * beat / 2 + (swing if e % 2 else 0), HAT, 0.12 if e % 2 else 0.08, 0.35, 0.1)
        if b >= 8:
            for e, note in enumerate(phrase[b - 8]):
                if note is not None:
                    mix.add(start + e * beat / 2 + (swing if e % 2 else 0),
                            pluck(note, beat * 0.45, 0.9, 1.4), 0.2, -0.3 + 0.08 * e, 0.55)
    write(mix.render(wet_gain=0.55, rt=2.0), os.path.join(ROOT, "music", "lab.ogg"))


def music_battle():
    """阶段试验（战斗）：124 BPM，E 小调十六分琶音 + 贝斯八分音型"""
    beat = 60 / 124
    bar = beat * 4
    cycle = [([64, 67, 71, 76], 40), ([60, 64, 67, 71], 36), ([57, 60, 64, 69], 33), ([59, 63, 66, 69], 35)]
    order = [0, 1, 2, 3, 2, 1, 3, 1, 0, 2, 1, 3, 2, 1, 0, 3]
    bass_pat = [0, 0, 12, 0, 0, 12, 0, 7]
    mix = Mix(bar * 16)
    for c in range(8):
        notes, root = cycle[c % 4]
        start = c * bar * 2
        mix.add(start, pad([n - 12 for n in notes], bar * 2, attack=0.4, release=0.8, bright=3.0), 0.28, 0, 0.4)
        if c % 2 == 0:
            mix.add(start, bell(notes[0] + 12, 0.6, 2.5, 1.5, 3.0), 0.12, -0.5, 0.6)
        for b in range(2):
            bs = start + b * bar
            for s in range(16):
                note = notes[order[s] % len(notes)] + (12 if (c >= 4 and s % 8 == 7) else 0)
                mix.add(bs + s * beat / 4, pluck(note, 0.09, 0.8 + 0.2 * (s % 4 == 0), 2.0), 0.16,
                        0.3 if s % 2 else -0.3, 0.3)
            for e in range(8):
                mix.add(bs + e * beat / 2, bass(root + bass_pat[e], beat * 0.45), 0.4, 0, 0.05)
            for q in range(4):
                mix.add(bs + q * beat, KICK, 0.6, 0, 0.05)
                if q % 2 == 1:
                    mix.add(bs + q * beat, SNARE, 0.3, 0.05, 0.3)
            for s in range(16):
                mix.add(bs + s * beat / 4, HAT, 0.1 if s % 4 == 2 else 0.05, 0.4, 0.05)
    write(mix.render(wet_gain=0.45, rt=1.6), os.path.join(ROOT, "music", "battle.ogg"))


def music_boss():
    """Boss 战：136 BPM，D 小调，低音八度冲击 + 弦乐式铺底 + 警报钟"""
    beat = 60 / 136
    bar = beat * 4
    cycle = [([62, 65, 69], 38), ([58, 62, 65], 34), ([60, 64, 67], 36), ([61, 64, 69], 33)]
    mix = Mix(bar * 16)
    for c in range(8):
        notes, root = cycle[c % 4]
        start = c * bar * 2
        mix.add(start, pad([n - 12 for n in notes] + [notes[0]], bar * 2, attack=0.15, release=0.6, bright=7.0), 0.32, 0, 0.35)
        for b in range(2):
            bs = start + b * bar
            for e in range(16):
                if e % 4 != 3:
                    note = root + (12 if e % 8 == 6 else 0)
                    mix.add(bs + e * beat / 4, bass(note, beat * 0.2, 1.0), 0.42, 0, 0.03)
            for q in range(4):
                mix.add(bs + q * beat, KICK, 0.75, 0, 0.05)
                mix.add(bs + q * beat + beat / 2, HAT, 0.12, 0.4, 0.05)
                if q % 2 == 1:
                    mix.add(bs + q * beat, SNARE, 0.4, 0, 0.35)
                else:
                    mix.add(bs + q * beat, TAIKO, 0.55, 0, 0.5)
            if c >= 4:
                for s16 in range(8):
                    mix.add(bs + s16 * beat / 2, pluck(notes[s16 % 3] + 12, 0.1, 0.9, 2.5), 0.14, -0.3 if s16 % 2 else 0.3, 0.3)
        mix.add(start, bell(notes[0] + 24, 0.7, 2.0, 1.41, 3.5), 0.14, 0.5, 0.6)
        mix.add(start + bar, bell(notes[1] + 24, 0.6, 2.0, 1.41, 3.5), 0.12, -0.5, 0.6)
    write(mix.render(wet_gain=0.4, rt=1.4), os.path.join(ROOT, "music", "boss.ogg"))


def music_boss_final():
    """最终 Boss（LM-001）：128 BPM，A 小调。前 8 小节是推进的低音与太鼓，后 8 小节钟声与拨弦齐奏 LM-001 主题"""
    beat = 60 / 128
    bar = beat * 4
    mix = Mix(bar * 16)
    for rep_i in range(2):
        for i, (root, notes) in enumerate(THEME_CHORDS):
            start = (rep_i * 8 + i) * bar
            mix.add(start, pad([n - 12 for n in notes] + [notes[0]], bar, attack=0.12, release=0.5, bright=7.0), 0.3, 0, 0.35)
            for e in range(16):
                if e % 4 != 3:
                    mix.add(start + e * beat / 4, bass(root + (12 if e % 8 == 6 else 0), beat * 0.2, 1.0), 0.42, 0, 0.03)
            for q in range(4):
                mix.add(start + q * beat, KICK, 0.75, 0, 0.05)
                mix.add(start + q * beat + beat / 2, HAT, 0.12, 0.4, 0.05)
                mix.add(start + q * beat, SNARE if q % 2 else TAIKO, 0.4 if q % 2 else 0.55, 0, 0.4)
    for t, note, beats in theme_notes():
        at = bar * 8 + t * beat
        mix.add(at, bell(note + 12, 0.85, 2.0, 1.41, 3.5), 0.2, 0.3, 0.55)
        for k in range(int(beats * 2)):
            mix.add(at + k * beat / 2, pluck(note, 0.12, 0.85, 2.2), 0.14, -0.3, 0.3)
    write(mix.render(wet_gain=0.4, rt=1.4), os.path.join(ROOT, "music", "boss_final.ogg"))


# ---------- 短乐句 ----------

def sting(name, build, tail=9.0):
    mix = Mix(0.1, tail=tail)
    build(mix)
    write(mix.render(loop=False, wet_gain=0.7, rt=2.2), os.path.join(ROOT, "music", name + ".ogg"), 0.75)


def _win(mix):
    for i, n in enumerate([72, 76, 79, 84]):
        mix.add(i * 0.09, pluck(n, 0.25, 1.0, 2.0), 0.35, -0.3 + i * 0.2, 0.4)
    mix.add(0.36, bell(84, 0.8), 0.3, 0, 0.6)
    mix.add(0.3, pad([60, 64, 67, 72], 1.3, 0.2, 1.2), 0.5, 0, 0.5)


def _lose(mix):
    for i, n in enumerate([69, 65, 62, 57]):
        mix.add(i * 0.16, pluck(n, 0.3, 0.9, 0.8), 0.32, 0.3 - i * 0.2, 0.4)
    mix.add(0.5, pad([57, 60, 63], 1.4, 0.3, 1.4, 3.0), 0.5, 0, 0.5)
    mix.add(0.5, bass(33, 1.5), 0.4)


def _approved(mix):
    mix.add(0, pad([48, 55, 60, 64, 67, 74], 4.5, 0.8, 2.5, 6.0), 0.7, 0, 0.6)
    mix.add(0, bass(36, 5.0), 0.4)
    for i, n in enumerate([72, 76, 79, 84, 88, 91, 96]):
        mix.add(0.3 + i * 0.14, bell(n, 0.8, 4.0), 0.22, -0.6 + i * 0.2, 0.7)
    mix.add(1.6, KICK, 0.5)
    mix.add(1.6, pad([67, 72, 76, 79], 3.0, 0.1, 2.5, 8.0), 0.35, 0, 0.6)


def _failed(mix):
    mix.add(0, pad([45, 48, 52], 3.5, 0.6, 2.5, 2.5), 0.6, 0, 0.5)
    mix.add(0, bass(33, 4.5), 0.4)
    for i, n in enumerate([72, 69, 67, 64, 60]):
        mix.add(0.4 + i * 0.35, bell(n, 0.6, 3.0, 2.0, 1.2), 0.2, 0.4 - i * 0.2, 0.7)


def _campaign_approved(mix):
    """主线获批：LM-001 主题转大调完整奏出（8 小节，90 BPM），结束在 A 大三和弦"""
    beat = 60 / 90
    bar = beat * 4
    major_chords = [(45, [57, 61, 64]), (50, [57, 62, 66]), (40, [56, 59, 64]), (45, [57, 61, 64]),
                    (45, [57, 61, 64]), (42, [54, 61, 64]), (50, [57, 62, 66]), (45, [57, 61, 64, 69])]
    for i, (root, notes) in enumerate(major_chords):
        mix.add(i * bar, pad(notes, bar * (1.6 if i == 7 else 1.0), attack=0.5, release=2.0, bright=6.0), 0.45, 0, 0.55)
        mix.add(i * bar, bass(root, bar - 0.1), 0.35, 0, 0.1)
    for t, note, beats in theme_notes(major=True):
        mix.add(t * beat, epiano(note, beats * beat * 0.95, 0.95), 0.36, -0.1, 0.5)
        mix.add(t * beat, bell(note + 12, 0.55, 3.0), 0.12, 0.3, 0.7)
    for i, n in enumerate([81, 85, 88, 93]):
        mix.add(bar * 7 + beat * 2 + i * 0.12, bell(n, 0.8, 4.0), 0.2, -0.4 + i * 0.25, 0.7)


def _campaign_archive(mix):
    """把答案留下：只用单音钟声安静地奏出主题前 4 小节，停在不解决的 E 上"""
    beat = 60 / 62
    mix.add(0, pad([45, 52, 57], beat * 16, attack=2.0, release=3.0, bright=2.5), 0.35, 0, 0.6)
    for t, note, beats in theme_notes(bars=3):
        mix.add(t * beat, bell(note, 0.55, 4.0, 2.0, 1.2), 0.24, -0.2, 0.8)
    mix.add(12 * beat, bell(76, 0.5, 6.0, 2.0, 1.2), 0.22, 0.2, 0.85)


def _terminated(mix):
    mix.add(0, pad([50, 55, 57, 62], 3.0, 0.5, 2.2, 4.0), 0.55, 0, 0.6)
    for i, n in enumerate([74, 69, 74, 76]):
        mix.add(0.5 + i * 0.4, bell(n, 0.5, 3.0), 0.18, -0.3 + i * 0.2, 0.7)


# ---------- 音效 ----------

def sfx(name, sig, peak=0.7):
    st = np.vstack([sig, sig])
    write(fade_stereo(st, 0.0, 0.01), os.path.join(ROOT, "sfx", name + ".ogg"), peak)


def noise_sweep(dur, f0, f1, tau):
    n = int(dur * SR)
    t = ts(n)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    seg = 512
    for i in range(0, n, seg):
        frac = i / n
        cutoff = f0 + (f1 - f0) * frac
        out[i:i + seg] = lowpass(noise[i:i + seg], cutoff)
    return out * np.exp(-t / tau) * np.minimum(1, t / 0.02)


def make_sfx():
    n = int(0.06 * SR)
    t = ts(n)
    sfx("click", np.sin(2 * np.pi * 1350 * t) * np.exp(-t / 0.012) + 0.2 * highpass(rng.standard_normal(n)) * np.exp(-t / 0.003), 0.5)
    n = int(0.04 * SR)
    t = ts(n)
    sfx("hover", np.sin(2 * np.pi * 2200 * t) * np.exp(-t / 0.008), 0.18)
    sfx("card_play", np.concatenate([noise_sweep(0.16, 600, 5000, 0.08), np.zeros(1)]) * 0.7 +
        np.pad(pluck(76, 0.12, 1.0, 2.0), (0, 0))[:int(0.16 * SR) + 1] * 0.6, 0.6)
    sfx("card_draw", noise_sweep(0.12, 2500, 900, 0.04), 0.35)
    # 偏差：降调方波 + 采样率压缩的“故障”感
    n = int(0.35 * SR)
    t = ts(n)
    freq = 520 * np.exp(-t / 0.15)
    sq = np.sign(np.sin(np.cumsum(2 * np.pi * freq / SR)))
    sq = np.repeat(sq[::6], 6)[:n] * np.exp(-t / 0.18)
    sfx("deviation", sq * 0.5, 0.45)
    sfx("gain", np.pad(bell(88, 0.8, 0.6, 2.0, 1.0), (0, int(0.08 * SR)))[:int(0.68 * SR)] +
        np.pad(bell(95, 0.7, 0.6, 2.0, 1.0), (int(0.08 * SR), 0))[:int(0.68 * SR)], 0.4)
    n = int(0.4 * SR)
    t = ts(n)
    phase = np.cumsum(2 * np.pi * (180 * np.exp(-t / 0.2) + 60) / SR)
    sfx("loss", np.sin(phase) * np.exp(-t / 0.15) + 0.3 * lowpass(rng.standard_normal(n), 800) * np.exp(-t / 0.05), 0.5)
    sfx("turn", noise_sweep(0.45, 300, 2200, 0.18), 0.4)
    blip = np.concatenate([pluck(81, 0.05, 1.0, 2.0)[:int(0.07 * SR)], pluck(88, 0.08, 1.0, 2.0)])
    sfx("node", blip, 0.45)
    n = int(0.3 * SR)
    t = ts(n)
    sfx("open", noise_sweep(0.3, 400, 3000, 0.12) * 0.6 + np.sin(2 * np.pi * 660 * t) * np.sin(np.pi * t / 0.3) * 0.2, 0.3)
    up = np.zeros(int(1.2 * SR))
    for i, note in enumerate([72, 76, 79, 84]):
        b = bell(note, 0.8, 1.0)
        s = int(i * 0.1 * SR)
        up[s:s + len(b)] += b[:len(up) - s]
    sfx("stage", up, 0.5)
    make_combat_sfx()
    n = int(0.15 * SR)
    t = ts(n)
    sfx("error", np.sign(np.sin(2 * np.pi * 140 * t)) * np.exp(-t / 0.06) * 0.6, 0.35)


def punch(dur, f0, f1, tau):
    """下扫正弦冲击（打击感的「肉」）"""
    n = int(dur * SR)
    t = ts(n)
    return np.sin(np.cumsum(2 * np.pi * (f1 + (f0 - f1) * np.exp(-t / 0.03)) / SR)) * np.exp(-t / tau)


def crunch(dur, cutoff, tau, drive=3.0):
    n = int(dur * SR)
    t = ts(n)
    return np.tanh(lowpass(rng.standard_normal(n), cutoff) * drive) * np.exp(-t / tau)


def click(dur=0.008):
    n = int(dur * SR)
    return highpass(rng.standard_normal(n)) * np.linspace(1, 0, n)


def layer(*parts):
    n = max(len(p) + int(d * SR) for p, _, d in parts)
    out = np.zeros(n + int(0.05 * SR))
    for sig, gain, delay in parts:
        i = int(delay * SR)
        out[i:i + len(sig)] += sig * gain
    return out


def metal(freqs, dur, tau):
    n = int(dur * SR)
    t = ts(n)
    return sum(np.sin(2 * np.pi * f * t) * np.exp(-t / (tau * (1.0 - 0.15 * i))) for i, f in enumerate(freqs)) / len(freqs)


def sfx_end_turn():
    """结束回合：低沉的「咚」（像按下实验台上的大按钮）+ 一阵风声 + 两音上行的钟声，交出回合的确认感。
    用独立随机数，单独生成时不影响其他音效。"""
    local = np.random.default_rng(42)
    n = int(0.9 * SR)
    t = ts(n)
    thump = np.sin(np.cumsum(2 * np.pi * (140 * np.exp(-t / 0.08) + 55) / SR)) * np.exp(-t / 0.12)
    whoosh = np.zeros(n)
    noise = local.standard_normal(n)
    env = np.sin(np.pi * np.minimum(t / 0.5, 1.0)) * np.exp(-np.maximum(t - 0.5, 0) / 0.1)
    whoosh[:] = lowpass(noise, 1800) * env
    chime = np.zeros(n)
    for i, note in enumerate([76, 83]):
        b = bell(note, 0.7, 0.9, 2.0, 1.5)
        st = int((0.06 + i * 0.09) * SR)
        chime[st:st + len(b)] += b[:n - st]
    sfx("end_turn", layer((thump, 1.0, 0), (whoosh, 0.25, 0), (chime, 0.35, 0)), 0.6)


def make_combat_sfx():
    # 出牌挥击：高频风声快速下扫
    sfx("slash", layer((noise_sweep(0.18, 7000, 1500, 0.06), 1.0, 0), (metal([2400, 3700], 0.15, 0.03), 0.25, 0.02)), 0.55)
    # AI 卡：电子音上扫 + 比特压缩
    n = int(0.22 * SR)
    t = ts(n)
    zap = np.sign(np.sin(np.cumsum(2 * np.pi * (300 + 2200 * t / 0.22) / SR))) * np.exp(-t / 0.09)
    sfx("zap", layer((np.repeat(zap[::4], 4)[:n], 0.6, 0), (metal([1800, 2600], 0.2, 0.05), 0.4, 0)), 0.5)
    # 命中：瞬态 + 冲击 + 颗粒噪声，重击再加低频轰鸣与金属回响
    sfx("hit", layer((click(), 0.9, 0), (punch(0.22, 260, 70, 0.06), 1.0, 0), (crunch(0.15, 3500, 0.03), 0.7, 0.003)), 0.8)
    sfx("hit_heavy", layer((click(0.012), 1.0, 0), (punch(0.5, 200, 42, 0.14), 1.3, 0), (crunch(0.35, 2200, 0.07, 5.0), 0.9, 0.004),
        (metal([310, 787, 1290], 0.6, 0.18), 0.25, 0.01)), 0.95)
    # 玩家受击：闷响 + 玻璃烧瓶的「叮」
    sfx("hurt", layer((punch(0.3, 180, 55, 0.08), 1.0, 0), (crunch(0.2, 1500, 0.05), 0.6, 0), (metal([1960, 2950, 4100], 0.4, 0.12), 0.35, 0.01)), 0.8)
    # 护盾：金属铛声
    sfx("block", layer((metal([523, 1310, 2140, 3020], 0.5, 0.12), 0.9, 0), (punch(0.12, 300, 120, 0.03), 0.5, 0), (click(), 0.4, 0)), 0.6)
    # 低血量心跳：咚-咚
    beat = punch(0.18, 90, 45, 0.06)
    sfx("heartbeat", layer((beat, 1.0, 0), (beat, 0.7, 0.22)), 0.7)
    # Boss 登场：咆哮（失谐锯齿 + 抖动包络）+ 鼓
    n = int(2.0 * SR)
    t = ts(n)
    f = 48 + 18 * np.sin(np.pi * np.minimum(t / 1.6, 1.0))
    growl = np.zeros(n)
    for det in (1.0, 1.013, 0.987, 2.004):
        ph = np.cumsum(2 * np.pi * f * det / SR)
        growl += 2 * (ph / (2 * np.pi) % 1.0) - 1
    growl = lowpass(growl, 900) * (1 + 0.5 * np.sin(2 * np.pi * 11 * t)) * np.minimum(1, t / 0.25) * np.exp(-np.maximum(t - 1.0, 0) / 0.4)
    sfx("boss", layer((np.tanh(growl * 0.6), 0.8, 0), (punch(0.8, 120, 38, 0.3), 1.2, 0), (noise_sweep(2.0, 300, 2500, 0.8), 0.35, 0),
        (punch(0.8, 120, 38, 0.3), 1.0, 0.9)), 0.95)
    # Boss 出招：沉重踏步
    sfx("boss_stomp", layer((punch(0.6, 140, 35, 0.2), 1.2, 0), (crunch(0.4, 900, 0.1, 4.0), 0.6, 0)), 0.85)
    # 升级：上行琶音 + 闪光
    up = np.zeros(int(1.4 * SR))
    for i, note in enumerate([72, 76, 79, 84, 88]):
        b = bell(note, 0.9, 1.0)
        st = int(i * 0.08 * SR)
        up[st:st + len(b)] += b[:len(up) - st]
    sfx("level_up", layer((up, 1.0, 0), (noise_sweep(1.0, 2000, 9000, 0.4), 0.2, 0.3)), 0.7)


if __name__ == "__main__":
    import sys
    if "--only-end-turn" in sys.argv:   # 只生成结束回合音效
        sfx_end_turn()
        sys.exit(0)
    music_title()
    music_lab()
    music_battle()
    music_boss()
    music_boss_final()
    sting("win", _win)
    sting("lose", _lose)
    sting("approved", _approved)
    sting("failed", _failed)
    sting("terminated", _terminated)
    sting("campaign_approved", _campaign_approved, tail=27.0)
    sting("campaign_archive", _campaign_archive, tail=21.0)
    if "--music-only" not in sys.argv:   # 只改音乐时加 --music-only，音效保持不变
        make_sfx()
    sfx_end_turn()
