#!/usr/bin/env bash
# Stage named paths: block `git add -A`, `git add .`, `git add -u` and `git commit -a`.
source "$(dirname "$0")/lib.sh"

msg="Stage named paths explicitly, e.g. git add src/a.ts."
while IFS= read -r seg; do
  words "$seg"
  [[ "${W[0]:-}" == git ]] || continue
  parse_git "${W[@]:1}"
  for a in "${GIT_ARGS[@]}"; do
    case "$GIT_SUB:$a" in
      add:--all | add:--update | add:. | add:./ | add:\* | add::/) deny "'git add $a' stages everything. $msg" ;;
      add:--*) ;;
      add:-*A* | add:-*u*) deny "'git add $a' stages everything. $msg" ;;
      commit:--all) deny "'git commit $a' stages everything. $msg" ;;
      commit:-m* | commit:-F* | commit:-C* | commit:-c* | commit:--) break ;; # the rest is a message
      commit:--*) ;;
      commit:-*a*) deny "'git commit $a' stages everything. $msg" ;;
    esac
  done
done < <(segments)
exit 0
