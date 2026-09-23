# Changelog

`install.sh --upgrade` prints every section above the installed version's
heading, so each entry says what an existing install has to know.

## 0.2.0 — unreleased

### Harden the trust boundary

- The agent guard has one protected-path predicate: the hook tree, the guard
  registration, the review and probe scripts, and anything under a git
  directory. A protected path is refused as a redirect target or in the same
  simple command as a write-shaped tool; reads stay allowed. File-tool
  payloads are judged by path only, so documentation that quotes a bypass
  flag is writable.
- Any command naming the attestation key path is refused.
- `review.conf` is data, not shell: one `KEY=VALUE` per line from an
  allowlist of `REVIEW_*` keys, with the environment winning over the file.
  **Breaking:** a line using variables or command substitution is reported
  and skipped.

### Align the reviewer with the brief

- The rubric leaves rules enforced by the configured lint and formatter
  tools to those tools, keeps findings within the change, and names code
  smells and per-function complexity as advisory WARNs.
- The prompt attaches the definitions of functions the added lines call,
  and the full text of changed files matching `REVIEW_CONTEXT_PATTERNS`.
- `review-ignore: <reason>` on or above a line demotes a finding there to
  WARN after the model answers; a marker without a reason is itself a WARN.
- The regress runner reports catch rate and false-positive rate separately;
  `expected.tsv` gains a description column.

### Dedupe the review pipeline

- `MANIFEST` is the one list of installed files. `install.sh`, the CI
  workflow and `selftest.sh` read it, and a guard probe fails when a
  manifest path is not protected.
- `VERSION` is stamped into `.githooks/VERSION`. A second install refuses,
  naming both versions; `--upgrade` replaces the manifest's files, keeps
  `review.conf`, the project rubric, `expected.tsv` and the workflow, and
  prints this changelog. **Breaking:** `--upgrade` replaces `--force`,
  which still works as an alias.
- `expected.tsv` is now created once and never overwritten, so a grown
  regress suite survives an upgrade.
- `templates/claude-settings.json` and `templates/github-workflow-review.yml`
  are gone: the repository's own `.claude/settings.json` and
  `.github/workflows/review.yml` are the source, and `install.sh` creates the
  workflow in the target when absent. The workflow runs `selftest.sh` only
  where it exists. `examples/roblox-luau/review-rubric.md`, the pre-split
  rubric, is gone.

## 0.1.0 — 2026-09-19

The hooks as extracted from the source repository: pre-commit review,
post-commit attestation, the pre-push backstop, and the agent guard.
