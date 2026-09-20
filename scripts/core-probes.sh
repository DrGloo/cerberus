#!/usr/bin/env bash
# No-model unit tests for lib/review-core.sh, starting with the review.conf
# loader: values land, quotes are stripped, shell in the file is inert and
# reported, unknown keys are ignored, the environment wins. Runs against a
# scratch hook directory holding a copy of the real lib; sub-second, no
# secrets, no git repository needed.
set -u
# Never inherit the caller's tuning: an exported REVIEW_MODEL or REVIEW_TIMEOUT
# would beat the fake review.conf and fail probes that have nothing wrong.
# shellcheck disable=SC2046
unset $(compgen -v REVIEW_) 2>/dev/null
R="$(cd "$(dirname "$0")/.." && pwd)"
S="$(mktemp -d "${TMPDIR:-/tmp}/core-probes.XXXXXX")"
trap 'rm -rf "$S"' EXIT;
fail=0
checks=0
ok() { echo "PASS: $1"; checks=$((checks + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); checks=$((checks + 1)); }

# A fake hook directory: the real lib, copied with tar, plus a review.conf
# that each probe rewrites.
H="$S/hooks"
mkdir -p "$H"
(cd "$R/.githooks" && tar -cf - lib) | tar -xf - -C "$H"
CONF="$H/review.conf"
ERR="$S/stderr"

# conf <line>...: write the probe's review.conf, one argument per line.
conf() { printf '%s\n' "$@" >"$CONF"; }
# load <check>...: source the core against the fake hook directory in a
# subshell, stderr captured to $ERR, then run the check there.
load() { ( REVIEW_HOOK_DIR="$H"; . "$H/lib/review-core.sh" 2>"$ERR"; "$@" ); }
# is <VAR> <value>: the named variable holds exactly the value.
is() { [ "${!1-<unset>}" = "$2" ]; }
# noted <n>: stderr carries the ignore note for line n.
noted() { grep -q "^\[review\] note: review.conf line $1 ignored: " "$ERR"; }
quiet() { [ ! -s "$ERR" ]; }

# --- plain assignment ----------------------------------------------------------
conf 'REVIEW_MODEL=conf-model' 'REVIEW_TIMEOUT=42'
load is REVIEW_MODEL conf-model && load is REVIEW_TIMEOUT 42 && quiet \
	&& ok "plain KEY=VALUE sets the model and timeout" || bad "plain assignment (stderr: $(cat "$ERR"))"

conf 'REVIEW_EXTRA_IGNORE='
load is REVIEW_EXTRA_IGNORE "" && quiet && ok "empty value is accepted silently" || bad "empty value"

conf 'REVIEW_MODEL='
load is REVIEW_MODEL claude-sonnet-5 && ok "empty model falls back to the default" || bad "empty model default"

# --- quoting -------------------------------------------------------------------
conf 'REVIEW_SOURCE_DIRS="src lib"'
load is REVIEW_SOURCE_DIRS "src lib" && ok "double quotes are stripped, spaces kept" || bad "double-quoted value"

conf "REVIEW_EXTRA_IGNORE='docs/* *.snap'"
load is REVIEW_EXTRA_IGNORE "docs/* *.snap" && ok "single quotes are stripped, globs kept literal" || bad "single-quoted value"

conf "REVIEW_LINT_CMD=\"it's fine\""
load is REVIEW_LINT_CMD "it's fine" && ok "an inner quote of the other kind survives" || bad "inner quote"

conf "REVIEW_MODEL=\"mismatched'"
load is REVIEW_MODEL "\"mismatched'" && ok "mismatched quotes are not stripped" || bad "mismatched quotes"

conf 'REVIEW_MODEL="'
load is REVIEW_MODEL '"' && ok "a lone quote is a one-character value" || bad "lone quote"

conf 'REVIEW_EXTRA_IGNORE=""' 'REVIEW_SOURCE_DIRS=""'
load is REVIEW_EXTRA_IGNORE "" && load is REVIEW_SOURCE_DIRS "." \
	&& ok "an empty quoted value is empty, so a default can still apply" || bad "empty quoted value"

# --- shell in the file is inert and reported -----------------------------------
SENTINEL="$S/sentinel"
conf "REVIEW_LINT_CMD=\$(touch $SENTINEL)"
load is REVIEW_LINT_CMD "" && noted 1 && [ ! -e "$SENTINEL" ] \
	&& ok "\$(...) in a value runs nothing, is reported, and leaves the default" || bad "command substitution (stderr: $(cat "$ERR"))"

conf "REVIEW_LINT_CMD=\`touch $SENTINEL\`"
load is REVIEW_LINT_CMD "" && noted 1 && [ ! -e "$SENTINEL" ] \
	&& ok "backticks in a value run nothing and are reported" || bad "backticks (stderr: $(cat "$ERR"))"

conf 'REVIEW_MODEL=conf-model' "touch $SENTINEL" 'REVIEW_TIMEOUT=42'
load is REVIEW_MODEL conf-model && load is REVIEW_TIMEOUT 42 && noted 2 && [ ! -e "$SENTINEL" ] \
	&& ok "a bare command line is inert and reported; the lines around it still load" || bad "bare command (stderr: $(cat "$ERR"))"

conf "REVIEW_MODEL=\"\$HOME\""
load is REVIEW_MODEL claude-sonnet-5 && noted 1 && ok "a \$VAR reference is refused, not expanded" || bad "variable reference"

# --- the legacy ${VAR:-default} form ---------------------------------------------
conf 'REVIEW_MODEL="${REVIEW_MODEL:-conf-model}"'
load is REVIEW_MODEL conf-model && ok "legacy form is accepted with its literal" || bad "legacy literal (stderr: $(cat "$ERR"))"

conf 'REVIEW_MODEL="${REVIEW_MODEL:-conf-model}"' 'REVIEW_TIMEOUT=${REVIEW_TIMEOUT:-42}' 'REVIEW_SOURCE_DIRS="${REVIEW_SOURCE_DIRS:-src lib}"'
load is REVIEW_TIMEOUT 42 && load is REVIEW_SOURCE_DIRS "src lib" \
	&& [ "$(grep -c 'uses the legacy' "$ERR")" -eq 1 ] && ! noted 1 \
	&& ok "legacy note is printed once per file, however many lines use the form" || bad "legacy note count (stderr: $(cat "$ERR"))"

conf 'REVIEW_MODEL="${REVIEW_MODEL:-conf-model}"'
REVIEW_MODEL=env-model load is REVIEW_MODEL env-model && ok "the environment still beats a legacy line" || bad "legacy vs environment"

conf 'REVIEW_LINT_CMD="${REVIEW_LINT_CMD:-$(touch '"$SENTINEL"')}"'
load is REVIEW_LINT_CMD "" && noted 1 && [ ! -e "$SENTINEL" ] && ! grep -q 'uses the legacy' "$ERR" \
	&& ok "legacy form with a nested \$(...) is refused and runs nothing" || bad "legacy nested substitution (stderr: $(cat "$ERR"))"

conf 'REVIEW_MODEL="${REVIEW_TIMEOUT:-conf-model}"'
load is REVIEW_MODEL claude-sonnet-5 && noted 1 && ok "legacy form naming a different key is refused" || bad "legacy mismatched key"

conf 'REVIEW_MODEL="${REVIEW_MODEL:-a`id`}"'
load is REVIEW_MODEL claude-sonnet-5 && noted 1 && ok "legacy form with a backtick literal is refused" || bad "legacy backtick"

conf 'REVIEW_MODEL=conf-model'
load true; quiet && ok "the plain form prints no legacy note" || bad "plain form noted"

conf 'REVIEW_MODEL=a; touch '"$SENTINEL"
load is REVIEW_MODEL "a; touch $SENTINEL" && [ ! -e "$SENTINEL" ] \
	&& ok "a semicolon is data, not a command separator" || bad "semicolon"

conf 'REVIEW_MODEL=conf-model REVIEW_TIMEOUT=42'
load is REVIEW_MODEL "conf-model REVIEW_TIMEOUT=42" && load is REVIEW_TIMEOUT 180 \
	&& ok "one assignment per line; the rest of the line is the value" || bad "two assignments on one line"

# --- unknown keys --------------------------------------------------------------
conf 'BOGUS=1' 'REVIEW_MODEL=conf-model'
load is BOGUS "<unset>" && load is REVIEW_MODEL conf-model && noted 1 && ! noted 2 \
	&& ok "an unknown key is ignored and reported; the known one still loads" || bad "unknown key (stderr: $(cat "$ERR"))"

conf 'REVIEW_MAX_CHUNKS=6'
load is REVIEW_MAX_CHUNKS "<unset>" && noted 1 && ok "a key that later changes will consume is not accepted yet" || bad "not-yet-accepted key"

conf 'PATH=/nowhere'
load is PATH "$PATH" && noted 1 && ok "PATH cannot be set from the file" || bad "PATH from file"

conf 'REVIEW_HOOK_DIR=/elsewhere'
load is REVIEW_HOOK_DIR "$H" && noted 1 && ok "REVIEW_HOOK_DIR is not in the allowlist" || bad "hook dir from file"

conf 'review_model=x'
load is REVIEW_MODEL claude-sonnet-5 && noted 1 && ok "keys are case-sensitive" || bad "lowercase key"

conf 'REVIEW_MODEL =x'
load is REVIEW_MODEL claude-sonnet-5 && noted 1 && ok "a space before = is not an assignment" || bad "space before ="

# --- environment wins ----------------------------------------------------------
conf 'REVIEW_MODEL=conf-model' 'REVIEW_TIMEOUT=42'
REVIEW_MODEL=env-model load is REVIEW_MODEL env-model && REVIEW_MODEL=env-model load is REVIEW_TIMEOUT 42 \
	&& ok "environment overrides the file for that key only" || bad "environment override"

REVIEW_MODEL="" load is REVIEW_MODEL claude-sonnet-5 && ok "an empty environment value still wins (then defaults)" || bad "empty env value"

conf 'REVIEW_EXTRA_IGNORE=' 'REVIEW_MODEL=first' 'REVIEW_EXTRA_IGNORE="docs/*"' 'REVIEW_MODEL=second'
load is REVIEW_EXTRA_IGNORE "docs/*" && load is REVIEW_MODEL second \
	&& ok "a key assigned twice in the file takes the later line" || bad "later line wins"

# --- blank lines, comments, whitespace ------------------------------------------
conf '# leading comment' '' '   ' 'REVIEW_MODEL=conf-model' '    # indented comment' '  REVIEW_TIMEOUT=42' ''
load is REVIEW_MODEL conf-model && load is REVIEW_TIMEOUT 42 && quiet \
	&& ok "blank, comment and indented lines load without a note" || bad "blank/comment lines (stderr: $(cat "$ERR"))"

conf 'REVIEW_MODEL=conf-model # trailing'
load is REVIEW_MODEL "conf-model # trailing" && ok "a trailing # is part of the value, not a comment" || bad "trailing comment"

printf 'REVIEW_MODEL=conf-model' >"$CONF"
load is REVIEW_MODEL conf-model && ok "a last line without a newline still loads" || bad "missing final newline"

# --- the note itself -----------------------------------------------------------
long="$(printf 'x%.0s' $(seq 1 90))"
conf 'REVIEW_MODEL=conf-model' '' "$long"
load true
grep -qx "\[review\] note: review.conf line 3 ignored: $(printf 'x%.0s' $(seq 1 60))" "$ERR" \
	&& ok "note names the line number and shows the first 60 characters" || bad "note format: $(cat "$ERR")"

unlink "$CONF"
load is REVIEW_MODEL claude-sonnet-5 && quiet && ok "a missing review.conf is silent and leaves the defaults" || bad "missing file"

# --- prompt context and suppression ------------------------------------------
P="$S/prompt-repo"
mkdir -p "$P/src"
(cd "$P" && git init -q && git config user.email probe@example.com && git config user.name probe &&
	printf '%s\n' 'function wrapInvoke(value)' ' return value' 'end' >src/Handler.lua &&
	git add . && git commit -qm base)
printf '%s\n' 'diff --git a/src/Handler.lua b/src/Handler.lua' '--- a/src/Handler.lua' '+++ b/src/Handler.lua' '@@ -1,3 +1,4 @@' ' function wrapInvoke(value)' ' return value' 'end' '+-- changed' >"$S/diff"
printf '%s\n' src/Handler.lua >"$S/paths"
: >"$S/deleted"
printf '%s\n' '## Untrusted content' >"$S/rubric"
(cd "$P" && REVIEW_CONTEXT_PATTERNS='Handler.lua' REVIEW_LINT_TOOLS='selene stylua' REVIEW_HOOK_DIR="$H"; export REVIEW_CONTEXT_PATTERNS REVIEW_LINT_TOOLS REVIEW_HOOK_DIR; . "$H/lib/review-core.sh"; review_build_prompt "$S/diff" "$S/paths" "$S/deleted" "$S/rubric" staged 'git show HEAD:' HEAD "$S/prompt")
grep -q -- '---- FULL CURRENT CONTENTS: src/Handler.lua' "$S/prompt" && ok "pattern-matched file is attached in full" || bad "pattern context attachment"
(cd "$R" && REVIEW_LINT_TOOLS='selene stylua' REVIEW_HOOK_DIR="$R/.githooks"; export REVIEW_LINT_TOOLS REVIEW_HOOK_DIR; . "$R/.githooks/lib/review-core.sh"; review_rubric_file "$R/.githooks" "$S/rubric-built")
grep -q 'selene stylua' "$S/rubric-built" && ok "configured lint tools appear in the rubric" || bad "pattern context/rubric injection"

printf '%s\n' 'function validateAmount(value)' ' return value > 0' 'end' >"$P/src/Validator.lua"
printf '%s\n' 'return validateAmount(amount)' >"$P/src/Caller.lua"
(cd "$P" && git add . && git commit -qm callee)
printf '%s\n' 'diff --git a/src/Caller.lua b/src/Caller.lua' '--- a/src/Caller.lua' '+++ b/src/Caller.lua' '@@ -0,0 +1 @@' '+return validateAmount(amount)' >"$S/callee.diff"
printf '%s\n' src/Caller.lua >"$S/callee.paths"
(cd "$P" && REVIEW_CONTEXT_PATTERNS='' REVIEW_LINT_TOOLS='' REVIEW_HOOK_DIR="$H"; export REVIEW_CONTEXT_PATTERNS REVIEW_LINT_TOOLS REVIEW_HOOK_DIR; . "$H/lib/review-core.sh"; review_build_prompt "$S/callee.diff" "$S/callee.paths" "$S/deleted" "$S/rubric" staged 'git show HEAD:' HEAD "$S/callee.prompt")
grep -q -- '---- CALLEE: validateAmount ----' "$S/callee.prompt" && ok "cross-file callee definition appears in the prompt" || bad "callee context"

printf '%s\n' '-- review-ignore: intentional' old >"$P/src/Marker.lua"
(cd "$P" && git add . && git commit -qm marker)
printf '%s\n' '-- review-ignore: intentional' new >"$P/src/Marker.lua"
(cd "$P" && git add . && git diff --cached >"$S/marker.diff")
printf '%s\n' '[BLOCKER] src/Marker.lua:2 - defect' '  why: x' '  fix: y' 'VERDICT: BLOCK' >"$S/marker.out"
(cd "$P" && . "$H/lib/review-core.sh"; review_apply_suppressions "$S/marker.out" "$S/marker.diff" HEAD)
grep -q '^\[WARN\].*intentional' "$S/marker.out" && grep -q '^VERDICT: PASS$' "$S/marker.out" && ok "base marker demotes a blocker with its reason" || bad "base suppression"

printf '%s\n' old >"$P/src/Marker.lua"
(cd "$P" && git add . && git commit -qm no-marker)
printf '%s\n' '-- review-ignore: same diff' broken >"$P/src/Marker.lua"
(cd "$P" && git add . && git diff --cached >"$S/marker-new.diff")
printf '%s\n' '[BLOCKER] src/Marker.lua:2 - defect' '  why: x' '  fix: y' 'VERDICT: BLOCK' >"$S/marker-new.out"
(cd "$P" && . "$H/lib/review-core.sh"; review_apply_suppressions "$S/marker-new.out" "$S/marker-new.diff" HEAD)
grep -q '^\[BLOCKER\]' "$S/marker-new.out" && grep -q 'takes effect only' "$S/marker-new.out" && ok "same-diff marker keeps the blocker and warns" || bad "same-diff suppression"

printf '%s\n' '-- review-ignore: too far' one two three four >"$P/src/Far.lua"
(cd "$P" && git add . && git commit -qm far-marker)
printf '%s\n' '-- review-ignore: too far' one two three changed >"$P/src/Far.lua"
(cd "$P" && git add . && git diff --cached >"$S/far.diff")
printf '%s\n' '[BLOCKER] src/Far.lua:4 - defect' '  why: x' '  fix: y' 'VERDICT: BLOCK' >"$S/far.out"
(cd "$P" && . "$H/lib/review-core.sh"; review_apply_suppressions "$S/far.out" "$S/far.diff" HEAD)
grep -q '^\[BLOCKER\]' "$S/far.out" && ! grep -q 'too far' "$S/far.out" && ok "marker three lines away does not suppress" || bad "distant suppression"

printf '%s\n' '-- review-ignore:' old >"$P/src/Bare.lua"
(cd "$P" && git add . && git commit -qm bare-marker)
printf '%s\n' '-- review-ignore:' new >"$P/src/Bare.lua"
(cd "$P" && git add . && git diff --cached >"$S/bare.diff")
printf '%s\n' '[BLOCKER] src/Bare.lua:2 - defect' '  why: x' '  fix: y' 'VERDICT: BLOCK' >"$S/bare.out"
(cd "$P" && . "$H/lib/review-core.sh"; review_apply_suppressions "$S/bare.out" "$S/bare.diff" HEAD)
grep -q '^\[BLOCKER\]' "$S/bare.out" && grep -q 'requires a reason' "$S/bare.out" && ok "bare marker warns and keeps the finding" || bad "bare suppression"

# --- the suite does not inherit the caller's environment ---------------------
# Run a nested copy with junk exported; it must pass exactly as this one did.
if [ -z "${CORE_PROBES_NESTED:-}" ]; then
	if CORE_PROBES_NESTED=1 REVIEW_MODEL=junk-model REVIEW_TIMEOUT=1 REVIEW_SOURCE_DIRS=junk bash "$0" >"$S/nested.log" 2>&1; then
		ok "the suite passes with REVIEW_MODEL and friends exported to junk"
	else
		bad "suite inherits the caller's environment ($(tail -3 "$S/nested.log" | tr '\n' ' '))"
	fi
fi

echo
echo "core-probes: $checks checks, $fail failure(s)"
[ "$fail" -eq 0 ]
