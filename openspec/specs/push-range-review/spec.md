# Purpose

Define push review bases and oversize range handling.

# Requirements

## Requirement: The review base is the merge base

For each pushed ref, pre-push SHALL compute the base as the merge base of the local tip and the remote tip when the remote tip exists locally. For a new branch it SHALL use the merge base with the remote's default branch, found through the remote's HEAD ref, else the remote's branches, else the local tip's ancestry clamped to the root commit. It SHALL never use `HEAD~N`. When no base resolves, it SHALL allow the push with a printed note and attest nothing. Probe suite: backstop-probes.

### Scenario: Branch behind main

- **WHEN** a feature branch is pushed whose base commit is older than the remote main
- **THEN** the reviewed diff contains only the branch's own changes and no reversal of main's newer files

### Scenario: Small repository, non-main default

- **WHEN** a repository with five commits and a default branch named `trunk` pushes a new branch
- **THEN** the branch's commits are reviewed against the merge base with `trunk`

### Scenario: First push of the default branch

- **WHEN** the default branch is pushed to an empty remote
- **THEN** its unattested commits are reviewed from the root and the hook prints what it reviewed

## Requirement: Oversize ranges are chunked, never waved through

When the diff for a range exceeds the size cap, the reviewer SHALL split it by file into chunks under the cap and review each; the range passes only if every chunk passes. If more than `REVIEW_MAX_CHUNKS` chunks are needed, pre-push SHALL refuse the push with a message naming the size and the human override `REVIEW_ALLOW_OVERSIZE=1`, and SHALL attest nothing. The same chunking applies to pre-commit, whose oversize diffs are then eligible for attestation. Probe suite: backstop-probes.

### Scenario: Range in three chunks

- **WHEN** a range's diff is three times the cap and every chunk reviews clean
- **THEN** the push proceeds and the commits are attested

### Scenario: One bad chunk

- **WHEN** one of the chunks returns BLOCK
- **THEN** the push is refused and nothing is attested

### Scenario: Too many chunks

- **WHEN** a range needs more chunks than the limit
- **THEN** the push is refused with the override named, and with the override set the push proceeds unattested and ledgered
