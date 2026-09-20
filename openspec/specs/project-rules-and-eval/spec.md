# Project Rules And Evaluation

## Purpose
Define checkable project rules, advisory code-smell review, and regression-suite reporting.

## Requirements

### Requirement: Project rules are checkable statements
Project-rule templates SHALL use statements such as `flag any X that does Y` or `every X must Y`, naming a concrete construct and observable condition. The generic template SHALL include one example for each BLOCKER class. Roblox rules SHALL cover exploit surface, lifecycle leaks, yielding and races, DataStore retries, session locking and budget, ProcessReceipt idempotency with grant-before-granted, and replication cost.

### Requirement: Code smells are reviewed and never block
The rubric SHALL cover complexity, deep nesting, dead code, bad naming, and duplication as WARN-only findings scoped to added or rewritten code. Complexity findings SHALL state cyclomatic and cognitive estimates, flagging above 10 and 15 respectively, and SHALL name a smaller extraction seam.

#### Scenario: Smell fixture
- **WHEN** a fixture adds deep nesting, an unreachable branch, and an unused parameter
- **THEN** the expected verdict is PASS with WARN findings for each.

#### Scenario: Complexity fixture
- **WHEN** a fixture adds twelve decision points over four nesting levels
- **THEN** the expected verdict is PASS with a WARN stating both estimates and a seam.

### Requirement: The regress runner reports rates
`review-regress.sh` SHALL read an optional fourth description column, show it on failures, and report BLOCK catch rate and PASS false-positive rate after per-case results. PASS expectations MAY require multiple WARN citations separated by `|`.

#### Scenario: Mixed suite
- **WHEN** six BLOCK cases are caught and one of two PASS cases blocks
- **THEN** the summary reports `6/6` caught and `1/2` false positives, with the description on failure.

#### Scenario: Old file format
- **WHEN** an expectations file has three columns
- **THEN** the runner behaves as before.
