#!/usr/bin/env bash
# End-to-end self-test with no model calls: build a throwaway repository from
# examples/sample-project, install the hooks into it with install.sh, and run
# the guard and backstop probe suites there. Exit 1 on any failure.
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

for f in pre-commit post-commit pre-push lib/no-bypass-guard.sh; do
	if [ -x "$REPO/$HOOKS/$f" ]; then ok "$f is executable"; else bad "$f is not executable"; fi
done
[ "$(git -C "$REPO" config --get core.hooksPath)" = "$HOOKS" ] && ok "core.hooksPath points at the hook directory" || bad "core.hooksPath not set"
[ -f "$REPO/$HOOKS/review.conf" ] && ok "review.conf created from the example" || bad "review.conf missing"
[ -f "$REPO/$HOOKS/review-rubric.project.md" ] && ok "project rubric created from the template" || bad "project rubric missing"
[ -f "$REPO/.claude/settings.json" ] && grep -q no-bypass-guard "$REPO/.claude/settings.json" && ok "agent guard registered" || bad "agent guard not registered"

# A second install without --force must refuse and leave the files alone.
out="$(bash "$ROOT/install.sh" "$REPO" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "second install refuses without --force" || bad "second install (rc=$rc): $out"

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

# --- review.conf values take effect, and the environment still wins ----------
(
	cd "$REPO" || exit 1
	printf 'REVIEW_MODEL="conf-model"\nREVIEW_TIMEOUT=42\n' >>"$HOOKS/review.conf"
	# shellcheck source=/dev/null
	. "$HOOKS/lib/review-core.sh"
	[ "$REVIEW_MODEL" = "conf-model" ] && [ "$REVIEW_TIMEOUT" = "42" ]
) && ok "review.conf sets the model and timeout" || bad "review.conf values ignored"
cat "$S/review.conf.orig" >"$REPO/$HOOKS/review.conf"
(
	cd "$REPO" || exit 1
	printf 'REVIEW_MODEL="${REVIEW_MODEL:-conf-model}"\n' >>"$HOOKS/review.conf"
	export REVIEW_MODEL="env-model"
	# shellcheck source=/dev/null
	. "$HOOKS/lib/review-core.sh"
	[ "$REVIEW_MODEL" = "env-model" ]
) && ok "environment overrides review.conf" || bad "environment override lost"
cat "$S/review.conf.orig" >"$REPO/$HOOKS/review.conf"

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

# --- optional: the sample regress suite against a live model -----------------
if [ "${SELFTEST_MODEL:-0}" = "1" ]; then
	(cd "$ROOT/examples/sample-project/regress" && tar -cf - .) | tar -xf - -C "$REPO/$HOOKS/regress"
	(cd "$REPO" && bash scripts/review-regress.sh) && ok "sample regress suite" || bad "sample regress suite"
fi

echo
echo "selftest: $fail failure(s)"
[ "$fail" -eq 0 ]
