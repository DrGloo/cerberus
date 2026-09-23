## Why

An adversarial review of the shipped guard reproduced a complete defeat: an agent can plant a passing verdict in the review cache or a forged line in the attestation log, because nothing protects writes under `.git/`, and it can overwrite any hook with a shell redirect, because the guard checks five verbs and nothing else. It can also append to `review.conf`, which is sourced as shell on every commit. Separately, three paths attest a commit the reviewer never saw: an amend after an unattested commit, a commit made only of non-ASCII filenames, and a diff over the size cap at push time, which the push hook waves through as "unavailable". These are the holes that matter; everything else in the review is secondary until they close.

## What Changes

- **Guard, one protected-path predicate.** The hook tree, the guard registration, the review scripts, and the git directory are protected. A Bash command that names a protected path as the target of a redirect, or as an argument to any write-shaped tool (the current five plus `tee`, `sed -i`, `ln`, `dd`, `install`, `patch`, and interpreter one-liners), is refused. Reads stay allowed. File-tool payloads are judged by path only; their content is no longer scanned as if it were a shell command.
- **`review.conf` becomes data.** A `KEY=VALUE` parser with an allowlist of `REVIEW_*` keys replaces sourcing. A config file can no longer contain executable statements.
- **Authenticated records.** Attestation lines and cache verdicts carry a MAC keyed by a per-clone secret the guard refuses to read. Records without a valid MAC are ignored. The cache moves to the repository's common git directory so worktrees share it.
- **Amend rule.** pre-commit records the current HEAD with the reviewed tree; post-commit attests an amended commit only when the commit it replaced was itself attested.
- **No silent attestation.** File names are read NUL-separated so quoting cannot empty the diff; a non-empty path list with an empty diff, or a failed temp directory, is a ledgered warn-and-pass, never a pass.
- **Oversize diffs are reviewed in file chunks**, each under the cap; a push whose range cannot be chunked within a bounded number of calls is refused with an explicit human override, not allowed as "unavailable".
- **Push base is the merge base**, chosen per remote, with fallbacks that never resolve to the wrong branch or skip silently.
- **Verdict and diagnostics.** A `[BLOCKER]` with no verdict line blocks; verdict lines tolerate trailing punctuation and case; reviewer stderr is captured and shown on failure; the cache key uses `git hash-object`; ignore globs are matched literally; `install.sh` never overwrites a grown `expected.tsv`.

**BREAKING for existing installs:** the attestation record gains a MAC column and the cache moves directory, so every branch re-reviews once after upgrading. `review.conf` lines with shell syntax stop working. `install.sh --upgrade` migrates the cache location and prints the one-time re-review notice.

## Capabilities

### New Capabilities
- `agent-guard`: what the PreToolUse guard refuses and allows, by command shape and by path.
- `attestation-integrity`: when a commit may be attested, how records are authenticated, and which paths must never attest silently.
- `push-range-review`: how pre-push picks a base, handles oversize ranges, and decides to attest, refuse, or pass through.
- `review-config-and-verdict`: the config file format, the verdict contract edge cases, diagnostics, and cache hygiene.

### Modified Capabilities
None. The repository has no main specs yet.

## Impact

- `.githooks/lib/no-bypass-guard.sh`, `lib/review-core.sh`, `pre-commit`, `post-commit`, `pre-push`, `scripts/review.sh`, `install.sh`.
- `scripts/guard-probes.sh` and `scripts/backstop-probes.sh` gain a probe per new rule.
- README sections on the guard, fail-open, and configuration.
- `examples/roblox-luau/review.conf` loses its `${VAR:-}` wrappers.
