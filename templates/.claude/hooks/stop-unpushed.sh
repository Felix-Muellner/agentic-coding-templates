#!/usr/bin/env bash
# Stop hook. The environment is disposable, so before Claude ends its turn,
# send it back once if there is uncommitted or unpushed work.
# Does not run when a turn ends because of a usage limit, an API error or an interrupt.
set -uo pipefail

command -v jq >/dev/null || exit 0

input=$(cat)
[[ "$(jq -r '.stop_hook_active // false' <<<"$input")" == true ]] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

problems=()
[[ -n "$(git status --porcelain 2>/dev/null)" ]] && problems+=("uncommitted changes")

branch=$(git branch --show-current 2>/dev/null)
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  ((ahead > 0)) && problems+=("$ahead commit(s) not pushed")
elif [[ -n "$branch" ]]; then
  local_only=$(git rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)
  ((local_only > 0)) && problems+=("branch '$branch' has $local_only commit(s) that are not on GitHub")
fi

((${#problems[@]})) || exit 0

joined=$(printf '%s; ' "${problems[@]}")
reason="Unpushed work: ${joined%; }. The environment is disposable: commit and push it, or tell the user why not."
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
