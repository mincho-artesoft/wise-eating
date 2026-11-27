#!/usr/bin/env python3
"""Apply Variant B local tempo/pause processing (0 ElevenLabs credits) to a generated language library.

Variant B:
  1. Decode original raw TTS audio to 48 kHz mono float32 PCM.
  2. Slow speech by 8% (tempo = 1 / 1.08 = 0.925926) via ffmpeg rubberband,
     preserving pitch and vocal formants.
  3. Extend internal silences matched to internal punctuation using 25 ms
     raised-cosine fades at the minimum-RMS midpoint of each pause:
       - phrase / comma / dash: 2.0x original pause (capped at 0.80 s)
       - sentence break (. ? !): up to 1.20 s total
  4. Re-master via generate.master_audio (-16 LUFS, alimiter <= -1.5 dBTP,
     mono 24 kHz 96 kbps MP3), then run full mlx_whisper ASR verification.
"""
import argparse
import concurrent.futures
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
import generate as gen  # noqa: E402

SR = 48000


def load_pcm(path: pathlib.Path) -> np.ndarray:
    raw = subprocess.check_output(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ar", str(SR), "-ac", "1", "-f", "f32le", "-"]
    )
    return np.frombuffer(raw, dtype=np.float32).copy()


def save_wav(x: np.ndarray, path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "pcm_s24le", str(path)],
        input=x.astype(np.float32).tobytes(),
        check=True,
    )


def stretch_8pct(in_wav: pathlib.Path, out_wav: pathlib.Path) -> None:
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-i", str(in_wav),
            "-af", "rubberband=tempo=0.925926:pitch=1.0:formant=preserved:transients=crisp:window=standard",
            "-ar", str(SR), "-ac", "1", "-c:a", "pcm_s24le", str(out_wav),
        ],
        check=True,
    )


def parse_internal_punct(text: str) -> list[str]:
    body = re.sub(r"[.?!…]+$", "", text.strip()).strip()
    kinds = []
    for m in re.finditer(r"([.?!])|([,;:]|\s—\s|—)", body):
        kinds.append("sent" if m.group(1) else "phrase")
    return kinds


def find_internal_pauses(x: np.ndarray, frame_ms: int = 10, thresh_db: float = -42.0, min_pause_s: float = 0.15) -> list[dict]:
    hop = int(SR * frame_ms / 1000)
    n = len(x) // hop
    if n <= 0:
        return []
    frames = x[: n * hop].reshape(n, hop)
    rms = np.sqrt(np.mean(frames ** 2, axis=1) + 1e-12)
    peak = np.max(rms) + 1e-12
    db = 20.0 * np.log10(rms / peak)
    silent = db < thresh_db
    speech_idx = np.where(~silent)[0]
    if len(speech_idx) == 0:
        return []
    first_s, last_s = int(speech_idx[0]), int(speech_idx[-1])
    pauses = []
    i = first_s
    while i <= last_s:
        if silent[i]:
            j = i
            while j <= last_s and silent[j]:
                j += 1
            dur = (j - i) * frame_ms / 1000.0
            if dur >= min_pause_s:
                m_lo = i + max(1, (j - i) // 4)
                m_hi = j - max(1, (j - i) // 4)
                mid_frame = (i + j) // 2 if m_hi <= m_lo else m_lo + int(np.argmin(rms[m_lo:m_hi]))
                pauses.append({"dur": dur, "split_sample": mid_frame * hop + hop // 2})
            i = j
        else:
            i += 1
    return pauses


def extend_pauses(x: np.ndarray, text: str) -> tuple[np.ndarray, list[tuple[str, float, float]]]:
    puncts = parse_internal_punct(text)
    if not puncts:
        return x, []
    pauses = find_internal_pauses(x)
    if not pauses:
        return x, []

    if len(pauses) > len(puncts):
        chosen = sorted(sorted(pauses, key=lambda p: -p["dur"])[: len(puncts)], key=lambda p: p["split_sample"])
    else:
        chosen = pauses

    kinds = puncts if len(chosen) == len(puncts) else ["sent" if p["dur"] >= 0.41 else "phrase" for p in chosen]

    fade_n = int(0.025 * SR)
    t_fade = np.linspace(0.0, np.pi, fade_n, dtype=np.float32)
    fade_out = 0.5 * (1.0 + np.cos(t_fade))
    fade_in = 0.5 * (1.0 - np.cos(t_fade))

    pieces = []
    log = []
    prev = 0
    for p, kind in zip(chosen, kinds):
        sp = p["split_sample"]
        dur = p["dur"]
        target = 1.20 if kind == "sent" else min(0.80, dur * 2.0)
        add_s = max(0.0, target - dur)
        if add_s < 0.03:
            continue
        seg = x[prev:sp].copy()
        if len(seg) >= fade_n:
            seg[-fade_n:] *= fade_out
        pieces.append(seg)
        pieces.append(np.zeros(int(round(add_s * SR)), dtype=np.float32))
        prev = sp
        log.append((kind, round(dur, 2), round(dur + add_s, 2)))

    if not pieces:
        return x, []

    tail = x[prev:].copy()
    if len(tail) >= fade_n:
        tail[:fade_n] *= fade_in
    pieces.append(tail)

    out_parts = []
    for idx_p, part in enumerate(pieces):
        if idx_p >= 2 and idx_p % 2 == 0 and idx_p < len(pieces) - 1:
            part = part.copy()
            if len(part) >= fade_n:
                part[:fade_n] *= fade_in
        out_parts.append(part)
    return np.concatenate(out_parts), log


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", required=True)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--whisper-model", default="mlx-community/whisper-large-v3-turbo")
    args = ap.parse_args()

    out_dir = HERE / "out" / args.lang
    orig_backup = out_dir / "_original"
    raw_dir = out_dir / "_raw"
    audio_dir = out_dir / "audio"

    # 1. Preserve originals once (never overwrite an existing backup)
    if not orig_backup.exists():
        orig_backup.mkdir(parents=True, exist_ok=True)
        shutil.copytree(audio_dir, orig_backup / "audio")
        shutil.copy2(out_dir / "manifest.json", orig_backup / "manifest.json")
        shutil.copy2(out_dir / "report.json", orig_backup / "report.json")
        print(f"Backed up originals to {orig_backup}", flush=True)
    else:
        print(f"Backup already exists at {orig_backup} (untouched)", flush=True)

    vcfg = json.loads((HERE / "voices.elevenlabs.json").read_text())
    mcfg = vcfg["mastering"]
    narr = json.loads((HERE / "narration.en.json").read_text())
    orig_report = json.loads((orig_backup / "report.json").read_text())

    # Map original report metadata by (slug, index)
    orig_by_key = {(c["slug"], c["index"]): c for c in orig_report["cues"]}
    tasks = []
    for p in narr["practices"]:
        slug = p["slug"]
        for c in p["cues"]:
            key = (slug, c["n"])
            orig_row = orig_by_key[key]
            tasks.append((p, c, orig_row))
    assert len(tasks) == 601, f"Expected 601 cues, got {len(tasks)}"

    def process_cue(item):
        p, c, orig_row = item
        slug = p["slug"]
        n = c["n"]
        raw_mp3 = raw_dir / slug / f"cue-{n:02d}.mp3"
        out_mp3 = audio_dir / slug / f"cue-{n:02d}.mp3"
        with tempfile.TemporaryDirectory() as td:
            td_p = pathlib.Path(td)
            x_raw = load_pcm(raw_mp3)
            raw_wav = td_p / "raw.wav"
            slow_wav = td_p / "slow.wav"
            final_wav = td_p / "final.wav"
            save_wav(x_raw, raw_wav)
            stretch_8pct(raw_wav, slow_wav)
            x_slow = load_pcm(slow_wav)
            x_b, pause_log = extend_pauses(x_slow, orig_row["text"])
            save_wav(x_b, final_wav)
            info = gen.master_audio(final_wav, out_mp3, mcfg)
        en_s = float(c["englishSeconds"])
        dur = info["durationSec"]
        new_row = dict(orig_row)
        new_row.update({
            "origDurationSec": orig_row["durationSec"],
            "durationSec": round(dur, 3),
            "ratio": round(dur / en_s, 3),
            "duration_ok": 0.6 <= (dur / en_s) <= 1.8,
            "lufs": info["lufs"],
            "truePeakDb": info["truePeakDb"],
            "tempo_variant": "B_rubberband_8pct_plus_pauses",
            "pauses_extended": pause_log,
            "out_path": str(out_mp3),
        })
        return slug, p["voice"], c["hold"], n, dur, new_row

    print(f"Processing {len(tasks)} cues with {args.workers} workers (Variant B)...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
        results = list(ex.map(process_cue, tasks))

    manifest_practices = {}
    new_cues = []
    asr_inputs = []
    for slug, voice_role, hold, n, dur, new_row in results:
        pentry = manifest_practices.setdefault(slug, {"cues": [], "voice": voice_role})
        pentry["cues"].append({
            "audioAssetName": f"narration/audio/{slug}/cue-{n:02d}.mp3",
            "durationSec": dur,
            "holdSec": hold,
            "index": n,
        })
        new_cues.append(new_row)
        asr_inputs.append((pathlib.Path(new_row["out_path"]), new_row["text"]))

    print(f"Finished DSP + mastering for {len(new_cues)} cues. Running mlx_whisper ASR check...", flush=True)
    asr_map = gen.run_asr_check(asr_inputs, args.lang, args.whisper_model)
    asr_flags = []
    for row in new_cues:
        info = asr_map[pathlib.Path(row["out_path"])]
        row["asr_heard"] = info["heard"]
        row["asr_similarity"] = info["similarity"]
        row["asr_ok"] = info["ok"]
        if not info["ok"]:
            asr_flags.append(row)
            print(f"  [ASR_CHECK] {row['slug']}/cue-{row['index']:02d} sim={info['similarity']}: EXP={row['text']!r} GOT={info['heard']!r}", flush=True)

    manifest = {
        "channels": mcfg["channels"],
        "codec": mcfg["codec"],
        "bitrateKbps": mcfg["bitrate_kbps"],
        "format": "wise-eating-production-narration/v2",
        "practices": dict(sorted(manifest_practices.items())),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

    new_report = dict(orig_report)
    new_report["tempo_processing"] = {
        "variant": "B",
        "stretch_filter": "rubberband=tempo=0.925926:pitch=1.0:formant=preserved:transients=crisp:window=standard",
        "phrase_pause_rule": "2.0x up to 0.80s",
        "sentence_pause_rule": "up to 1.20s",
        "fade_ms": 25,
        "credits_spent": 0,
    }
    new_report["cues"] = new_cues
    (out_dir / "report.json").write_text(json.dumps(new_report, ensure_ascii=False, indent=2) + "\n")

    tot_orig = sum(r["origDurationSec"] for r in new_cues)
    tot_new = sum(r["durationSec"] for r in new_cues)
    tot_en = sum(r["englishSeconds"] for r in new_cues)
    lufs = [r["lufs"] for r in new_cues if r["lufs"] is not None]
    tps = [r["truePeakDb"] for r in new_cues if r["truePeakDb"] is not None]
    tp_over = [r for r in new_cues if (r["truePeakDb"] or -99) > -1.5]
    in_range = sum(1 for r in new_cues if r["duration_ok"])
    print("\n=== VARIANT B COMPLETE ===", flush=True)
    print(f"Cues: {len(new_cues)}/601 | Practices: {len(manifest_practices)}/60", flush=True)
    print(f"Duration: orig={tot_orig/60:.2f}m -> B={tot_new/60:.2f}m vs EN={tot_en/60:.2f}m ({tot_new/tot_en:.2f}x EN, {(tot_new/tot_en)/0.58:.2f}x BG@0.58)", flush=True)
    print(f"In 0.6x-1.8x range: {in_range}/601 ({in_range/601*100:.1f}%)", flush=True)
    print(f"LUFS: {min(lufs):.1f}..{max(lufs):.1f} (median {sorted(lufs)[len(lufs)//2]:.1f})", flush=True)
    print(f"TP: {min(tps):.1f}..{max(tps):.1f} dB | > -1.5 dB: {len(tp_over)}", flush=True)
    print(f"ASR avg={sum(r['asr_similarity'] for r in new_cues)/len(new_cues):.4f} | flags(<0.85)={len(asr_flags)}", flush=True)


if __name__ == "__main__":
    main()
