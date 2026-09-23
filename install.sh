#!/usr/bin/env bash
# install.sh <target-repo> [--upgrade]
#
# Installs Cerberus, the review hooks, into another repository: every path in
# MANIFEST, then points core.hooksPath at the hook directory.
#   hook, lib, script, probe  copied; replaced by --upgrade
#   settings                  the agent guard registration, merged if present
#   seed                      created only when absent, never overwritten:
#                             review.conf, the project rubric, the regress
#                             suite's expected.tsv, the CI workflow
# VERSION is stamped into .githooks/VERSION. A repository that already has a
# hook directory is refused, naming both versions; --upgrade replaces the
# manifest's files, keeps the seeds, and prints the CHANGELOG entries since the
# installed version. File modes travel with the copy, so the hooks arrive
# executable. Flags may come in any position; --force is the old spelling of
# --upgrade.
set -u

HOOKS=".githooks"
SRC="$(cd "$(dirname "$0")" && pwd)"

usage() { sed -n '2,17p' "$0"; exit 2; }
TARGET=""
MODE="install"
for arg in "$@"; do
	case "$arg" in
		--upgrade|--force) MODE="upgrade" ;;
		-h|--help) usage ;;
		-*) echo "install: unknown flag $arg" >&2; exit 2 ;;
		*)
			[ -z "$TARGET" ] || { echo "install: one target repository only" >&2; exit 2; }
			TARGET="$arg"
			;;
	esac
done
[ -n "$TARGET" ] || usage
if ! DST="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)"; then
	echo "install: $TARGET is not inside a git repository" >&2
	exit 2
fi

new_version="$(cat "$SRC/VERSION")"
old_version=""
if [ -e "$DST/$HOOKS" ]; then
	# Installs before 0.2.0 carried no VERSION file.
	old_version="$(cat "$DST/$HOOKS/VERSION" 2>/dev/null)" || old_version="0.1.0"
	if [ "$MODE" != "upgrade" ]; then
		echo "install: $DST/$HOOKS already exists (installed: $old_version, this source: $new_version); pass --upgrade to replace the installed files (review.conf, the project rubric and the regress suite are kept)" >&2
		exit 1
	fi
fi

# --- copy the manifest --------------------------------------------------------
# cp -p, not cat: it carries the executable bit, and a hook that arrives
# without it is silently ignored by git.
changed=""
created=""
settings_path=""
settings_src=""
while read -r kind path src; do
	case "$kind" in ''|'#'*) continue ;; esac
	src="$SRC/${src:-$path}"
	case "$kind" in
		hook|lib|script|probe)
			cmp -s "$src" "$DST/$path" || changed="$changed $path"
			mkdir -p "$(dirname "$DST/$path")" && cp -p "$src" "$DST/$path" \
				|| { echo "install: could not copy $path" >&2; exit 1; }
			;;
		seed)
			[ -e "$DST/$path" ] && continue
			mkdir -p "$(dirname "$DST/$path")" && cp "$src" "$DST/$path" \
				|| { echo "install: could not create $path" >&2; exit 1; }
			created="$created $path"
			;;
		settings) settings_path="$path"; settings_src="$src" ;;
		*) echo "install: unknown kind '$kind' in MANIFEST" >&2; exit 2 ;;
	esac
done <"$SRC/MANIFEST"

# --- the agent guard registration ----------------------------------------------
# The guard is a Claude Code PreToolUse hook. The repository's own settings
# file is the source and holds only that registration, so a target without
# one receives it as-is. Merge into an existing file with jq; without jq, or
# with a file that already registers the guard, leave it alone and say so.
settings_dst="$DST/$settings_path"
if [ -f "$settings_dst" ]; then
	if grep -q "no-bypass-guard" "$settings_dst"; then
		guard_note="$settings_path already registers the guard"
	elif command -v jq >/dev/null 2>&1; then
		merged="$(jq -s '
			.[0] as $existing | .[1] as $source |
			$existing * {hooks: {PreToolUse: (($existing.hooks.PreToolUse // []) + $source.hooks.PreToolUse)}}
		' "$settings_dst" "$settings_src")" \
			&& printf '%s\n' "$merged" >"$settings_dst" \
			&& guard_note="guard merged into existing $settings_path"
	else
		guard_note="$settings_path exists and jq is not installed: add the PreToolUse entries from $settings_src by hand"
	fi
else
	mkdir -p "$(dirname "$settings_dst")"
	cat "$settings_src" >"$settings_dst"
	guard_note="guard registered in new $settings_path"
fi

git -C "$DST" config core.hooksPath "$HOOKS"   # the documented enable step; once per clone

if [ "$MODE" = "upgrade" ] && [ -n "$old_version" ]; then
	echo "Cerberus upgraded in $DST: $old_version -> $new_version"
	echo "  replaced: ${changed:- (nothing; files already current)}"
	echo "  created:  ${created:- (nothing; project files already present)}"
	echo "  agent:    $guard_note"
	if [ "$old_version" != "$new_version" ] && [ -f "$SRC/CHANGELOG.md" ]; then
		echo
		# Every section above the installed version's heading.
		awk -v old="$old_version" '/^## / { if ($2 == old) exit; seen = 1 } seen' "$SRC/CHANGELOG.md"
	fi
	exit 0
fi

cat <<MSG
Cerberus $new_version installed into $DST
  hooks:    $HOOKS/  (core.hooksPath set)
  scripts:  scripts/  (review, regress runner, probe suites)
  agent:    $guard_note
  created: ${created:- (nothing; project files already present)}

next:
  1. edit $HOOKS/review.conf (model, source dirs, lint command)
  2. write $HOOKS/review-rubric.project.md (house rules; see examples/)
  3. commit $HOOKS/ scripts/ .claude/settings.json .github/workflows/review.yml
     so every clone gets them; each clone still runs the config line above once
  4. bash scripts/guard-probes.sh && bash scripts/backstop-probes.sh
MSG
