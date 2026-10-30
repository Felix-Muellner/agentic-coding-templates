# agentic-coding-templates

Reusable markdown templates for agentic coding: instruction files, workflow rules, and project scaffolding that I would otherwise rewrite for every new repo.

> **Status:** experimental. Written for a solo workflow in disposable environments (e.g. Codespaces) and tried mostly with [Claude Code](https://docs.claude.com/en/docs/claude-code/overview). Expect changes as I learn what works.

## Contents

| File | Purpose |
|------|---------|
| [`templates/CLAUDE.md`](templates/CLAUDE.md) | Self-configuring agent instructions: first-run setup, test-driven development, issue-based workflow, independent verification, hard boundaries. |

More templates (glossary, spec, and similar) will be added as they prove useful.

## Usage

Copy the template you need into the root of the target repo, then start your agent. Each template explains its own conventions at the top.

For `CLAUDE.md`: on first run the agent fills in the project commands, checks `.gitignore`, and audits tests, linting, CI, and secret scanning. It asks for confirmation before changing anything.

## Principles

- **Write it once.** One canonical version of each file, so repos don't drift apart.
- **Defaults, not a cage.** Your prompt overrides the template, but any deviation is declared, never silent.
- **Tests and checks are never weakened quietly.** Changes to them are always flagged.
- **GitHub is the memory.** Anything not pushed does not exist.
- **A human reviews and merges into `main`.**

## Recommended repo setup

The `CLAUDE.md` template assumes `main` is protected:

- Require pull requests for `main`, with no bypass (including admins).
- Require the CI checks to pass.
- Add a `CODEOWNERS` file covering `.github/` and `context.md`.
- Do not give the agent admin-scoped credentials.

## Credits and how this was made

- The "grill me" planning step, where the agent interviews you one question at a time with a recommended answer until you share the same picture, is adapted from [Matt Pocock](https://github.com/mattpocock) and his [`grill-me` skill](https://github.com/mattpocock/skills/blob/HEAD/skills/productivity/grill-me/SKILL.md) (MIT licensed). His [skills repo](https://github.com/mattpocock/skills) is worth a look.
- These templates were written with AI assistance: an initial draft from Gemini, then Claude for the rest. They came out of grill-me-style interview sessions and long discussions about behaviors, trade-offs, and edge cases. The workflow decisions were made by me in those sessions; the drafting was AI-assisted.

## License

MIT, see [LICENSE](LICENSE).
