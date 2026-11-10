# agentic-coding-templates

Reusable templates for agentic coding: an agent instruction file, a dev container, and a branch ruleset that I would otherwise rewrite for every new repo.

> **Status:** experimental. Written for a solo workflow in disposable environments (e.g. Codespaces) and tried mostly with [Claude Code](https://docs.claude.com/en/docs/claude-code/overview). Expect changes as I learn what works.

## Contents

| File | Purpose |
|------|---------|
| [`templates/CLAUDE.md`](templates/CLAUDE.md) | Self-configuring agent instructions: first-run setup, test-driven development, issue-based workflow, independent verification, hard boundaries. |
| [`templates/.devcontainer/`](templates/.devcontainer/) | Baseline dev container: latest Ubuntu LTS base image, GitHub CLI, and Claude Code installed on create. |
| [`branch-rulesets/protect-main.json`](branch-rulesets/protect-main.json) | GitHub ruleset that protects `main`: PRs only, squash merges, no force pushes, no bypass. See its [README](branch-rulesets/README.md). |

More templates (glossary, spec, and similar) will be added as they prove useful.

## Usage

Copy the template you need into the root of the target repo, then start your agent. Each template explains its own conventions at the top.

For `CLAUDE.md`: on first run the agent fills in the project commands, checks `.gitignore`, adapts the dev container to the stack, and audits tests, linting, CI, and secret scanning. It asks for confirmation before making these changes, then removes its setup section.

For the dev container: copy `templates/.devcontainer/` into the target repo as `.devcontainer/`, then open the repo in Codespaces or VS Code Dev Containers. Copy it together with `CLAUDE.md`: the baseline gets the agent running, and the agent then extends it for the project's stack.

For the ruleset: import `protect-main.json` under **Settings → Rules → Rulesets** (steps in the [ruleset README](branch-rulesets/README.md)).

This repo uses its own dev container: the root `.devcontainer/` is a copy of the template, and a CI check fails if the two drift apart.

## Principles

- **Write it once.** One canonical version of each file, so repos don't drift apart.
- **Defaults, not a cage.** Your prompt overrides the template, but any deviation is declared, never silent.
- **Tests and checks are never weakened quietly.** Changes to them are always flagged.
- **GitHub is the memory.** Anything not pushed does not exist.
- **A human reviews and merges into `main`.**

## Recommended repo setup

The `CLAUDE.md` template assumes `main` is protected. The [ruleset](branch-rulesets/protect-main.json) covers the first point; the rest is manual:

- Require pull requests for `main`, with no bypass (including admins).
- Require the CI checks to pass.
- Add a `CODEOWNERS` file covering `.github/` and `context.md`.
- Do not give the agent admin-scoped credentials.

## Credits and how this was made

- The "grill me" planning step, where the agent interviews you one question at a time with a recommended answer until you share the same picture, is adapted from [Matt Pocock](https://github.com/mattpocock) and his [`grill-me` skill](https://github.com/mattpocock/skills/blob/HEAD/skills/productivity/grill-me/SKILL.md) (MIT licensed). His [skills repo](https://github.com/mattpocock/skills) is worth a look.
- These templates were written with AI assistance: an initial draft from Gemini, then Claude for the rest. They came out of grill-me-style interview sessions and long discussions about behaviors, trade-offs, and edge cases. The workflow decisions were made by me in those sessions; the drafting was AI-assisted.

## License

MIT, see [LICENSE](LICENSE).
