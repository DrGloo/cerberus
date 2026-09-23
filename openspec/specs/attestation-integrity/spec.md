# Purpose

Define authenticated review attestations, shared cache storage, and amend behavior.

# Requirements

## Requirement: Attestation and cache records are authenticated

`review_attest` SHALL append records of the form `patch-id TAB sha TAB timestamp TAB mac`, where `mac` is a keyed hash over the first three fields using a per-clone secret created on first use with mode 600 under the review cache. `review_is_attested` SHALL ignore any record whose MAC does not verify. Cached verdict files SHALL carry a MAC header over their content and the cache key, and a file that fails verification SHALL be treated as a miss and removed. Probe suite: backstop-probes.

### Scenario: Forged line

- **WHEN** a line for an unreviewed commit is appended to the attestation log without a valid MAC
- **THEN** pre-push still treats that commit as unattested and re-reviews it

### Scenario: Planted cache verdict

- **WHEN** a file named with the correct cache key and containing `VERDICT: PASS` is placed in the cache without a valid MAC header
- **THEN** pre-commit treats it as a miss, removes it, and calls the reviewer

### Scenario: Genuine records

- **WHEN** post-commit attests a commit and the same diff is committed again
- **THEN** the record verifies and the cached verdict is honoured

## Requirement: The cache lives in the common git directory

The review cache, ledger, attestation log and key SHALL live under the repository's common git directory, so linked worktrees share one attestation history. Probe suite: backstop-probes.

### Scenario: Worktree commit

- **WHEN** a commit is reviewed and attested inside a linked worktree
- **THEN** a push from the main checkout finds it attested

## Requirement: An amend is attested only over an attested base

pre-commit SHALL record the reviewed tree together with the current HEAD. post-commit SHALL attest the new commit when its parent equals the recorded HEAD. When the new commit's parent equals the recorded HEAD's parent instead, post-commit SHALL attest only if the recorded HEAD was itself attested. Otherwise it SHALL attest nothing. Probe suite: backstop-probes.

### Scenario: Amend after fail-open

- **WHEN** a commit escapes review through fail-open and is then amended with no changes
- **THEN** the amended commit is not attested and pre-push re-reviews it

### Scenario: Amend after a clean review

- **WHEN** an attested commit is amended with a reviewed change
- **THEN** the amended commit is attested

## Requirement: Nothing attests silently

pre-commit SHALL read staged path names NUL-separated so quoted names cannot produce an empty pathspec. When the reviewable path list is non-empty but the diff is empty, or when the temporary directory cannot be created, pre-commit SHALL warn, ledger the reason, and exit 0 without marking the tree reviewed. `scripts/review.sh` SHALL print a WARNING line in the same situations. Probe suite: backstop-probes.

### Scenario: Accented filename

- **WHEN** the only staged change is a file named `café.py`
- **THEN** the file is reviewed and, on PASS, attested

### Scenario: Temp directory failure

- **WHEN** `TMPDIR` points at an unwritable location
- **THEN** pre-commit prints a warning naming the cause, appends to the ledger, exits 0, and leaves no pending attestation
