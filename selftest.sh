#!/usr/bin/env bash
# End-to-end self-test with no model calls: build a throwaway repository from
# examples/sample-project, install the hooks into it with install.sh, and run
# the guard, backstop and core probe suites there. Exit 1 on any failure.
#
#   bash selftest.sh                    # install + probes, sub-minute
#   SELFTEST_MODEL=1 bash selftest.sh   # also replay the sample regress suite
#                                       # (live model calls; needs `claude` or
#                                       # ANTHROPIC_API_KEY; minutes)
#
# The probe suites and the regress runner take the hook files from the
# working tree, so nothing after the install has to be committed.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
S="$(mktemp -d "${TMPDIR:-/tmp}/review-selftest.XXXXXX")"
trap 'rm -rf "$S";' EXIT
REPO="$S/repo"
HOOKS=".githooks"
GIT_ID=(-c user.name=selftest -c user.email=selftest@example.invalid)
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

mkdir -p "$REPO"
(cd "$ROOT/examples/sample-project" && tar -cf - app tests) | tar -xf - -C "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" "${GIT_ID[@]}" add -A
git -C "$REPO" "${GIT_ID[@]}" commit -q -m "sample project"

# --- install ----------------------------------------------------------------
out="$(bash "$ROOT/install.sh" "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "install.sh exits 0"; else bad "install.sh (rc=$rc): $out"; fi

# Every manifest path arrives: hooks executable, seeds created, and nothing
# under the hook and script directories that the manifest does not name.
: >"$S/expected-files"
while read -r kind path src; do
	case "$kind" in ''|'#'*|settings) continue ;; esac
	if [ ! -f "$REPO/$path" ]; then bad "$kind $path not installed"; continue; fi
	[ "$kind" = hook ] && { [ -x "$REPO/$path" ] || bad "$path is not executable"; }
	case "$path" in "$HOOKS"/*|scripts/*) echo "$path" >>"$S/expected-files" ;; esac
done <"$ROOT/MANIFEST"
(cd "$REPO" && find "$HOOKS" scripts -type f | LC_ALL=C sort) >"$S/installed-files"
if LC_ALL=C sort "$S/expected-files" | cmp -s - "$S/installed-files"; then
	ok "installed files match the manifest, hooks executable"
else
	bad "installed files differ from the manifest: $(LC_ALL=C sort "$S/expected-files" | diff - "$S/installed-files" | grep '^[<>]' | tr '\n' ' ')"
fi
[ "$(cat "$REPO/$HOOKS/VERSION")" = "$(cat "$ROOT/VERSION")" ] && ok "VERSION stamped into the hook directory" || bad "VERSION not stamped"
[ "$(git -C "$REPO" config --get core.hooksPath)" = "$HOOKS" ] && ok "core.hooksPath points at the hook directory" || bad "core.hooksPath not set"
grep -q no-bypass-guard "$REPO/.claude/settings.json" 2>/dev/null && ok "agent guard registered" || bad "agent guard not registered"

# A second install without a flag must refuse, naming both versions.
V="$(cat "$ROOT/VERSION")"
out="$(bash "$ROOT/install.sh" "$REPO" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "installed: $V, this source: $V" && ok "second install refuses, naming both versions" || bad "second install (rc=$rc): $out"

# --upgrade over an older install: manifest files replaced, seeds and the
# target's own settings entries kept, the guard registered once, the
# CHANGELOG printed.
(
	U="$S/upgrade"
	SETTINGS="$U/.claude/settings.json"
	git init -q "$U" && mkdir -p "$U/.claude" || exit 1
	printf '%s\n' '{"permissions": {"allow": ["Bash(ls:*)"]}, "hooks": {"PostToolUse": [{"matcher": "Bash", "hooks": []}]}}' >"$SETTINGS"
	bash "$ROOT/install.sh" "$U" >/dev/null 2>&1 || exit 1
	echo "0.1.0" >"$U/$HOOKS/VERSION"
	echo "# stale" >"$U/$HOOKS/pre-commit"
	echo "REVIEW_MODEL=mine" >"$U/$HOOKS/review.conf"
	echo "mine" >"$U/$HOOKS/regress/expected.tsv"
	out="$(bash "$ROOT/install.sh" "$U" 2>&1)"
	printf '%s' "$out" | grep -q "installed: 0.1.0, this source: $V" || { echo "plain install over 0.1.0: $out"; exit 1; }
	out="$(bash "$ROOT/install.sh" --upgrade "$U" 2>&1)" || { echo "upgrade: $out"; exit 1; }
	printf '%s' "$out" | grep -q "0.1.0 -> $V" || { echo "no version line: $out"; exit 1; }
	[ ! -f "$ROOT/CHANGELOG.md" ] || printf '%s' "$out" | grep -q "^## $V" || { echo "no changelog: $out"; exit 1; }
	cmp -s "$ROOT/$HOOKS/pre-commit" "$U/$HOOKS/pre-commit" && [ -x "$U/$HOOKS/pre-commit" ] || { echo "pre-commit not replaced"; exit 1; }
	[ "$(cat "$U/$HOOKS/VERSION")" = "$V" ] || { echo "VERSION not replaced"; exit 1; }
	[ "$(cat "$U/$HOOKS/review.conf")" = "REVIEW_MODEL=mine" ] || { echo "review.conf overwritten"; exit 1; }
	[ "$(cat "$U/$HOOKS/regress/expected.tsv")" = "mine" ] || { echo "expected.tsv overwritten"; exit 1; }
	grep -q '"Bash(ls:\*)"' "$SETTINGS" && grep -q PostToolUse "$SETTINGS" || { echo "settings entries lost"; exit 1; }
	# Without jq the merge is left to the user; with it, two entries (Bash and
	# the file tools), not four.
	if command -v jq >/dev/null 2>&1; then
		[ "$(grep -c no-bypass-guard "$SETTINGS")" -eq 2 ] || { echo "guard not registered exactly once"; exit 1; }
	fi
) >"$S/upgrade.log" 2>&1 && ok "--upgrade replaces the manifest files, keeps seeds and settings, prints the changelog" || bad "--upgrade: $(cat "$S/upgrade.log")"

# --- the rubric the reviewer would see ---------------------------------------
(
	cd "$REPO" || exit 1
	# shellcheck source=/dev/null
	. "$HOOKS/lib/review-core.sh"
	review_rubric_file "$REPO/$HOOKS" "$S/rubric.md"
	grep -q '^## Project rules' "$S/rubric.md" || exit 1
	# The project section must land before the output contract.
	[ "$(grep -n '^## Project rules' "$S/rubric.md" | cut -d: -f1)" -lt "$(grep -n '^## Output contract' "$S/rubric.md" | cut -d: -f1)" ]
) && ok "project rubric is spliced in before the output contract" || bad "rubric assembly"

# --- the reviewable-path filter and the lint step ----------------------------
# Both tests append to review.conf; the original is restored afterwards so
# the probe suites below run against the installed defaults.
cat "$REPO/$HOOKS/review.conf" >"$S/review.conf.orig"

# The review.conf loader itself (values, quoting, inert shell, environment
# precedence) is covered by scripts/core-probes.sh, run below.
(
	cd "$REPO" || exit 1
	printf 'REVIEW_EXTRA_IGNORE="docs/* *.snap"\n' >>"$HOOKS/review.conf"
	# shellcheck source=/dev/null
	. "$HOOKS/lib/review-core.sh"
	printf '%s\n' app/handlers.py docs/notes.md tests/x.snap package-lock.json vendor/lib.py | review_filter_paths
) | tr '\n' ' ' | grep -qx 'app/handlers.py ' && ok "path filter honours built-in and REVIEW_EXTRA_IGNORE globs" || bad "path filter"

(
	cd "$REPO" || exit 1
	printf 'REVIEW_LINT_CMD="false"\n' >>"$HOOKS/review.conf"
	printf 'x = 1\n' >>app/config.py
	git add app/config.py
	out="$(bash "$HOOKS/pre-commit" 2>&1)"; rc=$?
	git reset -q app/config.py && git checkout -q -- app/config.py
	[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'lint step'
) && ok "a failing REVIEW_LINT_CMD blocks before any model call" || bad "lint step"
(
	cd "$REPO" || exit 1
	printf 'REVIEW_LINT_CMD="definitely-not-an-installed-linter"\n' >>"$HOOKS/review.conf"
	printf 'y = 2\n' >>app/config.py
	git add app/config.py
	# No reviewer on this PATH either, so the run ends in the fail-open branch.
	out="$(PATH="/usr/bin:/bin" ANTHROPIC_API_KEY="" REVIEW_TIMEOUT=5 bash "$HOOKS/pre-commit" 2>&1)"; rc=$?
	git reset -q app/config.py && git checkout -q -- app/config.py
	[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'lint step skipped'
) && ok "a missing lint tool is skipped with a note, not treated as a failure" || bad "missing lint tool"
cat "$S/review.conf.orig" >"$REPO/$HOOKS/review.conf"

# --- probe suites inside the installed repository ----------------------------
(cd "$REPO" && bash scripts/guard-probes.sh >"$S/guard.log" 2>&1) && ok "guard probes: $(tail -1 "$S/guard.log")" || { bad "guard probes"; cat "$S/guard.log"; }
(cd "$REPO" && bash scripts/backstop-probes.sh >"$S/backstop.log" 2>&1) && ok "backstop probes: $(tail -1 "$S/backstop.log")" || { bad "backstop probes"; cat "$S/backstop.log"; }
(cd "$REPO" && bash scripts/core-probes.sh >"$S/core.log" 2>&1) && ok "core probes: $(tail -1 "$S/core.log")" || { bad "core probes"; cat "$S/core.log"; }

# --- optional: the sample regress suite against a live model -----------------
if [ "${SELFTEST_MODEL:-0}" = "1" ]; then
	(cd "$ROOT/examples/sample-project/regress" && tar -cf - .) | tar -xf - -C "$REPO/$HOOKS/regress"
	(cd "$REPO" && bash scripts/review-regress.sh) && ok "sample regress suite" || bad "sample regress suite"
fi

echo
echo "selftest: $fail failure(s)"
[ "$fail" -eq 0 ]
