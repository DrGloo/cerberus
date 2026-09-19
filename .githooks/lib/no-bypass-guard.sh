#!/usr/bin/env bash
# Claude Code PreToolUse hook: refuse Bash commands that skip or defang the
# pre-commit AI code review. Humans can still bypass from their own terminal;
# agents cannot.
#
# Layers:
#   1. The command string is checked against bypass + tamper patterns.
#   2. Script files the command invokes (bash|sh|zsh <path>, ./<path>) are
#      scanned with the bypass patterns too — up to 3 regular files, first
#      64KB each — so a wrapper hiding `git commit --no-verify` is caught at
#      invocation. Tamper patterns are NOT applied to file contents (tracked
#      tooling like review-regress.sh legitimately copies .githooks into
#      worktrees), and the test-corpus scripts (scripts/guard-probes.sh,
#      scripts/backstop-probes.sh) are exempt — their content is trigger
#      strings by design. Overwriting an exempt file to smuggle a bypass is
#      part of the accepted residual surface below.
#
# Accepted residual holes (a static shell inspector cannot close these; the
# guard raises the cost of a bypass, it cannot make one impossible):
#   - a file written by a non-Bash tool in the same turn it is invoked;
#   - a script piped rather than named: `cat w.sh | bash`, `bash < w.sh`;
#   - a `cd other/ && ./w.sh` where w.sh is not at that path from the repo root;
#   - a ./script after a command-prefix word not in the command-position list;
#   - >64KB of leading padding before the bypass line in a scanned file;
#   - git plumbing beyond the listed commands.
#
# Pure bash builtins (read, [[ =~ ]]) on purpose: the guard must not fail open
# because an external tool is missing. jq is optional; without it the raw JSON
# payload is scanned — the command text is embedded in it verbatim (modulo
# quote escaping, which no pattern below relies on).

input=""
IFS= read -r -d '' input

cmd=""
if command -v jq >/dev/null 2>&1; then
	cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)" || cmd=""
fi
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
	ci '(^|[^a-z-])(chmod|rm|mv|cp|truncate)[^|;&]*(\.githooks|pre-commit)' && block "modifying the hook files is not allowed for agents."
	ci '(>>?[[:space:]]*[^|;&[:space:]]*review-rubric|tee[^|;&]*review-rubric|sed[[:space:]]+-i[^|;&]*review-rubric)' && block "editing the review rubric from the shell is not allowed for agents."
	return 0
}

hay="$cmd"
check_bypass_patterns
check_tamper_patterns

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
