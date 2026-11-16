#!/usr/bin/env bash
# PreToolUse hook for Bash: enforces the mechanical CLAUDE.md rules on shell commands.
# Deny = exit 2 with the reason on stderr. Ask = JSON permissionDecision "ask".
set -uo pipefail

command -v jq >/dev/null || { echo "Blocked: project hooks need jq, which is not installed." >&2; exit 2; }

cmd=$(jq -r '.tool_input.command // ""')
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true
MAIN=main

deny() { echo "Blocked by project hook: $1" >&2; exit 2; }
ask() {
  jq -n --arg r "$1 CLAUDE.md requires asking first." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}
on_main() { [[ "$(git branch --show-current 2>/dev/null)" == "$MAIN" ]]; }

# Keep this list in sync with guard-files.sh.
is_secret() {
  case "${1##*/}" in
    .env.example | .env.sample | .env.template | .env.dist | *.pub) return 1 ;;
    .env* | *.pem | *.key | id_rsa | id_dsa | id_ecdsa | id_ed25519) return 0 ;;
  esac
  return 1
}

check_secrets() {
  local -a w=("$@")
  local i n=$#
  for ((i = 1; i < n; i++)); do
    is_secret "${w[i]}" || continue
    # copying a template into place (cp .env.example .env) is fine
    [[ ("${w[0]}" == cp || "${w[0]}" == mv) && i -eq n-1 ]] && continue
    deny "'${w[i]}' looks like a secret file. Don't read it; ask the user if a value is needed."
  done
}

check_install() {
  local first=$1 rest=" ${*:2} "
  case "$first" in
    sudo) ask "sudo runs a command as root." ;;
    apt | apt-get | brew | gem | pipx | cargo | go)
      [[ "$rest" == *" install "* ]] && ask "'$first install' installs system-wide." ;;
    npm | pnpm)
      [[ "$rest" == *" -g "* || "$rest" == *" --global "* ]] && ask "Global $first install." ;;
    yarn)
      [[ "${2:-}" == global ]] && ask "Global yarn install." ;;
    pip | pip3 | python | python3)
      [[ ("$first" == pip* && "${2:-}" == install) || "$rest" == *" -m pip install "* ]] &&
        [[ -z "${VIRTUAL_ENV:-}" ]] && ask "pip install outside a virtualenv installs globally." ;;
  esac
}

check_git() {
  local sub="" a
  local -a args=()
  for a in "$@"; do
    if [[ -n "$sub" ]]; then args+=("$a"); elif [[ "$a" != -* ]]; then sub=$a; fi
  done

  case "$sub" in
    add)
      for a in "${args[@]}"; do
        case "$a" in
          --all | --update | . | ./ | '*') deny "bulk staging ('git add $a'). Stage named paths explicitly." ;;
          --*) ;;
          -*A* | -*u*) deny "bulk staging ('git add $a'). Stage named paths explicitly." ;;
        esac
      done
      ;;
    commit)
      for a in "${args[@]}"; do
        case "$a" in
          -m | -F | -C | -c | --) break ;; # the rest is a message, not flags
          --all) deny "'git commit $a' stages everything. Stage named paths, then commit." ;;
          --*) ;;
          -*a*) deny "'git commit $a' stages everything. Stage named paths, then commit." ;;
        esac
      done
      on_main && deny "you are on '$MAIN'. Create a branch first."
      ;;
    merge | cherry-pick | revert | am | rebase)
      on_main && deny "you are on '$MAIN'. Changes reach $MAIN only through a PR the user merges."
      ;;
    push)
      local re="[[:space:]:+](refs/heads/)?$MAIN[[:space:]]|[[:space:]]--(all|mirror)[[:space:]]"
      [[ " ${args[*]} " =~ $re ]] && deny "this would push to $MAIN. Push a branch and open a PR."
      on_main && deny "you are on '$MAIN'. Push from a branch instead."
      ;;
  esac
}

check_gh() {
  [[ "${1:-} ${2:-}" == "pr merge" ]] || return
  local -a sel=()
  local a base
  for a in "${@:3}"; do [[ "$a" != -* ]] && { sel=("$a"); break; }; done
  base=$(gh pr view "${sel[@]}" --json baseRefName -q .baseRefName 2>/dev/null) ||
    deny "couldn't verify the PR's base branch, so the merge was not run."
  [[ "$base" == "$MAIN" ]] && deny "this PR targets '$MAIN'. Merging into $MAIN is the user's job."
}

# Check each part of a chained command (&&, ||, ;, |, subshells) on its own.
while IFS= read -r seg; do
  read -ra w <<<"${seg//[\"\']/}"
  while ((${#w[@]})) && [[ "${w[0]}" == *=* ]]; do w=("${w[@]:1}"); done # skip VAR=value
  ((${#w[@]})) || continue
  check_secrets "${w[@]}"
  check_install "${w[@]}"
  case "${w[0]}" in
    git) check_git "${w[@]:1}" ;;
    gh) check_gh "${w[@]:1}" ;;
  esac
done < <(sed -E 's/(&&|\|\||;|\||\(|\)|`|\$\()/\n/g' <<<"$cmd")

exit 0
