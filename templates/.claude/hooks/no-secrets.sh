#!/usr/bin/env bash
# Keep secrets out of the conversation: block reading .env and key files,
# from the shell or with Claude's file tools. Example files (.env.example) stay allowed.
source "$(dirname "$0")/lib.sh"

msg="looks like a secret file. Don't read it; ask the user if a value is needed."

if [[ "$TOOL" != Bash ]]; then
  for p in "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""' <<<"$INPUT")" \
           "$(jq -r '.tool_input.glob // ""' <<<"$INPUT")"; do
    [[ -n "$p" ]] && is_secret "$p" && deny "'$p' $msg"
  done
  exit 0
fi

while IFS= read -r seg; do
  words "$seg"
  case "${W[0]:-}" in echo | printf | test | '[' | ls | touch | '') continue ;; esac
  for ((i = 1; i < ${#W[@]}; i++)); do
    is_secret "${W[i]}" || continue
    [[ "${W[i-1]}" == '>' || "${W[i-1]}" == '>>' ]] && continue # writing, not reading
    [[ ("${W[0]}" == cp || "${W[0]}" == mv) && i -eq ${#W[@]}-1 ]] && continue # cp .env.example .env
    deny "'${W[i]}' $msg"
  done
done < <(segments)
exit 0
