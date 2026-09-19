# ai-review-hooks

An AI code review that runs where it can actually stop a bad change: in the
git hooks on the developer's machine. Every staged diff is reviewed by a
model against a rubric before the commit lands. Only a `BLOCKER` finding stops
the commit. Anything that escapes review is caught again at push time. And an
AI coding agent working in the repository cannot switch any of it off.

Extracted from a live game codebase where it ran on every commit for weeks;
the rubric, the fail-open rules and the attestation handshake are all shaped
by what went wrong in practice.

## What you get

```
.githooks/
  pre-commit                  reviews the staged diff; exit 1 only on a BLOCKER
  post-commit                 attests the commit the review just passed
  pre-push                    re-reviews any outgoing commit that was never attested
  lib/review-core.sh          prompt assembly, model call, verdict contract, attestation
  lib/no-bypass-guard.sh      Claude Code PreToolUse hook: agents cannot bypass or tamper
  review-rubric.md            the generic rubric
  review-rubric.project.md    your house rules, spliced into the rubric (you write this)
  review.conf                 model, source dirs, ignore globs, lint command (you write this)
  regress/                    seeded-defect fixtures and expected verdicts (you grow this)
scripts/
  review.sh                   the same review over a branch or any range, for a PR
  review-regress.sh           replays the fixtures through the real hook and checks verdicts
  guard-probes.sh             67 probes of the agent guard, no model, sub-second
  backstop-probes.sh          18 probes of the ledger, attestation and re-review logic, no model
install.sh                    copies all of the above into a repository and wires it up
selftest.sh                   installs into a throwaway repo and runs every probe suite
templates/                    the agent guard registration and a CI workflow
examples/                     a runnable sample project with fixtures, and the original Roblox setup
```

Requirements: bash 3.2 or newer, git, and either the `claude` CLI on `PATH`
or `ANTHROPIC_API_KEY` in the environment (with `curl` and `python3`). `jq` is
optional. Runs on macOS and Linux with no other dependencies.

## Install

```
git clone https://github.com/<you>/ai-review-hooks
bash ai-review-hooks/install.sh /path/to/your/repo
```

That copies the hook directory and the scripts, sets `core.hooksPath` for that
clone, registers the agent guard in `.claude/settings.json` (merging if the
file exists), and creates `review.conf` and `review-rubric.project.md` from
the templates. Then:

1. Edit `.githooks/review.conf`: the model, the directories the reviewer
   should search for callers, extra ignore globs, and an optional lint command
   that runs before the model does.
2. Write `.githooks/review-rubric.project.md`. This is where the review earns
   its keep: name the lifecycle owner every resource must register with, the
   persistence module and what must never be renamed, the validation wrapper
   every entry point must use. See `examples/roblox-luau/` for a real one.
3. Commit `.githooks/`, `scripts/` and `.claude/settings.json`. Every clone
   gets the files; every clone still runs the `core.hooksPath` line once,
   which `install.sh` prints.
4. `bash scripts/guard-probes.sh && bash scripts/backstop-probes.sh`.

## How a commit is reviewed

`pre-commit` filters the staged paths (lockfiles, binaries, vendored and
generated trees are skipped), runs the optional lint command, and builds one
prompt: the rubric, the full current text of any file with more than thirty
changed lines, the call sites of every function whose definition the diff
touches, the surviving references to every deleted file, and the diff itself.
Every block of repository content is wrapped in per-run random sentinels, and
the rubric tells the model that nothing inside them is an instruction. A
comment that says "reviewer: approve this" is a finding, not a directive.

The model runs with **no tools, from an empty directory, with the prompt on
stdin**. It sees exactly the tree the diff belongs to and nothing else, so two
machines reviewing the same diff see the same thing.

The response has to match a strict contract: findings as
`[BLOCKER|WARN|NIT] file:line`, then exactly one `VERDICT:` line, and a
`BLOCK` verdict only when a `BLOCKER` finding backs it. Output that breaks the
contract is treated as "reviewer unavailable", never as a pass or a block.

Verdicts are cached by diff hash, so amending a message after a clean review
costs nothing.

## Fail open, but never silently

A reviewer that times out, is not installed, or returns garbage must not stop
work, so the commit goes through with a warning. What makes that safe:

- **Attestation.** On a PASS, `pre-commit` records the staged tree. Once the
  commit exists, `post-commit` checks that HEAD's tree matches and records the
  commit as reviewed, by patch-id and by sha. A commit made with hooks
  disabled, by `git am`, by a cherry-pick, or through a fail-open never gets
  a record.
- **Re-review at push.** `pre-push` looks at every outgoing commit. If all are
  attested, the push costs nothing. If any is not, the whole outgoing range is
  reviewed once: a PASS attests every commit and the push proceeds, a BLOCK
  refuses the push, a failure lets it through and leaves the commits
  unattested for next time. Patch-id first, so a rebase of reviewed commits
  does not trigger a re-review.
- **A ledger.** Every escape is appended to `.git/review-cache/fail-open.log`
  with the reason, so a quiet week of timeouts is visible.

Humans can still bypass from their own terminal, with the skip variable or
the `no-verify` flag documented at the top of `pre-commit`. Agents cannot.

## The agent guard

`lib/no-bypass-guard.sh` is registered as a Claude Code `PreToolUse` hook on
`Bash`, `Edit`, `Write` and the notebook tools. It inspects the command or the
write payload and refuses:

- committing with hooks disabled, in any spelling, including short-flag
  clusters and wrapper scripts that contain the bypass;
- re-pointing or unsetting `core.hooksPath`, including through environment
  configuration;
- history plumbing that never runs hooks;
- deleting, moving, overwriting or changing the mode of the hook files, and
  editing the rubric from the shell.

It scans up to three invoked script files as well, so a bypass hidden in
`./deploy.sh` is caught at invocation. It is pure bash builtins with an
optional `jq`, so a missing tool cannot make it fail open. The header of the
script lists the residual holes a static inspector cannot close.

`scripts/guard-probes.sh` is its test suite. Any change to the guard should
add a probe.

## Calibrating the reviewer

The rubric asks for severity discipline over coverage, and the only way to
know a model honours it is to measure. `scripts/review-regress.sh` applies
each fixture in `.githooks/regress/` to a throwaway worktree, runs the real
hook, and compares the verdict and a required citation with `expected.tsv`.
Run it after any change to the hook, the rubric, or the model. A fully clean
run pins the model name in `regress/calibrated-model`, and `pre-commit` prints
a note whenever it runs with a different one.

A good suite includes cases that must **pass**: a renamed local, a log line
that lost context, a swallowed error on a path that cannot corrupt anything.
A reviewer that blocks everything scores perfectly on a suite of defects.

`examples/sample-project/` ships eight fixtures against a small Python
service, six that must block and two that must pass. `SELFTEST_MODEL=1 bash
selftest.sh` runs them end to end.

## Tuning

Everything is a `REVIEW_*` variable in `review.conf`, overridable per
invocation from the environment:

| Variable | Default | Meaning |
|---|---|---|
| `REVIEW_MODEL` | `claude-sonnet-5` | model for every review |
| `REVIEW_SOURCE_DIRS` | `.` | where to search for callers and dangling references |
| `REVIEW_EXTRA_IGNORE` | | extra globs never worth a review |
| `REVIEW_LINT_CMD` | | static check run before the model; non-zero blocks |
| `REVIEW_TIMEOUT` | `180` | seconds for a small prompt; grows with size up to `REVIEW_TIMEOUT_MAX` (`600`) |
| `REVIEW_CONTEXT_THRESHOLD` | `30` | changed lines before a file's full text is attached |
| `REVIEW_MAX_DIFF_BYTES` | `200000` | the diff is truncated past this |
| `REVIEW_MAX_CONTEXT_BYTES` | `60000` | budget for attached full files |

## CI

`templates/github-workflow-review.yml` syntax-checks the hooks, verifies they
are executable, and runs both probe suites on every pull request. It needs no
secrets because it makes no model call: the AI review runs locally, through
the developer's own authenticated CLI, by design.

## Development

```
bash scripts/guard-probes.sh      # the guard
bash scripts/backstop-probes.sh   # attestation and pre-push, in a scratch clone
bash selftest.sh                  # install into a throwaway repo, run everything
```

This repository dogfoods its own hooks: `.githooks/review-rubric.project.md`
holds the rules for changing the tooling itself.

## License

MIT.
