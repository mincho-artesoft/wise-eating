#!/usr/bin/env python3
"""Encodes the narration masters into the app's resources as HE-AAC 24 kbps.

  bundle.py              every language that has masters
  bundle.py fr es-MX     only these

Masters (MP3 96 kbps, mono, 24 kHz, mastered; not in git):
  tools/practice-narration/out/<language>/audio/<slug>/cue-NN.mp3 + manifest.json
  (English: out/en, moved there from Resources/PracticeNarration the first time)

Written (in git, copied into the app by tools/copy-practice-narration.sh):
  Resources/PracticeNarration/manifest.json, audio/<slug>/cue-NN.m4a           English
  Resources/PracticeNarration/<language>/manifest.json, audio/<slug>/cue-NN.m4a
  tools/practice-narration-inputs.xcfilelist, -outputs.xcfilelist

HE-AAC at 24 kbps is about a quarter of the MP3: 14 MB a language instead of 60.
"""
import concurrent.futures
import json
import pathlib
import subprocess
import sys
import tempfile

here = pathlib.Path(__file__).resolve().parent
repo = here.parent.parent
resources = repo / "Resources" / "PracticeNarration"
masters = here / "out"
BITRATE = 24000


def run(*command):
    result = subprocess.run([str(c) for c in command], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"{command[0]} failed on {command[-1]}:\n{result.stderr[-600:]}")
    return result.stdout


def encode(job):
    source, target = job
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        wav = pathlib.Path(scratch) / "cue.wav"
        run("ffmpeg", "-y", "-loglevel", "error", "-i", source, "-ac", "1", "-ar", "24000", wav)
        run("afconvert", "-f", "m4af", "-d", "aach", "-b", BITRATE, wav, target)


def bundle(language):
    source = masters / language
    manifest = json.loads((source / "manifest.json").read_text())
    root = resources if language == "en" else resources / language
    prefix = "narration/" if language == "en" else f"narration/{language}/"
    jobs, cues = [], []
    for slug, practice in sorted(manifest["practices"].items()):
        for cue in practice["cues"]:
            name = f"audio/{slug}/cue-{cue['index']:02d}"
            jobs.append((source / f"{name}.mp3", root / f"{name}.m4a"))
            cues.append((cue, prefix + f"{name}.m4a"))
    with concurrent.futures.ThreadPoolExecutor(6) as pool:
        list(pool.map(encode, jobs))
    # durationSec stays the master's: a container reports the encoder's padding too.
    for cue, asset in cues:
        cue["audioAssetName"] = asset
    durations = [cue["durationSec"] for cue, _ in cues]
    manifest.update(codec="aac-he", bitrateKbps=BITRATE // 1000, sampleRate=24000, channels=1)
    (root / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    for stale in (root / "audio").rglob("*.mp3"):
        stale.unlink()
    size = sum(target.stat().st_size for _, target in jobs)
    print(f"{language}: {len(jobs)} cues, {sum(durations) / 60:.1f} min, {size / 1e6:.1f} MB")


languages = sys.argv[1:] or sorted(p.name for p in masters.iterdir() if (p / "manifest.json").exists() and (p / "audio").is_dir())
for language in languages:
    bundle(language)

files = sorted(p.relative_to(resources).as_posix() for p in resources.rglob("*")
               if p.is_file() and (p.suffix == ".m4a" or p.name == "manifest.json"))
(repo / "tools" / "practice-narration-inputs.xcfilelist").write_text(
    "".join(f"$(SRCROOT)/Resources/PracticeNarration/{name}\n" for name in files))
(repo / "tools" / "practice-narration-outputs.xcfilelist").write_text(
    "".join(f"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/narration/{name}\n" for name in files))
print(f"{len(files)} files in the build lists")
