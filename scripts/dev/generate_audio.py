#!/usr/bin/env python3
"""BGM と効果音の素材 (assets/audio/) を合成して書き出す。

外部の素材・音源を使わず、波形 (矩形波・三角波・正弦波・ノイズ) を足し合わせて作る。乱数は固定の seed で
作るため、同じスクリプトからは同じ波形になる。効果音は WAV、BGM は Ogg Vorbis (ffmpeg の libvorbis で
エンコードする) で書き出す。書き出した素材は assets/CREDITS.md に記録する。

実行方法 (リポジトリのルートで): python3 scripts/dev/generate_audio.py
必要なもの: Python 3 と、libvorbis を有効にした ffmpeg
"""

import math
import random
import struct
import subprocess
import sys
import wave
from pathlib import Path

# 書き出し先
OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "audio"
# サンプリング周波数 (Hz)。効果音と、素朴な波形の BGM にはこれで足りる
RATE = 22050
# 書き出す波形の最大振幅 (1.0 = 16 bit の最大値)。重ねた音が割れないよう余裕を残す
PEAK = 0.8
# BGM の Ogg Vorbis の品質 (ffmpeg の -q:a。0〜10)。22050 Hz モノラルの素朴な波形で音の崩れが聞き取れず、
# 1 曲 100 KB 前後に収まる値
OGG_QUALITY = "4"


def midi_freq(note):
    """MIDI のノート番号の周波数 (Hz)。69 = A4 = 440 Hz"""
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def osc(kind, phase, duty=0.5):
    """位相 phase (周期 1) の波形の値 (-1〜1)"""
    p = phase % 1.0
    if kind == "square":
        return 1.0 if p < duty else -1.0
    if kind == "triangle":
        return 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p
    return math.sin(2.0 * math.pi * p)


def envelope(t, length, attack, release):
    """長さ length (秒) の音の、時刻 t (秒) の音量 (0〜1)。attack で立ち上がり、最後の release で消える"""
    if t < attack:
        return t / attack
    if t > length - release:
        return max(0.0, (length - t) / release)
    return 1.0


def add_tone(buf, start, length, freq, kind, volume, duty=0.5, attack=0.005, release=0.05, wrap=False):
    """buf の start (秒) から length (秒) の音を足す。wrap なら buf の末尾を越えた分を先頭に足す (ループの継ぎ目を滑らかにする)"""
    first = int(start * RATE)
    count = int(length * RATE)
    for i in range(count):
        t = i / RATE
        index = first + i
        if index >= len(buf):
            if not wrap:
                break
            index %= len(buf)
        buf[index] += osc(kind, freq * t, duty) * envelope(t, length, attack, release) * volume


def add_noise(buf, start, length, volume, rng, decay, wrap=False):
    """buf の start (秒) から length (秒) のノイズ (打楽器) を足す。decay (秒) で指数的に減衰する"""
    first = int(start * RATE)
    for i in range(int(length * RATE)):
        index = first + i
        if index >= len(buf):
            if not wrap:
                break
            index %= len(buf)
        buf[index] += rng.uniform(-1.0, 1.0) * math.exp(-(i / RATE) / decay) * volume


def add_kick(buf, start, volume, wrap=False):
    """buf の start (秒) にバスドラム (下がっていく正弦波) を足す"""
    first = int(start * RATE)
    phase = 0.0
    for i in range(int(0.18 * RATE)):
        t = i / RATE
        index = first + i
        if index >= len(buf):
            if not wrap:
                break
            index %= len(buf)
        phase += (50.0 + 110.0 * math.exp(-t / 0.03)) / RATE
        buf[index] += math.sin(2.0 * math.pi * phase) * math.exp(-t / 0.07) * volume


def normalized(buf):
    """最大振幅が PEAK になるよう揃えた buf"""
    top = max(abs(v) for v in buf) or 1.0
    return [v * PEAK / top for v in buf]


def pcm16(buf):
    """-1〜1 の値の並びを 16 bit のリトルエンディアンの PCM にする"""
    return b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in buf)


def write_wav(path, buf):
    """buf を 16 bit モノラルの WAV にして path に書き出す"""
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm16(normalized(buf)))


def write_ogg(path, buf):
    """ffmpeg で Ogg Vorbis にエンコードする。エンコーダの版などのメタデータは書かない"""
    subprocess.run(
        [
            "ffmpeg", "-loglevel", "error", "-y",
            "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "pipe:0",
            "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
            "-c:a", "libvorbis", "-q:a", OGG_QUALITY, str(path),
        ],
        input=pcm16(normalized(buf)),
        check=True,
    )


def se_attack():
    """攻撃: 高い音から下がる風切り音"""
    rng = random.Random(1)
    buf = [0.0] * int(0.25 * RATE)
    low = 0.0
    phase = 0.0
    for i in range(len(buf)):
        t = i / RATE
        fade = math.exp(-t / 0.06)
        cutoff = 0.05 + 0.5 * fade
        low += (rng.uniform(-1.0, 1.0) - low) * cutoff
        phase += (300.0 + 900.0 * fade) / RATE
        buf[i] = (low * 0.9 + math.sin(2.0 * math.pi * phase) * 0.35) * fade * min(1.0, t / 0.004)
    return buf


def se_damage():
    """ダメージ: 短いノイズと、低く下がる矩形波"""
    rng = random.Random(2)
    buf = [0.0] * int(0.35 * RATE)
    add_noise(buf, 0.0, 0.06, 0.5, rng, 0.02)
    phase = 0.0
    for i in range(len(buf)):
        t = i / RATE
        phase += (220.0 * math.exp(-t / 0.15) + 60.0) / RATE
        buf[i] += osc("square", phase, 0.5) * 0.45 * math.exp(-t / 0.12)
    return buf


def se_sync():
    """同期ボーナス: 駆け上がる明るい和音"""
    buf = [0.0] * int(0.6 * RATE)
    for step, note in enumerate([72, 76, 79, 84]):
        start = step * 0.06
        add_tone(buf, start, 0.6 - start, midi_freq(note), "square", 0.25, duty=0.25, release=0.35)
        add_tone(buf, start, 0.6 - start, midi_freq(note + 12), "triangle", 0.2, release=0.35)
    return buf


def se_stitch():
    """影縫い: 針を刺す短い高音と、低く響く音"""
    rng = random.Random(3)
    buf = [0.0] * int(0.3 * RATE)
    add_noise(buf, 0.0, 0.015, 0.6, rng, 0.004)
    phase = 0.0
    for i in range(int(0.15 * RATE)):
        t = i / RATE
        phase += (1400.0 - 3000.0 * t) / RATE
        buf[i] += math.sin(2.0 * math.pi * phase) * 0.45 * math.exp(-t / 0.05)
    add_tone(buf, 0.03, 0.25, 110.0, "triangle", 0.5, release=0.2)
    return buf


# BGM の定義。chords は 1 小節ごとの和音 (MIDI のノート番号。先頭が根音)、melody は 1 小節を 8 分音符 8 つに
# 分けた旋律の並び (和音の構成音の番号。None は休符)。小節ごとに順に使い回す
BGMS = {
    # 昼: ハ長調の明るく速い曲。矩形波の旋律と打楽器を全部鳴らす
    "bgm_day": {
        "tempo": 140,
        "chords": [[60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60],
                   [60, 64, 67], [55, 59, 62], [53, 57, 60], [55, 59, 62]],
        "melody": [[0, None, 1, 2, 1, None, 2, 0], [2, 1, None, 0, 1, 2, None, 1]],
        "lead": "square",
        "lead_volume": 0.22,
        "drums": {"kick": [0, 4], "snare": [2, 6], "hat": list(range(8))},
        "seed": 10,
    },
    # 夕方: イ短調のゆっくりした曲。三角波の柔らかい旋律と、軽い打楽器
    "bgm_evening": {
        "tempo": 104,
        "chords": [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62],
                   [57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 56, 59]],
        "melody": [[2, None, 1, None, 0, 1, None, None], [0, None, 2, 1, None, None, 1, None]],
        "lead": "triangle",
        "lead_volume": 0.3,
        "drums": {"kick": [0], "snare": [], "hat": [2, 6]},
        "seed": 20,
    },
    # 夜: ニ短調の静かな曲。正弦波の分散和音と、まばらな打楽器
    "bgm_night": {
        "tempo": 88,
        "chords": [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52],
                   [50, 53, 57], [46, 50, 53], [48, 52, 55], [45, 49, 52]],
        "melody": [[0, 1, 2, 1, 0, 1, 2, 1], [2, None, 1, None, 0, None, None, None]],
        "lead": "sine",
        "lead_volume": 0.3,
        "drums": {"kick": [0], "snare": [], "hat": [4]},
        "seed": 30,
    },
}
# BGM の小節数。この長さで繰り返す。和音の進行 (chords) が 8 小節で 1 周するため
BARS = 8


def bgm(spec):
    """spec (BGMS の値) の BGM を BARS 小節ぶん作る。末尾を越えた音は先頭に足し、繰り返しの継ぎ目で途切れないようにする"""
    rng = random.Random(spec["seed"])
    eighth = 30.0 / spec["tempo"]
    bar = eighth * 8
    buf = [0.0] * int(bar * BARS * RATE)
    for index, chord in enumerate(spec["chords"]):
        start = index * bar
        root = chord[0] - 12
        for beat in range(4):
            add_tone(buf, start + beat * eighth * 2, eighth * 2, midi_freq(root), "triangle", 0.35,
                     release=0.03, wrap=True)
        for note in chord:
            add_tone(buf, start, bar, midi_freq(note), "sine", 0.07, attack=0.05, release=0.1, wrap=True)
        pattern = spec["melody"][index % len(spec["melody"])]
        for step, tone in enumerate(pattern):
            if tone is None:
                continue
            add_tone(buf, start + step * eighth, eighth * 1.5, midi_freq(chord[tone] + 12), spec["lead"],
                     spec["lead_volume"], duty=0.25, release=eighth * 0.8, wrap=True)
        drums = spec["drums"]
        for step in drums["kick"]:
            add_kick(buf, start + step * eighth, 0.5, wrap=True)
        for step in drums["snare"]:
            add_noise(buf, start + step * eighth, 0.15, 0.3, rng, 0.05, wrap=True)
        for step in drums["hat"]:
            add_noise(buf, start + step * eighth, 0.04, 0.08, rng, 0.01, wrap=True)
    return buf


def main():
    """全素材を OUT_DIR に書き出す。同じ名前の素材は上書きする"""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, make in [("se_attack", se_attack), ("se_damage", se_damage), ("se_sync", se_sync),
                       ("se_stitch", se_stitch)]:
        write_wav(OUT_DIR / f"{name}.wav", make())
    for name, spec in BGMS.items():
        write_ogg(OUT_DIR / f"{name}.ogg", bgm(spec))
    return 0


if __name__ == "__main__":
    sys.exit(main())
