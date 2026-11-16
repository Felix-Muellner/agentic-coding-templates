#!/bin/bash
# Stops Claude from pushing to main or merging into main.
#
# Claude Code runs this script before every shell command Claude wants to run.
# It sends the command to the script as JSON, like:
#   {"tool_input": {"command": "git push"}}
# If the script prints a "deny" answer, the command is not run.

# 1. This script needs jq. Without it, block everything instead of quietly allowing it.
if ! command -v jq >/dev/null; then
  echo "protect-main.sh needs jq, which is not installed." >&2
  exit 2
fi

# 2. Read the command Claude wants to run.
command=$(jq -r '.tool_input.command')

# 3. Find out which branch the project is on.
#    Some repos call their main branch "master" instead of "main".
branch=$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current)
on_main=false
if [[ "$branch" == "main" || "$branch" == "master" ]]; then
  on_main=true
fi

# 4. A helper that prints the "deny" answer with a reason, then stops.
deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# 5. On main (or master): no pushing and no merging.
if [[ "$on_main" == true && "$command" == *"git push"* ]]; then
  deny "You are on $branch. Create a branch, push that, and open a pull request."
fi
if [[ "$on_main" == true && "$command" == *"git merge"* ]]; then
  deny "You are on $branch. Changes reach $branch only through a pull request."
fi

# 6. Merging a pull request: only allowed into run/ branches.
if [[ "$command" == *"gh pr merge"* ]]; then
  pr_number=$(echo "$command" | grep -oE 'gh pr merge [0-9]+' | grep -oE '[0-9]+')
  if [[ -z "$pr_number" ]]; then
    deny "Put the PR number right after gh pr merge, e.g. gh pr merge 12 --squash."
  fi
  target=$(gh pr view "$pr_number" --json baseRefName --jq .baseRefName 2>/dev/null)
  if [[ -z "$target" ]]; then
    deny "Couldn't find the PR's target branch, so the merge was not run."
  fi
  if [[ "$target" != "run/"* ]]; then
    deny "This PR targets $target. Only PRs into run/ branches may be merged; merging into main or master is the user's job."
  fi
fi

# 7. Anything else: allowed.
exit 0
