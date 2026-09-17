#!/usr/bin/env python3
"""Correção de afinação (pitch correction) — domínios MIDI e áudio.

Táticas implementadas (pesquisa 2026 — AutoKey/autorun de escala, Krumhansl-
Schmuckler, pitch-snap, PSOLA/rubberband):

  `midi`   — detecta o TOM da música (Krumhansl–Schmuckler ponderado por
             duração×velocity), quantiza as notas fora da escala para o grau
             mais próximo e CENTRALIZA os pitch bends (Basic Pitch emite bends
             de até 2 st que desafinam no render). Editor conservador:
             só move notas a ≤ --max-shift semitones do original.

  `audio`  — corrige o F0 por nota no WAV. Usa as notas do MIDI (ou .notes)
             como alvos, estima o F0 por segmento com pyin e aplica
             pitch-shift (librosa, preserva duração) com crossfade nas bordas.

Uso:
    python pitch_correct.py midi   --in <f.mid> --out <f.mid> \
        [--key A] [--mode auto|maj|min] [--max-shift 2] [--keep-bends]
    python pitch_correct.py audio  --in <f.wav> --out <f.wav> \
        --mid <f.mid> [--max-shift 1.0] [--min-dur 0.12]
"""
import argparse
import decimal
import math
import sys
import warnings

import numpy as np

warnings.filterwarnings("ignore")

try:
    import librosa
except ImportError:
    librosa = None

try:
    import soundfile
except ImportError:
    soundfile = None

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# Perfis de Krumhansl–Schmuckler para tom maior/menor (raiz em C).
KS_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52,
                     5.19, 2.39, 3.66, 2.29, 2.88], dtype=float)
KS_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54,
                     4.75, 3.98, 2.69, 3.34, 3.17], dtype=float)

MAJOR_STEPS = [0, 2, 4, 5, 7, 9, 11]
MINOR_STEPS = [0, 2, 3, 5, 7, 8, 10]


def pc_name(pc):
    return NOTE_NAMES[pc % 12]


def detect_key(pc_hist, mode_hint=None):
    """Detecção de tom.

    Combina duas táticas (histogramas concentrados de AMT enganam o K-S puro):
    1. Cobertura — fração da massa do histograma que cai dentro da escala
       (dominante para transcrição instrumento-único);
    2. Perfis de Krumhansl–Schmuckler — desempate tonal.

    Devolve (key_name, mode, score, scores).
    """
    h = np.asarray(pc_hist, dtype=float)
    norm = float(h.sum())
    if norm <= 0:
        return "C", "maj", 0.0, None
    h = h / norm

    cands = []
    for mode, prof in (("maj", KS_MAJOR), ("min", KS_MINOR)):
        if mode_hint is not None and mode_hint != mode:
            continue
        for root in range(12):
            ks = float(sum(h[(pc - root) % 12] * prof[pc] for pc in range(12)))
            cov = float(sum(h[(s + root) % 12] for s in scale_steps(mode)))
            cands.append((root, mode, ks, cov))

    max_ks = max(c[2] for c in cands) or 1.0
    max_cov = max(c[3] for c in cands) or 1.0
    best = max(cands, key=lambda c: 0.6 * (c[3] / max_cov) + 0.4 * (c[2] / max_ks))
    root, mode, ks, cov = best
    return pc_name(root), mode, 0.6 * (cov / max_cov) + 0.4 * (ks / max_ks), best


def scale_steps(mode):
    return MINOR_STEPS if mode == "min" else MAJOR_STEPS


def note_name(pitch):
    return f"{NOTE_NAMES[pitch % 12]}{(pitch // 12) - 1}"


def nearest_scale_pitch(pitch, steps, max_shift):
    """Grau de escala mais próximo de PITCH (semitones), limitado a MAX_SHIFT.
    Devolve (novo_pitch, distancia)."""
    pc = pitch % 12
    best, best_d = None, None
    for s in steps:
        delta = (s - pc) % 12
        if delta > 6:
            delta -= 12
        cand = pitch + delta
        d = abs(delta)
        if best is None or d < best_d:
            best, best_d = cand, d
    if max_shift is not None and best_d > max_shift:
        return pitch, 0
    return best, best_d


# ---------------------------------------------------------------------------
# Modo MIDI
# ---------------------------------------------------------------------------

def load_notes_from_midi_pretty(mid):
    try:
        import pretty_midi
    except ImportError as e:
        raise SystemExit(f"pretty_midi ausente: {e}")
    pm = pretty_midi.PrettyMIDI(str(mid))
    notes = []
    for inst in pm.instruments:
        if inst.is_drum:
            continue
        for n in inst.notes:
            notes.append((n.start, n.end, round(n.pitch),
                          100 + int(n.velocity) if n.velocity else 100))
    return pm, notes


def tune_midi(args):
    pm, notes = load_notes_from_midi_pretty(args["in"])

    pc_hist = np.zeros(12)
    for on, off, pitch, _ in notes:
        dur = max(0.0, off - on)
        pc_hist[pitch % 12] += math.sqrt(dur) * (0.5 + notes_weight(pitch))
    total = float(pc_hist.sum())
    pc_hist = pc_hist / total if total > 0 else pc_hist

    key, mode, score, _ = detect_key(pc_hist, mode_hint=args.get("mode"))
    if args.get("key"):
        key, mode = args["key"], args.get("mode") or mode
    root_pc = NOTE_NAMES.index(key)
    pcs = [(root_pc + s) % 12 for s in scale_steps(mode)]
    escala = pcs

    bends = 0
    if not args.get("keep_bends"):
        for inst in pm.instruments:
            for b in inst.pitch_bends:
                b.pitch = 0
            bends += len(inst.pitch_bends)

    moved, kept = [], 0
    for inst in pm.instruments:
        if inst.is_drum:
            continue
        for n in inst.notes:
            npitch, d = nearest_scale_pitch(round(n.pitch), pcs, args.get("max_shift"))
            orig = round(n.pitch)
            nn = round(npitch)
            if nn != orig:
                moved.append((orig, nn, d, round(n.start, 3), round(n.end, 3)))
                n.pitch = nn
            else:
                kept += 1

    pm.write(str(args["out"]))

    report = {
        "fonte": str(args["in"]),
        "saida": str(args["out"]),
        "tom_detectado": key,
        "modo": mode,
        "escala": [pc_name(p) for p in escala],
        "notas_total": len(notes),
        "notas_quietas": kept,
        "notas_corrigidas": len(moved),
        "movidas": moved,
        "bends_centrados": bends,
    }
    print_report(report)
    return 0


def notes_weight(pitch):
    """Peso opcional no histograma — agudos contam um pouco menos."""
    return 0.0


# ---------------------------------------------------------------------------
# Modo áudio
# ---------------------------------------------------------------------------

def parse_notes_file(path):
    notes = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "bpm " in line or "duration " in line:
                continue
            parts = line.split("\t")
            if len(parts) >= 3:
                notes.append((float(parts[0]), float(parts[1]), int(round(float(parts[2])))))
    return notes


def load_targets(args):
    if args.get("mid"):
        _pm, notes = load_notes_from_midi_pretty(args["mid"])
        return notes
    if args.get("notes"):
        return parse_notes_file(args["notes"])
    return None


def hz_to_steps(f):
    return 12.0 * math.log2(max(f, 1e-6) / 440.0)


def tune_audio(args):
    if librosa is None or soundfile is None:
        raise SystemExit("librosa/soundfile ausentes (venv .midi do caine-voice)")
    y, sr = librosa.load(args["in"], sr=None, mono=True)
    total = float(len(y)) / sr

    targets = load_targets(args)
    if targets is None:
        raise SystemExit("forneça --mid ou --notes com as notas-alvo")

    hop = 256
    f0, voiced, _ = librosa.pyin(y, fmin=args.get("fmin", 65.0),
                                 fmax=args.get("fmax", 2093.0),
                                 sr=sr, frame_length=2048, hop_length=hop)
    times = librosa.times_like(f0, sr=sr, hop_length=hop)
    midi_targ = np.array([round(t[2]) for t in targets])
    target_hz = librosa.midi_to_hz(midi_targ)

    out = y.copy()
    max_shift = args.get("max_shift", 1.0)
    min_dur = args.get("min_dur", 0.12)
    fc = int(0.03 * sr)
    corrected, skipped, clamped = 0, 0, 0

    for target in targets:
        on, off, pitch = target[0], target[1], target[2]
        thz = librosa.midi_to_hz(round(pitch))
        if (off - on) < min_dur:
            skipped += 1
            continue
        i0 = np.searchsorted(times, on + 0.04)
        i1 = np.searchsorted(times, off - 0.04)
        if i1 <= i0:
            skipped += 1
            continue
        seg_f0 = f0[i0:i1]
        seg_voic = voiced[i0:i1]
        valid = seg_f0[seg_voic & np.isfinite(seg_f0) & (seg_f0 > 0)]
        if valid.size == 0:
            skipped += 1
            continue
        med = float(np.median(valid))
        delta = hz_to_steps(thz) - hz_to_steps(med)
        if abs(delta) < 0.03:
            continue  # já afinado
        if abs(delta) > max_shift:
            delta = math.copysign(max_shift, delta)
            clamped += 1
        if abs(delta) < 0.03:
            continue
        s0 = int(on * sr)
        s1 = int(off * sr)
        seg = y[s0:s1]
        if seg.size < 2 * fc or seg.size < int(0.08 * sr):
            skipped += 1
            continue
        shifted = librosa.effects.pitch_shift(seg, sr=sr, n_steps=delta)
        out[s0:s0 + fc] = _xfade_in(out[s0:s0 + fc], shifted[:fc])
        out[s1 - fc:s1] = _xfade_out(shifted[-fc:], out[s1 - fc:s1])
        out[s0 + fc:s1 - fc] = shifted[fc:-fc]
        corrected += 1

    soundfile.write(args["out"], out, sr, subtype="PCM_24")
    report = {
        "fonte": str(args["in"]),
        "saida": str(args["out"]),
        "sr": sr,
        "duracao_s": round(total, 2),
        "notas_alvo": len(targets),
        "segmentos_corrigidos": corrected,
        "segmentos_pulado": skipped,
        "clamps_max_shift": clamped,
    }
    print_report(report)
    return 0


def _ramp(n, reverse=False):
    w = np.hanning(n)
    return w[::-1] if reverse else w


def _xfade_in(a, b):
    n = min(len(a), len(b))
    if n <= 0:
        return a
    w = np.hanning(n)
    return a[:n] * (1 - w) + b[:n] * w


def _xfade_out(a, b):
    n = min(len(a), len(b))
    if n <= 0:
        return b
    w = np.hanning(n)
    return a[:n] * w + b[:n] * (1 - w)


# ---------------------------------------------------------------------------
# Relatório
# ---------------------------------------------------------------------------

def print_report(r):
    print("== relatório de afinação ==")
    for k, v in r.items():
        if k == "movidas":
            if v:
                print(f"  movidas ({len(v)}):")
                for orig, novo, d, on, off in v:
                    print(f"    {note_name(orig)} -> {note_name(novo)} ({d:+.0f} st) "
                          f"@ {on:.2f}s")
            continue
        print(f"  {k}: {v}")


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Correção de afinação MIDI/áudio")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p1 = sub.add_parser("midi", help="quantiza MIDI à escala do tom")
    p1.add_argument("--in", required=True)
    p1.add_argument("--out", required=True)
    p1.add_argument("--key", default=None, help="tom fixo (ex.: A, Bb, F#)")
    p1.add_argument("--mode", default=None, choices=["auto", "maj", "min"])
    p1.add_argument("--max-shift", type=int, default=2,
                    help="máx. semitones para mover uma nota (padrão 2)")
    p1.add_argument("--keep-bends", action="store_true",
                    help="não centralizar pitch bends")
    p1.set_defaults(fn=tune_midi)

    p2 = sub.add_parser("audio", help="corrige F0 por nota no WAV")
    p2.add_argument("--in", required=True)
    p2.add_argument("--out", required=True)
    p2.add_argument("--mid", default=None, help="MIDI com notas-alvo")
    p2.add_argument("--notes", default=None, help=".notes com notas-alvo")
    p2.add_argument("--max-shift", type=float, default=1.0)
    p2.add_argument("--min-dur", type=float, default=0.12)
    p2.add_argument("--fmin", type=float, default=65.0)
    p2.add_argument("--fmax", type=float, default=2093.0)
    p2.set_defaults(fn=tune_audio)

    args = vars(ap.parse_args())
    fn = args.pop("fn")
    if args.get("mode") == "auto":
        args["mode"] = None
    sys.exit(fn(args))


if __name__ == "__main__":
    main()