#!/usr/bin/env bash
# Stage named paths: block `git add -A`, `git add .`, `git add -u` and `git commit -a`.
source "$(dirname "$0")/lib.sh"

stages_all() { deny "'git $GIT_SUB $1' stages everything. Stage named paths explicitly, e.g. git add src/a.ts."; }

while IFS= read -r seg; do
  words "$seg"
  [[ "${W[0]:-}" == git ]] || continue
  parse_git "${W[@]:1}"
  skip=0
  for a in "${GIT_ARGS[@]}"; do
    if ((skip)); then skip=0; continue; fi
    case "$GIT_SUB:$a" in
      add:--all | add:--update | add:. | add:./ | add:\* | add::/ | add::\!* | add::^*) stages_all "$a" ;;
      add:--*) ;;
      add:-*A* | add:-*u*) stages_all "$a" ;;
      commit:--all) stages_all "$a" ;;
      commit:--) break ;;
      commit:-m | commit:-F | commit:-C | commit:-c) skip=1 ;; # the next word is the message
      commit:-m* | commit:-F* | commit:-C* | commit:-c* | commit:--*) ;;
      commit:-*a*) stages_all "$a" ;;
    esac
  done
done < <(segments)
exit 0
