# Purpose

Define the shared probe harness and suite ownership contract.

# Requirements

## Requirement: One harness for every suite

`scripts/lib/probe.sh` SHALL provide pass, fail and skip reporters with a summary and exit code, `assert_rc`, `assert_grep`, a scratch repository builder that copies the working-tree hook files, a stub reviewer that answers a chosen verdict, a "no reviewer" wrapper, and a guard payload builder for commands and file paths with jq-less, cwd and dev-mode options. Every suite SHALL use it and define no reporter of its own. Probe suite: selftest.

### Scenario: Count is derived

- **WHEN** a probe is added to any suite
- **THEN** the summary line's total changes with no other edit

### Scenario: Missing tool is a skip, not a pass

- **WHEN** `pgrep` or `jq` is absent for a probe that needs it
- **THEN** the probe reports skipped, is counted, and does not fail the suite

## Requirement: Suites own distinct behaviour

`guard-probes.sh` SHALL cover only the guard; `backstop-probes.sh` only attestation, pre-push and the timeout watcher; `core-probes.sh` only library functions; `selftest.sh` SHALL install into a throwaway repository, verify the manifest, and run the three suites there. No check SHALL appear in two suites. Probe suite: selftest.

### Scenario: selftest delegates

- **WHEN** selftest runs
- **THEN** its output contains the three suites' summary lines and its own install checks, and nothing else
