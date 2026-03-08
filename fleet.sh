#!/usr/bin/env bash
# fleet — Claude Worktree Manager with cmux.dev Integration
#
# Worktree lifecycle manager for parallel Claude Code sessions
# with native cmux.dev workspace/pane/sidebar support.
#
# Commands:
#   fleet new <branch> [-p <prompt>] [--team]  — New worktree, open workspace, launch Claude
#   fleet start <branch> [-p <prompt>]         — Focus workspace, resume Claude with --continue
#   fleet cd [branch]                          — cd into worktree (no args = repo root)
#   fleet ls [--status|--all]                  — List worktrees (--all for cross-repo)
#   fleet merge [branch] [--squash]            — Merge worktree branch into primary checkout
#   fleet rm [branch | --all] [-f]             — Remove worktree + workspace + branch
#   fleet init [--replace]                     — Generate .fleet/setup hook using Claude
#   fleet config [set <key> <value> [--global]] — View/set layout config
#   fleet focus <branch>                       — Switch to a branch's cmux.dev workspace
#   fleet team <branch> [--add|--rm <role>]    — Spawn/manage agent team in split panes
#   fleet send <branch> [--role <r>] <msg>     — Send message to pane
#   fleet status [branch] [--json]             — Show workspace/agent/git status
#   fleet register                             — Register current worktree with fleet
#   fleet update / fleet version

_FLEET_DOWNLOAD_URL="https://gitlab.com/nighthawk-oss/fleet/-/raw/main"
FLEET_VERSION="unknown"
[[ -f "$HOME/.fleet/VERSION" ]] && FLEET_VERSION="$(<"$HOME/.fleet/VERSION")"

fleet() {
  local cmd="$1"
  shift &>/dev/null

  _fleet_check_update

  case "$cmd" in
    new)     _fleet_new "$@" ;;
    start)   _fleet_start "$@" ;;
    cd)      _fleet_cd "$@" ;;
    ls)      _fleet_ls "$@" ;;
    merge)   _fleet_merge "$@" ;;
    rm)      _fleet_rm "$@" ;;
    init)    _fleet_init "$@" ;;
    config)  _fleet_config "$@" ;;
    focus)   _fleet_focus "$@" ;;
    team)    _fleet_team "$@" ;;
    send)    _fleet_send "$@" ;;
    status)  _fleet_status "$@" ;;
    register) _fleet_register "$@" ;;
    update)     _fleet_update "$@" ;;
    init-shell) _fleet_init_shell "$@" ;;
    version) echo "fleet $FLEET_VERSION" ;;
    --help|-h|"")
      echo "Usage: fleet <command> [args]"
      echo ""
      echo "  new <branch> [-p <prompt>] [--team]  New worktree + workspace, launch Claude"
      echo "  start <branch> [-p <prompt>]         Resume Claude in existing workspace"
      echo "  cd [branch]        cd into worktree (no args = repo root)"
      echo "  ls [--status|--all|--prune]  List worktrees (--all cross-repo)"
      echo "  merge [branch] [--title <t>]  Push branch + create PR/MR"
      echo "  rm [branch] [-f]   Remove worktree + workspace + branch"
      echo "  rm --all           Remove ALL worktrees (requires confirmation)"
      echo "  init [--replace]   Generate .fleet/setup hook using Claude"
      echo "  config             View or set configuration (layout, base-branch)"
      echo "  focus <branch>     Switch to a branch's cmux.dev workspace"
      echo "  team <branch> [--add|--rm <role>]  Spawn/manage agent team"
      echo "  send <branch> [--role <role>] <msg>  Send message to pane"
      echo "  status [branch] [--json]  Show workspace/agent/git status"
      echo "  register           Register current worktree with fleet"
      echo "  update             Update fleet to the latest version"
      echo "  version            Show current version"
      return 0
      ;;
    *)
      echo "Unknown command: $cmd"
      echo "Run 'fleet --help' for usage."
      return 1
      ;;
  esac
}

# ── Helpers ──────────────────────────────────────────────────────────

# Get the repo root from anywhere (works inside worktrees too)
_fleet_repo_root() {
  local git_common_dir
  git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  realpath "$(dirname "$git_common_dir")"
}

# Sanitize branch name: slashes become hyphens
_fleet_safe_name() {
  echo "${1//\//-}"
}

# Detect the base branch: config > origin/HEAD > main/master
_fleet_default_branch() {
  local repo_root="$1"

  # Check config first
  local configured
  configured="$(_fleet_get_config "$repo_root" "base-branch" "")"
  if [[ -n "$configured" ]]; then
    echo "$configured"
    return
  fi

  # Auto-detect from remote
  local default
  default="$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"
  if [[ -n "$default" ]]; then
    echo "$default"
    return
  fi
  if git -C "$repo_root" show-ref --verify --quiet refs/heads/main &>/dev/null; then
    echo "main"
  elif git -C "$repo_root" show-ref --verify --quiet refs/heads/master &>/dev/null; then
    echo "master"
  else
    git -C "$repo_root" rev-parse --abbrev-ref HEAD &>/dev/null
  fi
}

# Check if cmux.dev is available
_fleet_has_cmux() {
  command -v cmux &>/dev/null && cmux ping &>/dev/null 2>&1
}

# Extract a ref like "workspace:N" or "surface:N" from text
_fleet_extract_ref() {
  local text="$1" type="$2"
  printf '%s' "$text" | grep -oE "${type}:[0-9]+" | head -1
}

# Read a config value: per-project > global > default
_fleet_get_config() {
  local repo_root="$1" key="$2" default="${3:-}"
  local value=""
  # Per-project config
  if [[ -n "$repo_root" && -f "$repo_root/.fleet/config.json" ]]; then
    value="$(grep "\"$key\"" "$repo_root/.fleet/config.json" 2>/dev/null | sed 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  fi
  # Global config fallback
  if [[ -z "$value" && -f "$HOME/.fleet/config.json" ]]; then
    value="$(grep "\"$key\"" "$HOME/.fleet/config.json" 2>/dev/null | sed 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  fi
  echo "${value:-$default}"
}

# Read layout config: per-project > global > default (nested)
_fleet_get_layout() {
  _fleet_get_config "$1" "layout" "nested"
}

# Return the base directory that contains worktrees
_fleet_worktree_base() {
  local repo_root="$1"
  local layout
  layout="$(_fleet_get_layout "$repo_root")"
  case "$layout" in
    outer-nested) echo "$(dirname "$repo_root")/$(basename "$repo_root").worktrees" ;;
    sibling)      echo "$(dirname "$repo_root")" ;;
    *)            echo "$repo_root/.worktrees" ;;
  esac
}

# Resolve worktree directory for a branch
_fleet_worktree_dir() {
  local repo_root="$1"
  local safe_name="$(_fleet_safe_name "$2")"
  local layout
  layout="$(_fleet_get_layout "$repo_root")"
  case "$layout" in
    outer-nested) echo "$(dirname "$repo_root")/$(basename "$repo_root").worktrees/$safe_name" ;;
    sibling)      echo "$(dirname "$repo_root")/$(basename "$repo_root")-$safe_name" ;;
    *)            echo "$repo_root/.worktrees/$safe_name" ;;
  esac
}

# Detect branch name from current worktree directory
_fleet_detect_worktree_branch() {
  local repo_root="$1"
  local layout
  layout="$(_fleet_get_layout "$repo_root")"
  local base safe_name wt_dir

  case "$layout" in
    outer-nested)
      base="$(dirname "$repo_root")/$(basename "$repo_root").worktrees"
      if [[ "$PWD" == "$base/"* ]]; then
        safe_name="${PWD#$base/}"
        safe_name="${safe_name%%/*}"
        wt_dir="$base/$safe_name"
      fi
      ;;
    sibling)
      local repo_name
      repo_name="$(basename "$repo_root")"
      local parent
      parent="$(dirname "$repo_root")"
      local check_dir="$PWD"
      while [[ "$(dirname "$check_dir")" != "$parent" && "$check_dir" != "/" ]]; do
        check_dir="$(dirname "$check_dir")"
      done
      local current_dir
      current_dir="$(basename "$check_dir")"
      if [[ "$current_dir" == "${repo_name}-"* && "$check_dir" != "$repo_root" ]]; then
        safe_name="${current_dir#${repo_name}-}"
        wt_dir="$parent/$current_dir"
      fi
      ;;
    *)  # nested
      if [[ "$PWD" == */.worktrees/* ]]; then
        safe_name="${PWD##*/.worktrees/}"
        safe_name="${safe_name%%/*}"
        wt_dir="$repo_root/.worktrees/$safe_name"
      fi
      ;;
  esac

  [[ -z "$safe_name" ]] && return 1

  git -C "$repo_root" worktree list --porcelain \
    | grep -A2 "^worktree ${wt_dir}\$" \
    | grep '^branch ' \
    | sed 's|^branch refs/heads/||'
}

# Find hook in .fleet/ directory
_fleet_find_hook() {
  local dir="$1" hook_name="$2"
  if [[ -x "$dir/.fleet/$hook_name" ]]; then
    echo "$dir/.fleet/$hook_name"
  fi
}

_fleet_spinner_start() {
  [[ -n "$ZSH_VERSION" ]] && setopt localoptions nomonitor
  ( while true; do
      for c in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
        printf "\b%s" "$c"
        sleep 0.08
      done
    done ) &
  _FLEET_SPINNER_PID=$!
}

_fleet_spinner_stop() {
  [[ -z "$_FLEET_SPINNER_PID" ]] && return
  [[ -n "$ZSH_VERSION" ]] && setopt localoptions nomonitor
  kill "$_FLEET_SPINNER_PID" &>/dev/null
  wait "$_FLEET_SPINNER_PID" &>/dev/null
  printf "\b \n"
  unset _FLEET_SPINNER_PID
}

_fleet_check_update() {
  local cache_dir="$HOME/.fleet"
  local version_file="$cache_dir/.latest_version"
  local check_file="$cache_dir/.last_check"

  if [[ -f "$version_file" ]]; then
    local latest
    latest="$(<"$version_file")"
    if [[ -n "$latest" && "$latest" != "$FLEET_VERSION" ]]; then
      printf 'fleet: update available (%s → %s). Run "fleet update" to upgrade.\n' \
        "$FLEET_VERSION" "$latest"
    fi
  fi

  local now
  now="$(date +%s)"
  if [[ -f "$check_file" ]]; then
    local last_check
    last_check="$(<"$check_file")"
    if (( now - last_check < 86400 )); then
      return
    fi
  fi

  [[ -n "$ZSH_VERSION" ]] && setopt localoptions nomonitor
  {
    local v
    v="$(curl -fsSL "${_FLEET_DOWNLOAD_URL}/VERSION" 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$v" ]] && printf '%s' "$v" > "$version_file"
    printf '%s' "$now" > "$check_file"
  } &>/dev/null &
  disown &>/dev/null
}

# ── State Management ────────────────────────────────────────────────

_fleet_repo_hash() {
  if command -v md5 &>/dev/null; then
    printf '%s' "$1" | md5 -q
  else
    printf '%s' "$1" | md5sum | cut -d' ' -f1
  fi
}

_fleet_state_dir() {
  local repo_root="$1"
  local hash
  hash="$(_fleet_repo_hash "$repo_root")"
  echo "$HOME/.fleet/state/${hash:0:12}"
}

_fleet_state_file() {
  local repo_root="$1" branch="$2"
  local safe="$(_fleet_safe_name "$branch")"
  echo "$(_fleet_state_dir "$repo_root")/${safe}.json"
}

_fleet_save_state() {
  local repo_root="$1" branch="$2" worktree_dir="$3" workspace_id="$4" main_surface="${5:-}" base_branch="${6:-}"
  local state_dir state_file
  state_dir="$(_fleet_state_dir "$repo_root")"
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  mkdir -p "$state_dir"
  cat > "$state_file" <<EOF
{
  "branch": "$branch",
  "worktree_dir": "$worktree_dir",
  "workspace_id": "$workspace_id",
  "main_surface": "$main_surface",
  "repo_root": "$repo_root",
  "base_branch": "$base_branch"
}
EOF
}

# List all state files across all repos
_fleet_all_state_files() {
  local state_base="$HOME/.fleet/state"
  [[ -d "$state_base" ]] || return
  find "$state_base" -name '*.json' -type f 2>/dev/null
}

_fleet_read_state_field() {
  local state_file="$1" field="$2"
  [[ -f "$state_file" ]] || return 1
  sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state_file" | head -1
}

_fleet_rm_state() {
  local repo_root="$1" branch="$2"
  local state_file
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  rm -f "$state_file" &>/dev/null
}

# Update state file: add/update a single key-value pair
_fleet_state_set() {
  local state_file="$1" key="$2" value="$3"
  [[ -f "$state_file" ]] || return 1
  if grep -q "\"$key\"" "$state_file"; then
    # Update existing key
    sed -i '' 's|"'"$key"'"[[:space:]]*:[[:space:]]*"[^"]*"|"'"$key"'": "'"$value"'"|' "$state_file"
  else
    # Insert before closing brace
    sed -i '' 's|}|,\n  "'"$key"'": "'"$value"'"\n}|' "$state_file"
  fi
}

# Update state file with team surface refs (dynamic role names)
_fleet_save_team_surfaces() {
  local state_file="$1"; shift
  [[ -f "$state_file" ]] || return 1
  # Accept pairs: role_name surface_ref role_name surface_ref ...
  while [[ $# -ge 2 ]]; do
    local role="$1" surface="$2"; shift 2
    _fleet_state_set "$state_file" "team_${role}_surface" "$surface"
  done
}

# Load team roles from .fleet/team.json (project) or ~/.fleet/team.json (global)
# Falls back to hardcoded defaults. Outputs lines: name|agent|split
_fleet_load_team_roles() {
  local repo_root="$1"
  local config_file=""

  # Check per-project config first
  if [[ -n "$repo_root" && -f "$repo_root/.fleet/team.json" ]]; then
    config_file="$repo_root/.fleet/team.json"
  elif [[ -f "$HOME/.fleet/team.json" ]]; then
    config_file="$HOME/.fleet/team.json"
  fi

  if [[ -n "$config_file" ]]; then
    # Parse simple JSON array of roles
    # Each role has: name, agent, split
    local name="" agent="" split=""
    while IFS= read -r line; do
      # Trim whitespace
      line="${line#"${line%%[![:space:]]*}"}"
      [[ "$line" == *'"name"'* ]] && \
        name="$(echo "$line" | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
      [[ "$line" == *'"agent"'* ]] && \
        agent="$(echo "$line" | sed 's/.*"agent"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
      [[ "$line" == *'"split"'* ]] && \
        split="$(echo "$line" | sed 's/.*"split"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
      if [[ "$line" == *"}"* && -n "$name" ]]; then
        echo "${name}|${agent:-claude}|${split:-right}"
        name="" agent="" split=""
      fi
    done < "$config_file"
  else
    # Default roles matching original hardcoded behavior
    echo "explorer|code-explorer|right"
    echo "architect|code-architect|down"
    echo "reviewer|code-reviewer|down"
  fi
}

# ── Subcommands ──────────────────────────────────────────────────────

_fleet_new() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet new <branch> [-p <prompt>] [--team]"
    echo ""
    echo "  Create a new worktree and branch, run setup hook, and launch Claude Code."
    echo "  Use -p to pass an initial prompt to Claude."
    echo "  Use --team to auto-launch agent team in split panes (requires cmux.dev)."
    return 0
  fi

  local prompt=""
  local team=false
  local branch_words=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p)     prompt="$2"; shift 2 ;;
      --team) team=true; shift ;;
      *)      branch_words+=("$1"); shift ;;
    esac
  done
  local branch
  branch="$(IFS=-; echo "${branch_words[*]}")"

  if [[ -z "$branch" ]]; then
    echo "Usage: fleet new <branch> [-p <prompt>] [--team]"
    return 1
  fi

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  # Pull latest from default branch
  local default_branch
  default_branch="$(_fleet_default_branch "$repo_root")"
  if [[ -n "$default_branch" ]]; then
    echo "Pulling latest from $default_branch..."
    git -C "$repo_root" pull --ff-only origin "$default_branch" &>/dev/null || true
  fi

  local worktree_dir
  worktree_dir="$(_fleet_worktree_dir "$repo_root" "$branch")"

  # Idempotent: if worktree already exists, handle gracefully
  if [[ -d "$worktree_dir" ]]; then
    echo "Worktree already exists: $worktree_dir"
    if _fleet_has_cmux; then
      local state_file
      state_file="$(_fleet_state_file "$repo_root" "$branch")"
      local ws_id
      ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
      if [[ -n "$ws_id" ]]; then
        cmux select-workspace --workspace "$ws_id" &>/dev/null
        return 0
      fi
    fi
    ( cd "$worktree_dir" && if [[ -n "$prompt" ]]; then claude "$prompt"; else claude; fi )
    return
  fi

  # Create worktree
  local base_dir
  base_dir="$(_fleet_worktree_base "$repo_root")"
  local layout
  layout="$(_fleet_get_layout "$repo_root")"
  if [[ "$layout" != "sibling" ]]; then
    mkdir -p "$base_dir"
  fi
  git -C "$repo_root" worktree add "$worktree_dir" -b "$branch" || return 1

  if _fleet_has_cmux; then
    # ── cmux.dev mode ──
    # Create workspace
    local ws_output workspace_id
    ws_output="$(cmux new-workspace --command "cd $worktree_dir && exec \$SHELL" 2>/dev/null)"
    # cmux new-workspace returns "OK <uuid>"
    workspace_id="${ws_output#OK }"
    if [[ -z "$workspace_id" || "$workspace_id" == "$ws_output" ]]; then
      workspace_id="$(cmux current-workspace 2>/dev/null)"
    fi

    if [[ -n "$workspace_id" ]]; then
      cmux rename-workspace --workspace "$workspace_id" "$branch" &>/dev/null
      cmux set-status task "$branch" --icon git-branch --workspace "$workspace_id" &>/dev/null
      cmux set-status project "$(basename "$repo_root")" --icon folder --workspace "$workspace_id" &>/dev/null
      cmux set-status worktree "$worktree_dir" --workspace "$workspace_id" &>/dev/null
      cmux set-status created "$(date '+%Y-%m-%d %H:%M')" --icon clock --workspace "$workspace_id" &>/dev/null
      cmux set-status status "setting up" --color "#ffcc00" --workspace "$workspace_id" &>/dev/null

      # Capture main surface for fleet send
      local main_surface=""
      main_surface="$(cmux list-pane-surfaces --workspace "$workspace_id" 2>/dev/null \
        | head -1 | grep -oE 'surface:[0-9]+' || true)"

      # Save state
      _fleet_save_state "$repo_root" "$branch" "$worktree_dir" "$workspace_id" "$main_surface" "$default_branch"
    fi

    # Run setup hook (synchronously in subshell)
    local hook
    hook="$(_fleet_find_hook "$worktree_dir" "setup")"
    if [[ -n "$hook" ]]; then
      echo "Running setup hook..."
      ( cd "$worktree_dir" && "$hook" )
    else
      hook="$(_fleet_find_hook "$repo_root" "setup")"
      if [[ -n "$hook" ]]; then
        echo "Running setup hook from repo root..."
        ( cd "$worktree_dir" && "$hook" )
      else
        echo "No .fleet/setup found. Run 'fleet init' to generate one."
      fi
    fi

    if [[ -n "$workspace_id" ]]; then
      cmux set-status status "ready" --color "#00cc66" --workspace "$workspace_id" &>/dev/null
      cmux notify --title "fleet" --body "$branch ready" --workspace "$workspace_id" &>/dev/null

      # Launch team if requested
      if [[ "$team" == true ]]; then
        _fleet_team "$branch"
      fi

      # Send claude command to workspace, then rename the session
      local claude_cmd="claude"
      if [[ -n "$prompt" ]]; then
        claude_cmd="claude -p $(printf '%q' "$prompt")"
      fi
      cmux send --workspace "$workspace_id" "$claude_cmd" &>/dev/null
      cmux send-key --workspace "$workspace_id" Enter &>/dev/null
      sleep 1
      cmux send --workspace "$workspace_id" "/rename $branch" &>/dev/null
      cmux send-key --workspace "$workspace_id" Enter &>/dev/null
    fi

    echo "Workspace ready: $branch"
  else
    # ── Fallback mode ──

    # Run setup hook
    local hook
    hook="$(_fleet_find_hook "$worktree_dir" "setup")"
    if [[ -n "$hook" ]]; then
      echo "Running setup hook..."
      ( cd "$worktree_dir" && "$hook" )
    else
      hook="$(_fleet_find_hook "$repo_root" "setup")"
      if [[ -n "$hook" ]]; then
        echo "Running setup hook from repo root (not yet committed to branch)..."
        ( cd "$worktree_dir" && "$hook" )
        echo "Tip: commit .fleet/setup so it's available in new worktrees automatically."
      else
        echo "No .fleet/setup found — worktree will skip project-specific setup."
        printf "Run 'fleet init' to generate one? (y/N) "
        local reply=""
        read -r reply &>/dev/null || true
        if [[ "$reply" =~ ^[Yy]$ ]]; then
          _fleet_init
          hook="$(_fleet_find_hook "$repo_root" "setup")"
          if [[ -n "$hook" ]]; then
            echo "Running setup hook..."
            ( cd "$worktree_dir" && "$hook" )
          fi
        fi
      fi
    fi

    # Save state (no workspace, but track base branch and repo root)
    _fleet_save_state "$repo_root" "$branch" "$worktree_dir" "" "" "$default_branch"

    echo "Worktree ready: $worktree_dir"
    ( cd "$worktree_dir" && if [[ -n "$prompt" ]]; then claude "$prompt"; else claude; fi )
  fi
}

_fleet_start() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet start <branch> [-p <prompt>]"
    echo ""
    echo "  Resume work in an existing worktree by launching Claude Code with --continue."
    echo "  Use -p to pass an initial prompt to Claude."
    return 0
  fi

  local prompt=""
  local branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p) prompt="$2"; shift 2 ;;
      *)  branch="$1"; shift ;;
    esac
  done

  if [[ -z "$branch" ]]; then
    echo "Usage: fleet start <branch> [-p <prompt>]"
    return 1
  fi

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  local worktree_dir
  worktree_dir="$(_fleet_worktree_dir "$repo_root" "$branch")"

  if [[ ! -d "$worktree_dir" ]]; then
    echo "Worktree not found: $worktree_dir"
    echo "Run 'fleet ls' to see available worktrees, or 'fleet new $branch' to create one."
    return 1
  fi

  if _fleet_has_cmux; then
    # Focus workspace and send continue command
    local state_file
    state_file="$(_fleet_state_file "$repo_root" "$branch")"
    local ws_id
    ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
    if [[ -n "$ws_id" ]]; then
      cmux select-workspace --workspace "$ws_id" &>/dev/null
      local claude_cmd="claude -c"
      if [[ -n "$prompt" ]]; then
        claude_cmd="claude -c -p $(printf '%q' "$prompt")"
      fi
      cmux send --workspace "$ws_id" "$claude_cmd" &>/dev/null
      cmux send-key --workspace "$ws_id" Enter &>/dev/null
      return 0
    fi
    # No state file — fall through to fallback
    echo "No workspace state found. Falling back to local mode."
  fi

  ( cd "$worktree_dir" && if [[ -n "$prompt" ]]; then claude -c "$prompt"; else claude -c; fi )
}

_fleet_cd() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet cd [branch]"
    echo ""
    echo "  cd into a worktree directory (no args = repo root)."
    return 0
  fi
  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo" >&2; return 1; }

  if [[ -z "$1" ]]; then
    printf '%s\n' "$repo_root"
    return
  fi

  local branch="$1"
  local worktree_dir
  worktree_dir="$(_fleet_worktree_dir "$repo_root" "$branch")"

  if [[ ! -d "$worktree_dir" ]]; then
    echo "Worktree not found: $worktree_dir" >&2
    echo "Run 'fleet ls' to see available worktrees." >&2
    return 1
  fi

  printf '%s\n' "$worktree_dir"
}

_fleet_ls() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet ls [--status] [--all] [--prune]"
    echo ""
    echo "  List fleet worktrees. Use --status to show cmux.dev sidebar state."
    echo "  Use --all to show worktrees across all repos (works from any directory)."
    echo "  Use --prune to remove state for worktrees that no longer exist."
    return 0
  fi

  local show_status=false show_all=false prune=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) show_status=true; shift ;;
      --all)    show_all=true; shift ;;
      --prune)  prune=true; shift ;;
      *)        shift ;;
    esac
  done

  if [[ "$prune" == true ]]; then
    _fleet_prune_state
    return $?
  fi

  if [[ "$show_all" == true ]]; then
    _fleet_ls_all "$show_status"
    return $?
  fi

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  local layout
  layout="$(_fleet_get_layout "$repo_root")"
  local filter
  case "$layout" in
    outer-nested) filter="$(dirname "$repo_root")/$(basename "$repo_root").worktrees/" ;;
    sibling)      filter="$(dirname "$repo_root")/$(basename "$repo_root")-" ;;
    *)            filter="$(_fleet_worktree_base "$repo_root")/" ;;
  esac

  if [[ "$show_status" == true ]] && _fleet_has_cmux; then
    # Show worktrees with sidebar status
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local wt_dir branch_name status_info
      wt_dir="$(echo "$line" | awk '{print $1}')"
      branch_name="$(git -C "$repo_root" worktree list --porcelain \
        | grep -A2 "^worktree ${wt_dir}\$" \
        | grep '^branch ' \
        | sed 's|^branch refs/heads/||')"

      if [[ -n "$branch_name" ]]; then
        local state_file
        state_file="$(_fleet_state_file "$repo_root" "$branch_name")"
        local ws_id
        ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
        if [[ -n "$ws_id" ]]; then
          status_info="$(cmux list-status --workspace "$ws_id" 2>/dev/null | head -3)"
          printf "%s  [%s]\n" "$line" "$ws_id"
          if [[ -n "$status_info" ]]; then
            printf "  %s\n" "$status_info"
          fi
        else
          echo "$line"
        fi
      else
        echo "$line"
      fi
    done < <(git -C "$repo_root" worktree list | grep -F "$filter")
  else
    git -C "$repo_root" worktree list | grep -F "$filter"
  fi
}

# Show all fleet-managed worktrees across all repos
_fleet_ls_all() {
  local show_status="${1:-false}"
  local state_base="$HOME/.fleet/state"
  if [[ ! -d "$state_base" ]]; then
    echo "No fleet state found."
    return 0
  fi

  # Collect entries as "repo_root\tbranch\tworktree_dir\tstatus\tws_id\tbase_branch" lines
  local entries=""
  while IFS= read -r state_file; do
    [[ -f "$state_file" ]] || continue
    local branch worktree_dir repo_root ws_id base_branch
    branch="$(_fleet_read_state_field "$state_file" "branch")"
    worktree_dir="$(_fleet_read_state_field "$state_file" "worktree_dir")"
    repo_root="$(_fleet_read_state_field "$state_file" "repo_root")"
    ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
    base_branch="$(_fleet_read_state_field "$state_file" "base_branch")"

    [[ -z "$branch" ]] && continue

    # Backfill repo_root from worktree_dir for old state files
    if [[ -z "$repo_root" && -n "$worktree_dir" && -d "$worktree_dir" ]]; then
      repo_root="$(git -C "$worktree_dir" rev-parse --git-common-dir 2>/dev/null)"
      if [[ -n "$repo_root" ]]; then
        repo_root="$(realpath "$(dirname "$repo_root")" 2>/dev/null)"
        _fleet_state_set "$state_file" "repo_root" "$repo_root"
      fi
    fi
    [[ -z "$repo_root" ]] && repo_root="(unknown)"

    local status_tag="ready"
    if [[ -n "$worktree_dir" && ! -d "$worktree_dir" ]]; then
      status_tag="gone"
    fi

    entries+="${repo_root}"$'\t'"${branch}"$'\t'"${worktree_dir:-(unknown)}"$'\t'"${status_tag}"$'\t'"${ws_id}"$'\t'"${base_branch:--}"$'\n'
  done < <(_fleet_all_state_files)

  if [[ -z "$entries" ]]; then
    echo "No fleet worktrees found."
    return 0
  fi

  # Get unique repos in order
  local prev_repo=""
  printf '%s' "$entries" | sort -t$'\t' -k1,1 -k2,2 | while IFS=$'\t' read -r repo_root branch worktree_dir status_tag ws_id base_branch; do
    if [[ "$repo_root" != "$prev_repo" ]]; then
      [[ -n "$prev_repo" ]] && echo ""
      local count
      count="$(printf '%s' "$entries" | grep -c "^${repo_root}"$'\t')"
      echo "$repo_root ($count worktree$([ "$count" -ne 1 ] && echo 's'))"
      prev_repo="$repo_root"
    fi
    local detail=""
    [[ "$base_branch" != "-" ]] && detail=" ← $base_branch"
    if [[ "$show_status" == true && -n "$ws_id" ]] && _fleet_has_cmux; then
      printf '  %-20s %s  [%s]  {%s}%s\n' "$branch" "$worktree_dir" "$status_tag" "$ws_id" "$detail"
    else
      printf '  %-20s %s  [%s]%s\n' "$branch" "$worktree_dir" "$status_tag" "$detail"
    fi
  done
}

# Remove state files for worktrees that no longer exist
_fleet_prune_state() {
  local state_base="$HOME/.fleet/state"
  if [[ ! -d "$state_base" ]]; then
    echo "No fleet state found."
    return 0
  fi

  local pruned=0
  while IFS= read -r state_file; do
    [[ -f "$state_file" ]] || continue
    local branch worktree_dir
    branch="$(_fleet_read_state_field "$state_file" "branch")"
    worktree_dir="$(_fleet_read_state_field "$state_file" "worktree_dir")"

    if [[ -n "$worktree_dir" && ! -d "$worktree_dir" ]]; then
      echo "Pruned: $branch ($worktree_dir)"
      rm -f "$state_file"
      pruned=$((pruned + 1))
    fi
  done < <(_fleet_all_state_files)

  if [[ "$pruned" -eq 0 ]]; then
    echo "Nothing to prune."
  else
    echo "Pruned $pruned stale state file$([ "$pruned" -ne 1 ] && echo 's')."
  fi

  # Clean up empty state directories
  find "$state_base" -type d -empty -delete 2>/dev/null
}

_fleet_merge() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet merge [branch] [--title <title>]"
    echo ""
    echo "  Push the branch and create a pull/merge request."
    echo "  Uses 'gh' (GitHub) or 'glab' (GitLab) — whichever is available."
    echo "  Run with no args from inside a worktree directory to auto-detect."
    echo ""
    echo "  --title <title>  PR/MR title (default: branch name)"
    return 0
  fi
  local branch="" title=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      *)       branch="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  if [[ -z "$branch" ]]; then
    branch="$(_fleet_detect_worktree_branch "$repo_root")"
    if [[ -z "$branch" ]]; then
      echo "Usage: fleet merge [branch] [--title <title>]"
      echo "  (or run with no args from inside a worktree directory)"
      return 1
    fi
  fi

  local worktree_dir
  worktree_dir="$(_fleet_worktree_dir "$repo_root" "$branch")"

  if [[ ! -d "$worktree_dir" ]]; then
    echo "Worktree not found: $worktree_dir"
    echo "Run 'fleet ls' to see available worktrees."
    return 1
  fi

  if ! git -C "$worktree_dir" diff --quiet &>/dev/null || \
     ! git -C "$worktree_dir" diff --cached --quiet &>/dev/null; then
    echo "Worktree has uncommitted changes: $worktree_dir"
    echo "Commit or stash them before creating PR/MR."
    return 1
  fi

  # Determine target branch from state or config
  local state_file target_branch
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  target_branch="$(_fleet_read_state_field "$state_file" "base_branch")"
  [[ -z "$target_branch" ]] && target_branch="$(_fleet_default_branch "$repo_root")"

  [[ -z "$title" ]] && title="$branch"

  # Push the branch
  echo "Pushing '$branch'..."
  git -C "$worktree_dir" push -u origin "$branch" || return 1

  # Detect forge tool
  if command -v gh &>/dev/null; then
    echo "Creating pull request: $branch → $target_branch"
    gh pr create \
      --head "$branch" \
      --base "$target_branch" \
      --title "$title" \
      --fill \
      --repo "$(git -C "$repo_root" remote get-url origin 2>/dev/null)" \
      2>&1
  elif command -v glab &>/dev/null; then
    echo "Creating merge request: $branch → $target_branch"
    glab mr create \
      --source-branch "$branch" \
      --target-branch "$target_branch" \
      --title "$title" \
      --fill \
      2>&1
  else
    echo "Branch pushed. No CLI tool found to create PR/MR."
    echo "Install 'gh' (GitHub) or 'glab' (GitLab) to create PRs/MRs automatically."
    echo ""
    echo "  Branch: $branch → $target_branch"
    return 0
  fi

  # Notify via cmux.dev if available
  if _fleet_has_cmux; then
    cmux notify --title "fleet" --body "PR created: $branch → $target_branch" &>/dev/null
  fi
}

_fleet_rm() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet rm [branch] [-f|--force]"
    echo "       fleet rm --all"
    echo ""
    echo "  Remove a worktree, its workspace, and branch."
    echo "  Run with no args from inside a worktree directory to auto-detect."
    echo "  Use -f/--force to remove with uncommitted changes."
    echo "  Use --all to remove all fleet worktrees (requires confirmation)."
    return 0
  fi
  local force=false
  local branch=""
  local arg
  for arg in "$@"; do
    case "$arg" in
      --force|-f) force=true ;;
      --all)      branch="--all" ;;
      *)          branch="$arg" ;;
    esac
  done

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  if [[ "$branch" == "--all" ]]; then
    _fleet_rm_all "$repo_root"
    return $?
  fi

  if [[ -z "$branch" ]]; then
    branch="$(_fleet_detect_worktree_branch "$repo_root")"
    if [[ -z "$branch" ]]; then
      echo "Usage: fleet rm <branch>  (or run with no args from inside a worktree directory)"
      return 1
    fi
  fi

  local worktree_dir
  worktree_dir="$(_fleet_worktree_dir "$repo_root" "$branch")"

  if [[ ! -d "$worktree_dir" ]]; then
    echo "Worktree not found: $worktree_dir"
    return 1
  fi

  local remove_args=("$worktree_dir")
  if $force; then
    remove_args=("--force" "${remove_args[@]}")
  fi

  # Run teardown hook in subshell (worktree may be deleted next)
  local hook
  hook="$(_fleet_find_hook "$worktree_dir" "teardown")"
  if [[ -n "$hook" ]]; then
    echo "Running teardown hook..."
    ( cd "$worktree_dir" && "$hook" )
  else
    hook="$(_fleet_find_hook "$repo_root" "teardown")"
    if [[ -n "$hook" ]]; then
      echo "Running teardown hook from repo root..."
      ( cd "$worktree_dir" && "$hook" )
    fi
  fi

  # Close cmux.dev workspace if available
  local state_file
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  if _fleet_has_cmux; then
    local ws_id
    ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
    if [[ -n "$ws_id" ]]; then
      cmux close-workspace --workspace "$ws_id" &>/dev/null
    fi
  fi

  # Always clean state
  _fleet_rm_state "$repo_root" "$branch"

  if git -C "$repo_root" worktree remove "${remove_args[@]}"; then
    git -C "$repo_root" branch -d "$branch" &>/dev/null
    echo "Removed worktree and branch: $branch"
    if [[ "$PWD" == "$worktree_dir"* ]]; then
      echo "Warning: your shell is still in the deleted worktree directory."
      echo "  Run 'fleet cd' to return to the repo root."
    fi
  else
    echo "Failed to remove worktree: $branch"
    if ! $force; then
      echo "Hint: use 'fleet rm -f $branch' to remove with uncommitted changes"
    fi
    return 1
  fi
}

_fleet_rm_all() {
  local repo_root="$1"
  local base_dir
  base_dir="$(_fleet_worktree_base "$repo_root")"
  local layout
  layout="$(_fleet_get_layout "$repo_root")"

  if [[ "$layout" != "sibling" && ! -d "$base_dir" ]]; then
    echo "No worktrees directory found."
    return 0
  fi

  local filter
  case "$layout" in
    outer-nested) filter="$(dirname "$repo_root")/$(basename "$repo_root").worktrees/" ;;
    sibling)      filter="$(dirname "$repo_root")/$(basename "$repo_root")-" ;;
    *)            filter="$base_dir/" ;;
  esac

  local dirs=()
  local branches=()
  local wt_dir wt_branch
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    wt_dir="$(echo "$line" | awk '{print $1}')"
    wt_branch="$(git -C "$repo_root" worktree list --porcelain \
      | grep -A2 "^worktree ${wt_dir}\$" \
      | grep '^branch ' \
      | sed 's|^branch refs/heads/||')"
    dirs+=("$wt_dir")
    branches+=("${wt_branch:-unknown}")
  done < <(git -C "$repo_root" worktree list | grep -F "$filter")

  local count=${#dirs[@]}

  if [[ "$count" -eq 0 ]]; then
    echo "No fleet worktrees to remove."
    return 0
  fi

  echo "This will remove ALL fleet worktrees and their branches:"
  echo ""
  for (( i = 1; i <= ${#dirs[@]}; i++ )); do
    local rel_dir="${dirs[$i]#$repo_root/}"
    echo "  $rel_dir  (branch: ${branches[$i]})"
  done
  echo ""

  local expected="DELETE $count WORKTREES"
  printf 'Type "%s" to confirm: ' "$expected"
  read -r confirmation
  if [[ "$confirmation" != "$expected" ]]; then
    echo "Aborted."
    return 1
  fi

  echo ""
  local failed=0
  for (( i = 1; i <= ${#dirs[@]}; i++ )); do
    # Run teardown hook in subshell
    local hook
    hook="$(_fleet_find_hook "${dirs[$i]}" "teardown")"
    if [[ -n "$hook" ]]; then
      ( cd "${dirs[$i]}" && "$hook" )
    else
      hook="$(_fleet_find_hook "$repo_root" "teardown")"
      [[ -n "$hook" ]] && ( cd "${dirs[$i]}" && "$hook" )
    fi

    # Close cmux.dev workspace if available
    local state_file
    state_file="$(_fleet_state_file "$repo_root" "${branches[$i]}")"
    if _fleet_has_cmux; then
      local ws_id
      ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
      if [[ -n "$ws_id" ]]; then
        cmux close-workspace --workspace "$ws_id" &>/dev/null
      fi
    fi

    # Always clean state
    _fleet_rm_state "$repo_root" "${branches[$i]}"

    if git -C "$repo_root" worktree remove --force "${dirs[$i]}" &>/dev/null; then
      git -C "$repo_root" branch -d "${branches[$i]}" &>/dev/null
      echo "  Removed: ${branches[$i]}"
    else
      echo "  Failed:  ${branches[$i]}"
      ((failed++))
    fi
  done

  echo ""
  if [[ "$failed" -eq 0 ]]; then
    echo "All $count worktrees removed."
  else
    echo "Done. $((count - failed))/$count removed ($failed failed)."
  fi
}

_fleet_init() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet init [--replace]"
    echo ""
    echo "  Generate a .fleet/setup hook using Claude Code."
    echo "  Use --replace to regenerate an existing setup hook."
    return 0
  fi
  local replace=false
  for arg in "$@"; do
    case "$arg" in
      --replace) replace=true ;;
    esac
  done

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  # Add .worktrees/ to .gitignore if not already present
  local gitignore="$repo_root/.gitignore"
  if ! grep -qxF '.worktrees/' "$gitignore" &>/dev/null; then
    printf '\n# fleet worktrees\n.worktrees/\n' >> "$gitignore"
    echo "Added .worktrees/ to .gitignore"
  fi

  if ! command -v claude &>/dev/null; then
    echo "claude CLI not found. Install it: https://docs.anthropic.com/en/docs/claude-code"
    return 1
  fi

  local target_dir
  target_dir="$(git rev-parse --show-toplevel 2>/dev/null)" || target_dir="$repo_root"
  local setup_file="$target_dir/.fleet/setup"

  if [[ -f "$setup_file" ]] && [[ "$replace" != true ]]; then
    echo ".fleet/setup already exists: $setup_file"
    echo "Run 'fleet init --replace' to regenerate it."
    return 1
  fi

  local tmpfile
  tmpfile="$(mktemp)" || { echo "Failed to create temp file"; return 1; }

  printf "Analyzing repo to generate .fleet/setup...  "
  mkdir -p "$target_dir/.fleet"

  local system_prompt
  IFS= read -r -d '' system_prompt <<'SYSPROMPT' || true
You generate bash scripts. Output ONLY the script itself — no markdown fences, no prose, no explanation. The first line of your response must be #!/bin/bash. Do not wrap the script in ``` code blocks.
SYSPROMPT

  local prompt
  IFS= read -r -d '' prompt <<'PROMPT' || true
Generate a .fleet/setup script for this repo. This script runs after a git worktree is created, from within the new worktree directory.

Rules:
- Start with #!/bin/bash
- Set REPO_ROOT="$(git rev-parse --git-common-dir | xargs dirname)"
- Symlink any gitignored secret/config files (e.g. .env, .env.local) from $REPO_ROOT
- Install dependencies if a lock file exists (detect package manager)
- Run codegen/build steps if applicable
- Only include steps relevant to THIS repo — omit anything that doesn't apply
- Use short bash comments for non-obvious lines
- No echo statements, no status messages, no decorative output
- If the repo needs no setup, output just: #!/bin/bash followed by a one-line comment explaining why

Example output for a Node.js project:

#!/bin/bash
REPO_ROOT="$(git rev-parse --git-common-dir | xargs dirname)"
ln -sf "$REPO_ROOT/.env" .env
ln -sf "$REPO_ROOT/.dev.vars" .dev.vars
npm ci && npx prisma generate

IMPORTANT: Output ONLY the raw bash script. The very first characters of your response must be #!/bin/bash — no preamble, no markdown, no commentary.
PROMPT

  local claude_pid
  _fleet_spinner_start
  [[ -n "$ZSH_VERSION" ]] && setopt localoptions nomonitor
  claude -p --system-prompt "$system_prompt" "$prompt" < /dev/null > "$tmpfile" &>/dev/null &
  claude_pid=$!

  trap 'kill $claude_pid &>/dev/null; wait $claude_pid &>/dev/null; _fleet_spinner_stop; rm -f "$tmpfile"; trap - INT; printf "\nAborted.\n"; return 130' INT

  local raw_output
  if ! wait "$claude_pid"; then
    _fleet_spinner_stop
    rm -f "$tmpfile"
    trap - INT
    echo "Failed to generate setup script"
    return 1
  fi
  _fleet_spinner_stop
  raw_output="$(<"$tmpfile")"
  rm -f "$tmpfile"

  local script
  if [[ "$raw_output" == *'#!/bin/bash'* ]]; then
    script="$raw_output"
  else
    trap - INT
    echo "Error: generated output did not contain a valid bash script."
    echo ""
    echo "Raw output:"
    echo "$raw_output"
    return 1
  fi

  echo ""
  echo "Generated .fleet/setup:"
  echo "────────────────────────────────"
  echo "$script"
  echo "────────────────────────────────"
  echo ""

  while true; do
    printf "  [enter] Accept   [e] Edit in \$EDITOR   [r] Regenerate   [q] Quit\n\n> "
    read -r choice
    case "$choice" in
      "")
        echo "$script" > "$setup_file"
        chmod +x "$setup_file"
        echo ""
        echo "Created $setup_file"
        echo "Tip: commit .fleet/setup to your repo so it's available in new worktrees."
        trap - INT
        return 0
        ;;
      e|E)
        echo "$script" > "$setup_file"
        chmod +x "$setup_file"
        "${EDITOR:-vi}" "$setup_file"
        trap - INT
        if [[ -f "$setup_file" ]]; then
          echo ""
          echo "Saved $setup_file"
          echo "Tip: commit .fleet/setup to your repo so it's available in new worktrees."
          return 0
        else
          echo "File was removed during editing. Aborting."
          return 1
        fi
        ;;
      r|R)
        echo ""
        printf "Regenerating...  "
        tmpfile="$(mktemp)"
        _fleet_spinner_start
        [[ -n "$ZSH_VERSION" ]] && setopt localoptions nomonitor
        claude -p --system-prompt "$system_prompt" "$prompt" < /dev/null > "$tmpfile" &>/dev/null &
        claude_pid=$!
        trap 'kill $claude_pid &>/dev/null; wait $claude_pid &>/dev/null; _fleet_spinner_stop; rm -f "$tmpfile"; trap - INT; printf "\nAborted.\n"; return 130' INT
        if ! wait "$claude_pid"; then
          _fleet_spinner_stop
          rm -f "$tmpfile"
          trap - INT
          echo "Failed to generate setup script"
          return 1
        fi
        _fleet_spinner_stop
        raw_output="$(<"$tmpfile")"
        rm -f "$tmpfile"
        if [[ "$raw_output" == *'#!/bin/bash'* ]]; then
          script="$raw_output"
        else
          trap - INT
          echo "Error: generated output did not contain a valid bash script."
          echo ""
          echo "Raw output:"
          echo "$raw_output"
          return 1
        fi
        echo ""
        echo "Generated .fleet/setup:"
        echo "────────────────────────────────"
        echo "$script"
        echo "────────────────────────────────"
        echo ""
        ;;
      q|Q)
        trap - INT
        echo "Aborted."
        return 1
        ;;
      *)
        echo "Invalid choice."
        ;;
    esac
  done
}

_fleet_config() {
  local repo_root
  repo_root="$(_fleet_repo_root 2>/dev/null)"

  if [[ -z "$1" ]]; then
    _fleet_config_show "$repo_root"
    return 0
  fi

  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    _fleet_config_usage
    return 0
  fi

  if [[ "$1" != "set" ]]; then
    _fleet_config_usage
    return 1
  fi
  shift

  local global=false
  local key="" value=""
  for arg in "$@"; do
    case "$arg" in
      --global) global=true ;;
      *)
        if [[ -z "$key" ]]; then
          key="$arg"
        else
          value="$arg"
        fi
        ;;
    esac
  done

  if [[ -z "$key" || -z "$value" ]]; then
    _fleet_config_usage
    return 1
  fi

  # Validate key and value
  case "$key" in
    layout)
      case "$value" in
        nested|outer-nested|sibling) ;;
        *)
          echo "Invalid layout: $value"
          echo "Valid presets: nested, outer-nested, sibling"
          return 1
          ;;
      esac
      ;;
    base-branch)
      ;; # any value accepted
    *)
      echo "Unknown config key: $key"
      echo "Valid keys: layout, base-branch"
      return 1
      ;;
  esac

  local config_file
  if [[ "$global" == true ]]; then
    config_file="$HOME/.fleet/config.json"
    mkdir -p "$HOME/.fleet"
  else
    if [[ -z "$repo_root" ]]; then
      echo "Not in a git repo. Use --global to set globally."
      return 1
    fi
    config_file="$repo_root/.fleet/config.json"
    mkdir -p "$repo_root/.fleet"
  fi

  # Layout-specific warning
  if [[ "$key" == "layout" && -n "$repo_root" ]]; then
    local base_dir
    base_dir="$(_fleet_worktree_base "$repo_root")"
    local existing
    existing="$(git -C "$repo_root" worktree list 2>/dev/null | grep -F "$base_dir/" | wc -l | tr -d ' ')"
    if [[ "$existing" -gt 0 ]]; then
      echo "Warning: $existing existing worktrees use the current layout."
      echo "Changing layout won't move them. Remove them first with 'fleet rm --all'."
    fi
  fi

  if [[ -f "$config_file" ]] && grep -q "\"$key\"" "$config_file" &>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    sed 's|"'"$key"'"[[:space:]]*:[[:space:]]*"[^"]*"|"'"$key"'": "'"$value"'"|' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
  elif [[ -f "$config_file" ]]; then
    # Add key to existing config
    local tmp
    tmp="$(mktemp)"
    sed 's|}$|,\n  "'"$key"'": "'"$value"'"\n}|' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
  else
    printf '{\n  "%s": "%s"\n}\n' "$key" "$value" > "$config_file"
  fi

  local target="per-project"
  [[ "$global" == true ]] && target="global"
  echo "Set $target $key to: $value"
}

_fleet_config_show() {
  local repo_root="$1"

  # Show all config values with sources
  local layout base_branch layout_source base_branch_source

  # Layout
  if [[ -n "$repo_root" && -f "$repo_root/.fleet/config.json" ]] \
     && grep -q '"layout"' "$repo_root/.fleet/config.json" &>/dev/null; then
    layout="$(grep '"layout"' "$repo_root/.fleet/config.json" | sed 's/.*"layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    layout_source="$repo_root/.fleet/config.json"
  elif [[ -f "$HOME/.fleet/config.json" ]] \
     && grep -q '"layout"' "$HOME/.fleet/config.json" &>/dev/null; then
    layout="$(grep '"layout"' "$HOME/.fleet/config.json" | sed 's/.*"layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    layout_source="~/.fleet/config.json"
  else
    layout="nested"
    layout_source="default"
  fi

  # Base branch
  if [[ -n "$repo_root" && -f "$repo_root/.fleet/config.json" ]] \
     && grep -q '"base-branch"' "$repo_root/.fleet/config.json" &>/dev/null; then
    base_branch="$(grep '"base-branch"' "$repo_root/.fleet/config.json" | sed 's/.*"base-branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    base_branch_source="$repo_root/.fleet/config.json"
  elif [[ -f "$HOME/.fleet/config.json" ]] \
     && grep -q '"base-branch"' "$HOME/.fleet/config.json" &>/dev/null; then
    base_branch="$(grep '"base-branch"' "$HOME/.fleet/config.json" | sed 's/.*"base-branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    base_branch_source="~/.fleet/config.json"
  else
    base_branch="$(_fleet_default_branch "$repo_root" 2>/dev/null)"
    base_branch_source="auto-detected"
  fi

  echo "layout=$layout (source: $layout_source)"
  echo "base-branch=${base_branch:-main} (source: $base_branch_source)"
}

_fleet_config_usage() {
  echo "Usage: fleet config                                     Show effective config"
  echo "       fleet config set <key> <value> [--global]        Set config value"
  echo ""
  echo "Keys:"
  echo "  layout        Worktree layout: nested, outer-nested, sibling"
  echo "  base-branch   Branch to base new worktrees on (default: auto-detect)"
}

_fleet_focus() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet focus <branch>"
    echo ""
    echo "  Switch to a branch's cmux.dev workspace."
    return 0
  fi

  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "Usage: fleet focus <branch>"
    return 1
  fi

  if ! _fleet_has_cmux; then
    echo "cmux.dev is not available. Use 'fleet cd $branch' instead."
    return 1
  fi

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  local state_file
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  local ws_id
  ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"

  if [[ -z "$ws_id" ]]; then
    echo "No workspace found for branch: $branch"
    echo "Run 'fleet new $branch' to create one."
    return 1
  fi

  cmux select-workspace --workspace "$ws_id" &>/dev/null
}

_fleet_team() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet team <branch> [--add <role>] [--rm <role>]"
    echo ""
    echo "  Spawn agent team in split panes within the branch's workspace."
    echo "  Roles are defined in .fleet/team.json (project) or ~/.fleet/team.json (global)."
    echo "  Default roles: explorer, architect, reviewer."
    echo ""
    echo "  --add <role>  Add a single agent from the team config"
    echo "  --rm <role>   Remove a running agent pane"
    return 0
  fi

  local branch="" add_role="" rm_role=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --add) add_role="$2"; shift 2 ;;
      --rm)  rm_role="$2"; shift 2 ;;
      *)     branch="$1"; shift ;;
    esac
  done

  if [[ -z "$branch" ]]; then
    echo "Usage: fleet team <branch> [--add <role>] [--rm <role>]"
    return 1
  fi

  if ! _fleet_has_cmux; then
    echo "Agent teams require cmux.dev."
    return 1
  fi

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  local state_file
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  local ws_id
  ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"

  if [[ -z "$ws_id" ]]; then
    echo "No workspace found for branch: $branch"
    echo "Run 'fleet new $branch' to create one."
    return 1
  fi

  local worktree_dir
  worktree_dir="$(_fleet_read_state_field "$state_file" "worktree_dir")"

  # Handle --rm: remove a single agent
  if [[ -n "$rm_role" ]]; then
    local surface_ref
    surface_ref="$(_fleet_read_state_field "$state_file" "team_${rm_role}_surface")"
    if [[ -z "$surface_ref" ]]; then
      echo "No agent found for role: $rm_role"
      return 1
    fi
    cmux close-surface --surface "$surface_ref" --workspace "$ws_id" &>/dev/null
    _fleet_state_set "$state_file" "team_${rm_role}_surface" ""
    echo "Removed agent: $rm_role"
    return 0
  fi

  # Handle --add: add a single agent from team config
  if [[ -n "$add_role" ]]; then
    local found=false
    while IFS='|' read -r name agent split; do
      if [[ "$name" == "$add_role" ]]; then
        found=true
        local split_output surface_ref
        split_output="$(cmux new-split "$split" --workspace "$ws_id" 2>/dev/null)"
        surface_ref="$(_fleet_extract_ref "$split_output" "surface")"
        if [[ -n "$surface_ref" ]]; then
          cmux rename-tab --surface "$surface_ref" --workspace "$ws_id" "$name" &>/dev/null
          cmux send --surface "$surface_ref" --workspace "$ws_id" "cd $worktree_dir && claude --agent $agent" &>/dev/null
          cmux send-key --surface "$surface_ref" --workspace "$ws_id" Enter &>/dev/null
          _fleet_save_team_surfaces "$state_file" "$name" "$surface_ref"
          echo "Added agent: $name"
        else
          echo "Failed to create split for: $name"
          return 1
        fi
        break
      fi
    done < <(_fleet_load_team_roles "$repo_root")
    if [[ "$found" == false ]]; then
      echo "Role '$add_role' not found in team config."
      echo "Available roles:"
      _fleet_load_team_roles "$repo_root" | while IFS='|' read -r name agent split; do
        echo "  $name ($agent)"
      done
      return 1
    fi
    return 0
  fi

  # Default: spawn full team
  echo "Spawning agent team for $branch..."

  local role_names=()
  local surface_args=()
  local prev_surface=""
  local first=true

  while IFS='|' read -r name agent split; do
    local split_output surface_ref
    # First role always splits from the workspace; subsequent split from previous
    if [[ "$first" == true ]]; then
      split_output="$(cmux new-split "$split" --workspace "$ws_id" 2>/dev/null)"
      first=false
    else
      split_output="$(cmux new-split "$split" --surface "$prev_surface" --workspace "$ws_id" 2>/dev/null)"
    fi
    surface_ref="$(_fleet_extract_ref "$split_output" "surface")"
    if [[ -n "$surface_ref" ]]; then
      cmux rename-tab --surface "$surface_ref" --workspace "$ws_id" "$name" &>/dev/null
      cmux send --surface "$surface_ref" --workspace "$ws_id" "cd $worktree_dir && claude --agent $agent" &>/dev/null
      cmux send-key --surface "$surface_ref" --workspace "$ws_id" Enter &>/dev/null
      prev_surface="$surface_ref"
      role_names+=("$name")
      surface_args+=("$name" "$surface_ref")
    fi
  done < <(_fleet_load_team_roles "$repo_root")

  # Update sidebar status
  local role_list
  role_list="$(IFS=', '; echo "${role_names[*]}")"
  cmux set-status agents "$role_list" --workspace "$ws_id" &>/dev/null

  # Save surface refs to state
  _fleet_save_team_surfaces "$state_file" "${surface_args[@]}"

  echo "Agent team launched: $role_list"
}

_fleet_send() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet send <branch> [--role <role>] [--repo <path>] <message>"
    echo ""
    echo "  Send a message to a running pane in a branch's workspace."
    echo "  --role <role>  Send to a specific agent (e.g. explorer, architect)"
    echo "  --repo <path>  Target a different repo's worktree"
    echo "  No --role sends to the main pane."
    return 0
  fi

  if ! _fleet_has_cmux; then
    echo "fleet send requires cmux.dev."
    return 1
  fi

  local branch="" role="" repo_path="" message=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role) role="$2"; shift 2 ;;
      --repo) repo_path="$2"; shift 2 ;;
      *)
        if [[ -z "$branch" ]]; then
          branch="$1"
        else
          # Everything remaining is the message
          message="$*"
          break
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$branch" || -z "$message" ]]; then
    echo "Usage: fleet send <branch> [--role <role>] [--repo <path>] <message>"
    return 1
  fi

  local repo_root
  if [[ -n "$repo_path" ]]; then
    repo_root="$(cd "$repo_path" && git rev-parse --git-common-dir 2>/dev/null)" || {
      echo "Not a git repo: $repo_path"
      return 1
    }
    repo_root="$(cd "$repo_path" && realpath "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")")"
  else
    repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }
  fi

  local state_file
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  local ws_id
  ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"

  if [[ -z "$ws_id" ]]; then
    echo "No workspace found for branch: $branch"
    return 1
  fi

  local target_surface
  if [[ -n "$role" ]]; then
    target_surface="$(_fleet_read_state_field "$state_file" "team_${role}_surface")"
    if [[ -z "$target_surface" ]]; then
      echo "No agent surface found for role: $role"
      return 1
    fi
  else
    target_surface="$(_fleet_read_state_field "$state_file" "main_surface")"
    # Fallback: discover first surface from workspace
    if [[ -z "$target_surface" ]]; then
      target_surface="$(cmux list-pane-surfaces --workspace "$ws_id" 2>/dev/null \
        | head -1 | grep -oE 'surface:[0-9]+')"
    fi
    if [[ -z "$target_surface" ]]; then
      echo "No surface found for branch: $branch"
      return 1
    fi
  fi

  cmux send --surface "$target_surface" --workspace "$ws_id" "$message" &>/dev/null
  cmux send-key --surface "$target_surface" --workspace "$ws_id" Enter &>/dev/null

  if [[ -n "$role" ]]; then
    echo "Sent to $role ($branch): $message"
  else
    echo "Sent to $branch: $message"
  fi
}

_fleet_status() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet status [branch] [--json]"
    echo ""
    echo "  Show workspace status, agent liveness, and git info."
    echo "  No args = detect from current worktree."
    echo "  --json for machine-readable output."
    return 0
  fi

  local branch="" json_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      *)      branch="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  if [[ -z "$branch" ]]; then
    branch="$(_fleet_detect_worktree_branch "$repo_root")"
    if [[ -z "$branch" ]]; then
      echo "Usage: fleet status <branch> [--json]"
      echo "  (or run with no args from inside a worktree directory)"
      return 1
    fi
  fi

  local state_file
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  local ws_id worktree_dir
  ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
  worktree_dir="$(_fleet_read_state_field "$state_file" "worktree_dir")"

  # Git info — use stored base_branch if available, fall back to current default
  local base_branch git_ahead git_status_short
  base_branch="$(_fleet_read_state_field "$state_file" "base_branch")"
  [[ -z "$base_branch" ]] && base_branch="$(_fleet_default_branch "$repo_root")"
  if [[ -n "$worktree_dir" && -d "$worktree_dir" ]]; then
    git_ahead="$(git -C "$worktree_dir" log --oneline "${base_branch}..${branch}" 2>/dev/null | wc -l | tr -d ' ')"
    git_status_short="$(git -C "$worktree_dir" status --short 2>/dev/null)"
  fi

  local git_clean="true"
  [[ -n "$git_status_short" ]] && git_clean="false"

  # Collect agent info
  local agent_lines="" agent_json=""
  if [[ -f "$state_file" ]]; then
    while IFS= read -r line; do
      local role_name surface_ref
      role_name="$(echo "$line" | sed -n 's/.*"team_\(.*\)_surface".*/\1/p')"
      [[ -z "$role_name" ]] && continue
      surface_ref="$(_fleet_read_state_field "$state_file" "team_${role_name}_surface")"
      [[ -z "$surface_ref" ]] && continue

      local alive="unknown"
      if _fleet_has_cmux && [[ -n "$ws_id" ]]; then
        if cmux read-screen --surface "$surface_ref" --workspace "$ws_id" &>/dev/null; then
          alive="alive"
        else
          alive="gone"
        fi
      fi

      agent_lines+="  $(printf '%-12s %-14s %s' "$role_name" "$surface_ref" "$alive")"$'\n'
      agent_json+="$(printf '{"role":"%s","surface":"%s","status":"%s"},' "$role_name" "$surface_ref" "$alive")"
    done < "$state_file"
  fi

  if [[ "$json_mode" == true ]]; then
    # Remove trailing comma from agent_json
    agent_json="${agent_json%,}"
    cat <<EOF
{
  "branch": "$branch",
  "base_branch": "$base_branch",
  "workspace_id": "${ws_id:-}",
  "worktree_dir": "${worktree_dir:-}",
  "git": {
    "commits_ahead": ${git_ahead:-0},
    "clean": $git_clean
  },
  "agents": [${agent_json}]
}
EOF
    return 0
  fi

  echo "Branch:    $branch"
  echo "Parent:    $base_branch"
  [[ -n "$ws_id" ]] && echo "Workspace: $ws_id"
  [[ -n "$worktree_dir" ]] && echo "Worktree:  $worktree_dir"
  echo ""

  if [[ -n "$agent_lines" ]]; then
    echo "Agents:"
    printf '%s' "$agent_lines"
    echo ""
  fi

  echo "Git: ${git_ahead:-0} commits ahead of ${base_branch}, $([ "$git_clean" == "true" ] && echo "clean working tree" || echo "dirty working tree")"

  if _fleet_has_cmux && [[ -n "$ws_id" ]]; then
    echo ""
    cmux sidebar-state --workspace "$ws_id" &>/dev/null
  fi
}

_fleet_register() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet register"
    echo ""
    echo "  Register the current worktree directory with fleet."
    echo "  Creates state for worktrees not created by fleet."
    echo "  Run from inside a git worktree directory."
    return 0
  fi

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  # Detect branch from current directory
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    echo "Could not detect branch from current directory."
    return 1
  fi

  # Check we're actually in a worktree (not the main checkout)
  local git_dir common_dir
  git_dir="$(git rev-parse --git-dir 2>/dev/null)"
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"
  if [[ "$(realpath "$git_dir")" == "$(realpath "$common_dir")" ]]; then
    echo "Not in a worktree. Run this from inside a git worktree directory."
    return 1
  fi

  local worktree_dir
  worktree_dir="$(pwd -P)"

  # Check if already registered
  local existing_file
  existing_file="$(_fleet_state_file "$repo_root" "$branch")"
  if [[ -f "$existing_file" ]]; then
    echo "Branch '$branch' is already registered with fleet."
    return 1
  fi

  # Optionally create cmux workspace
  local workspace_id="" main_surface=""
  if _fleet_has_cmux; then
    local ws_output
    ws_output="$(cmux new-workspace 2>/dev/null)"
    # cmux new-workspace returns "OK <uuid>"
    workspace_id="${ws_output#OK }"
    if [[ -z "$workspace_id" || "$workspace_id" == "$ws_output" ]]; then
      workspace_id="$(cmux current-workspace 2>/dev/null)"
    fi
    if [[ -n "$workspace_id" ]]; then
      local safe
      safe="$(_fleet_safe_name "$branch")"
      cmux rename-workspace --workspace "$workspace_id" "$safe" &>/dev/null
    fi
  fi

  local base_branch
  base_branch="$(_fleet_default_branch "$repo_root")"
  _fleet_save_state "$repo_root" "$branch" "$worktree_dir" "$workspace_id" "$main_surface" "$base_branch"
  echo "Registered worktree: $branch"
  echo "  Directory: $worktree_dir"
  if [[ -n "$workspace_id" ]]; then
    echo "  Workspace: $workspace_id"
  fi
}

_fleet_update() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet update"
    echo ""
    echo "  Update fleet to the latest version."
    return 0
  fi
  local install_path="$HOME/.local/bin/fleet"

  echo "Checking for updates..."
  local remote_version
  remote_version="$(curl -fsSL "${_FLEET_DOWNLOAD_URL}/VERSION" 2>/dev/null | tr -d '[:space:]')"

  if [[ -z "$remote_version" ]]; then
    echo "Failed to check for updates (network error?)."
    return 1
  fi

  if [[ "$remote_version" == "$FLEET_VERSION" ]]; then
    echo "fleet is already up to date ($FLEET_VERSION)."
    return 0
  fi

  echo "Updating fleet ($FLEET_VERSION → $remote_version)..."
  mkdir -p "$HOME/.local/bin"
  if curl -fsSL "${_FLEET_DOWNLOAD_URL}/fleet.sh" -o "$install_path"; then
    chmod +x "$install_path"
    printf '%s' "$remote_version" > "$HOME/.fleet/VERSION"
    printf '%s' "$remote_version" > "$HOME/.fleet/.latest_version"
    FLEET_VERSION="$remote_version"
    echo "fleet updated to $FLEET_VERSION."
  else
    echo "Failed to download update."
    return 1
  fi
}

# ── Completions ──────────────────────────────────────────────────────

_fleet_worktree_names() {
  local repo_root
  repo_root="$(_fleet_repo_root 2>/dev/null)" || return
  local layout
  layout="$(_fleet_get_layout "$repo_root")"
  local prefix
  case "$layout" in
    outer-nested) prefix="$(dirname "$repo_root")/$(basename "$repo_root").worktrees/" ;;
    sibling)      prefix="$(dirname "$repo_root")/$(basename "$repo_root")-" ;;
    *)            prefix="$(_fleet_worktree_base "$repo_root")/" ;;
  esac
  git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | awk -v prefix="$prefix" '
        /^worktree / { wt=substr($0,10); in_wt=(index(wt,prefix)==1) }
        /^branch / && in_wt { sub(/^branch refs\/heads\//,""); print }'
}

_fleet_init_shell() {
  # Output the shell wrapper function and completions for eval.
  # Shell detection is embedded in the output so it runs in the
  # user's shell (zsh/bash), not in this bash script.
  cat <<'INIT_SHELL_OUTPUT'
fleet() {
  if [[ "$1" == "cd" ]]; then
    local dir
    dir="$(command fleet cd "${@:2}")" && cd "$dir"
  else
    command fleet "$@"
  fi
}
_fleet_worktree_names() {
  local repo_root
  repo_root="$(command fleet cd 2>/dev/null)" || return
  local layout=""
  if [[ -n "$repo_root" && -f "$repo_root/.fleet/config.json" ]]; then
    layout="$(grep '"layout"' "$repo_root/.fleet/config.json" 2>/dev/null | sed 's/.*"layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  fi
  if [[ -z "$layout" && -f "$HOME/.fleet/config.json" ]]; then
    layout="$(grep '"layout"' "$HOME/.fleet/config.json" 2>/dev/null | sed 's/.*"layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  fi
  layout="${layout:-nested}"
  local prefix
  case "$layout" in
    outer-nested) prefix="$(dirname "$repo_root")/$(basename "$repo_root").worktrees/" ;;
    sibling)      prefix="$(dirname "$repo_root")/$(basename "$repo_root")-" ;;
    *)            prefix="$repo_root/.worktrees/" ;;
  esac
  git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | awk -v prefix="$prefix" '
        /^worktree / { wt=substr($0,10); in_wt=(index(wt,prefix)==1) }
        /^branch / && in_wt { sub(/^branch refs\/heads\//,""); print }'
}
if [[ -n "$ZSH_VERSION" ]]; then
  _fleet_zsh_complete() {
    local -a subcmds=(
      'new:New worktree + workspace, launch Claude'
      'start:Resume Claude in existing workspace'
      'cd:cd into worktree'
      'ls:List worktrees'
      'merge:Push branch + create PR/MR'
      'rm:Remove worktree + workspace + branch'
      'init:Generate .fleet/setup hook'
      'config:View or set configuration'
      'focus:Switch to workspace'
      'team:Spawn/manage agent team'
      'send:Send message to pane'
      'status:Show workspace/agent/git status'
      'register:Register current worktree'
      'update:Update fleet to latest version'
      'version:Show current version'
    )
    if (( CURRENT == 2 )); then
      _describe 'fleet command' subcmds
    elif (( CURRENT == 3 )); then
      case "${words[2]}" in
        start|cd|merge|focus|team|send|status)
          local -a names=( ${(f)"$(_fleet_worktree_names)"} )
          compadd -a names
          ;;
        rm)
          local -a names=( ${(f)"$(_fleet_worktree_names)"} )
          compadd -a names
          compadd -- --all
          ;;
        init)
          compadd -- --replace
          ;;
        config)
          compadd -- set
          ;;
        ls)
          compadd -- --status --all --prune
          ;;
      esac
    else
      case "${words[2]}" in
        merge)
          compadd -- --title
          ;;
        team)
          compadd -- --add --rm
          ;;
        send)
          compadd -- --role --repo
          ;;
        status)
          compadd -- --json
          ;;
        config)
          if (( CURRENT == 4 )) && [[ "${words[3]}" == "set" ]]; then
            compadd -- layout base-branch
          elif (( CURRENT == 5 )) && [[ "${words[3]}" == "set" && "${words[4]}" == "layout" ]]; then
            compadd -- nested outer-nested sibling
          elif (( CURRENT == 5 )) && [[ "${words[3]}" == "set" && "${words[4]}" == "base-branch" ]]; then
            compadd -- main master development
          elif (( CURRENT == 6 )) && [[ "${words[3]}" == "set" ]]; then
            compadd -- --global
          fi
          ;;
      esac
    fi
  }
  if (( $+functions[compdef] )); then
    compdef _fleet_zsh_complete fleet
  fi
elif [[ -n "$BASH_VERSION" ]]; then
  _fleet_bash_complete() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    if (( COMP_CWORD == 1 )); then
      COMPREPLY=( $(compgen -W "new start cd ls merge rm init config focus team send status register update version" -- "$cur") )
    elif (( COMP_CWORD == 2 )); then
      case "$prev" in
        start|cd|merge|focus|team|send|status)
          COMPREPLY=( $(compgen -W "$(_fleet_worktree_names)" -- "$cur") )
          ;;
        rm)
          COMPREPLY=( $(compgen -W "$(_fleet_worktree_names) --all" -- "$cur") )
          ;;
        init)
          COMPREPLY=( $(compgen -W "--replace" -- "$cur") )
          ;;
        config)
          COMPREPLY=( $(compgen -W "set" -- "$cur") )
          ;;
        ls)
          COMPREPLY=( $(compgen -W "--status --all --prune" -- "$cur") )
          ;;
      esac
    else
      case "${COMP_WORDS[1]}" in
        merge)
          COMPREPLY=( $(compgen -W "--title" -- "$cur") )
          ;;
        team)
          COMPREPLY=( $(compgen -W "--add --rm" -- "$cur") )
          ;;
        send)
          COMPREPLY=( $(compgen -W "--role --repo" -- "$cur") )
          ;;
        status)
          COMPREPLY=( $(compgen -W "--json" -- "$cur") )
          ;;
        config)
          if (( COMP_CWORD == 3 )) && [[ "${COMP_WORDS[2]}" == "set" ]]; then
            COMPREPLY=( $(compgen -W "layout base-branch" -- "$cur") )
          elif (( COMP_CWORD == 4 )) && [[ "${COMP_WORDS[2]}" == "set" \
               && "${COMP_WORDS[3]}" == "layout" ]]; then
            COMPREPLY=( $(compgen -W "nested outer-nested sibling" -- "$cur") )
          elif (( COMP_CWORD == 4 )) && [[ "${COMP_WORDS[2]}" == "set" \
               && "${COMP_WORDS[3]}" == "base-branch" ]]; then
            COMPREPLY=( $(compgen -W "main master development" -- "$cur") )
          elif (( COMP_CWORD == 5 )) && [[ "${COMP_WORDS[2]}" == "set" ]]; then
            COMPREPLY=( $(compgen -W "--global" -- "$cur") )
          fi
          ;;
      esac
    fi
  }
  complete -F _fleet_bash_complete fleet
fi
INIT_SHELL_OUTPUT
}

# ── Main entrypoint ──────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fleet "$@"
fi
