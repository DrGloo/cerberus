## ADDED Requirements

### Requirement: Project rules are checkable statements

The project-rules template SHALL ask for rules of the form "flag any X that does Y" or "every X must Y", each naming a concrete construct, and SHALL carry one filled example per BLOCKER class in the generic rubric. The Roblox example SHALL include a domain checklist covering exploit surface, lifecycle leaks, yielding and race conditions, DataStore retries, session locking and budget, ProcessReceipt idempotency with grant-before-granted, and replication cost. Probe suite: regress.

#### Scenario: Template shape
- **WHEN** a new install creates the project rules file
- **THEN** every example rule names a construct and an observable condition

#### Scenario: Receipt fixture
- **WHEN** a Roblox fixture returns PurchaseGranted before the grant is saved
- **THEN** the expected verdict is BLOCK citing the receipt handler

### Requirement: Code smells are reviewed and never block

The rubric SHALL carry a code-smells dimension covering complexity, deep nesting, dead code, bad naming, and in-file duplication, each finding naming the line and the smaller shape, capped at WARN and scoped to code the diff adds or rewrites. Complexity SHALL be judged per function with a cyclomatic estimate (decision points plus one) and a cognitive estimate (decision points weighted by nesting depth, plus loop exits and recursion), flagged above 10 and 15 respectively with both numbers stated in the finding, and per file when several added functions exceed the thresholds or the file's cognitive total passes 100. When `REVIEW_LINT_TOOLS` names a complexity tool, the reviewer SHALL be told not to repeat what it enforces. Probe suite: regress.

#### Scenario: Smell fixture
- **WHEN** a sample fixture adds a function with five levels of nesting, an unreachable branch, and a parameter nothing reads
- **THEN** the expected verdict is PASS with WARN findings citing each

#### Scenario: Complexity fixture
- **WHEN** a sample fixture adds a function with twelve decision points across four nesting levels
- **THEN** the expected verdict is PASS with a WARN citing the function, stating both estimates, and naming a seam

#### Scenario: Smells in untouched code
- **WHEN** a fixture makes a one-line correct change inside an existing badly shaped function
- **THEN** the expected output has no smell finding on the untouched lines

### Requirement: The regress runner reports rates

`review-regress.sh` SHALL print, after the per-case lines, the catch rate over cases expected to BLOCK and the false-positive rate over cases expected to PASS, and SHALL read an optional fourth column of `expected.tsv` as a description shown on failure. Probe suite: selftest.

#### Scenario: Mixed suite
- **WHEN** a suite has six BLOCK cases and two PASS cases and one PASS case blocks
- **THEN** the summary shows 6/6 caught and 1/2 false positives, and the failing line shows the case description

#### Scenario: Old file format
- **WHEN** `expected.tsv` has three columns
- **THEN** the runner behaves as before
