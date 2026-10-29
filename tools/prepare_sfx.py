#!/usr/bin/env python3
"""把原始音效素材处理成游戏可直接用的 mono WAV。

做的事：
  1. 去头尾静音  2. 重采样到 22050Hz 单声道  3. 按事件指定的峰值做归一化
  4. 截断到目标时长并加淡入淡出（避免爆音）

用法：
  python tools/prepare_sfx.py --src <解压后的素材目录> --out art/sfx

素材是 CC0（IgnisForge Free SFX Sampler，OpenGameArt），
所以 art/sfx/*.wav 可以直接随仓库分发。
"""

import argparse
import os
import sys
import wave

import numpy as np
from scipy.signal import resample_poly

TARGET_SR = 22050

# 事件名 -> (素材文件, 目标峰值 dBFS, 最长时长秒)
# 峰值是相对音量：打击音压低，关键反馈音抬高。
EVENTS = {
    "ui_click": ("blip_01.wav", -12.0, 0.30),
    "ui_back": ("blip_05.wav", -14.0, 0.30),
    "place": ("plasma_01.wav", -9.0, 0.45),
    "upgrade": ("powerup_05.wav", -8.0, 0.80),
    "remove": ("blip_10.wav", -12.0, 0.35),
    "hit": ("hurt_01.wav", -20.0, 0.14),
    "die": ("hurt_15.wav", -14.0, 0.30),
    "leak": ("explosion_01.wav", -8.0, 0.55),
    "wave": ("blip_15.wav", -13.0, 0.40),
    "win": ("jingle_01.wav", -8.0, 1.60),
    "lose": ("stinger_01.wav", -7.0, 1.80),
    "card": ("coin_05.wav", -11.0, 0.60),
    "drawer": ("jump_05.wav", -14.0, 0.35),
    "boss": ("stinger_04.wav", -7.0, 1.20),
    "heal": ("spellzap_01.wav", -19.0, 0.25),
}


def read_wav(path):
    with wave.open(path, "rb") as w:
        n_ch = w.getnchannels()
        width = w.getsampwidth()
        sr = w.getframerate()
        raw = w.readframes(w.getnframes())
    if width == 1:
        data = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif width == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif width == 4:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise ValueError("unsupported sample width %d" % width)
    if n_ch > 1:
        data = data.reshape(-1, n_ch).mean(axis=1)
    return data, sr


def trim_silence(x, sr, threshold_db=-50.0, pad_ms=4.0):
    if x.size == 0:
        return x
    th = 10 ** (threshold_db / 20.0)
    idx = np.nonzero(np.abs(x) > th)[0]
    if idx.size == 0:
        return x[:0]
    pad = int(sr * pad_ms / 1000.0)
    a = max(0, int(idx[0]) - pad)
    b = min(x.size, int(idx[-1]) + pad + 1)
    return x[a:b]


def resample(x, sr, target=TARGET_SR):
    if sr == target or x.size == 0:
        return x
    g = np.gcd(int(sr), int(target))
    up, down = int(target // g), int(sr // g)
    return resample_poly(x, up, down).astype(np.float32)


def normalize_peak_db(x, peak_db):
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    if peak <= 1e-6:
        return x
    target = 10 ** (peak_db / 20.0)
    return (x * (target / peak)).astype(np.float32)


def fade(x, sr, in_ms=3.0, out_ms=8.0):
    if x.size == 0:
        return x
    n_in = min(int(sr * in_ms / 1000.0), x.size)
    n_out = min(int(sr * out_ms / 1000.0), x.size)
    if n_in > 0:
        x[:n_in] *= np.linspace(0.0, 1.0, n_in, dtype=np.float32)
    if n_out > 0:
        x[-n_out:] *= np.linspace(1.0, 0.0, n_out, dtype=np.float32)
    return x


def write_wav(path, x, sr=TARGET_SR):
    pcm = np.clip(x, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def describe(x, sr):
    """给不能试听的人一点判断依据：时长/峰值/RMS/频谱重心。"""
    if x.size == 0:
        return "empty"
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x.astype(np.float64) ** 2)))
    spec = np.abs(np.fft.rfft(x * np.hanning(x.size)))
    freqs = np.fft.rfftfreq(x.size, 1.0 / sr)
    centroid = float((spec * freqs).sum() / max(spec.sum(), 1e-9))
    return "dur=%.2fs peak=%.1fdB rms=%.1fdB centroid=%dHz" % (
        x.size / sr,
        20 * np.log10(max(peak, 1e-9)),
        20 * np.log10(max(rms, 1e-9)),
        int(centroid),
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="原始素材目录")
    ap.add_argument("--out", default="art/sfx", help="输出目录（相对项目根）")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    made, missing = [], []
    print("%-10s %-18s %s" % ("事件", "素材", "处理结果"))
    print("-" * 96)
    for name, (src_name, peak_db, max_dur) in EVENTS.items():
        src = os.path.join(args.src, src_name)
        if not os.path.isfile(src):
            missing.append(src_name)
            continue
        x, sr = read_wav(src)
        x = trim_silence(x, sr)
        x = resample(x, sr)
        limit = int(TARGET_SR * max_dur)
        if x.size > limit:
            x = x[:limit]
            x = fade(x, TARGET_SR, in_ms=1.0, out_ms=25.0)
        else:
            x = fade(x, TARGET_SR)
        x = normalize_peak_db(x, peak_db)
        dst = os.path.join(args.out, name + ".wav")
        write_wav(dst, x)
        made.append(dst)
        print("%-10s %-18s %-14s %s" % (name, src_name, describe(x, TARGET_SR),
                                        "%.0fKB" % (os.path.getsize(dst) / 1024)))

    print("-" * 96)
    print("生成 %d 个，跳过 %d 个%s" % (
        len(made), len(missing),
        ("（缺素材：" + ", ".join(missing) + "）") if missing else ""))
    return 0 if made else 1


if __name__ == "__main__":
    sys.exit(main())
