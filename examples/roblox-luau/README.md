# Example: a Roblox game (Luau)

This is the configuration the hooks ran with in the repository they were
extracted from: a Roblox slide-racing game written in Luau and synced with
Rojo. It is included as a worked example of the three project-specific pieces.

| File | Installed as | What it is |
|---|---|---|
| `review.conf` | `.githooks/review.conf` | Source roots, ignore globs, and a `selene` lint step. |
| `review-rubric.project.md` | `.githooks/review-rubric.project.md` | House rules: lifecycle owners by name, the persistence module and its schema rule, the validation wrapper every remote must use, vendored directories, and severity calibrations. |
| `regress/` | `.githooks/regress/` | Fifteen seeded-defect fixtures with expected verdicts, and the model they were last calibrated against. |
| `review-rubric.md` | (reference only) | The original single-file rubric before the generic/project split, kept so the split can be compared against it. |

## What the fixtures cover

Each `S*.patch` seeds one defect class into the game's source. They will not
apply to any other repository; they are here to show what a good fixture
looks like, not to be run.

The cases are described in the fourth column of `regress/expected.tsv`, which
also carries the expected verdict and required citation. They cover boundary
regressions, lifecycle, persistence, prompt injection, dependencies, and the
domain checklist for receipts, DataStore safety, and replication cost.

The mix matters: about a third of the cases must PASS. A rubric that blocks
everything scores perfectly on a suite of only defects and is useless in
practice.

## Authoring your own

1. Pick a defect class from the rubric's BLOCKER list, or a calibration case
   that must *not* block.
2. Make the change in a scratch worktree of your repository and save
   `git diff` as `.githooks/regress/<case>.patch`. Keep each patch to one
   defect and under about thirty lines, so a wrong verdict has one cause.
3. Add a line to `expected.tsv`: the case, `BLOCK` or `PASS`, a literal
   substring the finding must cite (`-` for none), and a short description.
4. Run `scripts/review-regress.sh`. A full clean run pins the model in
   `calibrated-model`; the staged-diff hook prints a note whenever it runs with
   a different one.
