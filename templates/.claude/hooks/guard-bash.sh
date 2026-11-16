#!/usr/bin/env bash
# PreToolUse hook for Bash: enforces the project's mechanical rules on shell commands.
# Deny = exit 2 with the reason on stderr. Ask = JSON permissionDecision "ask".
set -o pipefail

command -v jq >/dev/null || { echo "Blocked: project hooks need jq, which is not installed." >&2; exit 2; }

cmd=$(jq -r '.tool_input.command // ""')
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true
MAIN=main
ask_reason=""

deny() { echo "Blocked by project hook: $1" >&2; exit 2; }
ask() { [[ -n "$ask_reason" ]] || ask_reason="$1 Ask the user first."; } # reported after all checks
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
  case "${w[0]}" in echo | printf | test | '[' | ls | touch) return ;; esac
  for ((i = 1; i < n; i++)); do
    is_secret "${w[i]}" || continue
    [[ "${w[i-1]}" == '>' || "${w[i-1]}" == '>>' ]] && continue # writing, not reading
    [[ ("${w[0]}" == cp || "${w[0]}" == mv) && i -eq n-1 ]] && continue # cp .env.example .env
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
      [[ -n "${VIRTUAL_ENV:-}" ]] && return
      [[ ("$first" == pip* && "${2:-}" == install) || "$rest" == *" -m pip install "* ]] &&
        ask "pip install outside a virtualenv installs globally." ;;
  esac
}

check_git() {
  local sub="" a skip=0
  local -a args=()
  for a in "$@"; do
    if [[ -n "$sub" ]]; then args+=("$a")
    elif ((skip)); then skip=0
    elif [[ "$a" == -C || "$a" == -c || "$a" == --git-dir || "$a" == --work-tree ]]; then skip=1
    elif [[ "$a" != -* ]]; then sub=$a
    fi
  done

  case "$sub" in
    add)
      for a in "${args[@]}"; do
        case "$a" in
          --all | --update | . | ./ | '*' | :/) deny "bulk staging ('git add $a'). Stage named paths explicitly." ;;
          --*) ;;
          -*A* | -*u*) deny "bulk staging ('git add $a'). Stage named paths explicitly." ;;
        esac
      done
      ;;
    commit)
      for a in "${args[@]}"; do
        case "$a" in
          --all) deny "'git commit $a' stages everything. Stage named paths, then commit." ;;
          -m* | -F* | -C* | -c* | --) break ;; # the rest is a message, not flags
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
  local -a view=(gh pr view)
  local a sel="" skip=0 base
  for a in "${@:3}"; do
    if ((skip)); then view+=("$a"); skip=0
    elif [[ "$a" == -R || "$a" == --repo ]]; then view+=("$a"); skip=1
    elif [[ "$a" != -* && -z "$sel" ]]; then sel=$a; view+=("$a")
    fi
  done
  base=$("${view[@]}" --json baseRefName -q .baseRefName 2>/dev/null) ||
    deny "couldn't verify the PR's base branch, so the merge was not run."
  [[ "$base" == "$MAIN" ]] && deny "this PR targets '$MAIN'. Merging into $MAIN is the user's job."
}

# Drop text that is data, not commands: heredoc bodies and quoted messages/bodies.
# Then split chained commands (&&, ||, ;, |, subshells) and space out redirects.
segments=$(perl -0pe '
  s/<<-?[ \t]*([\x27"]?)(\w+)\1([^\n]*)\n.*?\n[ \t]*\2[ \t]*(?=\n|$)/HEREDOC$3/gs;
  s/(\s(?:-m|--message|--body|--title|--subject|-b|-t)[=\s]*)("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/$1MSG/gs;
  s/&&|\|\||;|\||\(|\)|`|\$\(/\n/g;
  s/(>>?|<)/ $1 /g;
' <<<"$cmd")

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
done <<<"$segments"

if [[ -n "$ask_reason" ]]; then
  jq -n --arg r "$ask_reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
fi
exit 0
