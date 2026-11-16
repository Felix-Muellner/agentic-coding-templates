#!/usr/bin/env bash
# Stop hook. The environment is disposable, so before Claude ends its turn,
# send it back once if there is uncommitted or unpushed work.
# Does not run when a turn ends because of a usage limit, an API error or an interrupt.
set -o pipefail

command -v jq >/dev/null || exit 0
[[ "$(jq -r '.stop_hook_active // false')" == true ]] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

found=""
[[ -n "$(git status --porcelain 2>/dev/null)" ]] && found+="uncommitted changes; "
unpushed=$(git rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)
((unpushed > 0)) && found+="$unpushed commit(s) not on GitHub; "

[[ -n "$found" ]] || exit 0
jq -n --arg r "Unpushed work: ${found%; }. The environment is disposable: commit and push it, or tell the user why not." \
  '{decision: "block", reason: $r}'
exit 0
