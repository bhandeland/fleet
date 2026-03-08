---
name: dispatch
description: Break a large task into parallel worktree workstreams. Use when the user wants to split work across multiple branches, parallelize a task, or create several fleet worktrees at once.
disable-model-invocation: true
argument-hint: <task description>
allowed-tools: Bash(fleet *), Bash(git *)
---

# Dispatch — Parallel Workstream Orchestration

Break a task into independent subtasks and create a fleet worktree for each.

## Steps

1. **Understand the task**: Read `$ARGUMENTS` as the task description. If no arguments, ask the user what they want to parallelize.

2. **Analyze the codebase**: Quickly explore the repo to understand its structure and identify natural decomposition boundaries (e.g., separate services, frontend/backend, independent features).

3. **Propose a plan**: Present a table of proposed worktrees:

   | Branch | Task | Files/Areas |
   |--------|------|-------------|
   | `auth-backend` | Implement auth API endpoints | `src/api/auth/` |
   | `auth-frontend` | Add login UI components | `src/components/auth/` |
   | `auth-tests` | Write integration tests | `test/integration/auth/` |

   Ask the user to confirm or adjust before creating anything.

4. **Create worktrees**: For each approved subtask, run:
   ```bash
   fleet new <branch> -p "<prompt describing the subtask>"
   ```
   If the user wants agent teams on any worktree, add `--team`.

5. **Report**: Show a summary of created worktrees and how to check on them:
   ```
   fleet status <branch>     # check one
   fleet ls --all             # see all
   fleet send <branch> "msg"  # send instructions
   ```

## Guidelines

- Keep branch names short and descriptive (2-3 words max, hyphenated)
- Each subtask should be independently mergeable
- Avoid overlapping file changes between worktrees when possible
- Default to 2-4 worktrees unless the task clearly needs more
- Include a clear, specific prompt for each worktree so Claude knows exactly what to do
