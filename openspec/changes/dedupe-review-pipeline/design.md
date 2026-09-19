## Context

The duplication was inherited from the source repository, where `review.sh` was added after `pre-commit` by copying it, and grew when the pre-push backstop was bolted on with a string protocol. The probe suites were written one at a time. None of it is wrong today; it is expensive to keep right, and the guard's protected list is the one copy that matters for security.

## Goals / Non-Goals

**Goals**
- Every behaviour lives in one place, with exit codes at the boundaries.
- Adding a file or a probe touches one list.
- A maintainer can read `pre-commit` top to bottom in ten minutes.

**Non-Goals**
- A `cerberus` CLI wrapper. Five scripts with plain names are easier to audit than a dispatcher.
- Renaming `review-core.sh` or `no-bypass-guard.sh`. The guard regexes, the settings file and every install name them; not worth the churn in this change.
- Changing any hook behaviour. The backstop and guard suites must pass unchanged before and after each step.

## Decisions

### 1. Two-phase driver, exit codes at the seam
`review_prepare` and `review_judge` are separate so `pre-commit` can look up its cache and run lint between them. Exit codes: 0 pass, 1 block, 10 timeout, 11 contract, 12 unavailable, 13 chunk limit. `review.sh` returns them unchanged; `pre-push` maps them. Stdout stays human-readable but nothing parses it.

### 2. Manifest format
One path per line, kind first: `hook .githooks/pre-commit`. Shell reads it with `while read -r kind path`. Seeds (`review.conf`, project rules, `expected.tsv`) are listed so `selftest` can verify they were created, but never copied.

### 3. The guard keeps its own list, verified by a probe
The guard cannot read a file and stay builtins-only. So the manifest is the source and a guard probe walks it, submitting each protected kind as a write target. Drift is a red suite, not a silent gap.

### 4. Probe library shape
```
probe_pass|probe_fail|probe_skip <msg>     probe_summary <suite>
assert_rc <want> <got> <msg>               assert_grep <ere> <text> <msg>
scratch_repo <dir>                         stub_reviewer <dir> [PASS|BLOCK]
without_reviewer <cmd...>                  guard_expect <rc> [--no-jq|--cwd d|--dev|--write path] <arg>
```
`probe_summary` derives totals from the counters; the pgrep double-`bad` workaround disappears.

### 5. Deletions
`examples/roblox-luau/review-rubric.md` is history now that the split exists. The settings template and the workflow template are the repository's own files; `install.sh` reads `.claude/settings.json` and `.github/workflows/review.yml`, and the workflow's selftest step runs only when `selftest.sh` exists.

### 6. Guard phases
`read_payload` (sets command and path; one loop over the two path keys), `check_bypass`, `check_tamper`, `check_write_path`, `invoked_scripts`, `scan_invoked_scripts`, `main`. `hay` becomes `subject`, `ci`/`cs` become `matches_ci`/`matches_cs`, `WHERE` becomes `context`, `block` becomes `refuse`. The residual-holes header stays as it is.

### 7. Knob pruning
`REVIEW_TIMEOUT_STEP_BYTES`, `REVIEW_TIMEOUT_STEP_SECS`, `REVIEW_CONTEXT_THRESHOLD` and `REVIEW_MAX_CONTEXT_BYTES` become constants in the core; nothing sets them. `REVIEW_HOOK_DIR` becomes internal. The README's table becomes a link to `review.conf.example`.

## Bash 3.2 and BSD compatibility

`while read -r kind path` and `printf -v` are 3.2-safe. No new tools.

## Risks / Trade-offs

- **A refactor of the pipeline can change a verdict** → backstop probes run after every step; a regress run with the pinned model closes the change.
- **Exit-code families are a new contract** → documented in the core header and asserted by backstop probes for each code.
- **Deleting templates breaks anyone who linked to them** → they were published for days; the README points at the new locations.

## Migration Plan

Order: deletions and dead code, then manifest and VERSION, then the probe library, then the driver with pre-push on exit codes, then guard phases and knob pruning. One commit per step, each green on every suite.

## Open Questions

- Should `CHANGELOG.md` start at this change or at the first tag?
