## ADDED Requirements

### Requirement: Protected paths are defined once

The guard SHALL hold a single predicate that decides whether a path is protected. Protected paths are everything under the hook directory, the Claude Code settings file, the review and probe scripts, and everything under the repository's git directory, including a linked worktree's git directory. Matching SHALL be case-insensitive and SHALL apply to relative and absolute spellings. Probe suite: guard-probes.

#### Scenario: Every manifest path is protected
- **WHEN** guard-probes submits a file-tool payload for each path the install manifest lists as hook, lib, script or settings
- **THEN** every one is refused

#### Scenario: Git directory paths
- **WHEN** a file-tool payload targets `.git/review-cache/attested.log`, `.git/config`, or `.git/worktrees/x/review-cache/y`
- **THEN** it is refused

### Requirement: Every write shape to a protected path is refused

For Bash commands, the guard SHALL refuse a command in which a protected path appears as the target of an output redirect (`>`, `>>`, `>|`), or as an argument to a write-shaped tool: the current delete, move, copy, mode-change and size-change verbs, plus `tee`, `sed -i`, `ln`, `dd`, `install`, `patch`, and an interpreter invoked with an inline program (`-c`, `-e`) in the same command. Commands that only read a protected path SHALL stay allowed. Probe suite: guard-probes.

#### Scenario: Redirect over a hook
- **WHEN** the command is `echo ok > .githooks/pre-commit` or `: > .githooks/pre-commit` or `printf x >> .githooks/review.conf`
- **THEN** it is refused

#### Scenario: Tool writes
- **WHEN** the command is `sed -i.bak s/x/y/ .githooks/pre-commit`, `ln -sf /dev/null .githooks/pre-commit`, `tee .githooks/pre-commit < f`, `dd of=.githooks/pre-commit if=/dev/null`, or `python3 -c "open('.githooks/pre-commit','w')"`
- **THEN** it is refused

#### Scenario: Reads stay allowed
- **WHEN** the command is `cat .githooks/pre-push`, `git add .githooks`, `ls -la .git/review-cache`, or `cat .git/review-cache/last-review.md`
- **THEN** it is allowed

### Requirement: File-tool payloads are judged by path only

When a payload carries a file path and no command, the guard SHALL apply the protected-path predicate to the path and SHALL NOT apply the command-string or invoked-script checks to the file content. A multi-edit payload SHALL be judged by its top-level path. Probe suite: guard-probes.

#### Scenario: Documentation that mentions a bypass
- **WHEN** a Write to `CONTRIBUTING.md` contains the words of the hook-skipping flag or the skip variable
- **THEN** it is allowed

#### Scenario: Content is irrelevant for a protected path
- **WHEN** a Write to `.githooks/post-commit` contains only `exit 0`
- **THEN** it is refused

### Requirement: The per-clone secret is unreadable to agents

Any Bash command that names the attestation key file SHALL be refused, whether it reads, copies, or writes it. Probe suite: guard-probes.

#### Scenario: Reading the key
- **WHEN** the command is `cat .git/review-cache/key` or `base64 .git/review-cache/key`
- **THEN** it is refused

### Requirement: Development mode lifts only tamper checks

With `REVIEW_HOOK_DEV=1` in the guard's environment, protected-path and tamper checks SHALL be lifted and bypass checks SHALL remain. Probe suite: guard-probes.

#### Scenario: Dev mode write
- **WHEN** a file-tool payload targets `.githooks/pre-commit` under dev mode
- **THEN** it is allowed

#### Scenario: Dev mode bypass
- **WHEN** a command commits with hooks disabled under dev mode
- **THEN** it is refused
