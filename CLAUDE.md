# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is fleet

fleet is a pure Bash shell tool that manages git worktree lifecycles for parallel Claude Code sessions, with native cmux.dev workspace/pane/sidebar integration. Each worktree gets its own isolated working directory (and optionally its own cmux.dev workspace) so multiple Claude agents can work on the same repo simultaneously.

## Architecture

**Single-file shell executable** — all logic lives in `fleet.sh` (~2100 lines), installed as `~/.local/bin/fleet`. A thin shell wrapper (output by `fleet init-shell`, loaded via `eval "$(fleet init-shell)"` in `.zshrc`/`.bashrc`) intercepts `fleet cd` to change the parent shell's directory; all other commands run as a subprocess.

**Function structure:**
- `fleet()` — public dispatcher, routes subcommands to `_fleet_<cmd>` functions
- `_fleet_*()` — private functions: `_fleet_new`, `_fleet_start`, `_fleet_cd`, `_fleet_ls`, `_fleet_ls_all`, `_fleet_prune_state`, `_fleet_merge`, `_fleet_rm`, `_fleet_rm_all`, `_fleet_init`, `_fleet_init_shell`, `_fleet_config`, `_fleet_focus`, `_fleet_team`, `_fleet_send`, `_fleet_status`, `_fleet_register`, `_fleet_update`
- Helpers: `_fleet_repo_root`, `_fleet_safe_name`, `_fleet_default_branch`, `_fleet_has_cmux`, `_fleet_worktree_dir`, `_fleet_spinner_start/stop`, `_fleet_find_hook`, `_fleet_load_team_roles`, `_fleet_all_state_files`, `_fleet_get_config`
- State management: `_fleet_save_state`, `_fleet_read_state_field`, `_fleet_state_set`, `_fleet_rm_state`, `_fleet_save_team_surfaces`

**Key design patterns:**
- Executable + shell wrapper: `fleet cd` prints the target path; the shell wrapper (from `init-shell`) does the actual `cd`. All other commands run as subprocesses.
- cmux.dev detection via `_fleet_has_cmux()` — graceful fallback to subshell cd + inline claude when unavailable
- Idempotent operations (e.g. `fleet new` reuses existing worktrees/workspaces)
- Context-aware: `fleet rm`, `fleet merge`, `fleet status` with no args detect the current worktree from `$PWD`
- Branch name sanitization: `feature/foo` → `feature-foo` for directory names
- State files at `~/.fleet/state/<repo-hash>/<safe-branch>.json` track workspace-to-branch mapping

**cmux.dev integration:** When cmux.dev is available, `fleet new` creates a new cmux.dev workspace instead of cd-ing. The user's terminal stays put, enabling rapid task launches. Workspace lifecycle (create, focus, close) is tied to worktree lifecycle.

**Agent teams:** `fleet team <branch>` spawns agents in split panes. Roles are configurable via `.fleet/team.json` (per-project) or `~/.fleet/team.json` (global), defaulting to explorer/architect/reviewer. Supports `--add <role>` and `--rm <role>` for dynamic membership. `fleet send <branch> [--role <role>] <msg>` injects messages into running panes.

**Multi-repo:** `fleet ls --all` shows worktrees across all repos using state files. State includes `repo_root` for self-describing entries. `fleet register` adopts existing worktrees not created by fleet.

## Key files

- `fleet.sh` — the entire application, installed as `~/.local/bin/fleet`
- `install.sh` — curl-pipe installer that downloads fleet.sh to `~/.local/bin/fleet` and adds eval line to shell RC
- `.fleet/setup` — project-specific worktree setup hook (committed to repo)
- `.fleet/team.json` — project-specific team role config (optional, committed to repo)
- `~/.fleet/team.json` — global team role config (fallback)
- `examples/setup-node` — example setup hook for Node.js projects
- `examples/team.json` — example team role config
- `.claude/skills/fleet/SKILL.md` — `/fleet` skill: status dashboard + actions
- `.claude/skills/dispatch/SKILL.md` — `/dispatch` skill: parallel workstream orchestration
- `.claude/skills/fleet-cleanup/SKILL.md` — `/fleet-cleanup` skill: prune merged/stale worktrees

## Shell conventions

- 2-space indentation
- Functions prefixed `_fleet_` for internal, `fleet` for public
- Zsh compatibility: uses `setopt localoptions nomonitor` where needed for job control
- Error handling: validate inputs, check `command -v`, guard with `|| return 1`
- No `set -e` in fleet.sh (functions use `return 1` for error handling); install.sh uses `set -e`
- cmux.dev calls always use `2>/dev/null` to suppress errors when workspace is stale

## QA — mandatory before considering any task done

Always self-test changes to fleet.sh before finishing work. Run the executable directly or source it in a bash subshell:

```bash
# As executable
bash /path/to/fleet.sh <subcommand> [args]
# Or source for testing internal functions
bash -c 'source /path/to/fleet.sh && _fleet_<function> [args]'
```

Test thoroughly: check happy paths, error paths, flag combinations, and edge cases (no args, bad input, missing worktrees, etc.). Do not consider a task complete until you have verified the changes work.
