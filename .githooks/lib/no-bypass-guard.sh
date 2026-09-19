#!/usr/bin/env bash
# Claude Code PreToolUse hook: refuse Bash commands that skip or defang the
# pre-commit AI code review. Humans can still bypass from their own terminal;
# agents cannot.
#
# Layers:
#   1. A Bash command string is checked against bypass + tamper patterns and
#      against the protected-path rule: a protected path (hook tree, guard
#      registration, review and probe scripts, anything under a git directory)
#      as the target of an output redirect, or in the same simple command as a
#      write-shaped word, is refused. Reads stay allowed. Any command naming
#      the attestation key (<git-common-dir>/review-cache/key) is refused.
#   2. Script files the command invokes (bash|sh|zsh <path>, ./<path>) are
#      scanned with the bypass patterns too — up to 3 regular files, first
#      64KB each — so a wrapper hiding `git commit --no-verify` is caught at
#      invocation. Tamper and protected-path rules are NOT applied to file
#      contents (tracked tooling like review-regress.sh legitimately copies
#      .githooks into worktrees), and the test-corpus scripts
#      (scripts/guard-probes.sh, scripts/backstop-probes.sh) are exempt —
#      their content is trigger strings by design. Overwriting an exempt file
#      is a protected-path write and is refused on its own.
#   3. File-tool payloads (Write/Edit/MultiEdit/NotebookEdit carry a path, no
#      command) are judged by their path alone: a protected path is refused
#      whatever the content says; any other path is allowed whatever the
#      content says. Content is never scanned as if it were a shell command,
#      so documentation that quotes a bypass flag is writable.
#
# Accepted residual holes (a static shell inspector cannot close these; the
# guard raises the cost of a bypass, it cannot make one impossible):
#   - a script written by a non-Bash tool and executed in the same turn;
#   - a program piped rather than named, to a shell or an interpreter on
#     stdin: `cat w.sh | bash`, `bash < w.sh`, `python3 < w.py`;
#   - a protected path reached through a symlink the guard has not seen (the
#     path predicate is textual: `./` and `..` are folded, links are not);
#   - the attestation key read through a path the guard does not recognise: a
#     directory-recursive reader over the cache directory (grep -r, tar), or a
#     variable that builds the key path at run time. (Quoted, `./`, `//` and
#     `cd <dir> && cat key` spellings are recognised.);
#   - a `cd other/ && ./w.sh` where w.sh is not at that path from the repo root;
#   - a ./script after a command-prefix word not in the command-position list;
#   - >64KB of leading padding before the bypass line in a scanned file;
#   - git plumbing beyond the listed commands.
#
# Pure bash builtins (read, [[ =~ ]]) on purpose: the guard must not fail open
# because an external tool is missing. jq is optional; without it the raw JSON
# payload is scanned — the command text is embedded in it verbatim (modulo
# quote escaping, which no pattern below relies on).

set -u

input=""
IFS= read -r -d '' input

have_jq=0
command -v jq >/dev/null 2>&1 && have_jq=1

cmd=""
if [ "$have_jq" = 1 ]; then
	cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)" || cmd=""
fi

# The file-editing tools carry a path instead of a command (MultiEdit: the
# top-level file_path; NotebookEdit: notebook_path). Such a payload is judged
# by its path alone. Without jq the path is cut out of the raw JSON — but only
# when the payload has no "command" key, so a Bash command that merely quotes
# the string "file_path" stays in command mode and keeps every check.
fpath=""
if [ "$have_jq" = 1 ]; then
	fpath="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)" || fpath=""
else
	case "$input" in
		*'"command"'*) ;;
		*'"file_path"'*)
			fpath="${input#*\"file_path\"}"
			fpath="${fpath#*\"}"
			fpath="${fpath%%\"*}"
			;;
		*'"notebook_path"'*)
			fpath="${input#*\"notebook_path\"}"
			fpath="${fpath#*\"}"
			fpath="${fpath%%\"*}"
			;;
	esac
fi

mode="command"
[ -z "$cmd" ] && [ -n "$fpath" ] && mode="file"
# No command and no path: scan the raw payload as if it were a command.
[ -n "$cmd" ] || cmd="$input"

WHERE=""
block() {
	echo "Blocked: $1$WHERE Fix the BLOCKER findings and commit again, or ask the user to bypass from their own terminal." >&2
	exit 2
}

# ci: case-insensitive ERE match; cs: case-sensitive (for short-flag clusters).
# Both match against the global $hay so the same checks run over the command
# string and over invoked-script contents.
hay=""
ci() {
	shopt -s nocasematch
	[[ "$hay" =~ $1 ]]
	local r=$?
	shopt -u nocasematch
	return "$r"
}
cs() { [[ "$hay" =~ $1 ]]; }

# --- protected paths ---------------------------------------------------------
# One predicate decides what the agent may not write. Normalisation is textual
# only — empty, `.` and `..` segments are folded, nothing is resolved on disk —
# so a symlink to a protected file is a stated residual, not a surprise.
# Case-insensitive: on a case-insensitive filesystem a differently spelled
# path reaches the same file. Relative and absolute spellings both match.
np=""
normalize_path() {
	local p="$1" seg out="" abs=""
	case "$p" in /*) abs="/" ;; esac
	local IFS='/'
	set -f
	for seg in $p; do
		case "$seg" in
			''|.) ;;
			..)
				case "$out" in
					''|..|*/..) out="${out:+$out/}.." ;;
					*/*) out="${out%/*}" ;;
					*) out="" ;;
				esac
				;;
			*) out="${out:+$out/}$seg" ;;
		esac
	done
	set +f
	np="$abs$out"
}

# Protected: the hook tree, the guard registration, the review and probe
# scripts and their library, and everything under a git directory — the
# attestation log and verdict cache live there, and a linked worktree's git
# directory is under <main>/.git/worktrees/.
is_protected_path() {
	local r=1
	# Cheap prefilter: the guard runs this per token of every Bash command,
	# and normalisation only drops segments, so a protected spelling always
	# contains one of these substrings before and after folding.
	shopt -s nocasematch
	case "$1" in
		*.git*|*settings.json*|*scripts*) ;;
		*) shopt -u nocasematch; return 1 ;;
	esac
	normalize_path "$1"
	case "$np" in
		.githooks|*/.githooks|.githooks/*|*/.githooks/*) r=0 ;;
		.git|*/.git|.git/*|*/.git/*) r=0 ;;
		.claude/settings.json|*/.claude/settings.json) r=0 ;;
		scripts/review.sh|*/scripts/review.sh) r=0 ;;
		scripts/review-regress.sh|*/scripts/review-regress.sh) r=0 ;;
		scripts/guard-probes.sh|*/scripts/guard-probes.sh) r=0 ;;
		scripts/backstop-probes.sh|*/scripts/backstop-probes.sh) r=0 ;;
		scripts/core-probes.sh|*/scripts/core-probes.sh) r=0 ;;
		scripts/lib|*/scripts/lib|scripts/lib/*|*/scripts/lib/*) r=0 ;;
	esac
	shopt -u nocasematch
	return "$r"
}

# --- protected paths: the attestation key ------------------------------------
# The per-clone secret lives at <git-common-dir>/review-cache/key. Nothing an
# agent does needs it, so naming it at all (read, copy, write, any prefix) is
# refused, as is a glob under the cache directory that could expand to it.
# Applied to the command string or the file-tool path only, never to invoked
# script contents: the hooks and review scripts legitimately read the key.
#
# Spellings that fold to the key path are caught per token: each token is
# normalised (`./`, `//`, `..` folded, case ignored) and matched against
# review-cache/key. Quotes split tokens, so review-cache/"key" leaves a bare
# `key` token; a bare `key` token in a command that also names review-cache
# (`cd .git/review-cache && cat key`) is refused. `key` without review-cache
# anywhere in the command (`git config user.name key`) is not.
toks=()
tokenize() {
	local norm="$1" c
	norm="${norm//$'\n'/ ; }"
	norm="${norm//$'\r'/ ; }"
	for c in '>' '<' '|' ';' '&' '(' ')' '"' "'" '`' ',' '='; do
		norm="${norm//"$c"/ $c }"
	done
	# Iterated by the callers, not indexed: bash 3.2 arrays index in O(n).
	read -ra toks <<<"$norm ;" || true
}

check_key_path() {
	local t
	hay="$1"
	ci 'review-cache/+key([^a-z0-9_-]|$)' && block "the attestation key under review-cache is not readable or writable by agents."
	ci 'review-cache/+[^[:space:]"'"'"';|&]*[*?[]' && block "globbing under review-cache could reach the attestation key."
	# Everything below needs the cache directory named somewhere.
	ci 'review-cache' || return 0
	tokenize "$1"
	for t in ${toks[@]+"${toks[@]}"}; do
		normalize_path "$t"
		hay="$np"
		ci '(^|/)review-cache/key([^a-z0-9_-]|$)' && block "the attestation key under review-cache is not readable or writable by agents."
		ci '^key$' && block "a bare 'key' in a command naming review-cache could reach the attestation key."
	done
	return 0
}

# --- protected paths: write shapes in a Bash command -------------------------
# The command is split into tokens on whitespace and on redirect, control and
# grouping characters, quotes, commas and '='. A token rule, not a shell
# grammar: a quoted '>' still counts as a redirect (a false refusal on
# `grep '>' hook`, never a missed write), and a protected path inside a quoted
# interpreter program still surfaces as its own token. Tokens are grouped into
# simple commands at ';', '|', '&' and newlines; parentheses do not split, so
# a $(...) or a subshell shares its enclosing command's verdict.
#
# Refused: a protected token as the target of '>', '>>', '>|' (or '>&'); a
# write-shaped word in the same simple command as a protected token; sed with
# an in-place flag, or an interpreter with an inline program (-c/-e), in the
# same simple command as a protected token (coarse by design: a read-only
# one-liner naming a hook is refused too). Plain reads pass.
#
# A write-shaped word counts wherever it sits in the simple command, even as
# data (`grep tee hook` is refused; `grep 'te[e]' hook` is not). Deciding
# command position would mean parsing every wrapper's options (`sudo -u me
# tee`, `timeout 5 tee`, `xargs -I{} tee`), and a wrong guess there is a
# missed write; a wrong guess here is a rephrased read.
#
# The verbs live in WRITE_WORDS (matched by basename, so /bin/tee counts).
# NOTE: the regex in check_tamper_patterns covers the same five verbs (the
# mode, delete, move, copy and truncate ones) for the hook directory; keep the
# two in sync. guard-probes fails if they drift.
# Also refused, in the same simple command as a protected token: find with
# -delete/-exec/-ok/-fprint*/-fls; git with a working-tree or index rewriting
# subcommand; sed with a `w` command. awk is not covered (a '>' inside its
# program is ambiguous).
WRITE_WORDS="tee ln dd install patch gpatch rm rmdir unlink mv cp chmod chown truncate shred rsync touch mkdir"
GIT_WRITE_SUBS=" apply checkout restore clean stash reset rm mv update-index am cherry-pick rebase merge revert "

# Per-simple-command state, owned by check_protected_writes (dynamic scope):
# prot write sedw sedi sedwc interp inline findc findw gitc gitw.
classify_token() {
	local t="$1" b="${1##*/}"
	is_protected_path "$t" && prot="$t"
	case " $WRITE_WORDS " in *" $b "*) write="$t" ;; esac
	case "$t" in
		sed|*/sed|gsed) sedw="$t" ;;
		-i*|-[a-zA-Z]*i*|--in-place*) sedi=1 ;;
		python*|*/python*|perl*|*/perl*|ruby*|*/ruby*|node|*/node|php*|*/php*|lua*|*/lua*) interp="$t" ;;
	esac
	case "$t" in
		-c|-e|-[a-zA-Z]*[ce]) inline=1 ;;
	esac
	case "$t" in
		-delete|-exec*|-ok*|-fprint*|-fls) findw=1 ;;
	esac
	case "$t" in
		w|w[./]*|*/w|*/w[./]*|*[0-9\$]w|s/*/*/*w) sedwc=1 ;;
	esac
	case "$b" in find) findc=1 ;; git) gitc=1 ;; esac
	case "$GIT_WRITE_SUBS" in *" $t "*) gitw=1 ;; esac
}

# Verdict for the simple command just ended, then reset its state.
judge_simple_command() {
	if [ -n "$prot" ]; then
		[ -n "$write" ] && block "'$write' on a protected path is not allowed for agents (path: $prot)."
		[ -n "$sedw" ] && [ -n "$sedi" ] && block "in-place sed on a protected path is not allowed for agents (path: $prot)."
		[ -n "$sedw" ] && [ -n "$sedwc" ] && block "a sed w command on a protected path is not allowed for agents (path: $prot)."
		[ -n "$findc" ] && [ -n "$findw" ] && block "a find action on a protected path is not allowed for agents (path: $prot)."
		[ -n "$gitc" ] && [ -n "$gitw" ] && block "a git rewriting subcommand on a protected path is not allowed for agents (path: $prot)."
		[ -n "$interp" ] && [ -n "$inline" ] && block "an inline '$interp' program naming a protected path is not allowed for agents (path: $prot)."
	fi
	prot="" write="" sedw="" sedi="" sedwc="" interp="" inline="" findc="" findw="" gitc="" gitw=""
}

check_protected_writes() {
	local t redir=0
	local prot="" write="" sedw="" sedi="" sedwc="" interp="" inline="" findc="" findw="" gitc="" gitw=""
	# Nothing to protect unless a protected spelling is present somewhere;
	# the same substrings is_protected_path prefilters on. Keeps the common
	# command free of the per-token walk.
	hay="$cmd"
	ci '\.git|scripts|settings\.json' || return 0
	# A trailing ';' sentinel (added by tokenize) closes the last simple command.
	tokenize "$cmd"
	for t in ${toks[@]+"${toks[@]}"}; do
		if [ "$redir" = 1 ]; then
			# '>>', '>|' and '>&' tokenise as '>' plus a second operator token;
			# a quote glued to the target is skipped. The next token is the target.
			case "$t" in '>'|'|'|'&'|'"'|"'"|'`') continue ;; esac
			redir=0
			is_protected_path "$t" && block "redirecting output onto a protected path is not allowed for agents (path: $t)."
			continue
		fi
		case "$t" in
			';'|'|'|'&')
				judge_simple_command
				continue
				;;
			'>') redir=1; continue ;;
			'<'|'('|')'|'"'|"'"|'`'|','|'=') continue ;;
		esac
		classify_token "$t"
	done
	return 0
}

# Hook-skipping and history-plumbing patterns — applied to the command AND to
# invoked script contents.
check_bypass_patterns() {
	# --no-verify and its unambiguous prefixes.
	ci '[-][-]no-verif' && block "committing with the git hook disabled is not allowed for agents."
	ci 'review_?skip[[:space:]]*=' && block "committing with REVIEW_SKIP set is not allowed for agents."
	# git commit -n, including bundled clusters like -anm (any lowercase
	# short-flag cluster containing n is -n). Case-sensitive: -S<keyid> etc.
	cs 'git[^|;&]*[[:space:]]commit([^|;&]*)?[[:space:]]-[a-z]*n' && block "git commit -n skips the review hook."
	# Re-pointing or unsetting the hooks path. Reading it is fine, and setting
	# it to .githooks is the documented enable step.
	if ci 'core\.hookspath[[:space:]]*=[[:space:]]*[^[:space:]]' && ! ci 'core\.hookspath=(\./)?\.githooks([[:space:]]|$|"|'"'"')'; then
		block "re-pointing core.hookspath disables the review hook."
	fi
	if ci 'config[^|;&]*core\.hookspath[[:space:]]+[^[:space:]]' && ! ci 'config[^|;&]*core\.hookspath[[:space:]]+(\./)?\.githooks([[:space:]]|$|"|'"'"')'; then
		block "re-pointing core.hookspath disables the review hook."
	fi
	ci '[-][-]unset[^|;&]*core\.hookspath' && block "unsetting core.hookspath disables the review hook."
	# Hooks-path override supplied as environment configuration, e.g.
	# GIT_CONFIG_KEY_0=core.hookspath (the value assignment is '=core.hookspath').
	ci '=[[:space:]]*core\.hookspath' && block "hooks-path override via environment configuration disables the review hook."
	# History plumbing that never runs hooks.
	ci '(^|[^a-z-])(commit-tree|update-ref|filter-branch|fast-import)([^a-z-]|$)' && block "low-level history plumbing bypasses the review hook."
	return 0
}

# Tampering with the hook files themselves — command string only (script
# contents legitimately mention these paths, e.g. review-regress.sh).
check_tamper_patterns() {
	# The regex on the next line covers the same five write verbs as WRITE_WORDS
	# (the token rule above); keep the two in sync. guard-probes fails on drift.
	ci '(^|[^a-z-])(chmod|rm|mv|cp|truncate)[^|;&]*(\.githooks|pre-commit)' && block "modifying the hook files is not allowed for agents."
	ci '(>>?[[:space:]]*[^|;&[:space:]]*review-rubric|tee[^|;&]*review-rubric|sed[[:space:]]+-i[^|;&]*review-rubric)' && block "editing the review rubric from the shell is not allowed for agents."
	return 0
}

# The key path is refused in every mode, dev or not.
if [ "$mode" = file ]; then
	check_key_path "$fpath"
else
	check_key_path "$cmd"
fi

# --- file-tool payloads: judged by path only ---------------------------------
# The content is never scanned: a protected path is refused whatever it says,
# any other path is allowed whatever it says. REVIEW_HOOK_DEV=1 lifts this so
# the hooks themselves can be worked on from an agent session.
if [ "$mode" = file ]; then
	if [ "${REVIEW_HOOK_DEV:-0}" != "1" ] && is_protected_path "$fpath"; then
		block "writing to a protected path is not allowed for agents (path: $fpath)."
	fi
	exit 0
fi

# --- Bash commands -----------------------------------------------------------
hay="$cmd"
check_bypass_patterns
# REVIEW_HOOK_DEV=1 in the agent's environment lifts the tamper and
# protected-path checks so the hooks themselves can be worked on from an agent
# session. The bypass checks above and the key check stay on regardless.
if [ "${REVIEW_HOOK_DEV:-0}" != "1" ]; then
	check_tamper_patterns
	check_protected_writes
fi

# --- scan invoked script files (bounded; regular files only) -----------------
# A path is a scan target only when it is being executed: the argument to
# bash/sh/zsh/source, or a ./script in command position. A ./ or bash-shaped
# path sitting in argument position (`cat ./notes.md`, `wc -l ./x`) is data,
# not code, and must not be scanned — the guard runs on every Bash call, so a
# false block there freezes the session.
targets=()
prev=""
cmdpos=1 # the first word of the line is in command position
# Space-pad control operators so glued forms (`./x;then`, `a&&./x`) tokenize
# into separate words; only used for target discovery, never for pattern
# matching (which stays on the raw $cmd).
norm="$cmd"
norm="${norm//;/ ; }"
norm="${norm//&/ & }"
norm="${norm//|/ | }"
set -f
for w in $norm; do
	case "$prev" in
		bash|sh|zsh|*/bash|*/sh|*/zsh|source)
			case "$w" in -*) ;; *) targets[${#targets[@]}]="$w" ;; esac
			;;
	esac
	if [ "$cmdpos" = 1 ]; then
		case "$w" in ./*) targets[${#targets[@]}]="$w" ;; esac
	fi
	# The NEXT word is in command position after an operator, a shell keyword,
	# or a command-prefix wrapper (`time ./x`, `exec ./x`, `sudo ./x`). The
	# list can't be exhaustive — an unlisted wrapper (busybox-style) before a
	# ./script is residual, same class as the piped/cd holes in the header.
	case "$w" in
		"&&"|"||"|";"|";;"|"|"|"|&"|"("|"{"|"&") cmdpos=1 ;;
		if|then|elif|else|while|until|do|"!") cmdpos=1 ;;
		time|exec|env|nohup|nice|command|sudo|xargs|setsid|stdbuf|busybox) cmdpos=1 ;;
		*) cmdpos=0 ;;
	esac
	prev="$w"
done
set +f

scanned=0
for f in ${targets[@]+"${targets[@]}"}; do
	[ "$scanned" -ge 3 ] && break
	case "$f" in *scripts/guard-probes.sh|*scripts/backstop-probes.sh) continue ;; esac
	# Regular files only: a FIFO or device would block this pure-builtin read
	# forever, freezing every Bash call from inside the PreToolUse hook.
	[[ -f "$f" && -r "$f" ]] || continue
	scanned=$((scanned + 1))
	content=""
	IFS= read -r -d '' -n 65536 content <"$f" || true
	hay="$content"
	WHERE=" (found inside invoked script: $f.)"
	check_bypass_patterns
done

exit 0
