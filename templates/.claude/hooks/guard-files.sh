#!/usr/bin/env bash
# PreToolUse hook for Claude's file tools. Enforces the project's rules:
#   - no reading or writing secret files (.env, keys); example files stay allowed
#   - editing files outside the project needs the user's approval
set -o pipefail

command -v jq >/dev/null || { echo "Blocked: project hooks need jq, which is not installed." >&2; exit 2; }

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""' <<<"$input")
glob=$(jq -r '.tool_input.glob // ""' <<<"$input")

# Keep this list in sync with guard-bash.sh.
for p in "$path" "$glob"; do
  case "${p##*/}" in
    "" | .env.example | .env.sample | .env.template | .env.dist | *.pub) ;;
    .env* | *.pem | *.key | id_rsa | id_dsa | id_ecdsa | id_ed25519)
      echo "Blocked by project hook: '$p' looks like a secret file. Don't read or write it; ask the user if a value is needed." >&2
      exit 2 ;;
  esac
done

case "$tool" in
  Edit | MultiEdit | Write | NotebookEdit) ;;
  *) exit 0 ;;
esac
[[ -n "$path" ]] || exit 0

project=$(realpath -m "${CLAUDE_PROJECT_DIR:-$PWD}")
[[ "$path" == /* ]] || path="$project/$path"
target=$(realpath -m "$path")

# Claude's own plan files live outside the project and need no prompt.
[[ "$target" == "$(realpath -m "$HOME/.claude/plans")"/* ]] && exit 0

if [[ "$target" != "$project" && "$target" != "$project"/* ]]; then
  jq -n --arg r "'$target' is outside the project. Ask the user first." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
fi
exit 0
