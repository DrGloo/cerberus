## ADDED Requirements

### Requirement: Project rules are checkable statements

The project-rules template SHALL ask for rules of the form "flag any X that does Y" or "every X must Y", each naming a concrete construct, and SHALL carry one filled example per BLOCKER class in the generic rubric. The Roblox example SHALL include a domain checklist covering exploit surface, lifecycle leaks, yielding and race conditions, DataStore retries, session locking and budget, ProcessReceipt idempotency with grant-before-granted, and replication cost. Probe suite: regress.

#### Scenario: Template shape
- **WHEN** a new install creates the project rules file
- **THEN** every example rule names a construct and an observable condition

#### Scenario: Receipt fixture
- **WHEN** a Roblox fixture returns PurchaseGranted before the grant is saved
- **THEN** the expected verdict is BLOCK citing the receipt handler

### Requirement: The regress runner reports rates

`review-regress.sh` SHALL print, after the per-case lines, the catch rate over cases expected to BLOCK and the false-positive rate over cases expected to PASS, and SHALL read an optional fourth column of `expected.tsv` as a description shown on failure. Probe suite: selftest.

#### Scenario: Mixed suite
- **WHEN** a suite has six BLOCK cases and two PASS cases and one PASS case blocks
- **THEN** the summary shows 6/6 caught and 1/2 false positives, and the failing line shows the case description

#### Scenario: Old file format
- **WHEN** `expected.tsv` has three columns
- **THEN** the runner behaves as before
