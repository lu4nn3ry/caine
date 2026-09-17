#!/usr/bin/env python3
"""Transcreve a melodia (monofônica) de um áudio para notas.

Uso:
    python midi_transcribe.py <audio> <saida.notes> [--fmin 65] [--fmax 2093]

Saída (.notes) em texto simples, fácil de ler no Lisp:
    bpm <valor>
    duration <segundos>
    onset<TAB>offset<TAB>pitch<TAB>velocity
"""
import argparse
import numpy as np
import librosa


def main():
    ap = argparse.ArgumentParser(description="Transcreve melodia para notas.")
    ap.add_argument("audio")
    ap.add_argument("out")
    ap.add_argument("--fmin", type=float, default=65.0)
    ap.add_argument("--fmax", type=float, default=2093.0)
    ap.add_argument("--sr", type=int, default=22050)
    ap.add_argument("--min-dur", type=float, default=0.08)
    ap.add_argument("--max-gap", type=float, default=0.06)
    args = ap.parse_args()

    y, sr = librosa.load(args.audio, sr=args.sr, mono=True)
    if y.size == 0:
        raise SystemExit("áudio vazio")
    duration = float(len(y) / sr)

    tempo = 120.0
    try:
        t, _ = librosa.beat.beat_track(y=y, sr=sr)
        t = np.atleast_1d(t).ravel()
        if t.size and float(t[0]) > 0:
            tempo = float(t[0])
    except Exception:
        pass

    hop = 256
    f0, voiced, _ = librosa.pyin(
        y, fmin=args.fmin, fmax=args.fmax, sr=sr,
        frame_length=2048, hop_length=hop,
    )
    times = librosa.times_like(f0, sr=sr, hop_length=hop)
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=hop)[0]
    hop_s = hop / sr

    frames = []
    for i in range(len(f0)):
        f = f0[i]
        if bool(voiced[i]) and f is not None and np.isfinite(f) and f > 0:
            midi = int(round(69 + 12 * np.log2(float(f) / 440.0)))
            r = float(rms[i]) if i < len(rms) else 0.0
            frames.append((float(times[i]), midi, r))

    notes = []
    if frames:
        start_t, pitch, _ = frames[0]
        end_t = start_t
        acc = [frames[0][2]]
        prev_t = start_t
        gap_limit = hop_s * 4 + args.max_gap
        for t, m, r in frames[1:]:
            if m == pitch and (t - prev_t) <= gap_limit:
                end_t, prev_t = t, t
                acc.append(r)
            else:
                notes.append((start_t, end_t + hop_s, pitch, float(np.mean(acc))))
                start_t, pitch, end_t, prev_t = t, m, t, t
                acc = [r]
        notes.append((start_t, end_t + hop_s, pitch, float(np.mean(acc))))

    notes = [n for n in notes if (n[1] - n[0]) >= args.min_dur]

    peak = max((n[3] for n in notes), default=1.0) or 1.0
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(f"bpm {tempo:.3f}\n")
        fh.write(f"duration {duration:.3f}\n")
        for on, off, pitch, r in notes:
            vel = int(max(1, min(127, round(20 + 107 * (r / peak)))))
            fh.write(f"{on:.4f}\t{off:.4f}\t{pitch}\t{vel}\n")

    print(f"notas={len(notes)} bpm={tempo:.1f} dur={duration:.1f}s -> {args.out}")


if __name__ == "__main__":
    main()
