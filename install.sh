#!/usr/bin/env bash
# install.sh <target-repo> [--force]
#
# Installs Cerberus, the review hooks, into another repository:
#   .githooks/            the three hooks, the shared library, the agent guard,
#                         the generic rubric, a config example, and an empty
#                         regress suite
#   scripts/review*.sh    branch review, regress runner, and the probe suites
#   .claude/settings.json the agent guard registration (merged if present)
# then points core.hooksPath at the hook directory. Without --force it refuses
# to overwrite an existing hook directory. File modes travel with the copy, so
# the hooks arrive executable.
#
# Project-specific files are created only when absent and never overwritten:
#   .githooks/review.conf              (from review.conf.example)
#   .githooks/review-rubric.project.md (from templates/)
set -u

HOOKS=".githooks"
SCRIPTS="scripts"
GUARD_SETTINGS=".claude/settings.json"
HOOK_FILES="pre-commit post-commit pre-push lib/review-core.sh lib/no-bypass-guard.sh review-rubric.md review.conf.example regress/expected.tsv"
SCRIPT_FILES="review.sh review-regress.sh guard-probes.sh backstop-probes.sh"
PROJECT_RUBRIC="review-rubric.project.md"
PROJECT_CONF="review.conf"

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-}"
FORCE="${2:-}"
if [ -z "$TARGET" ] || [ "$TARGET" = "-h" ] || [ "$TARGET" = "--help" ]; then
	sed -n '2,15p' "$0"
	exit 2
fi
if ! DST="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)"; then
	echo "install: $TARGET is not inside a git repository" >&2
	exit 2
fi
if [ -e "$DST/$HOOKS" ] && [ "$FORCE" != "--force" ]; then
	echo "install: $DST/$HOOKS already exists; pass --force to overwrite the hook files (project files are kept)" >&2
	exit 1
fi

# tar, not a file-by-file copy: it carries the executable bit, and a hook that
# arrives without it is silently ignored by git.
# shellcheck disable=SC2086
(cd "$SRC/$HOOKS" && tar -cf - $HOOK_FILES) | (mkdir -p "$DST/$HOOKS" && tar -xf - -C "$DST/$HOOKS")
# shellcheck disable=SC2086
(cd "$SRC/$SCRIPTS" && tar -cf - $SCRIPT_FILES) | (mkdir -p "$DST/$SCRIPTS" && tar -xf - -C "$DST/$SCRIPTS")

created=""
conf_dst="$DST/$HOOKS/$PROJECT_CONF"
if [ ! -f "$conf_dst" ]; then
	cat "$SRC/$HOOKS/review.conf.example" >"$conf_dst"
	created="$created $HOOKS/$PROJECT_CONF"
fi
rubric_dst="$DST/$HOOKS/$PROJECT_RUBRIC"
if [ ! -f "$rubric_dst" ]; then
	cat "$SRC/templates/$PROJECT_RUBRIC" >"$rubric_dst"
	created="$created $HOOKS/$PROJECT_RUBRIC"
fi

# The agent guard is a Claude Code PreToolUse hook. Merge into an existing
# settings file with jq; without jq, or with a settings file that already has
# a guard entry, leave it alone and say so.
guard_note=""
settings_dst="$DST/$GUARD_SETTINGS"
if [ -f "$settings_dst" ]; then
	if grep -q "no-bypass-guard" "$settings_dst"; then
		guard_note="$GUARD_SETTINGS already registers the guard"
	elif command -v jq >/dev/null 2>&1; then
		merged="$(jq -s '
			.[0] as $existing | .[1] as $template |
			$existing * {hooks: {PreToolUse: (($existing.hooks.PreToolUse // []) + $template.hooks.PreToolUse)}}
		' "$settings_dst" "$SRC/templates/claude-settings.json")" \
			&& printf '%s\n' "$merged" >"$settings_dst" \
			&& guard_note="guard merged into existing $GUARD_SETTINGS"
	else
		guard_note="$GUARD_SETTINGS exists and jq is not installed: add the PreToolUse entries from templates/claude-settings.json by hand"
	fi
else
	mkdir -p "$DST/.claude"
	cat "$SRC/templates/claude-settings.json" >"$settings_dst"
	guard_note="guard registered in new $GUARD_SETTINGS"
fi

git -C "$DST" config core.hooksPath .githooks   # the documented enable step; once per clone

cat <<MSG
Cerberus installed into $DST
  hooks:    $HOOKS/  (core.hooksPath set)
  scripts:  $SCRIPTS/review.sh review-regress.sh guard-probes.sh backstop-probes.sh
  agent:    $guard_note
  created: ${created:- (nothing; project files already present)}

next:
  1. edit $HOOKS/$PROJECT_CONF (model, source dirs, lint command)
  2. write $HOOKS/$PROJECT_RUBRIC (house rules; see examples/)
  3. commit $HOOKS/ $SCRIPTS/ $GUARD_SETTINGS so every clone gets them;
     each clone still runs the config line above once
  4. bash $SCRIPTS/guard-probes.sh && bash $SCRIPTS/backstop-probes.sh
MSG
