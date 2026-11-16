#!/usr/bin/env bash
# Keep secrets out of the conversation: block reading .env and key files,
# from the shell or with Claude's file tools. Example files (.env.example) stay allowed.
source "$(dirname "$0")/lib.sh"

is_secret() {
  local name=${1##*/}
  case "${name##*:}" in # ${name##*:} also catches git paths like HEAD:.env
    .env.example | .env.sample | .env.template | .env.dist | *.pub) return 1 ;;
    .env* | *.pem | *.key | id_rsa | id_dsa | id_ecdsa | id_ed25519) return 0 ;;
  esac
  return 1
}
msg="looks like a secret file. Don't read it; ask the user if a value is needed."

if [[ "$TOOL" != Bash ]]; then
  while IFS= read -r p; do
    is_secret "$p" && deny "'$p' $msg"
  done < <(jq -r '.tool_input | (.file_path, .notebook_path, .path, .glob) // empty' <<<"$INPUT")
  exit 0
fi

while IFS= read -r seg; do
  words "$seg"
  case "${W[0]:-}" in echo | printf | test | '[' | ls | touch | '') continue ;; esac
  [[ "${W[0]} ${W[1]:-}" == "git rm" || "${W[0]} ${W[1]:-}" == "git check-ignore" ]] && continue
  pattern=0 # grep/rg: the first plain word is the search pattern, not a file
  for ((i = 1; i < ${#W[@]}; i++)); do
    if [[ "${W[0]}" =~ ^(grep|rg)$ && "${W[i]}" != -* ]] && ((!pattern)); then pattern=1; continue; fi
    is_secret "${W[i]}" || continue
    [[ "${W[i-1]}" == '>' || "${W[i-1]}" == '>>' ]] && continue # writing, not reading
    [[ ("${W[0]}" == cp || "${W[0]}" == mv) && i -eq ${#W[@]}-1 ]] && continue # cp .env.example .env
    deny "'${W[i]}' $msg"
  done
done < <(segments)
exit 0
