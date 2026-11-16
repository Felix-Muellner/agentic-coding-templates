# Shared helpers for the PreToolUse hook scripts. Sourced, not run.
set -o pipefail

command -v jq >/dev/null || { echo "Blocked: project hooks need jq, which is not installed." >&2; exit 2; }

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // ""' <<<"$INPUT")
CMD=$(jq -r '.tool_input.command // ""' <<<"$INPUT")
MAIN=main
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true

decide() { # decide deny|ask "reason"
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}
deny() { decide deny "$1"; }
ask() { decide ask "$1 Ask the user first."; }

on_main() { [[ "$(git branch --show-current 2>/dev/null)" == "$MAIN" ]]; }

is_secret() {
  case "${1##*/}" in
    .env.example | .env.sample | .env.template | .env.dist | *.pub) return 1 ;;
    .env* | *.pem | *.key | id_rsa | id_dsa | id_ecdsa | id_ed25519) return 0 ;;
  esac
  return 1
}

# Prints the shell command one part per line. Heredoc bodies and quoted
# messages/bodies are dropped (they are text, not commands), chains
# (&&, ||, ;, |, subshells) are split, and redirects get spaces around them.
segments() {
  perl -0pe '
    s/<<-?[ \t]*([\x27"]?)(\w+)\1([^\n]*)\n.*?\n[ \t]*\2[ \t]*(?=\n|$)/HEREDOC$3/gs;
    s/(\s(?:-m|--message|--body|--title|--subject|-b|-t)[=\s]*)("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/$1MSG/gs;
    s/&&|\|\||;|\||\(|\)|`|\$\(/\n/g;
    s/(>>?|<)/ $1 /g;
  ' <<<"$CMD"
}

# Splits one part into the array W: quotes stripped, leading VAR=value dropped.
words() {
  read -ra W <<<"${1//[\"\']/}"
  while ((${#W[@]})) && [[ "${W[0]}" == *=* ]]; do W=("${W[@]:1}"); done
}

# For the words after "git": sets GIT_SUB (e.g. "push") and GIT_ARGS.
parse_git() {
  local a skip=0
  GIT_SUB="" GIT_ARGS=()
  for a in "$@"; do
    if [[ -n "$GIT_SUB" ]]; then GIT_ARGS+=("$a")
    elif ((skip)); then skip=0
    elif [[ "$a" == -C || "$a" == -c || "$a" == --git-dir || "$a" == --work-tree ]]; then skip=1
    elif [[ "$a" != -* ]]; then GIT_SUB=$a
    fi
  done
}
