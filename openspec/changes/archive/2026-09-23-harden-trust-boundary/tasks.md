## 1. Guard: protected paths and write shapes

- [x] 1.1 `no-bypass-guard.sh`: add `is_protected_path` covering the hook tree, the settings file, the review and probe scripts, and any path under `.git/` or a worktree git directory, case-insensitive, relative and absolute
- [x] 1.2 `no-bypass-guard.sh`: tokenise the command and refuse a protected path as the target of `>`, `>>`, `>|`, or in the same simple command as a write-shaped word (existing verbs plus `tee`, `sed -i`, `ln`, `dd`, `install`, `patch`, interpreters with `-c`/`-e`)
- [x] 1.3 `no-bypass-guard.sh`: refuse any command naming the attestation key path
- [x] 1.4 `no-bypass-guard.sh`: for file-tool payloads, judge the path only; stop running the command patterns and the script scanner over file content; handle multi-edit payloads by top-level path
- [x] 1.5 `guard-probes.sh`: probes for each redirect and tool shape above, reads that must stay allowed, the key path, `.git/` targets, a Write whose content mentions the bypass flag, and a manifest sweep that refuses every manifest path as a write target

## 2. Config as data

- [x] 2.1 `review-core.sh`: `review_load_conf` parsing `KEY=VALUE` with an allowlist, quote stripping, no expansion, environment precedence, and a warning per rejected line
- [x] 2.2 Remove the `${VAR:-}` wrappers from `review.conf.example` and `examples/roblox-luau/review.conf`; update the README configuration section
- [x] 2.3 `core-probes.sh` (new suite): plain assignment, quoted value, shell in the file is inert and reported, environment wins

## 3. Authenticated records and the common cache

- [x] 3.1 `review-core.sh`: cache directory from `git rev-parse --git-common-dir`; key creation with mode 600; `review_mac`
- [x] 3.2 `review_attest` writes the MAC column; `review_is_attested` verifies and ignores bad records
- [x] 3.3 `pre-commit`: cache files carry a MAC header; a failing file is a miss and is removed
- [x] 3.4 `backstop-probes.sh`: forged attestation line ignored, planted cache verdict ignored and removed, genuine records honoured, worktree attestation visible from the main checkout

## 4. The amend rule and silent-attest paths

- [x] 4.1 `pre-commit`: record HEAD alongside the tree in `pending-attest`; `post-commit`: attest on parent match, on amend only over an attested base
- [x] 4.2 `pre-commit`, `review.sh`: NUL-separated path lists; non-empty paths with an empty diff and a failed `mktemp` become ledgered warn-and-pass, and a WARNING line in `review.sh`
- [x] 4.3 `backstop-probes.sh`: amend after fail-open is not attested, amend after a clean review is attested, accented filename is reviewed, unwritable `TMPDIR` warns and attests nothing

## 5. Push base and oversize ranges

- [x] 5.1 `pre-push`: merge-base with the remote tip; per-remote default-branch discovery; ancestry clamp for the last resort; no `HEAD~N`; a printed note when the base is the tip
- [x] 5.2 `review-core.sh`: `review_prepare` chunks an oversize file list; every chunk reviewed; `REVIEW_MAX_CHUNKS`; pre-push refuses above the limit with `REVIEW_ALLOW_OVERSIZE=1` as the override; pre-commit chunks and may attest
- [x] 5.3 `backstop-probes.sh`: branch behind main sees no phantom deletions, five-commit repo with `trunk`, first push of the default branch, three clean chunks attest, one bad chunk refuses, too many chunks refuses then passes unattested with the override

## 6. Verdict, diagnostics, portability, install

- [x] 6.1 `review-core.sh`: `[BLOCKER]` without a verdict is BLOCK; verdict line tolerates trailing punctuation and case; stderr captured and shown on failure; curl path surfaces the API error and raises the token limit; crash exit not reported as timeout
- [x] 6.2 `review-core.sh`: cache key via `git hash-object`; ignore globs under `set -f`; `LC_ALL=C` in the label sanitizer; `review-regress.sh` traps INT and TERM and feeds `</dev/null` to the hook
- [x] 6.3 `install.sh`: flags in any position; `--upgrade` replaces manifest files only, moves the cache to the common directory, prints the re-review notice; `expected.tsv` and patches are create-only
- [x] 6.4 `core-probes.sh` and `selftest.sh`: cut-off blocker blocks, decorated verdict passes, ignore glob with an existing subdirectory, cache works without `shasum`, upgrade keeps three fixtures
- [x] 6.5 Guard header and README: list the accepted residual holes from the design, the key path, the override, and the upgrade notice

## 7. Verification

- [x] 7.1 Run `selftest.sh`, `guard-probes.sh`, `backstop-probes.sh`, `core-probes.sh` and record the counts in the README
- [x] 7.2 `SELFTEST_MODEL=1 bash selftest.sh` still passes 8 for 8

## Dependencies

- Group 1 is independent and lands first.
- Group 2 precedes groups 3 to 6, which read config through the new loader.
- Group 3 precedes group 4, which records into the authenticated log.
- The dedupe change waits for this one; it will fold `review_prepare` into the shared driver.
