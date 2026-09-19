#!/usr/bin/env bash
# Regression suite for the pre-commit AI review hook itself.
#
# Each .githooks/regress/*.patch seeds one known defect class into a throwaway
# worktree; the real pre-commit hook then reviews it and the verdict is checked
# against .githooks/regress/expected.tsv (case, BLOCK|PASS, required citation
# substring or "-"). Run after any change to the hook, the rubric, or the model.
#
#   scripts/review-regress.sh            # all cases
#   scripts/review-regress.sh S02 S11    # just these
#
# Every case is a live model call: expect ~30-60s per case.
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGRESS_DIR="$ROOT_DIR/.githooks/regress"
EXPECTED="$REGRESS_DIR/expected.tsv"

# Regress cases carry a longer per-case timeout than the commit-time default.
# Set it BEFORE sourcing review-core.sh, whose own `:-180` default would
# otherwise win and silently tighten every case to 180s.
export REVIEW_TIMEOUT="${REVIEW_TIMEOUT:-300}"

# For REVIEW_MODEL (defaults live in one place) — used by the calibration pin.
. "$ROOT_DIR/.githooks/lib/review-core.sh"

[ -f "$EXPECTED" ] || { echo "missing $EXPECTED"; exit 2; }

# Guard regressions must fail the suite before any model call is spent.
if ! probe_out="$(bash "$ROOT_DIR/scripts/guard-probes.sh" 2>&1)"; then
	printf '%s\n' "$probe_out"
	echo "guard probes FAILED — fix the guard before measuring the reviewer"
	exit 2
fi

filter=("$@")
wanted() {
	[ "${#filter[@]}" -eq 0 ] && return 0
	local f
	for f in "${filter[@]}"; do
		case "$1" in "$f"*) return 0 ;; esac
	done
	return 1
}

pass=0 fail=0
while IFS=$'\t' read -r case_id expect cite; do
	case "$case_id" in ''|'#'*) continue ;; esac
	wanted "$case_id" || continue
	patch="$REGRESS_DIR/$case_id.patch"
	[ -f "$patch" ] || { echo "FAIL $case_id: missing $patch"; fail=$((fail+1)); continue; }

	wt="$(mktemp -d "${TMPDIR:-/tmp}/review-regress.XXXXXX")/wt"
	git -C "$ROOT_DIR" worktree add -q --detach "$wt" HEAD || { echo "FAIL $case_id: worktree"; fail=$((fail+1)); continue; }
	# The hook under test is the *current* one, not the committed one.
	rm -rf "$wt/.githooks"
	cp -R "$ROOT_DIR/.githooks" "$wt/.githooks"

	# Apply and review in separate steps: a patch that fails to apply must be
	# its own failure, never mistaken for the hook blocking the commit.
	if ! (cd "$wt" && git apply --index "$patch" 2>&1); then
		echo "FAIL $case_id: patch did not apply"
		fail=$((fail+1))
		git -C "$ROOT_DIR" worktree remove --force "$wt" >/dev/null 2>&1
		rm -rf "$(dirname "$wt")"
		continue
	fi
	out="$(cd "$wt" && REVIEW_TIMEOUT="${REVIEW_TIMEOUT:-300}" bash .githooks/pre-commit 2>&1)"
	rc=$?

	verdict=PASS
	[ "$rc" -ne 0 ] && verdict=BLOCK
	ok=1
	[ "$verdict" = "$expect" ] || ok=0
	if [ "$ok" -eq 1 ] && [ "$cite" != "-" ]; then
		# -F: the citation is a literal substring, not a regex — a '.' in a
		# path (aftman.toml) or an '@*' in a version must match themselves.
		if [ "$expect" = "BLOCK" ]; then
			printf '%s' "$out" | grep -qF "$cite" || ok=0
		else
			# PASS with a required citation = an advisory WARN must be present.
			printf '%s' "$out" | grep '^\[WARN\]' | grep -qF "$cite" || ok=0
		fi
	fi
	# A skipped review (reviewer down, contract violation) is a FAIL here even
	# though the hook fails open on purpose: the suite exists to measure the
	# reviewer, and "unavailable" measured nothing.
	printf '%s' "$out" | grep -q '^\[review\] WARNING:' && ok=0

	if [ "$ok" -eq 1 ]; then
		echo "PASS $case_id ($verdict)"
		pass=$((pass+1))
	else
		echo "FAIL $case_id: expected $expect${cite:+ citing '$cite'}, got $verdict"
		printf '%s\n' "$out" | sed 's/^/    /'
		fail=$((fail+1))
	fi

	git -C "$ROOT_DIR" worktree remove --force "$wt" >/dev/null 2>&1
	rm -rf "$(dirname "$wt")"
done <"$EXPECTED"

echo
echo "regress: $pass passed, $fail failed"

# An unfiltered zero-failure run is the calibration event: pin the model the
# expectations were just verified against. Filtered runs never touch the pin.
if [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ] && [ "${#filter[@]}" -eq 0 ]; then
	printf '%s\n' "$REVIEW_MODEL" >"$REGRESS_DIR/calibrated-model"
	echo "regress: calibrated-model pinned to $REVIEW_MODEL"
fi

[ "$fail" -eq 0 ]
