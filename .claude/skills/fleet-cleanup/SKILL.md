---
name: fleet-cleanup
description: Clean up fleet worktrees that are merged, stale, or no longer needed. Use when the user asks to clean up, prune, or remove old worktrees.
disable-model-invocation: true
allowed-tools: Bash(fleet *), Bash(git *), Bash(gh *), Bash(glab *)
---

# Fleet Cleanup

Identify and clean up fleet worktrees that are done, merged, or stale.

## Steps

1. **Survey**: Run `fleet ls --all` to see all worktrees across repos.

2. **Classify each worktree**:

   - **Merged**: Branch has been merged into its base branch (check with `git log --oneline <base>..<branch>` — if empty after fetch, it's merged). Also check for closed/merged PRs via `gh pr list --head <branch> --state merged` or `glab mr list --source-branch <branch> --state merged`.
   - **Stale state**: Worktree directory no longer exists (`[gone]` in ls output). These can be pruned.
   - **Clean & ahead**: Has commits but clean working tree — candidate for PR, not cleanup.
   - **Dirty**: Has uncommitted changes — warn, do not remove.

3. **Present findings** as a table:

   | Branch | Repo | Status | Action |
   |--------|------|--------|--------|
   | `auth-feature` | ~/workspace/api | merged | `fleet rm auth-feature` |
   | `old-experiment` | ~/workspace/api | gone | prune |
   | `wip-refactor` | ~/workspace/lib | dirty | skip (uncommitted changes) |

4. **Ask for confirmation** before removing anything. Show the exact commands that will run.

5. **Execute approved cleanup**:
   - For stale state: `fleet ls --prune`
   - For merged worktrees: `fleet rm <branch>` for each
   - For force-removable: `fleet rm -f <branch>` (only if user explicitly approves)

6. **Report**: Show what was cleaned up and what remains.

## Safety

- Never remove a worktree with uncommitted changes without explicit `-f` approval
- Always check if a branch is merged before suggesting removal
- Show the user exactly what will happen before doing it
