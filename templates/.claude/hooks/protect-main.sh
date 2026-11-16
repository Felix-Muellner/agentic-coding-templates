#!/bin/bash
# Stops Claude from pushing to main or merging into main.
#
# Claude Code runs this script before every shell command Claude wants to run.
# It sends the command to the script as JSON, like:
#   {"tool_input": {"command": "git push"}}
# If the script prints a "deny" answer, the command is not run.

# 1. Read the command Claude wants to run.
command=$(jq -r '.tool_input.command')

# 2. Find out which branch the project is on.
#    Some repos call their main branch "master" instead of "main".
branch=$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current)
on_main=false
if [[ "$branch" == "main" || "$branch" == "master" ]]; then
  on_main=true
fi

# 3. A helper that prints the "deny" answer with a reason, then stops.
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

# 4. On main (or master): no pushing and no merging.
if [[ "$on_main" == true && "$command" == *"git push"* ]]; then
  deny "You are on $branch. Create a branch, push that, and open a pull request."
fi
if [[ "$on_main" == true && "$command" == *"git merge"* ]]; then
  deny "You are on $branch. Changes reach $branch only through a pull request."
fi

# 5. Merging a pull request: only allowed if it does NOT target main.
if [[ "$command" == *"gh pr merge"* ]]; then
  pr_number=$(echo "$command" | grep -oE 'gh pr merge [0-9]+' | grep -oE '[0-9]+')
  target=$(gh pr view $pr_number --json baseRefName --jq .baseRefName)
  if [[ "$target" != "run/"* ]]; then
    deny "Only pull requests into run/ branches may be merged. Merging into main or master is the user's job."
  fi
fi

# 6. Anything else: allowed.
exit 0
