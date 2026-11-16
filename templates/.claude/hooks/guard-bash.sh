#!/usr/bin/env bash
# PreToolUse hook for Bash. Enforces CLAUDE.md rules on shell commands:
#   - no bulk staging (git add -A / . / -u, git commit -a)
#   - nothing lands on main (commit/merge on main, push to main, PR merge into main)
#   - global installs need the user's approval
#   - no reading secret files (.env, keys)
# Deny = exit 2 with the reason on stderr. Ask = JSON permissionDecision "ask".
set -uo pipefail

command -v jq >/dev/null || { echo "Blocked: project hooks need jq, which is not installed." >&2; exit 2; }

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true

MAIN=main

deny() { echo "Blocked by project hook: $1" >&2; exit 2; }
ask() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}

on_main() { [[ "$(git branch --show-current 2>/dev/null)" == "$MAIN" ]]; }

is_secret() {
  local b="${1##*/}"
  case "$b" in
    .env.example | .env.sample | .env.template | .env.dist | *.pub) return 1 ;;
    .env* | *.pem | *.key | id_rsa | id_dsa | id_ecdsa | id_ed25519) return 0 ;;
  esac
  return 1
}

check_secrets() { # words of one command segment
  local -a w=("$@")
  local n=${#w[@]} i t prev="" last_idx=$((${#w[@]} - 1))
  case "${w[0]:-}" in ls | touch | test | '[' | stat) return ;; esac
  for ((i = 1; i < n; i++)); do
    t="${w[i]}"
    # output redirection targets (> .env, >>.env) are writes, not reads
    if [[ "$prev" == ">" || "$prev" == ">>" || "$t" == '>'* ]]; then prev="$t"; continue; fi
    prev="$t"
    t="${t#<}"
    is_secret "$t" || continue
    # cp/mv into a secret file (e.g. cp .env.example .env) is allowed
    if [[ "${w[0]}" == cp || "${w[0]}" == mv ]] && ((i == last_idx)); then continue; fi
    deny "'$t' looks like a secret file. Don't read or use it; ask the user if a value is needed."
  done
}

check_git() { # words after "git"
  local -a w=("$@")
  local i=0
  while ((i < ${#w[@]})); do
    case "${w[i]}" in
      -C | -c | --git-dir | --work-tree | --namespace) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  local sub="${w[i]:-}"
  local -a args=("${w[@]:i+1}")
  local a

  case "$sub" in
    add)
      for a in "${args[@]}"; do
        case "$a" in
          -A | --all | --no-ignore-removal | . | ./ | '*' | ':/' | -u | --update | -[!-]*A* | -[!-]*u*)
            deny "bulk staging ('git add $a'). Stage named paths explicitly." ;;
        esac
      done
      ;;
    commit)
      for a in "${args[@]}"; do
        case "$a" in
          -m | -F | -C | -c | --) break ;; # the rest is a message/file, not flags
          --all | -[!-]*a* | -a)
            deny "'git commit $a' stages everything. Stage named paths with git add, then commit." ;;
        esac
      done
      on_main && deny "you are on '$MAIN'. Create a branch first; nothing is committed to $MAIN directly."
      ;;
    merge | cherry-pick | revert | am | rebase)
      on_main && deny "you are on '$MAIN'. Changes reach $MAIN only through a PR merged by the user."
      ;;
    push)
      local -a pos=()
      local skip=0
      for a in "${args[@]}"; do
        if ((skip)); then skip=0; continue; fi
        case "$a" in
          --all | --mirror) deny "'git push $a' would push $MAIN." ;;
          -o | --push-option | --repo | --receive-pack | --exec) skip=1 ;;
          -*) ;;
          *) pos+=("$a") ;;
        esac
      done
      if ((${#pos[@]} <= 1)); then
        on_main && deny "you are on '$MAIN'; this would push to $MAIN."
      else
        local ref dst
        for ref in "${pos[@]:1}"; do
          ref="${ref#+}"
          dst="${ref##*:}"
          dst="${dst#refs/heads/}"
          if [[ "$dst" == "$MAIN" ]]; then deny "pushing to '$MAIN' is not allowed. Push a branch and open a PR."; fi
          if [[ "$ref" != *:* && "$ref" == HEAD ]] && on_main; then deny "this would push to $MAIN."; fi
        done
      fi
      ;;
  esac
}

check_gh() { # words after "gh"
  local -a w=("$@")
  [[ "${w[0]:-}" == pr && "${w[1]:-}" == merge ]] || return
  local -a args=("${w[@]:2}")
  local sel="" repo="" skip="" a
  for a in "${args[@]}"; do
    if [[ -n "$skip" ]]; then
      [[ "$skip" == repo ]] && repo="$a"
      skip=""; continue
    fi
    case "$a" in
      -R | --repo) skip=repo ;;
      -t | --subject | -b | --body | -F | --body-file | -A | --author-email | --match-head-commit) skip=1 ;;
      --repo=*) repo="${a#--repo=}" ;;
      -*) ;;
      *) [[ -z "$sel" ]] && sel="$a" ;;
    esac
  done
  local -a view=(gh pr view)
  [[ -n "$sel" ]] && view+=("$sel")
  [[ -n "$repo" ]] && view+=(-R "$repo")
  local base
  if ! base=$("${view[@]}" --json baseRefName -q .baseRefName 2>/dev/null) || [[ -z "$base" ]]; then
    deny "couldn't verify the PR's base branch, so the merge was not run."
  fi
  [[ "$base" == "$MAIN" ]] && deny "this PR targets '$MAIN'. Merging into $MAIN is the user's job."
}

check_install() { # words of one command segment
  local -a w=("$@")
  local first="${w[0]:-}" rest=" ${w[*]:1} "
  case "$first" in
    sudo) ask "sudo runs a command as root; CLAUDE.md requires asking first." ;;
    apt | apt-get | brew | gem | pipx | cargo | go)
      [[ "$rest" == *" install "* || ( "$first" == brew && "$rest" == *" tap "* ) ]] &&
        ask "'$first install' installs system-wide; CLAUDE.md requires asking first." ;;
    npm | pnpm)
      [[ "$rest" == *" -g "* || "$rest" == *" --global "* || "$rest" == *" --location=global "* ]] &&
        ask "global $first install; CLAUDE.md requires asking first." ;;
    yarn)
      [[ "${w[1]:-}" == global ]] && ask "global yarn install; CLAUDE.md requires asking first." ;;
    pip | pip3 | python | python3)
      local is_pip=0
      [[ "$first" == pip* && "${w[1]:-}" == install ]] && is_pip=1
      [[ "$first" == python* && "$rest" == *" -m pip install "* ]] && is_pip=1
      ((is_pip)) || return
      if [[ "$rest" == *" --user "* || "$rest" == *" --break-system-packages "* ]]; then
        ask "pip install outside a virtualenv; CLAUDE.md requires asking first."
      fi
      [[ -n "${VIRTUAL_ENV:-}" || "$cmd" == *activate* ]] ||
        ask "pip install with no active virtualenv installs globally; CLAUDE.md requires asking first."
      ;;
  esac
}

# Split chained commands into segments and check each one.
segments=$(sed -E 's/(\&\&|\|\||;|\||\(|\)|`|\$\()/\n/g' <<<"$cmd")
while IFS= read -r seg; do
  read -ra words <<<"$seg" || true
  ((${#words[@]})) || continue
  # strip quotes from each word
  for i in "${!words[@]}"; do words[i]="${words[i]//[\"\']/}"; done
  # skip leading VAR=value assignments
  while ((${#words[@]})) && [[ "${words[0]}" == *=* && "${words[0]}" != -* ]]; do words=("${words[@]:1}"); done
  ((${#words[@]})) || continue

  check_secrets "${words[@]}"
  check_install "${words[@]}"
  [[ "${words[0]}" == sudo ]] && words=("${words[@]:1}")
  case "${words[0]:-}" in
    git) check_git "${words[@]:1}" ;;
    gh) check_gh "${words[@]:1}" ;;
  esac
done <<<"$segments"

exit 0
