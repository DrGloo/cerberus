## ADDED Requirements

### Requirement: Lint-enforced rules are out of scope

The assembled rubric SHALL contain a section naming the tools listed in `REVIEW_LINT_TOOLS` and instructing the reviewer not to report anything those tools enforce: formatting, import order, naming conventions the linter checks, and unused variables. When no tools are configured the section SHALL say that formatting and style are out of scope regardless. Probe suite: core-probes, regress.

#### Scenario: Configured linters
- **WHEN** `REVIEW_LINT_TOOLS` is `selene stylua`
- **THEN** the rubric the reviewer sees names both tools in the exclusion section

#### Scenario: Style-only fixture
- **WHEN** a regress fixture changes only indentation and line wrapping
- **THEN** the expected verdict is PASS with no findings

### Requirement: Callees and entry-point files are attached

For every added line, the prompt builder SHALL collect called identifiers, look up their definitions in the tree under review, and attach each definition with a few lines of context under a `---- CALLEE: name ----` block, bounded by the existing attachment budget and a count cap. A changed file whose path or content matches `REVIEW_CONTEXT_PATTERNS` SHALL be attached in full regardless of its changed-line count, within the budget. Probe suite: core-probes.

#### Scenario: Handler calling a validator
- **WHEN** an added line calls `validateAmount(x)` defined in another file
- **THEN** the prompt contains a CALLEE block with that definition

#### Scenario: Remote handler file
- **WHEN** `REVIEW_CONTEXT_PATTERNS` is `OnServerEvent|wrapInvoke` and a changed file contains `wrapInvoke`
- **THEN** the file's full current text is attached even though only two lines changed

### Requirement: Scope discipline is stated

The rubric SHALL state that findings never propose refactors, renames or rewrites outside the change, and that a proposed fix is the smallest change that addresses the finding. Probe suite: regress.

#### Scenario: Refactor bait
- **WHEN** a fixture makes a small correct change inside a long, badly named function
- **THEN** the expected verdict is PASS with at most a NIT
