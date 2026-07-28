# Pre-REPO-1 orphaned commits

Four commits referenced by `TASK-D6-VERIFY.md` and `REPORT-D6-VERIFY.md` that
were **never pushed to origin**. They existed only in one local clone's reflog,
unreachable from any branch, and would have been destroyed by the
`git gc --prune=now` that REPO-1 gate R4 requires.

| original SHA | subject | files | insertions |
|---|---|---:|---:|
| `e9a3a95` | D6 design: schema+seeder architecture + Codex dispatch packet | 3 | 292 |
| `e8d1b3e` | D6: Ayurveda schema + seeder (models, seed bundle, SeedManager hook) | 8 | 1,481 |
| `3ba69eb` | Run 6 fix: ObserversHub type-check budget, mechanical split only | 1 | 49 |
| `3801eee` | dravyas | 26 | 52,793 |

## No content was lost

Every file touched by all four commits is present in the current HEAD — verified
file by file, zero absent. A rebase carried the work forward and orphaned the
original commit objects. What was lost is the four commit SHAs, not the work.

This matters for how the doc references should be read: those SHAs were **already
unresolvable from any clone of origin before REPO-1 ran**. The history rewrite did
not break them. It surfaced a pre-existing documentation defect.

## Why patches rather than a bundle

A `git bundle` of these four commits is *thin* — it stores only the objects unique
to them and requires two base commits from the surrounding history. Those base
SHAs change during the rewrite, so the bundle would verify today and fail
afterwards. A self-contained bundle would instead have to carry full ancestry,
which pulls in the very blobs REPO-1 exists to remove.

`git format-patch` output is self-contained text: full diff, message, author and
date, readable without any repository at all. 3.8 MB, and it compresses.

## Recovering one

    git am ayurveda-data/archive/pre-repo1-orphans/02-e8d1b3e-d6-schema-seeder.patch

The resulting commit will have a different SHA — the original cannot be recreated,
because its parent no longer exists in the rewritten history. Read these as an
archive of what happened, not as commits to restore.
