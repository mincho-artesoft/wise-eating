#!/usr/bin/env python3
"""Generate, master, and verify translated practice narration cues with ElevenLabs.

Usage examples:
  # Pilot for bg on eleven_multilingual_v2 (6 practices)
  python3 tools/practice-narration/generate.py \\
    --lang bg --model eleven_multilingual_v2 \\
    --out-dir tools/practice-narration/out/bg/eleven_multilingual_v2 \\
    --practices rain-on-the-roof the-fading-bell hissing-breath the-candle the-open-window the-empty-room \\
    --asr

  # Full language library
  python3 tools/practice-narration/generate.py --lang bg --model eleven_multilingual_v2 --asr
"""
import argparse
import concurrent.futures
import difflib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata

import httpx

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
API_BASE = "https://api.elevenlabs.io/v1"


def require_api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not key:
        sys.exit("ERROR: ELEVENLABS_API_KEY environment variable is not set.")
    return key


def get_subscription(client: httpx.Client, headers: dict) -> dict:
    r = client.get(f"{API_BASE}/user/subscription", headers=headers)
    r.raise_for_status()
    d = r.json()
    return {
        "tier": d.get("tier"),
        "character_count": d.get("character_count"),
        "character_limit": d.get("character_limit"),
        "characters_remaining": (d.get("character_limit") or 0) - (d.get("character_count") or 0),
    }


class QuotaExceededError(RuntimeError):
    """Raised when ElevenLabs rejects a request due to insufficient character quota."""


def resolve_voice(voices_cfg: dict, role: str, lang: str, voice_slot: str | None = None) -> dict:
    if voice_slot:
        return dict(voices_cfg["language_pilots"][lang][voice_slot])
    lang_voices = voices_cfg.get("language_voices") or {}
    if lang in lang_voices:
        return dict(lang_voices[lang])
    base = dict(voices_cfg["voices"][role])
    override = (voices_cfg.get("language_overrides") or {}).get(lang, {}).get(role)
    if override:
        base.update(override)
    return base


def build_tts_payload(
    text: str,
    model_id: str,
    model_caps: dict,
    voice_cfg: dict,
    lang: str,
    prev_text: str | None,
    next_text: str | None,
    seed: int,
) -> dict:
    settings = dict(voice_cfg["settings"][model_id])
    payload = {
        "text": text,
        "model_id": model_id,
        "voice_settings": settings,
    }
    if model_caps.get("supports_seed", True):
        payload["seed"] = seed
    if model_caps.get("supports_language_code", False):
        payload["language_code"] = lang.split("-")[0]
    if model_caps.get("supports_previous_next_text", True):
        if prev_text:
            payload["previous_text"] = prev_text
        if next_text:
            payload["next_text"] = next_text
    return payload


def synthesize_cue(
    client: httpx.Client,
    headers: dict,
    voice_id: str,
    output_format: str,
    payload: dict,
    raw_path: pathlib.Path,
) -> dict:
    url = f"{API_BASE}/text-to-speech/{voice_id}"
    params = {"output_format": output_format}
    for attempt in range(1, 5):
        r = client.post(url, headers={**headers, "Accept": "audio/mpeg"}, params=params, json=payload)
        if r.status_code == 200:
            raw_path.parent.mkdir(parents=True, exist_ok=True)
            raw_path.write_bytes(r.content)
            char_cost = r.headers.get("character-cost") or r.headers.get("x-character-count")
            return {
                "request_id": r.headers.get("request-id"),
                "character_cost": int(char_cost) if char_cost and char_cost.isdigit() else len(payload["text"]),
                "bytes": len(r.content),
            }
        if r.status_code in (401, 402, 422, 429) and (
            "quota_exceeded" in r.text or "exceeds your quota" in r.text.lower() or "insufficient" in r.text.lower()
        ):
            raise QuotaExceededError(f"Quota exceeded HTTP {r.status_code}: {r.text[:300]}")
        if r.status_code in (429, 500, 502, 503, 504) and attempt < 4:
            wait = 2.0 * attempt
            print(f"    retryable HTTP {r.status_code}, waiting {wait}s...", file=sys.stderr)
            time.sleep(wait)
            continue
        raise RuntimeError(f"TTS failed HTTP {r.status_code}: {r.text[:400]}")
    raise RuntimeError("TTS failed after retries")


def ffprobe_duration(path: pathlib.Path) -> float:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)],
        text=True,
    ).strip()
    return float(out)


def measure_ebur128(path: pathlib.Path) -> tuple[float | None, float | None]:
    p = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"],
        capture_output=True,
        text=True,
        check=True,
    )
    i_val = None
    tp_val = None
    in_summary = False
    for line in p.stderr.splitlines():
        if "Summary:" in line:
            in_summary = True
        if not in_summary:
            continue
        m_i = re.search(r"I:\s+(-?\d+(?:\.\d+)?)\s+LUFS", line)
        if m_i:
            i_val = float(m_i.group(1))
        m_tp = re.search(r"Peak:\s+(-?\d+(?:\.\d+)?)\s+dBFS", line)
        if m_tp:
            tp_val = float(m_tp.group(1))
    return i_val, tp_val


def master_audio(raw_path: pathlib.Path, out_path: pathlib.Path, mcfg: dict) -> dict:
    """Trim leading/trailing silence to natural edge, two-pass loudnorm to -16 LUFS / -1.5 dBTP,
    output mono 24 kHz 96 kbps MP3, then measure actual duration, LUFS, and true peak."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    target_i = mcfg["target_lufs"]
    target_tp = mcfg["target_true_peak_db"]
    target_lra = mcfg["target_lra"]
    thresh = mcfg["trim_threshold_db"]
    pad_start_s = mcfg["pad_start_ms"] / 1000.0
    pad_end_s = mcfg["pad_end_ms"] / 1000.0
    sr = mcfg["sample_rate_hz"]
    br = f"{mcfg['bitrate_kbps']}k"

    with tempfile.TemporaryDirectory() as td:
        trimmed = pathlib.Path(td) / "trimmed.wav"
        # Trim leading and trailing silence, keep natural small pads at start and end
        trim_filter = (
            f"aformat=sample_rates=48000:channel_layouts=mono,"
            f"silenceremove=start_periods=1:start_duration=0.02:start_threshold={thresh}dB,"
            f"areverse,"
            f"silenceremove=start_periods=1:start_duration=0.02:start_threshold={thresh}dB,"
            f"areverse,"
            f"adelay={int(pad_start_s*1000)}:all=1,"
            f"apad=pad_dur={pad_end_s:.3f}"
        )
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-y", "-i", str(raw_path), "-af", trim_filter, "-c:a", "pcm_s16le", str(trimmed)],
            capture_output=True,
            text=True,
            check=True,
        )
        # Fallback if aggressive trim emptied an ultra-quiet clip
        if ffprobe_duration(trimmed) < 0.3:
            subprocess.run(
                ["ffmpeg", "-hide_banner", "-y", "-i", str(raw_path), "-ar", "48000", "-ac", "1", "-c:a", "pcm_s16le", str(trimmed)],
                capture_output=True,
                text=True,
                check=True,
            )

        # Pass 1: measure loudnorm stats
        p1 = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-i", str(trimmed),
                "-af", f"loudnorm=I={target_i}:TP={target_tp}:LRA={target_lra}:print_format=json",
                "-f", "null", "-",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", p1.stderr, re.S)
        if not m:
            raise RuntimeError(f"Could not parse loudnorm JSON for {raw_path}:\n{p1.stderr[-500:]}")
        stats = json.loads(m.group(0))

        # Pass 2: apply linear loudnorm + resample + true-peak ceiling before MP3 encode
        ln2 = (
            f"loudnorm=I={target_i}:TP={target_tp}:LRA={target_lra}:"
            f"measured_I={stats['input_i']}:measured_LRA={stats['input_lra']}:"
            f"measured_TP={stats['input_tp']}:measured_thresh={stats['input_thresh']}:"
            f"offset={stats['target_offset']}:linear=true:print_format=summary,"
            f"aresample={sr},"
            f"alimiter=limit=0.79:attack=0.5:release=50:level=false:asc=false"
        )
        subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-y", "-i", str(trimmed),
                "-af", ln2,
                "-ar", str(sr), "-ac", str(mcfg["channels"]),
                "-c:a", "libmp3lame", "-b:a", br,
                str(out_path),
            ],
            capture_output=True,
            text=True,
            check=True,
        )

    dur = ffprobe_duration(out_path)
    lufs, tp = measure_ebur128(out_path)
    return {"durationSec": dur, "lufs": lufs, "truePeakDb": tp}


def norm_text(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).lower()
    s = re.sub(r"[^\w\s]", " ", s, flags=re.U)
    return " ".join(s.split())


def run_asr_check(audio_paths: list[tuple[pathlib.Path, str]], lang: str, whisper_model: str) -> dict[pathlib.Path, dict]:
    import mlx_whisper
    lang_code = lang.split("-")[0]
    results = {}
    for path, expected in audio_paths:
        res = mlx_whisper.transcribe(
            str(path),
            path_or_hf_repo=whisper_model,
            language=lang_code,
            condition_on_previous_text=False,
        )
        heard = (res.get("text") or "").strip()
        ne, nh = norm_text(expected), norm_text(heard)
        ratio = difflib.SequenceMatcher(None, ne, nh).ratio()
        results[path] = {
            "heard": heard,
            "similarity": round(ratio, 3),
            "ok": ratio >= 0.85,
        }
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", required=True, help="Target language code, e.g. bg")
    ap.add_argument("--model", required=True, help="ElevenLabs model_id, e.g. eleven_multilingual_v2 or eleven_v4")
    ap.add_argument("--out-dir", help="Output directory (default: tools/practice-narration/out/<lang>)")
    ap.add_argument("--practices", nargs="*", help="Optional subset of practice slugs")
    ap.add_argument("--resume", action="store_true", help="Skip API call if raw file already exists")
    ap.add_argument("--asr", action="store_true", help="Run mlx_whisper back-transcription check")
    ap.add_argument("--whisper-model", default="mlx-community/whisper-large-v3-turbo", help="mlx_whisper model repo")
    ap.add_argument("--seed-overrides", help="Optional JSON file mapping 'slug/NN' -> seed int for retakes")
    ap.add_argument("--voice-slot", help="Optional single-voice slot under language_pilots[lang][slot], e.g. A or B")
    ap.add_argument("--workers", type=int, default=1, help="Concurrent TTS+mastering workers per practice (default: 1)")
    args = ap.parse_args()

    api_key = require_api_key()
    headers = {"xi-api-key": api_key}

    narr = json.loads((HERE / "narration.en.json").read_text())
    voices_cfg = json.loads((HERE / "voices.elevenlabs.json").read_text())
    trans_path = REPO / "tools" / "practice-content" / f"{args.lang}.json"
    if not trans_path.exists():
        sys.exit(f"ERROR: Missing reviewed translation file {trans_path}")
    trans = json.loads(trans_path.read_text())

    if args.model not in voices_cfg["models"]:
        sys.exit(f"ERROR: Unknown model {args.model} in voices.elevenlabs.json")
    model_caps = voices_cfg["models"][args.model]
    mcfg = voices_cfg["mastering"]

    out_dir = pathlib.Path(args.out_dir) if args.out_dir else (HERE / "out" / args.lang)
    raw_dir = out_dir / "_raw"
    audio_dir = out_dir / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)

    seed_overrides = json.loads(pathlib.Path(args.seed_overrides).read_text()) if args.seed_overrides else {}

    selected = narr["practices"]
    if args.practices:
        want = set(args.practices)
        selected = [p for p in selected if p["slug"] in want]
        found_slugs = {p["slug"] for p in selected}
        missing = want - found_slugs
        if missing:
            sys.exit(f"ERROR: Unknown practice slugs: {sorted(missing)}")

    # Pre-check every cue translation exists
    planned_chars = 0
    for p in selected:
        for c in p["cues"]:
            if c["text"] not in trans:
                sys.exit(f"ERROR: Missing translation for {p['slug']} cue {c['n']}: {c['text']!r}")
            planned_chars += len(trans[c["text"]])

    with httpx.Client(timeout=60) as client:
        sub_before = get_subscription(client, headers)
        print(f"Before run ({args.model}): remaining={sub_before['characters_remaining']} (used={sub_before['character_count']}/{sub_before['character_limit']}), planned_chars={planned_chars}")
        if not args.resume and planned_chars > sub_before["characters_remaining"]:
            sys.exit(f"ERROR: Planned chars ({planned_chars}) exceed remaining ({sub_before['characters_remaining']}). Aborting.")

        manifest_practices = {}
        report_cues = []
        asr_inputs = []
        total_billed_header = 0
        generated_count = 0
        stopped_on_quota = False
        stopped_at = None

        for p in selected:
            if stopped_on_quota:
                break
            slug = p["slug"]
            role = p["voice"]
            vcfg = resolve_voice(voices_cfg, role, args.lang, args.voice_slot)
            cues_tr = [trans[c["text"]] for c in p["cues"]]
            manifest_cues = []

            print(f"\n[{args.model}] {slug} ({role} -> {vcfg['library_name']}, {len(p['cues'])} cues)", flush=True)
            practice_incomplete = False
            quota_event = threading.Event()

            def process_one(idx_cue):
                idx, cue = idx_cue
                n = cue["n"]
                text_tr = cues_tr[idx]
                prev_text = cues_tr[idx - 1] if idx > 0 else None
                next_text = cues_tr[idx + 1] if idx + 1 < len(cues_tr) else None
                key_id = f"{slug}/{n:02d}"
                seed = int(seed_overrides.get(key_id, vcfg["seed"]))
                raw_path = raw_dir / slug / f"cue-{n:02d}.mp3"
                out_path = audio_dir / slug / f"cue-{n:02d}.mp3"

                if args.resume and raw_path.exists() and raw_path.stat().st_size > 1000:
                    synth_info = {"request_id": "cached", "character_cost": 0, "bytes": raw_path.stat().st_size, "generated": False}
                else:
                    if quota_event.is_set():
                        return (idx, None, f"{slug}/cue-{n:02d}")
                    payload = build_tts_payload(text_tr, args.model, model_caps, vcfg, args.lang, prev_text, next_text, seed)
                    try:
                        synth_info = synthesize_cue(client, headers, vcfg["voice_id"], voices_cfg["output_format"], payload, raw_path)
                        synth_info["generated"] = True
                    except QuotaExceededError as qe:
                        quota_event.set()
                        print(f"  [QUOTA_STOP] {slug}/cue-{n:02d}: {qe}", flush=True)
                        return (idx, None, f"{slug}/cue-{n:02d}")

                master_info = master_audio(raw_path, out_path, mcfg)
                return (idx, (cue, text_tr, seed, synth_info, master_info, out_path), None)

            if args.workers > 1:
                with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
                    results_list = list(ex.map(process_one, enumerate(p["cues"])))
            else:
                results_list = [process_one(x) for x in enumerate(p["cues"])]

            for idx, res_tuple, stopped_key in results_list:
                if res_tuple is None:
                    stopped_on_quota = True
                    if stopped_at is None:
                        stopped_at = stopped_key
                    practice_incomplete = True
                    continue
                cue, text_tr, seed, synth_info, master_info, out_path = res_tuple
                n = cue["n"]
                if synth_info["generated"]:
                    total_billed_header += synth_info["character_cost"]
                    generated_count += 1
                en_sec = float(cue["englishSeconds"])
                dur = master_info["durationSec"]
                ratio = dur / en_sec if en_sec > 0 else 0.0
                flag = "" if (0.6 <= ratio <= 1.8) else " [LEN_OUTLIER]"
                print(
                    f"  cue-{n:02d}: loc={dur:5.2f}s en={en_sec:5.1f}s ({ratio:4.2f}x) "
                    f"I={master_info['lufs']} LUFS TP={master_info['truePeakDb']} dB{flag}",
                    flush=True,
                )
                manifest_cues.append({
                    "audioAssetName": f"narration/audio/{slug}/cue-{n:02d}.mp3",
                    "durationSec": dur,
                    "holdSec": cue["hold"],
                    "index": n,
                })
                report_cues.append({
                    "slug": slug,
                    "voice": role,
                    "voice_id": vcfg["voice_id"],
                    "index": n,
                    "seed": seed,
                    "text": text_tr,
                    "chars": len(text_tr),
                    "billed_chars": synth_info["character_cost"],
                    "request_id": synth_info["request_id"],
                    "englishSeconds": en_sec,
                    "durationSec": round(dur, 3),
                    "ratio": round(ratio, 3),
                    "duration_ok": 0.6 <= ratio <= 1.8,
                    "lufs": master_info["lufs"],
                    "truePeakDb": master_info["truePeakDb"],
                    "out_path": str(out_path),
                })
                asr_inputs.append((out_path, text_tr))

            if manifest_cues and not practice_incomplete:
                manifest_practices[slug] = {
                    "cues": manifest_cues,
                    "voice": role,
                }
            elif manifest_cues and practice_incomplete:
                manifest_practices[slug] = {
                    "cues": manifest_cues,
                    "voice": role,
                    "incomplete": True,
                }

        sub_after = get_subscription(client, headers)

    if args.asr:
        print(f"\nRunning mlx_whisper ASR check ({args.whisper_model}) on {len(asr_inputs)} cues...")
        asr_map = run_asr_check(asr_inputs, args.lang, args.whisper_model)
        for row in report_cues:
            info = asr_map[pathlib.Path(row["out_path"])]
            row["asr_heard"] = info["heard"]
            row["asr_similarity"] = info["similarity"]
            row["asr_ok"] = info["ok"]
            if not info["ok"]:
                print(f"  [ASR_CHECK] {row['slug']}/cue-{row['index']:02d} sim={info['similarity']}:")
                print(f"    EXP: {row['text']}")
                print(f"    GOT: {info['heard']}")

    manifest = {
        "channels": mcfg["channels"],
        "codec": mcfg["codec"],
        "bitrateKbps": mcfg["bitrate_kbps"],
        "format": "wise-eating-production-narration/v2",
        "practices": dict(sorted(manifest_practices.items())),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

    actual_delta = sub_after["character_count"] - sub_before["character_count"]
    report = {
        "lang": args.lang,
        "model_id": args.model,
        "practices_count": len(selected),
        "cues_count": len(report_cues),
        "generated_cues": generated_count,
        "planned_chars": planned_chars,
        "billed_chars_header_sum": total_billed_header,
        "subscription_before": sub_before,
        "subscription_after": sub_after,
        "actual_chars_spent": actual_delta,
        "stopped_on_quota": stopped_on_quota,
        "stopped_at": stopped_at,
        "cues": report_cues,
    }
    (out_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"\nDONE ({args.model}): spent={actual_delta} chars, remaining={sub_after['characters_remaining']}")


if __name__ == "__main__":
    main()
