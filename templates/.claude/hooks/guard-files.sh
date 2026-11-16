#!/usr/bin/env bash
# PreToolUse hook for Claude's file tools. Enforces CLAUDE.md rules:
#   - no reading or writing secret files (.env, keys); example files stay allowed
#   - editing files outside the project needs the user's approval
set -uo pipefail

command -v jq >/dev/null || { echo "Blocked: project hooks need jq, which is not installed." >&2; exit 2; }

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""' <<<"$input")
[[ -n "$path" ]] || exit 0

# Keep this list in sync with guard-bash.sh.
case "${path##*/}" in
  .env.example | .env.sample | .env.template | .env.dist | *.pub) ;;
  .env* | *.pem | *.key | id_rsa | id_dsa | id_ecdsa | id_ed25519)
    echo "Blocked by project hook: '$path' looks like a secret file. Don't read or write it; ask the user if a value is needed." >&2
    exit 2 ;;
esac

case "$tool" in
  Edit | MultiEdit | Write | NotebookEdit) ;;
  *) exit 0 ;;
esac

project=$(realpath -m "${CLAUDE_PROJECT_DIR:-$PWD}")
[[ "$path" == /* ]] || path="$project/$path"
target=$(realpath -m "$path")

# Claude's own plan files live outside the project and need no prompt.
[[ "$target" == "$(realpath -m "$HOME/.claude/plans")"/* ]] && exit 0

if [[ "$target" != "$project" && "$target" != "$project"/* ]]; then
  jq -n --arg r "'$target' is outside the project; CLAUDE.md requires asking first." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
fi
exit 0
