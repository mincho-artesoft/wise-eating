#!/usr/bin/env python3
"""Order accepted frames so visually similar images sit next to each other.

    python3 order_frames.py --accepted accepted/batch-000.json --out frame-order.json

Reads the accepted list, computes an ordering, writes {"order": [frameKey, ...]}
for build_archive2.py to consume with --order.

WHAT IT BUYS — read this before deciding to use it
---------------------------------------------------
Measured on an 800-frame 512px set with catalogue-like family structure:
similarity ordering improved mean adjacent distance by 6.7x and shrank the
encoded archive by 2.5%. Not 25%. Food photographs differ in every texture pixel
even when they are "the same dish", and high-frequency detail is what costs bits;
it does not predict from a neighbour no matter how well sorted.

At GOP 1 — which the 144px thumbnail variant uses deliberately, so a seek decodes
exactly one frame — ordering buys 0.2%, i.e. nothing. All-intra frames have no
neighbour to predict from. Do not order the thumbnail variant expecting a gain.

So this is a real but small optimisation. It is here because it is cheap,
deterministic, and free at build time; not because it is the lever that matters.

HOW IT COMPARES, AND WHY NOT AT 64x64
-------------------------------------
The obvious approach — downscale to 64x64 and compare pixels pairwise — works
and is far more expensive than it needs to be. 14,400 frames at 64x64 grey is a
236 MB feature matrix; a nearest-neighbour chain streams all of it once per
frame, so ~3.4 TB of memory traffic, and it ran over twelve minutes.

Projecting to 8 dimensions first produces an ordering within 1.3% of the same
quality in about five seconds. Measured at 14,400 frames, all scored in the full
4096-dim space so the cheap features get no credit for being cheap:

    features used to order      time     adjacency vs unordered
    16x16 (256d)               17.7s          0.34x
    PCA-8                       3.9s          0.34x
    PCA-32                      4.5s          0.34x
    k-means + chain on PCA-32   1.2s          0.34x
    Hilbert curve on PCA-3      2.2s          0.47x
    full 64x64 (4096d)        >12 min         0.34x

Everything except the Hilbert curve lands on the same answer. The pixels beyond
the first handful of principal components carry no ordering information.

DETERMINISM
-----------
Same accepted set in, same order out, or archive rebuilds stop being reproducible:
  - features come from a fixed 16x16 LANCZOS resize;
  - PCA is seeded and sklearn's sign convention is deterministic;
  - the chain starts at the lowest frameKey, not at whatever the filesystem
    listed first;
  - distance ties break on frameKey.
"""
import argparse, json, os, sys
import numpy as np

try:
    from PIL import Image
    from sklearn.decomposition import PCA
except ImportError:
    sys.exit("pip install pillow scikit-learn --break-system-packages")

THUMB = 16
DIMS = 8


def features(rows):
    F = np.empty((len(rows), THUMB * THUMB * 3), np.float32)
    for i, r in enumerate(rows):
        im = Image.open(r["path"]).convert("RGB").resize((THUMB, THUMB), Image.LANCZOS)
        F[i] = np.asarray(im, np.float32).ravel()
    return F


def chain(F, keys):
    """Greedy nearest-neighbour, ties broken by frameKey so it is reproducible."""
    n = len(F)
    sq = (F * F).sum(1)
    used = np.zeros(n, bool)
    rank = np.argsort(np.argsort(keys)).astype(np.float64)   # frameKey rank, for ties
    cur = int(np.argmin(rank))
    order = [cur]
    used[cur] = True
    for _ in range(n - 1):
        d = sq - 2.0 * (F @ F[cur])
        d[used] = np.inf
        # tiny rank term is below any real distance gap; only decides exact ties
        cur = int(np.argmin(d + rank * 1e-9))
        order.append(cur)
        used[cur] = True
    return order


def adjacency(F, order):
    A = F[order]
    return float(np.mean(np.linalg.norm(A[1:] - A[:-1], axis=1)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--accepted", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                       "accepted", "batch-000.json"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "frame-order.json"))
    ap.add_argument("--dims", type=int, default=DIMS)
    a = ap.parse_args()

    rows = json.load(open(a.accepted))["accepted"]
    rows.sort(key=lambda r: r["frameKey"])          # canonical starting state
    keys = [r["frameKey"] for r in rows]
    print(f"{len(rows)} accepted frames")
    if len(rows) < 3:
        print("too few to order; writing frameKey order unchanged")
        json.dump({"method": "frameKey", "order": keys}, open(a.out, "w"), indent=0)
        return

    F = features(rows)
    d = min(a.dims, len(rows) - 1, F.shape[1])
    P = PCA(n_components=d, random_state=0).fit_transform(F).astype(np.float32)
    order = chain(P, np.array(keys))

    before, after = adjacency(F, list(range(len(rows)))), adjacency(F, order)
    print(f"adjacency  {before:.0f} -> {after:.0f}  ({after/before:.2f}x)")
    # No predicted saving is printed here on purpose. Adjacency and file size are
    # only loosely coupled: the one case measured end to end went 0.15x on
    # adjacency and 0.975x on bytes. Any formula mapping one to the other would be
    # invented. Encode both orders and compare the two numbers.
    print("build both orders and compare sizes; adjacency does not predict bytes")

    json.dump({"method": f"pca{d}-nnchain", "frames": len(rows),
               "adjacencyBefore": before, "adjacencyAfter": after,
               "order": [keys[i] for i in order]},
              open(a.out, "w"), indent=0, ensure_ascii=False)
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
