## Why

A reviewer earns trust by finding logic bugs and staying quiet otherwise. Measured against a ten-point brief for a code-review agent, Cerberus already has the severity gate, the evidence rule, the eval set and scope discipline. It is missing four things that decide whether findings are useful in practice: it never tells the model to leave lint-enforced style alone, so attention goes to formatting; it shows callers but not callees or the module an entry point lives in, where boundary bugs sit; it has no inline suppression, so a false positive on a deliberate choice can only be answered with a full bypass; and its project-rules template invites prose instead of checkable statements. The Roblox example also lacks a domain checklist for what linters cannot catch.

## What Changes

- **Lint exclusion in the rubric.** A "Not yours to review" section: anything a configured linter or formatter enforces is out of scope, named by tool from `review.conf` so the model knows which rules those are.
- **Context widening in the prompt.** Alongside callers, the prompt attaches the definitions of functions the added lines call, and the full file of any changed file matching `REVIEW_CONTEXT_PATTERNS` (for example remote handlers), within the existing attachment budget.
- **Inline suppression with a required reason.** A `review-ignore: <reason>` comment on or immediately above a line demotes any finding on that line to WARN, with the reason printed. The hook enforces this after the model answers, so it does not depend on the model noticing. A marker with no reason is itself a WARN.
- **Checkable project rules.** The template asks for statements of the form "flag any X that does Y", with one example per BLOCKER class. The Roblox example gains a domain checklist: DataStore budget and session locking, ProcessReceipt idempotency and grant-before-granted, replication cost, yields in loops and callbacks.
- **Eval set reporting.** The regress runner reports catch rate on BLOCK cases and false-positive rate on PASS cases separately, and `expected.tsv` gains a description column. Three fixtures are added to the Roblox example for the new checklist items.
- **Scope discipline stated.** One rubric line: no refactors, renames or rewrites outside the change; fixes are the smallest change that addresses the finding.

Structured output stays as the fixed line format, which the hook already parses and validates; a JSON block would add a parser the pure-bash hooks cannot have.

Not BREAKING. Rubric and template text, prompt additions, one new config key, one optional column.

## Capabilities

### New Capabilities
- `review-prompt-context`: what the reviewer is shown beyond the diff and what it is told not to review.
- `finding-suppression`: the inline marker, its enforcement, and its reporting.
- `project-rules-and-eval`: the shape of project rules, the domain checklist, and regress reporting.

### Modified Capabilities
None.

## Impact

- `.githooks/review-rubric.md`, `templates/review-rubric.project.md`, `examples/roblox-luau/review-rubric.project.md` and three new fixtures with expectations.
- `lib/review-core.sh` (callee lookup, pattern attachments, suppression pass), `review.conf.example` (`REVIEW_CONTEXT_PATTERNS`, `REVIEW_LINT_TOOLS`).
- `scripts/review-regress.sh` (rates, description column).
- README sections on the rubric and calibration.
