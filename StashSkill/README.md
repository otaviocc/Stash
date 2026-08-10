# StashSkill

A skill for LLM coding agents (Claude Code, opencode, and others) that drives
the `stash` CLI, defined in [`SKILL.md`](SKILL.md).

`SKILL.md` follows the common agent-skill format: YAML frontmatter (`name` +
`description`) that tells the agent *when* to invoke the skill, followed by a
concise reference for the `stash` command-line client. Deep reference material
sits in `reference/` (`admin.md`, `errors.md`, `import-export.md`,
`output-formats.md`) and is read on demand.

## Installing

Make the skill discoverable by placing this folder where your agent looks for
skills, naming the folder after the skill (`stash-cli`):

```bash
# Project-scoped (Claude Code, this repo):
mkdir -p .claude/skills
ln -s "$(pwd)/StashSkill" .claude/skills/stash-cli

# User-scoped (all projects):
ln -s "$(pwd)/StashSkill" ~/.claude/skills/stash-cli

# opencode:
ln -s "$(pwd)/StashSkill" ~/.config/opencode/skills/stash-cli
```

Agents then load the skill automatically when a request matches its
`description`, or you can invoke it explicitly.

## Using without installing

You can also just point the agent at the file at the start of a session:

> Read `StashSkill/SKILL.md`, then help me manage my Stash bookmarks.

Either way, make sure the `stash` binary is installed and configured (`stash
config set-url`, `stash login`) before starting.
