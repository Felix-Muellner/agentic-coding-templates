#!/usr/bin/env bash
# Nothing lands on main: block commits/merges on main, pushes to main and PR merges into main.
# Merging PRs into other branches (e.g. run/...) stays allowed.
source "$(dirname "$0")/lib.sh"

check_pr_merge() { # words after "gh pr merge"
  local -a view=(gh pr view)
  local a sel="" skip=0 base
  for a in "$@"; do
    if ((skip)); then view+=("$a"); skip=0
    elif [[ "$a" == -R || "$a" == --repo ]]; then view+=("$a"); skip=1
    elif [[ "$a" != -* && -z "$sel" ]]; then sel=$a; view+=("$a")
    fi
  done
  base=$("${view[@]}" --json baseRefName -q .baseRefName 2>/dev/null) ||
    deny "Couldn't verify the PR's base branch, so the merge was not run."
  [[ "$base" == "$MAIN" ]] && deny "This PR targets $MAIN. Merging into $MAIN is the user's job."
}

push_re="[[:space:]:+](refs/heads/)?$MAIN[[:space:]]|[[:space:]]--(all|mirror)[[:space:]]"
while IFS= read -r seg; do
  words "$seg"
  if [[ "${W[0]:-} ${W[1]:-} ${W[2]:-}" == "gh pr merge" ]]; then check_pr_merge "${W[@]:3}"; continue; fi
  [[ "${W[0]:-}" == git ]] || continue
  parse_git "${W[@]:1}"
  case "$GIT_SUB" in
    commit | merge | cherry-pick | revert | am | rebase)
      on_main && deny "You are on $MAIN. Create a branch first; $MAIN only changes through a PR the user merges." ;;
    push)
      [[ " ${GIT_ARGS[*]} " =~ $push_re ]] && deny "Don't push to $MAIN. Push a branch and open a pull request instead."
      on_main && deny "You are on $MAIN. Push from a branch and open a pull request instead." ;;
  esac
done < <(segments)
exit 0
