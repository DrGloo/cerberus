#!/usr/bin/env bash
# Pre-PR review: runs the same rubric as the pre-commit hook over a branch diff.
#
#   scripts/review.sh                 # git diff main...HEAD
#   scripts/review.sh origin/develop  # diff against another base
#   scripts/review.sh --range A..B    # any diff range (used by the dry-run)
#
# Exits 1 on a BLOCKER, 0 otherwise. Reviewer failures print a warning and exit 0.
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

. "$ROOT_DIR/.githooks/lib/review-core.sh"

if [ "${1:-}" = "--range" ]; then
	RANGE="${2:?usage: review.sh --range <rev>..<rev>}"
	LABEL="diff $RANGE"
	SHOW_REV="${RANGE##*..}"
else
	BASE="${1:-main}"
	RANGE="$BASE...HEAD"
	LABEL="branch diff against $BASE"
	SHOW_REV="HEAD"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

RUBRIC="$TMP/rubric.md"
review_rubric_file "$REVIEW_HOOK_DIR" "$RUBRIC"

git diff --diff-filter=ACMR --name-only "$RANGE" | review_filter_paths >"$TMP/paths"
git diff --diff-filter=D --name-only "$RANGE" | review_filter_paths >"$TMP/deleted"
if [ ! -s "$TMP/paths" ] && [ ! -s "$TMP/deleted" ]; then
	echo "[review] nothing reviewable in $LABEL."
	exit 0
fi

paths=()
while IFS= read -r p; do paths+=("$p"); done <"$TMP/paths"
while IFS= read -r p; do paths+=("$p"); done <"$TMP/deleted"
git diff --unified=8 --diff-filter=ACMRD "$RANGE" -- "${paths[@]}" >"$TMP/diff"
[ -s "$TMP/diff" ] || exit 0

review_build_prompt "$TMP/diff" "$TMP/paths" "$TMP/deleted" "$RUBRIC" "$LABEL" "git show $SHOW_REV:" "$SHOW_REV" "$TMP/prompt"

PROMPT_BYTES="$(wc -c <"$TMP/prompt" | tr -d ' ')"
REVIEW_TIMEOUT="$(review_effective_timeout "$TMP/prompt")"
echo "[review] reviewing ${#paths[@]} file(s) in $LABEL with $REVIEW_MODEL (prompt ${PROMPT_BYTES} bytes, timeout ${REVIEW_TIMEOUT}s)..."
rc=0
review_call_model "$TMP/prompt" "$TMP/out" || rc=$?
case "$rc" in
	0) ;;
	124) echo "[review] WARNING: reviewer timed out after ${REVIEW_TIMEOUT}s."; exit 0 ;;
	3)
		echo "[review] WARNING: reviewer response violated the output contract; raw response follows."
		cat "$TMP/out"
		exit 0
		;;
	*)   echo "[review] WARNING: reviewer unavailable or returned an invalid response (exit $rc)."; exit 0 ;;
esac

echo
if review_report "$TMP/out"; then
	echo "[review] PASS"
	exit 0
fi
echo "[review] BLOCK — at least one BLOCKER finding above."
exit 1
