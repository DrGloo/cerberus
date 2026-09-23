## ADDED Requirements

### Requirement: One pipeline serves both hooks

`review_prepare <staged|range> [range] <dir>` SHALL produce the rubric, path lists, diff, and prompt (or chunked prompts) in the directory, and return 0 when there is something to review and 2 when there is nothing reviewable. `review_judge <dir>` SHALL run every prompt, print the announce line and findings, and return 0 for PASS, 1 for BLOCK, 10 for timeout, 11 for a contract violation, 12 for unavailable, and 13 for a range that exceeded the chunk limit. Both `pre-commit` and `scripts/review.sh` SHALL call these and contain no diff or prompt construction of their own. Probe suite: core-probes, backstop-probes.

#### Scenario: Same diff, same prompt
- **WHEN** the same change is reviewed as a staged diff and as a one-commit range
- **THEN** the two prompts differ only in the mode label and the show revision

#### Scenario: Exit codes drive pre-push
- **WHEN** `review.sh` returns 0, 1, 10, 11, 12 or 13 for a range
- **THEN** pre-push attests and allows (0), refuses (1), allows unattested with a warning (10, 11, 12), or refuses naming the `REVIEW_ALLOW_OVERSIZE=1` override (13), without parsing stdout. Code 13 is the one deliberate refusal outside a BLOCK: an unreviewable range is a size the author chose, not a reviewer failure, and the override keeps the human in charge

### Requirement: Outcome handling stays in the hooks

`mark_reviewed`, the ledger, the cache and the lint step SHALL exist only in `pre-commit`; attestation of a range SHALL exist only in `pre-push`. Probe suite: backstop-probes.

#### Scenario: review.sh never attests
- **WHEN** `scripts/review.sh` is run directly on a range and passes
- **THEN** the attestation log is unchanged
