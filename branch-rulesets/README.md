# Protect main – GitHub Ruleset

A branch ruleset that protects the repository's default branch (`main`).

## What it does

| Rule | Effect |
|---|---|
| **Target** | Default branch only (`~DEFAULT_BRANCH`), enforcement **active** |
| **No deletion** | The default branch can't be deleted |
| **No force push** | Rewriting history (`non_fast_forward`) is blocked |
| **Pull request required** | All changes go through a PR – no direct pushes |
| **0 approvals** | No review needed, so a solo dev can merge their own PRs |
| **Stale reviews dismissed** | New pushes reset existing approvals |
| **Resolve conversations** | All review threads must be resolved before merging |
| **Squash only** | Each PR lands as a single commit |
| **Status checks (strict)** | Branch must be up to date with `main` before merging; no specific checks listed yet |
| **No bypass** | Nobody, including admins, can skip these rules |

## How to use

1. Repo → **Settings → Rules → Rulesets**
2. **New ruleset → Import a ruleset**
3. Select `protect-main.json` and save

## Customizing

- Add CI checks: put job names into `required_status_checks`
- Require reviews: raise `required_approving_review_count`
- Allow an escape hatch: add yourself to `bypass_actors`
