## Why

Every fix to the review pipeline has to be made twice, because `pre-commit` and `scripts/review.sh` carry the same sixty lines, and `pre-push` couples to the second copy by grepping its stdout for exact strings. The list of installed files is hand-maintained in seven places, one of which is the guard's protected-path list, so a new script is silently unprotected until someone remembers. Three probe suites each define their own counters, stub reviewer and payload builders. Three files are byte-for-byte or near duplicates of others. The maintenance cost is around the core, not in it, and it is about six hundred lines.

## What Changes

- **One review driver.** `review_prepare` and `review_judge` in the core library take a mode (`staged` or `range`) and return exit codes: pass, block, and a distinct family for unavailable, cut short, and contract violation. `pre-commit` keeps only what is unique to it: skip, cache, lint, attestation. `review.sh` becomes a thin CLI. `pre-push` switches from stdout scraping to exit codes.
- **One manifest.** `MANIFEST` lists every installed path with its kind. `install.sh`, both workflows and `selftest.sh` read it; a guard probe asserts every manifest path is refused as a write target, so drift fails CI.
- **One probe harness.** `scripts/lib/probe.sh` supplies assertions, a scratch repository builder, the stub reviewer and the payload builders. The guard suite becomes a table; the backstop suite drops its hard-coded counters; `selftest.sh` runs the suites instead of re-implementing their checks; the core-level checks move into `core-probes.sh`.
- **Deletions.** `examples/roblox-luau/review-rubric.md`, `templates/claude-settings.json` and `templates/github-workflow-review.yml` go; the repository's own copies are the source, and the workflow guards its selftest step so it works as-is in a target.
- **Guard phases.** `read_payload`, `check_bypass`, `check_tamper`, `scan_invoked_scripts`, and a six-line main. Globals renamed to say what they hold.
- **Smaller surface.** The two timeout-step knobs and the two context-budget knobs become constants; `review.conf.example` is the only config reference and the README links to it. Probe counts leave the README.
- **Version.** `VERSION` at the root, stamped into the target on install; `--upgrade` compares it.

**BREAKING for existing installs:** `templates/` paths change and the installed file list gains `VERSION` and `scripts/lib/probe.sh`; `install.sh --upgrade` handles both.

## Capabilities

### New Capabilities
- `review-driver`: the shared pipeline's modes, outputs and exit codes, and what each hook does with them.
- `install-manifest`: the manifest, what reads it, and how upgrades use the version.
- `probe-harness`: the shared test library and what each suite is responsible for.

### Modified Capabilities
None.

## Impact

- Every file under `.githooks/` and `scripts/`, `install.sh`, `selftest.sh`, both workflows, README.
- About 3,700 lines become about 2,900.
