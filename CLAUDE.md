# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is fleet

fleet is a pure Bash shell tool that manages git worktree lifecycles for parallel Claude Code sessions, with native cmux.dev workspace/pane/sidebar integration. Each worktree gets its own isolated working directory (and optionally its own cmux.dev workspace) so multiple Claude agents can work on the same repo simultaneously.

## Architecture

**Single-file shell tool** — all logic lives in `fleet.sh` (~1200 lines), which is sourced into the user's shell (bash/zsh). There is no build step, no dependencies, and no test suite.

**Function structure:**
- `fleet()` — public dispatcher, routes subcommands to `_fleet_<cmd>` functions
- `_fleet_*()` — private functions: `_fleet_new`, `_fleet_start`, `_fleet_cd`, `_fleet_ls`, `_fleet_merge`, `_fleet_rm`, `_fleet_rm_all`, `_fleet_init`, `_fleet_config`, `_fleet_focus`, `_fleet_team`, `_fleet_status`, `_fleet_update`
- Helpers: `_fleet_repo_root`, `_fleet_safe_name`, `_fleet_default_branch`, `_fleet_has_cmux`, `_fleet_worktree_dir`, `_fleet_spinner_start/stop`, `_fleet_find_hook`
- State management: `_fleet_save_state`, `_fleet_read_state_field`, `_fleet_rm_state`, `_fleet_save_team_surfaces`

**Key design patterns:**
- cmux.dev detection via `_fleet_has_cmux()` — graceful fallback to cd + inline claude when unavailable
- Idempotent operations (e.g. `fleet new` reuses existing worktrees/workspaces)
- Context-aware: `fleet rm`, `fleet merge`, `fleet status` with no args detect the current worktree from `$PWD`
- Branch name sanitization: `feature/foo` → `feature-foo` for directory names
- State files at `~/.fleet/state/<repo-hash>/<safe-branch>.json` track workspace-to-branch mapping

**cmux.dev integration:** When cmux.dev is available, `fleet new` creates a new cmux.dev workspace instead of cd-ing. The user's terminal stays put, enabling rapid task launches. Workspace lifecycle (create, focus, close) is tied to worktree lifecycle.

**Agent teams:** `fleet team <branch>` splits the workspace into explorer, architect, and reviewer panes, each running a specialized Claude agent.

## Key files

- `fleet.sh` — the entire application
- `install.sh` — curl-pipe installer that downloads fleet.sh to `~/.fleet/` and adds source line to shell RC
- `.fleet/setup` — project-specific worktree setup hook (committed to repo)
- `examples/setup-node` — example setup hook for Node.js projects

## Shell conventions

- 2-space indentation
- Functions prefixed `_fleet_` for internal, `fleet` for public
- Zsh compatibility: uses `setopt localoptions nomonitor` where needed for job control
- Error handling: validate inputs, check `command -v`, guard with `|| return 1`
- No `set -e` in fleet.sh (it's sourced, not executed); install.sh uses `set -e`
- cmux.dev calls always use `2>/dev/null` to suppress errors when workspace is stale

## QA — mandatory before considering any task done

Always self-test changes to fleet.sh before finishing work. Source the file in a bash subshell and run the affected commands to verify correct output and behavior:

```bash
bash -c 'source /path/to/fleet.sh && fleet <subcommand> [args]'
```

Test thoroughly: check happy paths, error paths, flag combinations, and edge cases (no args, bad input, missing worktrees, etc.). Do not consider a task complete until you have verified the changes work.
