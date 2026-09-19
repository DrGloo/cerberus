#!/usr/bin/env bash
# No-model unit tests for the review backstop: ledger writes in pre-commit
# and branch logic in pre-push. Runs in a scratch clone with a stubbed
# scripts/review.sh; sub-second, no secrets.
#
# NOTE: contains hook-bypass trigger strings BY DESIGN (they exercise the
# ledger paths); the guard's script scanner exempts exactly this path.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
S="$(mktemp -d "${TMPDIR:-/tmp}/backstop.XXXXXX")"
trap 'rm -rf "$S"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

git clone -q "$R" "$S/repo"
cd "$S/repo"
rm -rf .githooks scripts
cp -R "$R/.githooks" .githooks
mkdir -p scripts && cp "$R/scripts/review.sh" scripts/review.sh
GITDIR="$(git rev-parse --git-dir)"
LEDGER="$GITDIR/review-cache/fail-open.log"
TAB="$(printf '\t')"

# --- 3.1a: REVIEW_SKIP is ledgered and exits 0 -------------------------------
REVIEW_SKIP=1 bash .githooks/pre-commit >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$LEDGER" ] && grep -q "REVIEW_SKIP" "$LEDGER"; then
	ok "skip ledgered (rc=0, reason recorded)"
else
	bad "skip ledgered (rc=$rc, ledger: $(cat "$LEDGER" 2>/dev/null))"
fi
lines_before="$(wc -l <"$LEDGER" | tr -d ' ')"
[ "$lines_before" -eq 1 ] && ok "exactly one entry" || bad "expected 1 entry, got $lines_before"
grep -q "${TAB}$(git symbolic-ref --short -q HEAD || echo detached)${TAB}" "$LEDGER" && ok "entry carries branch" || bad "branch field missing"

# --- 3.1b: fail-open (no reviewer available) is ledgered ---------------------
printf 'x' >x.txt && git add x.txt
PATH="/usr/bin:/bin" ANTHROPIC_API_KEY="" REVIEW_TIMEOUT=5 bash .githooks/pre-commit >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l <"$LEDGER" | tr -d ' ')" -eq 2 ]; then
	ok "fail-open ledgered (rc=0, second entry)"
else
	bad "fail-open ledgered (rc=$rc, lines=$(wc -l <"$LEDGER"))"
fi

# --- 3.1c: cap holds at 200 --------------------------------------------------
for i in $(seq 1 210); do printf '2026-01-01T00:00:00Z\tmain\tpad\t-\n'; done >>"$LEDGER"
REVIEW_SKIP=1 bash .githooks/pre-commit >/dev/null 2>&1
n="$(wc -l <"$LEDGER" | tr -d ' ')"
[ "$n" -le 200 ] && ok "cap holds (n=$n)" || bad "cap exceeded (n=$n)"


# --- 3.3: the attestation handshake ------------------------------------------
# From here on the reviewer is a stub `claude` on PATH that answers PASS, so
# the PASS path of the staged-diff hook (pending-attest) and the attestation
# in post-commit run without a model. Hooks are invoked by hand through
# $HOOKS: the scratch clone has no hooks path configured, so a plain
# `git commit` runs none of them.
HOOKS=".githooks"
STUBBIN="$S/bin"
mkdir -p "$STUBBIN"
printf '%s\n' '#!/bin/sh' 'cat >/dev/null' 'echo "VERDICT: PASS"' >"$STUBBIN/claude"
chmod +x "$STUBBIN/claude";
export PATH="$STUBBIN:$PATH"
ATTEST="$GITDIR/review-cache/attested.log"
PENDING="$GITDIR/review-cache/pending-attest"
checks=5 # the ledger checks above
ok() { echo "PASS: $1"; checks=$((checks + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); checks=$((checks + 1)); }
attested() { [ -s "$ATTEST" ] && grep -q "${TAB}$1${TAB}" "$ATTEST"; }

# 3.3a: a PASS leaves pending-attest holding exactly the staged tree
printf 'a' >a.txt && git add a.txt
out="$(bash "$HOOKS/pre-commit" 2>&1)"; rc=$?
tree="$(git write-tree)"
if [ "$rc" -eq 0 ] && [ "$(cat "$PENDING" 2>/dev/null)" = "$tree" ]; then
	ok "PASS writes pending-attest = staged tree"
else
	bad "pending-attest after PASS (rc=$rc out=$out)"
fi

# 3.3b: post-commit attests HEAD when its tree matches, and consumes the file
git commit -q -m "a";
bash "$HOOKS/post-commit"
sha_a="$(git rev-parse HEAD)"
if [ ! -e "$PENDING" ] && attested "$sha_a"; then
	ok "post-commit attests the matching commit and clears pending"
else
	bad "post-commit attest (pending=$(cat "$PENDING" 2>/dev/null) log=$(cat "$ATTEST" 2>/dev/null))"
fi

# 3.3c: a stale pending tree (review passed, commit aborted, other commit made)
# is consumed but attests nothing
printf '%s\n' 4b825dc642cb6eb9a060e54bf8d69288fbee4904 >"$PENDING"
printf 'b' >b.txt && git add b.txt && git commit -q -m "b";
bash "$HOOKS/post-commit"
sha_b="$(git rev-parse HEAD)"
if [ ! -e "$PENDING" ] && ! attested "$sha_b"; then
	ok "stale pending-attest is consumed and attests nothing"
else
	bad "stale pending (pending=$(cat "$PENDING" 2>/dev/null) attested_b=$(attested "$sha_b" && echo yes || echo no))"
fi

# 3.3d: fail-open (no reviewer reachable) never marks the tree reviewed
printf 'c' >c.txt && git add c.txt
PATH="/usr/bin:/bin" ANTHROPIC_API_KEY="" REVIEW_TIMEOUT=5 bash "$HOOKS/pre-commit" >/dev/null 2>&1
if [ ! -e "$PENDING" ]; then
	ok "fail-open leaves no pending-attest"
else
	bad "fail-open wrote pending-attest"
fi
git commit -q -m "c";
sha_c="$(git rev-parse HEAD)"

# 3.3e: a diff over REVIEW_MAX_DIFF_BYTES is reviewed truncated and never
# attested, on the first run and on a re-run of the same diff (no cache)
printf '%0400d' 0 >big.txt && git add big.txt
out="$(REVIEW_MAX_DIFF_BYTES=100 bash "$HOOKS/pre-commit" 2>&1)"; rc=$?
out2="$(REVIEW_MAX_DIFF_BYTES=100 bash "$HOOKS/pre-commit" 2>&1)"; rc2=$?
if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && [ ! -e "$PENDING" ] \
	&& printf '%s' "$out" | grep -q "TRUNCATED" && printf '%s' "$out2" | grep -q "TRUNCATED" \
	&& grep -q "REVIEW_MAX_DIFF_BYTES" "$LEDGER"; then
	ok "truncated diff passes without attestation, ledgered, uncached"
else
	bad "truncated diff (rc=$rc rc2=$rc2 pending=$([ -e "$PENDING" ] && echo yes || echo no) out2=$out2)"
fi
git reset -q big.txt

# 3.3f: the range reviewer reports a truncated PASS as a WARNING line, which
# is what pre-push keys on to leave the range unattested
out="$(REVIEW_MAX_DIFF_BYTES=10 bash scripts/review.sh --range "$sha_a..$sha_c" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^\[review\] WARNING:.*truncated'; then
	ok "range review of a truncated diff warns instead of passing clean"
else
	bad "range truncation (rc=$rc out=$out)"
fi

# --- 3.4: pre-push re-reviews only what was never attested ------------------
# Ref lines as git supplies them: <local-ref> <local-sha> <remote-ref> <remote-sha>.
BR="$(git symbolic-ref --short HEAD)"
push_line() { printf 'refs/heads/%s %s refs/heads/%s %s\n' "$BR" "$(git rev-parse HEAD)" "$BR" "$1"; }
stub_review() { printf '%s\n' '#!/usr/bin/env bash' "$1" >scripts/review.sh; }

# 3.4a: range b..c holds one unattested commit; a clean stub review attests it
stub_review 'echo "STUB REVIEW RAN"; exit 0'
out="$(push_line "$sha_b" | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "STUB REVIEW RAN" && attested "$sha_c"; then
	ok "unattested commit is re-reviewed and attested on PASS"
else
	bad "re-review PASS path (rc=$rc out=$out)"
fi

# 3.4b: range a..c: b is still unattested, so the range is reviewed once more
# and every outgoing commit ends up attested
out="$(push_line "$sha_a" | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "STUB REVIEW RAN" && attested "$sha_b" && attested "$sha_c"; then
	ok "a range with one unattested commit is reviewed and fully attested"
else
	bad "mixed range (rc=$rc out=$out)"
fi

# 3.4c: the same push again costs nothing: no stub call, silent, rc 0
out="$(push_line "$sha_a" | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
	ok "fully attested range makes no review call"
else
	bad "attested range not silent (rc=$rc out=$out)"
fi

# 3.4d: BLOCK refuses the push and attests nothing
printf 'd' >d.txt && git add d.txt && git commit -q -m "d";
sha_d="$(git rev-parse HEAD)"
stub_review 'echo "[review] BLOCK — at least one BLOCKER finding above."; exit 1'
out="$(push_line "$sha_c" | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && ! attested "$sha_d"; then
	ok "BLOCK refuses the push, nothing attested"
else
	bad "BLOCK path (rc=$rc attested_d=$(attested "$sha_d" && echo yes || echo no))"
fi

# 3.4e: a crashing reviewer (non-zero, no BLOCK verdict) is never a BLOCK:
# push allowed, commit stays unattested for the next push
stub_review 'exit 127'
out="$(push_line "$sha_c" | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ! attested "$sha_d" && printf '%s' "$out" | grep -q "unavailable or crashed"; then
	ok "reviewer crash allows the push and attests nothing"
else
	bad "crash path (rc=$rc out=$out)"
fi

# 3.4f: an unavailable reviewer (WARNING, exit 0) behaves the same way
stub_review 'echo "[review] WARNING: reviewer unavailable or returned an invalid response (exit 1)."; exit 0'
out="$(push_line "$sha_c" | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ! attested "$sha_d"; then
	ok "unavailable reviewer allows the push and attests nothing"
else
	bad "unavailable path (rc=$rc out=$out)"
fi

# 3.4g: attestation survives a rewrite that keeps the patch: amend the message
stub_review 'echo "STUB REVIEW RAN"; exit 0'
push_line "$sha_c" | bash "$HOOKS/pre-push" >/dev/null 2>&1
git commit -q --amend -m "d, reworded";
sha_d2="$(git rev-parse HEAD)"
out="$(push_line "$sha_c" | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$sha_d2" != "$sha_d" ]; then
	ok "amended commit with the same patch-id is still attested"
else
	bad "patch-id stability (rc=$rc out=$out)"
fi

# 3.4h: deleting a remote ref reviews nothing
out="$(printf 'refs/heads/%s %s refs/heads/%s %s\n' "$BR" 0000000000000000000000000000000000000000 "$BR" "$sha_c" | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
	ok "ref deletion is free"
else
	bad "ref deletion (rc=$rc out=$out)"
fi

# 3.4i: a remote sha that does not resolve locally must never count as
# reviewed clean: the push is allowed with a note and nothing is attested
printf 'e' >e.txt && git add e.txt && git commit -q -m "e";
sha_e="$(git rev-parse HEAD)"
out="$(push_line ffffffffffffffffffffffffffffffffffffffff | bash "$HOOKS/pre-push" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "cannot resolve" && ! attested "$sha_e"; then
	ok "unresolvable base allows the push and attests nothing"
else
	bad "unresolvable base (rc=$rc out=$out)"
fi

echo
echo "backstop-probes: $((checks - fail))/$checks checks passed"
[ "$fail" -eq 0 ]
