## Project rules: this repository

This repository *is* the review tooling: bash hooks, a shared library, probe
suites, and fixtures. Judge changes here by what they do to the guarantees the
README promises.

- **Fail-open on reviewer failure, fail-closed on BLOCK.** A timeout, a missing
  CLI, a malformed response, or a crash must let the commit or push through
  with a loud warning and no attestation. Only a `VERDICT: BLOCK` backed by a
  `[BLOCKER]` line may refuse. A change that turns any failure path into a
  refusal, or any BLOCK into a pass, is a BLOCKER.
- **Attestation is the only thing that skips a re-review.** `post-commit` may
  attest HEAD only when its tree equals the one `pre-commit` reviewed;
  `pre-push` may attest only commits it just reviewed clean. Any other write to
  `attested.log` is a BLOCKER.
- **Every untrusted block stays inside the sentinels.** New prompt sections
  built from repository content must go through `review_untrusted`. A block
  outside the sentinels reopens the injection surface: BLOCKER.
- **The reviewer runs with no tools, from an empty directory, on stdin.** Do
  not add tools back to `review_claude_exec`, move its working directory into
  the repository, or pass the prompt as an argument.
- **The guard is pure bash builtins.** `no-bypass-guard.sh` must not depend
  on any external command to reach a verdict (jq is optional). A guard that
  fails open when a tool is missing is a BLOCKER.
- **Probe suites are the contract.** A behaviour change in a hook without a
  matching change in `scripts/guard-probes.sh` or `scripts/backstop-probes.sh`
  is at least a WARN naming the missing probe.
- **Portability.** Scripts run on macOS bash 3.2 and Linux: no `mapfile`,
  no `declare -A`, no GNU-only flags (`sed -i ''` vs `sed -i`, no `timeout`
  binary, no `readlink -f`). Flag any of these.
- Indentation is tabs in shell files. `set -u` at the top of every hook.
