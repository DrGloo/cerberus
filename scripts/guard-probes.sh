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
# Spelling must not matter: a case-insensitive filesystem reaches the same file.
tw '.GitHooks/Pre-Commit' 'x'
tw 'Scripts/Review.sh' 'x'

expect_allow
tw 'src/server/Foo.lua' 'return {}'
tw 'docs/hooks.md' 'the staged-diff hook lives in the hook directory'
tw 'scripts/deploy.sh' 'echo deploying'
twraw 'README.md' 'x'
# Hook development mode lifts only the path and tamper checks.
tdev '.githooks/pre-commit'
tdev 'scripts/review.sh'

# Command under hook-development mode: protected-path checks are lifted, the
# bypass checks and the key check are not.
tdevc() {
	local rc=0
	jq -cn --arg c "$1" '{tool_input:{command:$c}}' | REVIEW_HOOK_DEV=1 bash "$G" >/dev/null 2>&1 || rc=$?
	note "$rc" "hook-dev: $1"
}
# MultiEdit-shaped payload: top-level file_path plus an edits array.
tme() {
	local rc=0
	jq -cn --arg p "$1" '{tool_input:{file_path:$p,edits:[{old_string:"a",new_string:"b"}]}}' | bash "$G" >/dev/null 2>&1 || rc=$?
	note "$rc" "multi-edit $1"
}
# NotebookEdit-shaped payload.
tnb() {
	local rc=0
	jq -cn --arg p "$1" '{tool_input:{notebook_path:$p,new_source:"x"}}' | bash "$G" >/dev/null 2>&1 || rc=$?
	note "$rc" "notebook $1"
}

# --- protected paths: every write shape from the shell is refused ------------
# Redirects, write-shaped tools, in-place sed and inline interpreter programs
# aimed at the hook tree, the settings file, the review scripts or the git
# directory. The same paths as plain reads stay allowed (next section).
expect_block
t 'echo ok > .githooks/pre-commit'
t ': > .githooks/pre-commit'
t 'printf x >> .githooks/review.conf'
t 'echo y > .claude/settings.json'
t 'echo x >| .githooks/pre-commit'
t 'echo x >.githooks/pre-commit'
t 'echo x > "./.githooks/pre-commit"'
t "echo x > './.githooks/pre-commit'"
t 'echo x > ./lib/../.githooks/pre-commit'
t 'echo x > /repo/.githooks/pre-commit'
t 'echo x > .GITHOOKS/PRE-COMMIT'
t 'cat > .githooks/pre-commit <<EOF
exit 0
EOF'
t 'true &> scripts/review.sh'
t 'echo x 2> scripts/lib/helper.sh'
t 'ls -la .githooks && echo x > .githooks/pre-commit'
t 'sed -i.bak s/x/y/ .githooks/pre-commit'
t 'sed -i "" s/x/y/ .githooks/post-commit'
t 'sed -ni s/x/y/ .githooks/pre-push'
t 'sed --in-place s/x/y/ scripts/review.sh'
t 'ln -sf /dev/null .githooks/pre-commit'
t 'ln .githooks/pre-commit /tmp/x'
t 'tee .githooks/pre-commit < f'
t 'echo x | tee -a .githooks/review.conf'
t 'echo x | sudo tee .githooks/pre-commit'
t 'echo x | /usr/bin/tee .githooks/pre-commit'
# A write word counts wherever it sits: wrapper options are not parsed, so
# these cannot slip through as "arguments".
t 'echo x | sudo -u me tee .githooks/pre-commit'
t 'echo x | timeout 5 tee .githooks/pre-commit'
t 'echo x | xargs -I{} tee .githooks/pre-commit'
t 'dd of=.githooks/pre-commit if=/dev/null'
t 'install -m 0644 /dev/null .githooks/pre-commit'
t 'patch .githooks/pre-commit < fix.diff'
t "python3 -c \"open('.githooks/pre-commit','w')\""
t "python -c \"open('.githooks/pre-commit','w')\""
t "perl -pi -e 's/x/y/' .githooks/pre-commit"
t "ruby -e 'File.write(\".githooks/pre-commit\", \"\")'"
t "node -e \"require('fs').writeFileSync('.githooks/pre-commit','')\""
t "lua -e 'io.open(\".githooks/pre-commit\",\"w\")'"
# Targets under the git directory: the attestation log and the verdict cache.
t 'echo x > .git/HEAD'
t 'echo PASS > .git/review-cache/abc123.verdict'
t 'echo "sha tree ok" >> .git/review-cache/attested.log'
t 'echo x > .git/worktrees/x/review-cache/y'
t 'echo x > /abs/path/.git/config'
t 'tee .git/review-cache/attested.log < f'
t 'echo "gitdir: /tmp/x" > .git'

# --- protected paths: reads stay allowed -------------------------------------
expect_allow
t 'cat .githooks/pre-push'
t 'git add .githooks'
t 'ls -la .git/review-cache'
t 'cat .git/review-cache/last-review.md'
t 'grep -n x .githooks/pre-commit'
t 'head -5 scripts/review.sh'
t 'cat .git/objects/info/packs'
t 'find .git/objects -type f | head'
t 'diff .githooks/pre-commit /tmp/other'
t 'cat .githooks/pre-commit > /tmp/copy.sh'
t 'cat .githooks/pre-commit; tee /tmp/out < /dev/null'
t 'grep -rn hookspath .githooks | head'
t 'sed -n 1,5p .githooks/pre-commit'
t 'sed -e s/x/y/ .githooks/pre-commit'
t 'python3 scripts/tool.py .githooks/pre-commit'
t 'git diff .githooks/pre-commit | patch -p1 -R /tmp/other'
t 'echo "see .githooks/pre-commit" > docs/notes.md'
t 'git commit -m "install: tee up the patch" -- src/x.lua'
t 'git log -p -- .git/review-cache'
t 'wc -l scripts/review-regress.sh scripts/guard-probes.sh'

# --- the attestation key is unreadable, in every mode ------------------------
expect_block
t 'cat .git/review-cache/key'
t 'base64 .git/review-cache/key'
t 'cat "$(git rev-parse --git-common-dir)/review-cache/key"'
t 'cat /abs/.git/review-cache/key | pbcopy'
t 'xxd .GIT/REVIEW-CACHE/KEY'
t 'cat .git/review-cache/k*'
t 'cat .git/review-cache/*'
tdevc 'cat .git/review-cache/key'
tw '.git/review-cache/key' 'x'
tdev '.git/review-cache/key'
expect_allow
t 'cat .git/review-cache/keyring.md'

# --- hook-development mode: writes lifted, bypasses not ----------------------
# The bypass spellings below are assembled at run time so this file's own text
# does not carry them.
hookspath="core.hooks""Path"
expect_allow
tdevc 'echo x > .githooks/pre-commit'
tdevc 'tee .githooks/pre-commit < f'
expect_block
tdevc "git config --un""set $hookspath"

# --- file-tool payloads: path only, content never -----------------------------
expect_block
tw '.git/review-cache/attested.log' 'x'
tw '.git/config' 'x'
tw '.git/worktrees/x/review-cache/y' 'x'
tw '/repo/.git/HEAD' 'x'
tw '.git' 'gitdir: /tmp/x'
tw '.githooks/post-commit' 'exit 0'
tw './.githooks/post-commit' 'exit 0'
tw 'docs/../.githooks/post-commit' 'exit 0'
tw '.githooks//pre-commit' 'x'
tw 'scripts/lib/review-driver.sh' 'x'
tw 'scripts/core-probes.sh' 'x'
tw 'scripts/review-regress.sh' 'x'
tw 'scripts/guard-probes.sh' 'x'
tme '.githooks/pre-commit'
tme '.git/review-cache/attested.log'
tnb '.githooks/notes.ipynb'
twraw '.git/review-cache/attested.log' 'x'
expect_allow
# Documentation may quote the bypass flag and the skip variable: the content
# is not a shell command.
flag="--no-ver"; flag="$flag""ify"
skipvar="REVIEW_SK"; skipvar="$skipvar""IP=1"
tw 'CONTRIBUTING.md' "never run git commit $flag, and never set $skipvar before git commit"
twraw 'CONTRIBUTING.md' "never run git commit $flag"
tw 'docs/guard.md' "git config --un""set $hookspath is refused by the guard"
twraw 'README.md' 'the JSON payload carries a "command" key'
tme 'src/app.lua'
tnb 'notebooks/x.ipynb'
tw 'scripts/deploy.sh' 'echo x > .githooks/pre-commit'
tw '.githooks.md' 'x'
tw 'src/.gitignore' 'x'
# In the degraded path a Bash command that quotes "file_path" is still a
# command, so a bypass in it is still caught.
expect_block
traw "grep '\"file_path\"' x; git commit -m y $flag"

# --- manifest sweep: every installed path is a protected write target --------
# The list is read from install.sh in the Cerberus checkout; an installed
# copy (selftest runs this suite inside a scratch install) has no install.sh
# and falls back to the same list spelled here.
M_HOOKS=".githooks"
M_SCRIPTS="scripts"
M_HOOK_FILES="pre-commit post-commit pre-push lib/review-core.sh lib/no-bypass-guard.sh review-rubric.md review.conf.example regress/expected.tsv"
M_SCRIPT_FILES="review.sh review-regress.sh guard-probes.sh backstop-probes.sh"
M_SETTINGS=".claude/settings.json"
if [ -f "$ROOT_DIR/install.sh" ]; then
	mf() { sed "s/^$1=\"\(.*\)\"\$/\1/p;d" "$ROOT_DIR/install.sh"; }
	M_HOOKS="$(mf HOOKS)"
	M_SCRIPTS="$(mf SCRIPTS)"
	M_HOOK_FILES="$(mf HOOK_FILES)"
	M_SCRIPT_FILES="$(mf SCRIPT_FILES)"
	M_SETTINGS="$(mf GUARD_SETTINGS)"
fi
if [ -z "$M_HOOKS" ] || [ -z "$M_HOOK_FILES" ] || [ -z "$M_SCRIPT_FILES" ] || [ -z "$M_SETTINGS" ]; then
	echo "MISMATCH :: could not read the install manifest from install.sh"
	fail=$((fail + 1))
fi
expect_block
for f in $M_HOOK_FILES; do
	tw "$M_HOOKS/$f" 'x'
	t "echo x > $M_HOOKS/$f"
done
for f in $M_SCRIPT_FILES; do
	tw "$M_SCRIPTS/$f" 'x'
	t "echo x > $M_SCRIPTS/$f"
done
tw "$M_SETTINGS" 'x'
t "echo x > $M_SETTINGS"

# --- the existing verbs cover every protected path, not just the hooks ------
expect_block
t 'rm -f .git/review-cache/attested.log'
t 'rm -rf .git/review-cache'
t 'mv .git/review-cache /tmp/x'
t 'cp /tmp/forged.log .git/review-cache/attested.log'
t 'chmod 777 .git/config'
t 'truncate -s 0 .git/review-cache/attested.log'
t 'rm scripts/review-regress.sh'
t 'cp /dev/null .claude/settings.json'
t 'rm -rf scripts/lib'
expect_allow
t 'rm -rf build/ && ls .git/review-cache'
t 'cp src/a.lua src/b.lua; cat .git/review-cache/last-review.md'

echo "guard-probes: $((total - fail))/$total passed"
[ "$fail" -eq 0 ]
