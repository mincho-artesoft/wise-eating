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
from pathlib import Path

SAN = re.compile(r'[/\\:*?"<>|]')          # verbatim from build_food_index.py
GENERATED_FRAME_KEY_OVERRIDES = {
    # The dravya and recipe share a display name but have reviewed distinct art.
    # Runtime is DB-id keyed, so the recipe gets a private physical-frame key.
    "recipe-panchamrita": "recipe-panchamrita",
}


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


def generated_frame_key(filename, authored_frame_key):
    return GENERATED_FRAME_KEY_OVERRIDES.get(filename, sanitize(authored_frame_key))


def prepare_catalogue_frames(a, Image, np):
    """Stage a simple id-keyed catalogue without food's legacy ZIP/reuse layers."""
    catalogue_path = Path(a.catalogue).expanduser().resolve()
    images_dir = Path(a.images).expanduser().resolve()
    if not catalogue_path.is_file():
        sys.exit(f"missing catalogue: {catalogue_path}")
    if not images_dir.is_dir():
        sys.exit(f"missing image directory: {images_dir}")

    rows = json.loads(catalogue_path.read_text(encoding="utf-8"))
    if not isinstance(rows, list) or not rows:
        sys.exit("catalogue must be a non-empty JSON array")
    try:
        ordered = sorted(rows, key=lambda row: int(row[a.id_field]))
        ids = [int(row[a.id_field]) for row in ordered]
        assets = [row[a.asset_field] for row in ordered]
    except (KeyError, TypeError, ValueError) as error:
        sys.exit(f"invalid catalogue id/asset field: {error}")
    if len(ids) != len(set(ids)):
        sys.exit(f"catalogue repeats {a.id_field}")
    if ids != list(range(ids[0], ids[-1] + 1)):
        sys.exit(
            f"catalogue ids are not contiguous: {ids[0]}...{ids[-1]} "
            f"contains {len(ids)} rows"
        )
    if any(not isinstance(asset, str) or not asset for asset in assets):
        sys.exit(f"catalogue has an empty/non-string {a.asset_field}")
    if len(assets) != len(set(assets)):
        sys.exit(f"catalogue repeats {a.asset_field}")

    supported = {".jpg", ".jpeg", ".png", ".webp"}
    by_stem = {}
    for source in sorted(images_dir.iterdir()):
        if not source.is_file() or source.suffix.lower() not in supported:
            continue
        if source.stem in by_stem:
            sys.exit(
                f"image filename collision for {source.stem!r}: "
                f"{by_stem[source.stem].name}, {source.name}"
            )
        by_stem[source.stem] = source

    expected = set(assets)
    missing = sorted(expected - set(by_stem))
    extra = sorted(set(by_stem) - expected)
    print(f"catalogue           : {len(rows)} rows, ids {ids[0]}...{ids[-1]}")
    print(f"catalogue images    : {len(expected) - len(missing)}/{len(expected)} present")
    print(f"missing             : {len(missing)}")
    for key in missing[:20]:
        print(f"  {key}")
    print(f"non-catalogue images: {len(extra)} (ignored)")
    for key in extra[:20]:
        print(f"  {key}")
    if missing and not a.allow_missing:
        sys.exit("REFUSING — every catalogue id must have its own source image")

    hash_groups = {}
    for asset in assets:
        source = by_stem.get(asset)
        if source is None:
            continue
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        hash_groups.setdefault(digest, []).append(asset)
    duplicates = [members for members in hash_groups.values() if len(members) > 1]
    print(f"duplicate hash pairs: {len(duplicates)} (retained as separate frames)")
    for members in duplicates:
        print("  " + " == ".join(members))

    if a.dry_run:
        print("DRY RUN — validated only; no pool files written")
        return

    pool = Path(a.pool).expanduser().resolve()
    existing = list(pool.glob("[0-9][0-9][0-9][0-9][0-9].jpg")) if pool.exists() else []
    existing += [pool / name for name in ("features.npy", "manifest.json") if (pool / name).exists()]
    if existing:
        sys.exit(
            "REFUSING TO OVERWRITE an existing frame pool:\n  "
            + "\n  ".join(str(path) for path in existing[:10])
        )
    pool.mkdir(parents=True, exist_ok=True)
    present_rows = [row for row in ordered if row[a.asset_field] in by_stem]
    feats = np.zeros((len(present_rows), a.feature_px * a.feature_px), dtype=np.float32)
    manifest = []
    print(f"\nstaging {len(present_rows)} frame(s) -> {pool}")
    for index, row in enumerate(present_rows):
        asset = row[a.asset_field]
        source = by_stem[asset]
        image = Image.open(source).convert("RGB")
        width, height = image.size
        if max(width, height) != a.size:
            scale = a.size / max(width, height)
            image = image.resize(
                (
                    max(2, int(width * scale)) // 2 * 2,
                    max(2, int(height * scale)) // 2 * 2,
                ),
                Image.LANCZOS,
            )
        output = pool / f"{index:05d}.jpg"
        image.save(output, quality=a.quality)
        feats[index] = (
            np.asarray(
                image.convert("L").resize((a.feature_px, a.feature_px), Image.LANCZOS),
                dtype=np.float32,
            ).ravel()
            / 255.0
        )
        manifest.append(
            {
                "idx": index,
                "dbId": int(row[a.id_field]),
                "frameKey": asset,
                "source": source.name,
                "origin": "catalogue",
            }
        )
        if (index + 1) % 100 == 0:
            print(f"  {index + 1}/{len(present_rows)}")

    np.save(pool / "features.npy", feats)
    (pool / "manifest.json").write_text(
        json.dumps(
            {
                "count": len(manifest),
                "size": a.size,
                "featurePx": a.feature_px,
                "catalogue": str(catalogue_path),
                "idField": a.id_field,
                "assetField": a.asset_field,
                "frames": manifest,
            },
            indent=1,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    total = sum((pool / f"{index:05d}.jpg").stat().st_size for index in range(len(manifest)))
    print(f"\nstaged {len(manifest)} frames, {total / 1e9:.2f} GB")
    print(f"next: order_and_encode.py --pool {pool}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo")
    ap.add_argument("--zip", help="extra_images.zip (read, never extracted)")
    ap.add_argument("--new", help="directory of newly generated images")
    ap.add_argument("--pool", required=True, help="scratch dir for staged frames — needs ~8 GB")
    ap.add_argument("--catalogue", help="simple JSON-array catalogue (generic id-keyed mode)")
    ap.add_argument("--images", help="image directory for --catalogue mode")
    ap.add_argument("--id-field", default="id")
    ap.add_argument("--asset-field", default="assetImageName")
    ap.add_argument("--dry-run", action="store_true")
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

    if a.catalogue:
        if not a.images:
            sys.exit("--catalogue requires --images")
        prepare_catalogue_frames(a, Image, np)
        return

    if not all((a.repo, a.zip, a.new)):
        sys.exit("food mode requires --repo, --zip and --new")
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

    extra = [k for k in zkey if k not in fmap]
    print(f"  zip images not in frame_map            : {len(extra)}")
    for k in extra[:10]:
        print(f"    {k}")

    # ---- generated images ---------------------------------------------------
    # On the first unified build these are all additions to the legacy ZIP.
    # On subsequent builds most are already keys in frame_map.json and are the
    # source material for those existing frames. Treating the ZIP as the only
    # source for an existing key makes an incremental rebuild reject every
    # generated frame before it can consider this directory.
    newfiles, newclaims = {}, {}
    for p in sorted(glob.glob(os.path.join(os.path.expanduser(a.new), "*"))):
        stem, ext = os.path.splitext(os.path.basename(p))
        if ext.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
            continue
        row = newrows.get(stem)
        if not row:
            print(f"  ! {stem} is on disk but not in jobs.json — skipped")
            continue
        key = generated_frame_key(stem, row["frameKey"])
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

    available = set(zkey) | set(newfiles)
    missing = [k for k in fmap if k not in available]
    print(f"  frame_map keys with no source image     : {len(missing)}")
    for k in missing[:10]:
        print(f"    {k}")
    if missing and not a.allow_missing:
        sys.exit("\nREFUSING — a missing frame does not leave a gap, it shifts every later "
                 "frame by one and every food after it shows the wrong picture. "
                 "Resolve, or pass --allow-missing for a diagnostic run.")

    additions = sorted(set(newfiles) - set(fmap))
    print(f"  generated keys already in frame_map     : {len(set(newfiles) & set(fmap))}")
    print(f"  generated keys to append                : {len(additions)}")

    # ---- one decode per image: staged JPEG + ordering feature ---------------
    pool = os.path.expanduser(a.pool)
    os.makedirs(pool, exist_ok=True)
    order_keys = sorted(fmap, key=lambda k: fmap[k]) + additions
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
