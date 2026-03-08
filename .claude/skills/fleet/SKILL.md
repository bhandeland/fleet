---
name: fleet
description: Show fleet worktree status across repos and suggest next actions. Use when the user asks about worktree status, what branches are active, or what to do next with their fleet workspaces.
allowed-tools: Bash(fleet *), Bash(git *)
---

# Fleet Status & Actions

Gather the current fleet state and present a concise dashboard with suggested next actions.

## Steps

1. **Get context**: Run `fleet ls --all` to see all worktrees across repos, and `fleet status` if inside a worktree.

2. **Show dashboard**: Present a summary table:
   - Branch name
   - Status (commits ahead, clean/dirty working tree)
   - Base branch (parent)
   - Agent team status (if any)

3. **Suggest actions** based on what you see:
   - Branches with commits ahead and clean working trees: suggest `fleet merge <branch>` to create a PR
   - Worktrees marked `[gone]`: suggest `fleet ls --prune` to clean up
   - Worktrees with uncommitted changes: note them
   - If agents are running: show their status

4. If `$ARGUMENTS` is provided, treat it as a fleet subcommand to run. For example:
   - `/fleet ls` → run `fleet ls`
   - `/fleet status auth-feature` → run `fleet status auth-feature`
   - `/fleet send auth-feature --role explorer "check the tests"` → run that command

Keep output concise. Use tables for multi-worktree summaries.
