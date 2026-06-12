# StashSkill

A Claude Code skill for the `stash` CLI, defined in [`SKILL.md`](SKILL.md).

`SKILL.md` follows the Claude Code skill format: YAML frontmatter (`name` + `description`)
that tells Claude *when* to invoke the skill, followed by a full reference for the `stash`
command-line client.

## Installing

Make the skill discoverable by placing it where Claude Code looks for skills — copy or symlink
this folder into a skills directory, naming the folder after the skill (`stash-cli`):

```bash
# Project-scoped (this repo):
mkdir -p .claude/skills
ln -s "$(pwd)/StashSkill" .claude/skills/stash-cli

# Or user-scoped (all projects):
ln -s "$(pwd)/StashSkill" ~/.claude/skills/stash-cli
```

Claude then loads the skill automatically when a request matches its `description`, or you can
invoke it explicitly with `/stash-cli`.

## Using without installing

You can also just point Claude at the file at the start of a session:

> Read `StashSkill/SKILL.md`, then help me manage my Stash bookmarks.

Either way, make sure the `stash` binary is installed and configured (`stash config set-url`,
`stash login`) before starting.
