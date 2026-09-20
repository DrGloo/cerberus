# Review Prompt Context

## Purpose
Define the repository context and review boundaries shown to the AI reviewer.

## Requirements

### Requirement: Lint-enforced rules are out of scope
The assembled rubric SHALL name configured lint and formatter tools and instruct the reviewer not to report rules they enforce. With no tools configured, formatting and style SHALL remain out of scope.

#### Scenario: Configured linters
- **WHEN** `REVIEW_LINT_TOOLS` is `selene stylua`
- **THEN** the rubric names both tools in the exclusion section.

#### Scenario: Style-only fixture
- **WHEN** a change only adjusts indentation or wrapping
- **THEN** the expected verdict is PASS with no findings.

### Requirement: Callees and entry-point files are attached
For added lines, the prompt builder SHALL collect called identifiers, look up definitions in the tree under review, and attach capped definition context under `---- CALLEE: name ----` blocks. A changed file matching `REVIEW_CONTEXT_PATTERNS` by path or content SHALL be attached in full within the attachment budget.

#### Scenario: Handler calling a validator
- **WHEN** an added line calls `validateAmount(x)` defined in another file
- **THEN** the prompt contains a CALLEE block with that definition.

#### Scenario: Remote handler file
- **WHEN** `REVIEW_CONTEXT_PATTERNS` matches a changed handler file with only two changed lines
- **THEN** the full current file is attached.

### Requirement: Scope discipline is stated
The rubric SHALL state that findings never propose refactors, renames, or rewrites outside the change, and that fixes are the smallest change addressing the finding.

#### Scenario: Refactor bait
- **WHEN** a fixture makes a small correct change inside a badly shaped function
- **THEN** the expected verdict is PASS with at most a NIT.
