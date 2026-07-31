#!/usr/bin/env python3
"""Stage every frame for the unified archive, without unpacking the 16 GB zip.

    python3 prepare_frames.py --repo ~/work/wise-eating \
        --zip "$HOME/Downloads/gemini-food-stylist/generated images/extra_images.zip" \
        --new ~/wise-eating-images \
        --pool /Volumes/scratch/frame-pool

WHY IT STREAMS INSTEAD OF EXTRACTING
    The zip is 16.1 GB and the disk it lives on has ~24 GB free. Unpacking it
    and then staging 14,467 resized frames would need roughly 24 GB at peak,
    which is the entire margin. Reading each member straight out of the zip,
    resizing it, and writing only the staged JPEG never materialises the PNGs at
    all: peak usage is the pool alone, about 7 GB.

    It is also faster. The PNGs are decoded exactly once, and the 64x64 feature
    used for ordering is taken from the same decode rather than from a second
    pass over 14,467 files.

WHAT IT REFUSES TO DO
    Silently ship a partial set. Archive 1 has 12,601 frames and the zip holds
    12,603 images; that discrepancy is real and this script reports it by name
    rather than trusting a count. If any frame_map key has no source image, it
    stops. A missing frame does not produce a gap in the video — it shifts every
    later frame by one, so every food after it shows the wrong picture.
"""
import argparse, glob, hashlib, io, json, os, re, sys, unicodedata, zipfile

SAN = re.compile(r'[/\\:*?"<>|]')          # verbatim from build_food_index.py


def zip_name(info):
    """The real filename of a zip member, on two counts.

    1. This archive was written WITHOUT the UTF-8 flag bit (0x800) on any of its
       12,603 entries, so zipfile decodes the names as cp437 per the spec. An
       em-dash comes back as 'GCo', 'jalapeno' loses its tilde into mojibake.
       Re-encoding to cp437 and decoding as UTF-8 recovers the original bytes.

    2. macOS stores filenames decomposed (NFD): 'Aji' + a combining acute, where
       frame_map.json holds the composed form (NFC). They are the same string to
       a human and different keys to a dict.

    Measured on the real archive: as-is leaves 29 frame_map keys unmatched,
    cp437 recovery alone leaves 22, and cp437 + NFC leaves 0.
    """
    n = info.filename
    if not (info.flag_bits & 0x800):
        try:
            n = n.encode("cp437").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
    return unicodedata.normalize("NFC", n)


def sanitize(name):
    return SAN.sub("_", unicodedata.normalize("NFC", name))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--zip", required=True, help="extra_images.zip (read, never extracted)")
    ap.add_argument("--new", required=True, help="directory of newly generated images")
    ap.add_argument("--pool", required=True, help="scratch dir for staged frames — needs ~8 GB")
    ap.add_argument("--size", type=int, default=1024, help="staged frame long edge")
    ap.add_argument("--quality", type=int, default=95)
    ap.add_argument("--feature-px", type=int, default=64)
    ap.add_argument("--prefer", choices=("dravya", "recipe"),
                    help="which kind wins when two new images claim one frame key")
    ap.add_argument("--allow-missing", action="store_true",
                    help="stage anyway and list the gaps. Do not use for a shipping build.")
    a = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        sys.exit("pip install pillow --break-system-packages")
    try:
        import numpy as np
    except ImportError:
        sys.exit("pip install numpy --break-system-packages")

    repo = os.path.expanduser(a.repo)
    fmap = json.load(open(f"{repo}/Ayura/Food/frame_map.json"))
    print(f"archive 1 frame_map : {len(fmap)} keys")

    jobs = json.load(open(f"{repo}/ayurveda-data/imagery/jobs.json"))
    newrows = {j["output"]["filename"]: j["_row"] for j in jobs["jobs"]}
    print(f"jobs.json           : {len(newrows)} generated rows")

    # ---- index the zip by frame key, without reading any content ------------
    zf = zipfile.ZipFile(os.path.expanduser(a.zip))
    zkey = {}
    skipped_apple = 0
    for info in zf.infolist():
        if info.is_dir():
            continue
        base = os.path.basename(zip_name(info))
        if base.startswith("._"):        # AppleDouble resource forks, 2 of them
            skipped_apple += 1
            continue
        zkey.setdefault(sanitize(os.path.splitext(base)[0]), []).append(info)
    if skipped_apple:
        print(f"  skipped {skipped_apple} AppleDouble '._' entr(y/ies)")
    dupes = {k: [i.filename for i in v] for k, v in zkey.items() if len(v) > 1}
    print(f"zip                 : {sum(len(v) for v in zkey.values())} images, {len(zkey)} distinct keys")
    if dupes:
        print(f"  {len(dupes)} key(s) claimed by more than one zip entry:")
        for k, v in list(dupes.items())[:5]:
            print(f"    {k} <- {v}")

    missing = [k for k in fmap if k not in zkey]
    extra = [k for k in zkey if k not in fmap]
    print(f"  frame_map keys with no image in the zip : {len(missing)}")
    for k in missing[:10]:
        print(f"    {k}")
    print(f"  zip images not in frame_map            : {len(extra)}")
    for k in extra[:10]:
        print(f"    {k}")
    if missing and not a.allow_missing:
        sys.exit("\nREFUSING — a missing frame does not leave a gap, it shifts every later "
                 "frame by one and every food after it shows the wrong picture. "
                 "Resolve, or pass --allow-missing for a diagnostic run.")

    # ---- the new images -----------------------------------------------------
    newfiles, newclaims = {}, {}
    for p in sorted(glob.glob(os.path.join(os.path.expanduser(a.new), "*"))):
        stem, ext = os.path.splitext(os.path.basename(p))
        if ext.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
            continue
        row = newrows.get(stem)
        if not row:
            print(f"  ! {stem} is on disk but not in jobs.json — skipped")
            continue
        key = sanitize(row["frameKey"])
        newclaims.setdefault(key, []).append((row["kind"], p))
    # Two new images can claim one frame key, and the app cannot tell them apart:
    # FoodItem.swift looks a frame up by the sanitised FOOD NAME, so one name has
    # exactly one frame however many rows carry that name. Panchamrita is both a
    # dravya and a recipe; both were generated, and only one can be addressed.
    collided = {k: v for k, v in newclaims.items() if len(v) > 1}
    if collided:
        print(f"\n{len(collided)} frame key(s) claimed by more than one new image:")
        for k, v in collided.items():
            print(f"  {k!r}")
            for kind, path in v:
                print(f"      {kind:<7} {os.path.basename(path)}")
        if not a.prefer:
            sys.exit("REFUSING — pass --prefer dravya or --prefer recipe to say which "
                     "image wins. The other is discarded, not lost: it stays on disk.")
    for k, v in newclaims.items():
        pick = next((p for kind, p in v if kind == a.prefer), v[0][1]) if len(v) > 1 else v[0][1]
        if len(v) > 1:
            print(f"  {k!r}: using the {a.prefer} image, discarding {len(v)-1} other(s)")
        newfiles[k] = pick
    print(f"new images matched to a job : {sum(len(v) for v in newclaims.values())} "
          f"-> {len(newfiles)} distinct frame key(s)")

    collide = sorted(set(newfiles) & set(fmap))
    if collide:
        print(f"\n{len(collide)} new frame key(s) ALREADY EXIST in archive 1: {collide[:5]}")
        sys.exit("REFUSING — a duplicate key would silently shadow the archive-1 frame.")

    # ---- one decode per image: staged JPEG + ordering feature ---------------
    pool = os.path.expanduser(a.pool)
    os.makedirs(pool, exist_ok=True)
    order_keys = sorted(fmap, key=lambda k: fmap[k]) + sorted(newfiles)
    print(f"\nstaging {len(order_keys)} frame(s) -> {pool}")

    feats = np.zeros((len(order_keys), a.feature_px * a.feature_px), dtype=np.float32)
    manifest = []
    for i, key in enumerate(order_keys):
        if key in newfiles:
            data = open(newfiles[key], "rb").read()
            src = os.path.basename(newfiles[key])
        else:
            info = zkey[key][0]
            data = zf.read(info)
            src = info.filename
        img = Image.open(io.BytesIO(data)).convert("RGB")
        w, h = img.size
        if max(w, h) != a.size:
            s = a.size / max(w, h)
            img = img.resize((max(2, int(w * s)) // 2 * 2, max(2, int(h * s)) // 2 * 2),
                             Image.LANCZOS)
        out = os.path.join(pool, f"{i:05d}.jpg")
        img.save(out, quality=a.quality)
        feats[i] = np.asarray(img.convert("L").resize((a.feature_px, a.feature_px), Image.LANCZOS),
                              dtype=np.float32).ravel() / 255.0
        manifest.append({"idx": i, "frameKey": key, "source": src,
                         "origin": "new" if key in newfiles else "archive1"})
        if (i + 1) % 500 == 0:
            print(f"   {i + 1}/{len(order_keys)}")

    np.save(os.path.join(pool, "features.npy"), feats)
    json.dump({"count": len(manifest), "size": a.size, "featurePx": a.feature_px,
               "frames": manifest},
              open(os.path.join(pool, "manifest.json"), "w"), indent=1, ensure_ascii=False)
    total = sum(os.path.getsize(os.path.join(pool, f"{i:05d}.jpg")) for i in range(len(manifest)))
    print(f"\nstaged {len(manifest)} frames, {total/1e9:.2f} GB")
    print(f"  archive 1 : {sum(1 for m in manifest if m['origin']=='archive1')}")
    print(f"  new       : {sum(1 for m in manifest if m['origin']=='new')}")
    print(f"\nnext: order_and_encode.py --pool {pool}")


if __name__ == "__main__":
    main()
