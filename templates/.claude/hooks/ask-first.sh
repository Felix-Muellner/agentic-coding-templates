#!/usr/bin/env bash
# Ask the user before global installs (shell) or edits outside the project (file tools).
source "$(dirname "$0")/lib.sh"

if [[ "$TOOL" != Bash ]]; then
  path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$INPUT")
  [[ -n "$path" ]] || exit 0
  project=$(realpath -m "${CLAUDE_PROJECT_DIR:-$PWD}")
  [[ "$path" == /* ]] || path="$project/$path"
  target=$(realpath -m "$path")
  [[ "$target" == "$(realpath -m "$HOME/.claude/plans")"/* ]] && exit 0 # Claude's own plan files
  [[ "$target" == "$project" || "$target" == "$project"/* ]] || ask "'$target' is outside the project."
  exit 0
fi

while IFS= read -r seg; do
  words "$seg"
  first=${W[0]:-} rest=" ${W[*]:1} "
  case "$first" in
    sudo) ask "sudo runs a command as root." ;;
    apt | apt-get | brew | gem | pipx | cargo | go)
      [[ "$rest" == *" install "* ]] && ask "'$first install' installs system-wide." ;;
    npm | pnpm)
      [[ "$rest" == *" -g "* || "$rest" == *" --global "* ]] && ask "Global $first install." ;;
    yarn)
      [[ "${W[1]:-}" == global ]] && ask "Global yarn install." ;;
    pip | pip3 | python | python3)
      [[ -n "${VIRTUAL_ENV:-}" ]] && continue
      [[ ("$first" == pip* && "${W[1]:-}" == install) || "$rest" == *" -m pip install "* ]] &&
        ask "pip install outside a virtualenv installs globally." ;;
  esac
done < <(segments)
exit 0
