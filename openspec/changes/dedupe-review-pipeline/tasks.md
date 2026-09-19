## 1. Deletions and dead code

- [ ] 1.1 Delete `examples/roblox-luau/review-rubric.md`, `templates/claude-settings.json`, `templates/github-workflow-review.yml`; `install.sh` reads the repository's own settings and workflow; the workflow's selftest step is conditional on the file existing
- [ ] 1.2 `review-regress.sh`: drop the second `REVIEW_TIMEOUT` default; `pre-commit`: collapse the two attestation comments into one; drop the "SonarQube-style" header
- [ ] 1.3 `review-core.sh`: Roblox-specific ignore patterns move to `examples/roblox-luau/review.conf`
- [ ] 1.4 README: probe counts removed; configuration table replaced by a link to `review.conf.example`

## 2. Manifest and version

- [ ] 2.1 `MANIFEST` with kinds; `install.sh` copies from it, stamps `VERSION`, refuses a plain re-install naming both versions, `--upgrade` replaces manifest paths only
- [ ] 2.2 Workflows and `selftest.sh` read the manifest for syntax and exec checks
- [ ] 2.3 `guard-probes.sh`: manifest sweep asserting every protected kind is refused as a write target
- [ ] 2.4 `VERSION` 0.2.0 and a `CHANGELOG.md` with the entries for the three changes

## 3. Probe harness

- [ ] 3.1 `scripts/lib/probe.sh` per the design
- [ ] 3.2 `guard-probes.sh` rewritten as a table over `guard_expect`
- [ ] 3.3 `backstop-probes.sh` on the harness: no hard-coded counters, `scratch_repo`, `stub_reviewer`, `without_reviewer`; skip instead of fail when `pgrep` is absent
- [ ] 3.4 `core-probes.sh` takes the library checks from `selftest.sh`; `selftest.sh` installs, verifies the manifest, and runs the three suites

## 4. The driver

- [ ] 4.1 `review-core.sh`: `review_prepare`, `review_judge`, exit-code families, `review_outcome_message`
- [ ] 4.2 `pre-commit` reduced to skip, prepare, cache, lint, judge, outcome; `save_last_review` and `finish` extracted
- [ ] 4.3 `scripts/review.sh` reduced to argument parsing plus the two calls
- [ ] 4.4 `pre-push` maps exit codes; no stdout parsing
- [ ] 4.5 `backstop-probes.sh`: one probe per exit code as seen by pre-push; `review.sh` never attests

## 5. Guard phases and knobs

- [ ] 5.1 `no-bypass-guard.sh` split into the named phases with the renamed globals; guard-probes unchanged and green
- [ ] 5.2 Timeout-step and context-budget knobs become constants; `REVIEW_HOOK_DIR` internal
- [ ] 5.3 `review.conf.example` is the only config reference

## 6. Verification

- [ ] 6.1 Every suite green after each numbered group; counts recorded in the CHANGELOG
- [ ] 6.2 `SELFTEST_MODEL=1 bash selftest.sh` passes on the pinned model

## Dependencies

- Lands after harden-trust-boundary and align-reviewer-with-brief; the driver absorbs `review_prepare` chunking and `review_apply_suppressions` from them.
