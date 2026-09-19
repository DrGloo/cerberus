#!/usr/bin/env bash
# Probe suite for .githooks/lib/no-bypass-guard.sh. No model calls; sub-second.
# Every probe asserts an exact guard rc: 2 (blocked) or 0 (allowed); any
# mismatch is printed and the suite exits 1. review-regress.sh runs this first
# so a guard regression fails a suite run before any model call.
#
# NOTE: this file contains bypass trigger strings BY DESIGN — they are the
# test corpus. The guard's script scanner exempts exactly this path.
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
G="$ROOT_DIR/.githooks/lib/no-bypass-guard.sh"

fail=0
total=0
want=2
expect_block() { want=2; }
expect_allow() { want=0; }

note() {
	if [ "$1" -ne "$want" ]; then
		echo "MISMATCH rc=$1 want=$want :: $2"
		fail=$((fail + 1))
	fi
	total=$((total + 1))
}

# Normal path: valid JSON payload, jq available to the guard.
t() {
	local rc=0
	jq -cn --arg c "$1" '{tool_input:{command:$c}}' | bash "$G" >/dev/null 2>&1 || rc=$?
	note "$rc" "$1"
}

# Degraded path: guard runs with no jq (empty PATH) and must scan raw JSON.
traw() {
	local json rc=0
	json="$(jq -cn --arg c "$1" '{tool_input:{command:$c}}')"
	printf '%s' "$json" | PATH=/nonexistent /bin/bash "$G" >/dev/null 2>&1 || rc=$?
	note "$rc" "no-jq: $1"
}

# Run the guard with a specific working directory (for ./relative probes).
tcd() {
	local dir="$1" cmdstr="$2" rc=0
	jq -cn --arg c "$cmdstr" '{tool_input:{command:$c}}' | (cd "$dir" && bash "$G") >/dev/null 2>&1 || rc=$?
	note "$rc" "cwd=$dir :: $cmdstr"
}

# --- command-string probes: must BLOCK ---------------------------------------
expect_block
t 'git commit -m x --no-verify'
t 'git commit --no-verif -m x'
t 'git commit -n -m x'
t 'git commit -anm x'
t 'git commit -m x -n'
t 'git commit -m "msg with quotes" --no-verify'
t 'git -c core.hookspath=/dev/null commit -m x'
t 'git -c core.hooksPath=/tmp/none commit'
t 'git config core.hooksPath /tmp/none'
t 'git config --unset core.hooksPath'
t 'REVIEW_SKIP=1 git commit -m x'
t 'REVIEW_SKIP="1" git commit -m x'
t "REVIEW_SKIP='1' git commit -m x"
t 'REVIEW_SKIP=true git commit -m x'
t 'export REVIEW_SKIP=1; git commit -m x'
t 'chmod -x .githooks/pre-commit'
t 'rm -rf .githooks'
t 'mv .githooks/pre-commit /tmp/'
t 'cp /dev/null .githooks/pre-commit'
t 'echo lenient > .githooks/review-rubric.md'
t 'echo x | tee .githooks/review-rubric.md'
t 'sed -i "" -e "s/BLOCKER/NIT/" .githooks/review-rubric.md'
t 'git update-ref refs/heads/x abc123'
t 'git commit-tree HEAD^{tree} -m x'
t 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hookspath GIT_CONFIG_VALUE_0=/dev/null git commit -m x'
t 'git filter-branch --tree-filter "true" HEAD'
t 'git fast-import < dump.fi'

# --- command-string probes: must ALLOW ---------------------------------------
expect_allow
t 'git commit -m "clean snapshot"'
t 'git commit --amend --no-edit'
t 'git commit -S -m x'
t 'git commit -m "release: pin review model"'
t 'git add .githooks scripts/review.sh'
t 'cat .githooks/review-rubric.md'
t 'ls -la .githooks'
t 'git config core.hooksPath .githooks'
t 'git config --get core.hooksPath'
t 'git config core.hooksPath'
t 'grep -rn update-refs src'
t 'git status && git diff'
t 'bash scripts/review.sh'
t 'bash scripts/review-regress.sh'
t 'bash scripts/guard-probes.sh'
t 'bash scripts/backstop-probes.sh'
t 'git log --oneline -5'
t 'echo "review skipped nothing" > /tmp/note.txt'

# --- degraded mode: guard has no jq ------------------------------------------
expect_block
traw 'git commit -m x --no-verify'
traw 'REVIEW_SKIP=1 git commit'
expect_allow
traw 'git status'
traw 'ls -la src'

# --- invoked-script scanning -------------------------------------------------
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/guard-probe.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
printf '%s\n' '#!/bin/sh' 'git commit -m wip --no-verify' >"$TMPD/wrapper.sh"
printf '%s\n' '#!/bin/sh' 'GIT_CONFIG_KEY_0=core.hookspath git commit -m x' >"$TMPD/envwrap.sh"
printf '%s\n' '#!/bin/sh' 'echo hello' 'ls -la' >"$TMPD/innocent.sh"
mkfifo "$TMPD/pipe.sh" 2>/dev/null || true

expect_block
t "bash $TMPD/wrapper.sh"
t "sh $TMPD/wrapper.sh"
t "/bin/bash $TMPD/envwrap.sh"
t "source $TMPD/wrapper.sh"
tcd "$TMPD" './wrapper.sh'
tcd "$TMPD" 'if ./wrapper.sh; then :; fi'
tcd "$TMPD" 'time ./wrapper.sh'
tcd "$TMPD" 'exec ./wrapper.sh'
tcd "$TMPD" 'sudo ./wrapper.sh'
tcd "$TMPD" '! ./wrapper.sh'

expect_allow
t "bash $TMPD/innocent.sh"
tcd "$TMPD" './innocent.sh'
t "bash $TMPD/absent.sh"
t "bash $TMPD/pipe.sh"
# A bypass-containing script named as an ARGUMENT (data), not executed, must
# not be scanned — these are the regression the command-position rule fixes.
t "cat $TMPD/wrapper.sh"
tcd "$TMPD" 'cat ./wrapper.sh'
tcd "$TMPD" 'wc -l ./wrapper.sh'
tcd "$TMPD" 'grep -n Rate ./wrapper.sh'

# --- file-editing tools: a path under the hook tree is a tamper --------------
# Write/Edit payloads carry a path instead of a command; the content is
# irrelevant to the verdict.
tw() {
	local rc=0
	jq -cn --arg p "$1" --arg c "$2" '{tool_input:{file_path:$p,content:$c}}' | bash "$G" >/dev/null 2>&1 || rc=$?
	note "$rc" "write $1"
}
twraw() {
	local json rc=0
	json="$(jq -cn --arg p "$1" --arg c "$2" '{tool_input:{file_path:$p,content:$c}}')"
	printf '%s' "$json" | PATH=/nonexistent /bin/bash "$G" >/dev/null 2>&1 || rc=$?
	note "$rc" "no-jq write $1"
}
tdev() {
	local rc=0
	jq -cn --arg p "$1" --arg c "x" '{tool_input:{file_path:$p,content:$c}}' | REVIEW_HOOK_DEV=1 bash "$G" >/dev/null 2>&1 || rc=$?
	note "$rc" "hook-dev write $1"
}

expect_block
tw '.githooks/pre-commit' 'echo relaxed'
tw '/repo/.githooks/review-rubric.md' '# lenient'
tw '.githooks/lib/review-core.sh' 'x'
tw '.claude/settings.json' '{}'
tw 'scripts/review.sh' 'exit 0'
tw 'scripts/backstop-probes.sh' 'exit 0'
twraw '.githooks/lib/no-bypass-guard.sh' 'x'
twraw '/repo/.claude/settings.json' '{}'

expect_allow
tw 'src/server/Foo.lua' 'return {}'
tw 'docs/hooks.md' 'the staged-diff hook lives in the hook directory'
tw 'scripts/deploy.sh' 'echo deploying'
twraw 'README.md' 'x'
# Hook development mode lifts only the path and tamper checks.
tdev '.githooks/pre-commit'
tdev 'scripts/review.sh'

echo "guard-probes: $((total - fail))/$total passed"
[ "$fail" -eq 0 ]
