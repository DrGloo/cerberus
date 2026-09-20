## Context

The rubric and prompt were tuned on one Roblox codebase. They already encode evidence requirements, severity tiers, a nit cap and "silence is a valid review". The gaps are in what the model is shown and what it is told to leave alone, plus an escape hatch that does not require abandoning the whole gate.

## Goals / Non-Goals

**Goals**
- The reviewer spends its attention on logic at the diff boundary, not on style.
- A deliberate choice can be marked once, with a reason, and stops blocking.
- Project rules read like tests.

**Non-Goals**
- Giving the reviewer tools. The no-tools, empty-directory call is what makes reviews reproducible and injection-resistant; context is widened on the prompt side instead.
- JSON output. The line format is a fixed grammar already parsed and validated by the hooks; adding JSON would add a parser bash cannot provide without jq or python, both optional.

## Decisions

### 1. Exclusion by named tool
`REVIEW_LINT_TOOLS` is a space-separated list; the rubric section is generated from it at prompt time. Naming the tools lets the model map rules to them ("selene flags unused variables") instead of guessing what "style" means.

### 2. Callee lookup reuses the definition regex
Identifiers followed by `(` on added lines are collected, deduplicated, filtered against language keywords, and looked up with `review_grep_tree` using `review_definition_regex` anchored on the name. Each hit is attached with five lines of trailing context. Cap: eight callees, within the core's context byte budget (a constant after the dedupe change; the same value the full-file attachments already share). Callers stay as they are.

### 3. Pattern-driven full attachment
`REVIEW_CONTEXT_PATTERNS` is an ERE matched against the path and the staged content of each changed file. A match attaches the whole file regardless of the core's changed-line threshold. This is how "the file a RemoteEvent handler lives in" gets in front of the reviewer without tools.

### 4. Suppression enforced by the hook, honoured only from the base revision
The model is told about the marker but asked to report anyway. After `review_call_model`, `review_apply_suppressions` walks the findings and reads the cited line and the line above from the **base revision**, not the tree under review: `HEAD:path` for a staged diff, `<base>:path` for a range, with the cited line number mapped back through the diff's hunks. A marker that exists in the base demotes the finding to WARN with its reason printed. A marker the diff itself adds does not demote anything; the finding keeps its severity and the hook adds a WARN saying the marker takes effect only once it has been reviewed in. The sanitized, validated output is the input, so the contract holds before and after.

This is what stops a change from clearing its own blocker: a marker has to land in one reviewed commit before it can suppress a finding in the next.

- *Alternative: read markers from the tree under review.* Rejected: the diff that introduces a defect could introduce its excuse in the same line and pass.
- *Alternative: let the model apply suppressions.* Rejected: unreliable, and it would let a prompt-injected comment argue with the reviewer.

### 5. Rates in the regress summary
Two counters split by expected verdict. The description column is read into a fourth `read` variable; bash puts extra fields in the last variable, so three-column files still parse.

## Bash 3.2 and BSD compatibility

All additions use `grep -E`, `sed -E`, `awk` and `read` as the existing code does. No new constructs.

## Risks / Trade-offs

- **Callee lookups on a large diff cost grep time** → capped at eight names; `review_grep_tree` already scopes to `REVIEW_SOURCE_DIRS`.
- **A suppression marker could be abused to silence real defects** → it demotes to WARN, never drops; the reason is printed every time; a PR that adds markers is itself reviewed.
- **Rubric growth crowds the diff** → the exclusion section is short; measure prompt size in the regress run.

## Open Questions

- Should suppression also accept a file-level marker in the first three lines for generated code?
