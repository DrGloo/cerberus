## Context

The guard was written to stop an agent from skipping the review. Its tamper checks were an afterthought: five verbs, one redirect rule for the rubric, and a file-path check added later for the editing tools. The attestation store and the verdict cache sit under `.git/`, which the guard never considered, and their records are plain text. An attacker model that includes the agent writing files by any means was never applied end to end. This change applies it.

Attacker model, matching the guard header: an AI agent with the Bash and file-editing tools inside a repository where Cerberus is installed, trying to land a commit that the reviewer never judged, or to make a BLOCK into a PASS. Humans are out of scope; they can bypass from their own terminal by design.

Accepted residual holes after this change, to be listed in the guard header: a script written by a non-Bash tool and executed in the same turn, a program piped into an interpreter on stdin, a protected path reached through a symlink the guard has not seen, and an agent that can read the attestation key through a path the guard does not recognise.

## Goals / Non-Goals

**Goals**
- No write to a protected path from Bash or a file tool passes the guard, whatever its shape.
- No record in the attestation log or the verdict cache is honoured unless the hooks wrote it.
- No commit is attested that the reviewer did not judge in full.
- Push-time review judges the branch's own patches, never a reversal of main.

**Non-Goals**
- Protecting against a human with a terminal.
- Sandboxing the reviewer beyond the current no-tools, empty-directory call.
- Reviewing merge-commit conflict resolutions (still the accepted residual from pre-push).

## Decisions

### 1. One protected-path predicate, applied by shape

`is_protected_path` is the only place that knows the list. For Bash, the guard tokenises the command on whitespace and redirect operators and refuses when a protected token is the target of an output redirect, or when a write-shaped word appears anywhere in the same simple command as a protected token. The write-shaped list is explicit and short, and a probe asserts each entry. Interpreters are handled coarsely: an interpreter with `-c` or `-e` in a command that also names a protected path is refused, which over-blocks a read-only one-liner and is accepted.

- *Alternative: parse the command with a real shell grammar.* Rejected: the guard is pure builtins by rule, and a partial parser is worse than a stated token rule.
- *Alternative: block every mention of a protected path.* Rejected: `cat .git/review-cache/last-review.md` is documented and useful.

### 2. Config is parsed, not sourced

`review_load_conf` reads lines matching `^[A-Z_]+=` whose key is in the allowlist, strips one layer of matching quotes, and assigns with `printf -v`. No `eval`, no expansion. The `${VAR:-default}` ceremony disappears from every conf file because precedence is enforced by the loader: it skips keys already set in the environment.

- *Alternative: keep sourcing and protect the file.* Rejected: the guard protects the file from the agent, but a pull request that edits it still runs code on every reviewer's machine at their next commit.

### 3. Authenticated records with a per-clone key

`review_mac <text>` is `git hash-object --stdin` over `key || text`, which is HMAC-shaped enough for this threat and needs no OpenSSL. The key is 32 random bytes from `/dev/urandom` written with mode 600 on first use. The guard refuses any command that names the key path. Records without a valid MAC are ignored; the cache removes them on read.

- *Alternative: move the cache outside the repository.* Rejected: a second location per clone complicates install, and the key already denies the agent the one thing it needs.
- *Alternative: rely on the guard alone.* Rejected: defense in depth is cheap here, and the guard has been wrong before.

### 4. The amend rule

`pending-attest` gains a second line: the HEAD at review time. post-commit attests when `HEAD^ == recorded`. When `HEAD^ == recorded^` it is an amend, and it attests only if `review_is_attested recorded`. This keeps message-only amends of reviewed commits free and closes the laundering path.

### 5. Chunked review for oversize diffs

`review_prepare` splits the file list greedily into chunks whose diffs each fit the cap, capped at `REVIEW_MAX_CHUNKS` (default 6). Every chunk is a full prompt with the rubric and its own attachments. A range passes only if every chunk passes. Above the chunk limit, pre-push refuses with the override named; pre-commit warns and passes unattested as today, since blocking a commit for size punishes the wrong moment.

- *Alternative: fail closed at push without chunking.* Rejected: a legitimate large refactor would be unpushable without the override, and the override would become routine.

### 6. Merge-base and per-remote base discovery

The base is `git merge-base <remote-tip> <local-tip>`. For a new branch, the remote's default branch comes from `refs/remotes/<remote>/HEAD`, else the remote branch with the nearest merge base, else the local tip's ancestry clamped to the root (`rev-list --max-parents=0` bound). The remote name comes from the push's URL argument, resolved through `git remote`.

### 7. Verdict, diagnostics, portability

A `[BLOCKER]` without a verdict is a BLOCK. Stderr goes to a file next to the output and its tail is printed on failure. The cache key uses `git hash-object --stdin`. Ignore globs are matched under `set -f`. Frame labels run under `LC_ALL=C`. The regress runner traps INT and TERM.

## Bash 3.2 and BSD compatibility

Tokenising uses `read -ra` on a space-padded copy of the command, which bash 3.2 supports. `printf -v` exists in 3.2. `git hash-object --stdin`, `git merge-base`, `git rev-list --max-parents=0` are all in git 2.x. `/dev/urandom` is present on macOS and Linux. No `mapfile`, no associative arrays, no GNU-only flags.

## Risks / Trade-offs

- **Over-blocking legitimate commands that mention a protected path with a write-shaped word** → the write-shaped list is explicit; probes assert reads stay allowed; dev mode remains the escape.
- **Upgrade forces one re-review per branch** → stated in the upgrade notice; cost is one model call per outgoing range.
- **A repository whose conf relied on shell** → the loader reports the offending line at every commit until fixed; the Roblox example is updated in this change.
- **Chunked reviews lose cross-file context** → chunks are split by file and each carries callers and attachments; the limit keeps the cost bounded.

## Migration Plan

1. Land the guard predicate and its probes first; it is independent and closes the worst hole.
2. Land config parsing, then records and the amend rule, then chunking and base discovery, each with its backstop probes.
3. `install.sh --upgrade` writes the new VERSION, moves the cache, and prints the re-review notice.
4. Rollback per commit; a downgraded hook ignores the MAC column because it never reads a fourth field.

## Open Questions

- Should `REVIEW_MAX_CHUNKS` default to 6 or scale with the cap?
- Should the key be per clone or per user (in `~/.config`), so worktrees and re-clones share it? Per clone is simpler and the guard already protects it.
