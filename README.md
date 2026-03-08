# fleet

> **This repo is mirrored from [GitLab](https://gitlab.com/nighthawk-oss/fleet).** Issues, merge requests, and contributions should go there.

Claude Worktree Manager with [cmux.dev](https://cmux.dev) integration.

Manages git worktree lifecycles for parallel Claude Code sessions. Each agent gets its own worktree — no conflicts, one command each. When cmux.dev is available, each worktree gets its own workspace with sidebar status and notifications.

![fleet help](assets/fleet-help.png)

## Install

```bash
curl -fsSL https://gitlab.com/nighthawk-oss/fleet/-/raw/main/install.sh | sh
```

## Quick start

```bash
cd your-repo
fleet new auth-feature -p "Add OAuth2 login"
```

![fleet new](assets/fleet-new.png)

Without cmux.dev, this cd's into the worktree and launches Claude inline. With cmux.dev, each branch gets its own workspace tab — launch several in parallel and switch between them:

![fleet cmux tabs](assets/fleet-cmux-tabs.png)

Each workspace has sidebar status showing the branch name and current state:

![fleet workspace](assets/fleet-workspace.png)

## Managing worktrees

List active worktrees and clean up when done:

![fleet ls](assets/fleet-ls.png)

![fleet rm](assets/fleet-rm.png)

## Commands

```
fleet new <branch> [-p <prompt>] [--team]  — New worktree + workspace, launch Claude
fleet start <branch> [-p <prompt>]         — Resume Claude in existing workspace
fleet cd [branch]                          — cd into worktree (no args = repo root)
fleet ls [--status]                        — List worktrees (+ sidebar status)
fleet merge [branch] [--squash]            — Merge worktree branch into primary checkout
fleet rm [branch | --all] [-f]             — Remove worktree + workspace + branch
fleet init [--replace]                     — Generate .fleet/setup hook using Claude
fleet config [set <key> <value> [--global]] — View/set layout config
fleet focus <branch>                       — Switch to a branch's cmux.dev workspace
fleet team <branch>                        — Spawn agent team in split panes
fleet status [branch]                      — Show sidebar state for a workspace
fleet update / fleet version
```

## Agent teams

With cmux.dev, `--team` spawns explorer, architect, and reviewer agents in split panes:

```bash
fleet new big-refactor --team
```

![fleet team](assets/fleet-team.png)

## Setup hooks

Generate a project-specific setup hook that runs after worktree creation:

```bash
fleet init
```

This creates `.fleet/setup` — a bash script that symlinks secrets, installs deps, and runs codegen. Commit it to your repo.

## Common workflows

### Parallel feature development

Spin up multiple features at once — each gets its own worktree and Claude session:

```bash
fleet new auth-feature -p "Add OAuth2 login with Google provider"
fleet new fix-navbar -p "Fix responsive navbar overflow on mobile"
fleet new api-refactor -p "Refactor REST endpoints to use versioned routes"
```

List what's running, then switch between them:

```bash
fleet ls
fleet focus auth-feature
```

### Review and merge

When a feature is ready, merge it back:

```bash
fleet merge auth-feature            # fast-forward/merge into main checkout
fleet merge fix-navbar --squash     # squash all commits into one
fleet rm auth-feature               # clean up worktree + branch
```

### Resume work

Pick up where you left off — Claude resumes with `--continue`:

```bash
fleet start auth-feature
fleet start auth-feature -p "Now add the logout endpoint"
```

### Full lifecycle

```bash
fleet new my-feature -p "Build the thing"   # create worktree, launch Claude
fleet ls                                     # check progress
fleet cd my-feature                          # jump into the worktree
fleet merge my-feature                       # merge into main
fleet rm my-feature                          # clean up
```

### Team mode

Launch a full agent team — explorer, architect, and reviewer — in split panes:

```bash
fleet new big-refactor --team
# or add agents to an existing workspace:
fleet team big-refactor
```

### Setup hooks

Generate a setup hook so new worktrees auto-configure themselves:

```bash
fleet init                    # Claude analyzes your repo and generates .fleet/setup
git add .fleet/setup && git commit -m "add fleet setup hook"
```

After this, every `fleet new` will automatically symlink secrets, install deps, and run codegen.

## Layout modes

```bash
fleet config set layout nested          # .worktrees/<branch> (default)
fleet config set layout outer-nested    # ../<repo>.worktrees/<branch>
fleet config set layout sibling         # ../<repo>-<branch>
```

## Running tests

```bash
brew install bats-core    # or: apk add bats
bats test/
```
