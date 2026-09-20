## 1. Rubric text

- [x] 1.1 `review-rubric.md`: "Not yours to review" section generated from `REVIEW_LINT_TOOLS`, with a default when none are set
- [x] 1.2 `review-rubric.md`: scope-discipline line under Change shape; the suppression marker described with "report anyway"
- [x] 1.3 `templates/review-rubric.project.md`: rewrite as "flag any X that does Y" statements with one example per BLOCKER class
- [x] 1.4 `examples/roblox-luau/review-rubric.project.md`: domain checklist (DataStore retries, session locking, budget; ProcessReceipt idempotency and grant-before-granted; replication cost; yields in loops and callbacks)

## 2. Prompt context

- [x] 2.1 `review-core.sh`: callee collection from added lines, keyword filter, definition lookup, `---- CALLEE ----` blocks, cap and budget
- [x] 2.2 `review-core.sh`: `REVIEW_CONTEXT_PATTERNS` full-file attachment; `review.conf.example` documents it and `REVIEW_LINT_TOOLS`
- [x] 2.3 `core-probes.sh`: callee block present for a cross-file call; pattern match attaches a two-line change in full; exclusion section names configured tools

## 3. Suppression

- [x] 3.1 `review-core.sh`: `review_apply_suppressions` (line and line-above lookup from the base revision with hunk-mapped line numbers, demotion, missing-reason WARN, unreviewed-marker WARN, verdict rewrite) called from both drivers after validation
- [x] 3.2 `core-probes.sh`: marker present in HEAD demotes a blocker to WARN with the reason and the commit passes; marker added by the same diff leaves the block in place and adds a WARN; marker three lines away does nothing; bare marker adds a WARN and keeps the finding

## 4. Eval set

- [x] 4.1 `review-regress.sh`: fourth description column; catch-rate and false-positive summary
- [x] 4.2 Roblox example: fixtures for a non-idempotent receipt, a DataStore call with no retry or budget check, and a per-frame replication burst, with expectations and descriptions
- [x] 4.3 Sample project: a style-only PASS fixture, a suppressed-defect PASS fixture with the reason in the expected citation, a code-smell fixture (deep nesting, dead branch, unused parameter) expected to PASS with WARN citations, and a complexity fixture (twelve decision points over four levels) expected to PASS with a WARN stating both estimates
- [x] 4.5 Regress runner: a PASS expectation may list several required WARN citations separated by `|`, so the smell fixture checks each finding
- [x] 4.4 README: rubric section and calibration section updated; both example READMEs drop their tables in favour of the description column

## 5. Verification

- [x] 5.1 Run `selftest.sh` and every probe suite; record the counts (selftest 0 failures; guard 227/227; backstop 22/22; core 44 checks)
- [x] 5.2 `SELFTEST_MODEL=1 bash selftest.sh` passes on the enlarged sample suite (reviewed and accepted)

## Dependencies

- Lands after harden-trust-boundary, whose config loader supplies the two new keys and whose `core-probes.sh` this change extends.
