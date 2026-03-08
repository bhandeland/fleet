# fleet — Claude Worktree Manager with cmux.dev Integration
#
# Worktree lifecycle manager for parallel Claude Code sessions
# with native cmux.dev workspace/pane/sidebar support.
#
# Commands:
#   fleet new <branch> [-p <prompt>] [--team]  — New worktree, open workspace, launch Claude
#   fleet start <branch> [-p <prompt>]         — Focus workspace, resume Claude with --continue
#   fleet cd [branch]                          — cd into worktree (no args = repo root)
#   fleet ls [--status]                        — List worktrees (+ sidebar status)
#   fleet merge [branch] [--squash]            — Merge worktree branch into primary checkout
#   fleet rm [branch | --all] [-f]             — Remove worktree + workspace + branch
#   fleet init [--replace]                     — Generate .fleet/setup hook using Claude
#   fleet config [set <key> <value> [--global]] — View/set layout config
#   fleet focus <branch>                       — Switch to a branch's cmux.dev workspace
#   fleet team <branch>                        — Spawn agent team in split panes
#   fleet status [branch]                      — Show sidebar state for a workspace
#   fleet update / fleet version

_FLEET_DOWNLOAD_URL="https://gitlab.com/nighthawk-oss/fleet/-/raw/main"
FLEET_VERSION="unknown"
[[ -f "$HOME/.fleet/VERSION" ]] && FLEET_VERSION="$(<"$HOME/.fleet/VERSION")"

fleet() {
  local cmd="$1"
  shift 2>/dev/null

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
    status)  _fleet_status "$@" ;;
    update)  _fleet_update "$@" ;;
    version) echo "fleet $FLEET_VERSION" ;;
    --help|-h|"")
      echo "Usage: fleet <command> [args]"
      echo ""
      echo "  new <branch> [-p <prompt>] [--team]  New worktree + workspace, launch Claude"
      echo "  start <branch> [-p <prompt>]         Resume Claude in existing workspace"
      echo "  cd [branch]        cd into worktree (no args = repo root)"
      echo "  ls [--status]      List worktrees (+ sidebar status when available)"
      echo "  merge [branch] [--squash]  Merge worktree branch into primary checkout"
      echo "  rm [branch] [-f]   Remove worktree + workspace + branch"
      echo "  rm --all           Remove ALL worktrees (requires confirmation)"
      echo "  init [--replace]   Generate .fleet/setup hook using Claude"
      echo "  config             View or set worktree layout configuration"
      echo "  focus <branch>     Switch to a branch's cmux.dev workspace"
      echo "  team <branch>      Spawn agent team in split panes"
      echo "  status [branch]    Show sidebar state for a workspace"
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

# Detect the default branch (main/master)
_fleet_default_branch() {
  local repo_root="$1"
  local default
  default="$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"
  if [[ -n "$default" ]]; then
    echo "$default"
    return
  fi
  if git -C "$repo_root" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    echo "main"
  elif git -C "$repo_root" show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    echo "master"
  else
    git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null
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

# Read layout config: per-project > global > default (nested)
_fleet_get_layout() {
  local repo_root="$1"
  local layout=""
  # Per-project config
  if [[ -n "$repo_root" && -f "$repo_root/.fleet/config.json" ]]; then
    layout="$(grep '"layout"' "$repo_root/.fleet/config.json" 2>/dev/null | sed 's/.*"layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  fi
  # Global config fallback
  if [[ -z "$layout" && -f "$HOME/.fleet/config.json" ]]; then
    layout="$(grep '"layout"' "$HOME/.fleet/config.json" 2>/dev/null | sed 's/.*"layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  fi
  echo "${layout:-nested}"
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
  kill "$_FLEET_SPINNER_PID" 2>/dev/null
  wait "$_FLEET_SPINNER_PID" 2>/dev/null
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
  disown 2>/dev/null
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
  local repo_root="$1" branch="$2" worktree_dir="$3" workspace_id="$4" main_surface="${5:-}"
  local state_dir state_file
  state_dir="$(_fleet_state_dir "$repo_root")"
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  mkdir -p "$state_dir"
  cat > "$state_file" <<EOF
{
  "branch": "$branch",
  "worktree_dir": "$worktree_dir",
  "workspace_id": "$workspace_id",
  "main_surface": "$main_surface"
}
EOF
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
  rm -f "$state_file" 2>/dev/null
}

# Update state file with team surface refs
_fleet_save_team_surfaces() {
  local state_file="$1"
  local explorer_surface="$2" architect_surface="$3" reviewer_surface="$4"
  [[ -f "$state_file" ]] || return 1
  local branch worktree_dir workspace_id main_surface
  branch="$(_fleet_read_state_field "$state_file" "branch")"
  worktree_dir="$(_fleet_read_state_field "$state_file" "worktree_dir")"
  workspace_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
  main_surface="$(_fleet_read_state_field "$state_file" "main_surface")"
  cat > "$state_file" <<EOF
{
  "branch": "$branch",
  "worktree_dir": "$worktree_dir",
  "workspace_id": "$workspace_id",
  "main_surface": "$main_surface",
  "explorer_surface": "$explorer_surface",
  "architect_surface": "$architect_surface",
  "reviewer_surface": "$reviewer_surface"
}
EOF
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
    git -C "$repo_root" pull --ff-only origin "$default_branch" 2>/dev/null || true
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
        cmux select-workspace --workspace "$ws_id" 2>/dev/null
        return 0
      fi
    fi
    cd "$worktree_dir"
    if [[ -n "$prompt" ]]; then
      claude "$prompt"
    else
      claude
    fi
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
    local ws_output
    ws_output="$(cmux new-workspace --command "cd $worktree_dir && exec \$SHELL" --json 2>/dev/null)"
    local workspace_id
    workspace_id="$(_fleet_extract_ref "$ws_output" "workspace")"
    if [[ -z "$workspace_id" ]]; then
      workspace_id="$(cmux current-workspace --json 2>/dev/null | grep -oE 'workspace:[0-9]+' | head -1)"
    fi

    if [[ -n "$workspace_id" ]]; then
      cmux rename-workspace --workspace "$workspace_id" "$branch" 2>/dev/null
      cmux set-status task "$branch" --icon git-branch --workspace "$workspace_id" 2>/dev/null
      cmux set-status status "setting up" --color "#ffcc00" --workspace "$workspace_id" 2>/dev/null

      # Save state
      local main_surface
      main_surface="$(_fleet_extract_ref "$ws_output" "surface")"
      _fleet_save_state "$repo_root" "$branch" "$worktree_dir" "$workspace_id" "$main_surface"
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
      cmux set-status status "ready" --color "#00cc66" --workspace "$workspace_id" 2>/dev/null
      cmux notify --title "fleet" --body "$branch ready" --workspace "$workspace_id" 2>/dev/null

      # Launch team if requested
      if [[ "$team" == true ]]; then
        _fleet_team "$branch"
      fi

      # Send claude command to workspace
      local claude_cmd="claude"
      if [[ -n "$prompt" ]]; then
        claude_cmd="claude -p $(printf '%q' "$prompt")"
      fi
      cmux send --workspace "$workspace_id" "$claude_cmd" 2>/dev/null
      cmux send-key --workspace "$workspace_id" Enter 2>/dev/null
    fi

    echo "Workspace ready: $branch"
  else
    # ── Fallback mode ──
    cd "$worktree_dir"

    # Run setup hook
    local hook
    hook="$(_fleet_find_hook "$worktree_dir" "setup")"
    if [[ -n "$hook" ]]; then
      echo "Running setup hook..."
      "$hook"
    else
      hook="$(_fleet_find_hook "$repo_root" "setup")"
      if [[ -n "$hook" ]]; then
        echo "Running setup hook from repo root (not yet committed to branch)..."
        "$hook"
        echo "Tip: commit .fleet/setup so it's available in new worktrees automatically."
      else
        echo "No .fleet/setup found — worktree will skip project-specific setup."
        printf "Run 'fleet init' to generate one? (y/N) "
        local reply=""
        read -r reply 2>/dev/null || true
        if [[ "$reply" =~ ^[Yy]$ ]]; then
          _fleet_init
          hook="$(_fleet_find_hook "$repo_root" "setup")"
          if [[ -n "$hook" ]]; then
            echo "Running setup hook..."
            "$hook"
          fi
        fi
      fi
    fi

    echo "Worktree ready: $worktree_dir"
    if [[ -n "$prompt" ]]; then
      claude "$prompt"
    else
      claude
    fi
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
      cmux select-workspace --workspace "$ws_id" 2>/dev/null
      local claude_cmd="claude -c"
      if [[ -n "$prompt" ]]; then
        claude_cmd="claude -c -p $(printf '%q' "$prompt")"
      fi
      cmux send --workspace "$ws_id" "$claude_cmd" 2>/dev/null
      cmux send-key --workspace "$ws_id" Enter 2>/dev/null
      return 0
    fi
    # No state file — fall through to fallback
    echo "No workspace state found. Falling back to local mode."
  fi

  cd "$worktree_dir"
  if [[ -n "$prompt" ]]; then
    claude -c "$prompt"
  else
    claude -c
  fi
}

_fleet_cd() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet cd [branch]"
    echo ""
    echo "  cd into a worktree directory (no args = repo root)."
    return 0
  fi
  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  if [[ -z "$1" ]]; then
    cd "$repo_root"
    return
  fi

  local branch="$1"
  local worktree_dir
  worktree_dir="$(_fleet_worktree_dir "$repo_root" "$branch")"

  if [[ ! -d "$worktree_dir" ]]; then
    echo "Worktree not found: $worktree_dir"
    echo "Run 'fleet ls' to see available worktrees."
    return 1
  fi

  cd "$worktree_dir"
}

_fleet_ls() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet ls [--status]"
    echo ""
    echo "  List all fleet worktrees. Use --status to show cmux.dev sidebar state."
    return 0
  fi

  local show_status=false
  [[ "$1" == "--status" ]] && show_status=true

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

_fleet_merge() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet merge [branch] [--squash]"
    echo ""
    echo "  Merge a worktree branch into the primary checkout."
    echo "  Run with no args from inside a worktree directory to auto-detect."
    return 0
  fi
  local branch=""
  local squash=false

  for arg in "$@"; do
    case "$arg" in
      --squash) squash=true ;;
      *)        branch="$arg" ;;
    esac
  done

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  if [[ -z "$branch" ]]; then
    branch="$(_fleet_detect_worktree_branch "$repo_root")"
    if [[ -z "$branch" ]]; then
      echo "Usage: fleet merge <branch> [--squash]"
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

  if ! git -C "$worktree_dir" diff --quiet 2>/dev/null || \
     ! git -C "$worktree_dir" diff --cached --quiet 2>/dev/null; then
    echo "Worktree has uncommitted changes: $worktree_dir"
    echo "Commit or stash them before merging."
    return 1
  fi

  local target_branch
  target_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [[ -z "$target_branch" ]]; then
    echo "Could not determine branch in main checkout."
    return 1
  fi

  if [[ "$branch" == "$target_branch" ]]; then
    echo "Cannot merge '$branch' into itself."
    return 1
  fi

  cd "$repo_root"

  echo "Merging '$branch' into '$target_branch'..."

  if [[ "$squash" == true ]]; then
    git merge --squash "$branch" || return 1
    echo ""
    echo "Squash merge staged. Review and commit the changes:"
    echo "  cd $repo_root && git commit"
  else
    git merge "$branch" || return 1
    echo "Merged '$branch' into '$target_branch'."
  fi

  # Notify via cmux.dev if available
  if _fleet_has_cmux; then
    cmux notify --title "fleet" --body "Merged $branch into $target_branch" 2>/dev/null
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
    cd "$repo_root"
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

  # Run teardown hook
  cd "$worktree_dir"
  local hook
  hook="$(_fleet_find_hook "$worktree_dir" "teardown")"
  if [[ -n "$hook" ]]; then
    echo "Running teardown hook..."
    "$hook"
  else
    hook="$(_fleet_find_hook "$repo_root" "teardown")"
    if [[ -n "$hook" ]]; then
      echo "Running teardown hook from repo root..."
      "$hook"
    fi
  fi

  # Close cmux.dev workspace if available
  if _fleet_has_cmux; then
    local state_file
    state_file="$(_fleet_state_file "$repo_root" "$branch")"
    local ws_id
    ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
    if [[ -n "$ws_id" ]]; then
      cmux close-workspace --workspace "$ws_id" 2>/dev/null
    fi
    _fleet_rm_state "$repo_root" "$branch"
  fi

  if git -C "$repo_root" worktree remove "${remove_args[@]}"; then
    git -C "$repo_root" branch -d "$branch" 2>/dev/null
    if [[ "$PWD" == "$worktree_dir"* ]]; then
      cd "$repo_root"
    fi
    echo "Removed worktree and branch: $branch"
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

  if _fleet_detect_worktree_branch "$repo_root" &>/dev/null; then
    cd "$repo_root"
  fi

  echo ""
  local failed=0
  for (( i = 1; i <= ${#dirs[@]}; i++ )); do
    # Run teardown hook
    cd "${dirs[$i]}"
    local hook
    hook="$(_fleet_find_hook "${dirs[$i]}" "teardown")"
    if [[ -n "$hook" ]]; then
      "$hook"
    else
      hook="$(_fleet_find_hook "$repo_root" "teardown")"
      [[ -n "$hook" ]] && "$hook"
    fi

    # Close cmux.dev workspace
    if _fleet_has_cmux; then
      local state_file
      state_file="$(_fleet_state_file "$repo_root" "${branches[$i]}")"
      local ws_id
      ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"
      if [[ -n "$ws_id" ]]; then
        cmux close-workspace --workspace "$ws_id" 2>/dev/null
      fi
      _fleet_rm_state "$repo_root" "${branches[$i]}"
    fi

    if git -C "$repo_root" worktree remove --force "${dirs[$i]}" 2>/dev/null; then
      git -C "$repo_root" branch -d "${branches[$i]}" 2>/dev/null
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
  claude -p --system-prompt "$system_prompt" "$prompt" < /dev/null > "$tmpfile" 2>/dev/null &
  claude_pid=$!

  trap 'kill $claude_pid 2>/dev/null; wait $claude_pid 2>/dev/null; _fleet_spinner_stop; rm -f "$tmpfile"; trap - INT; printf "\nAborted.\n"; return 130' INT

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
        claude -p --system-prompt "$system_prompt" "$prompt" < /dev/null > "$tmpfile" 2>/dev/null &
        claude_pid=$!
        trap 'kill $claude_pid 2>/dev/null; wait $claude_pid 2>/dev/null; _fleet_spinner_stop; rm -f "$tmpfile"; trap - INT; printf "\nAborted.\n"; return 130' INT
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
    local layout source
    if [[ -n "$repo_root" && -f "$repo_root/.fleet/config.json" ]] \
       && grep -q '"layout"' "$repo_root/.fleet/config.json" 2>/dev/null; then
      layout="$(grep '"layout"' "$repo_root/.fleet/config.json" | sed 's/.*"layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
      source="$repo_root/.fleet/config.json"
    elif [[ -f "$HOME/.fleet/config.json" ]] \
       && grep -q '"layout"' "$HOME/.fleet/config.json" 2>/dev/null; then
      layout="$(grep '"layout"' "$HOME/.fleet/config.json" | sed 's/.*"layout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
      source="~/.fleet/config.json"
    else
      layout="nested"
      source="default"
    fi
    echo "layout=$layout (source: $source)"
    return 0
  fi

  if [[ "$1" != "set" ]]; then
    echo "Usage: fleet config                               Show effective layout"
    echo "       fleet config set layout <preset>            Set per-project"
    echo "       fleet config set layout <preset> --global   Set global default"
    echo ""
    echo "Presets: nested, outer-nested, sibling"
    return 1
  fi
  shift

  local global=false
  local key="" preset=""
  for arg in "$@"; do
    case "$arg" in
      --global) global=true ;;
      layout)   key="layout" ;;
      *)        preset="$arg" ;;
    esac
  done

  if [[ "$key" != "layout" || -z "$preset" ]]; then
    echo "Usage: fleet config set layout <preset> [--global]"
    return 1
  fi
  case "$preset" in
    nested|outer-nested|sibling) ;;
    *)
      echo "Invalid layout: $preset"
      echo "Valid presets: nested, outer-nested, sibling"
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

  if [[ -n "$repo_root" ]]; then
    local base_dir
    base_dir="$(_fleet_worktree_base "$repo_root")"
    local existing
    existing="$(git -C "$repo_root" worktree list 2>/dev/null | grep -F "$base_dir/" | wc -l | tr -d ' ')"
    if [[ "$existing" -gt 0 ]]; then
      echo "Warning: $existing existing worktrees use the current layout."
      echo "Changing layout won't move them. Remove them first with 'fleet rm --all'."
    fi
  fi

  if [[ -f "$config_file" ]] && grep -q '"layout"' "$config_file" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    sed 's/"layout"[[:space:]]*:[[:space:]]*"[^"]*"/"layout": "'"$preset"'"/' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
  else
    printf '{\n  "layout": "%s"\n}\n' "$preset" > "$config_file"
  fi

  local target="per-project"
  [[ "$global" == true ]] && target="global"
  echo "Set $target layout to: $preset"
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

  cmux select-workspace --workspace "$ws_id" 2>/dev/null
}

_fleet_team() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet team <branch>"
    echo ""
    echo "  Spawn agent team in split panes within the branch's workspace."
    echo "  Creates explorer, architect, and reviewer agents."
    return 0
  fi

  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "Usage: fleet team <branch>"
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

  echo "Spawning agent team for $branch..."

  # Create right split for explorer
  local split_output explorer_surface
  split_output="$(cmux new-split right --workspace "$ws_id" --json 2>/dev/null)"
  explorer_surface="$(_fleet_extract_ref "$split_output" "surface")"
  if [[ -n "$explorer_surface" ]]; then
    cmux rename-tab --surface "$explorer_surface" --workspace "$ws_id" "explorer" 2>/dev/null
    cmux send --surface "$explorer_surface" --workspace "$ws_id" "cd $worktree_dir && claude --agent code-explorer" 2>/dev/null
    cmux send-key --surface "$explorer_surface" --workspace "$ws_id" Enter 2>/dev/null
  fi

  # Create down split from right pane for architect
  local architect_surface
  split_output="$(cmux new-split down --surface "$explorer_surface" --workspace "$ws_id" --json 2>/dev/null)"
  architect_surface="$(_fleet_extract_ref "$split_output" "surface")"
  if [[ -n "$architect_surface" ]]; then
    cmux rename-tab --surface "$architect_surface" --workspace "$ws_id" "architect" 2>/dev/null
    cmux send --surface "$architect_surface" --workspace "$ws_id" "cd $worktree_dir && claude --agent code-architect" 2>/dev/null
    cmux send-key --surface "$architect_surface" --workspace "$ws_id" Enter 2>/dev/null
  fi

  # Create down split from architect pane for reviewer
  local reviewer_surface
  split_output="$(cmux new-split down --surface "$architect_surface" --workspace "$ws_id" --json 2>/dev/null)"
  reviewer_surface="$(_fleet_extract_ref "$split_output" "surface")"
  if [[ -n "$reviewer_surface" ]]; then
    cmux rename-tab --surface "$reviewer_surface" --workspace "$ws_id" "reviewer" 2>/dev/null
    cmux send --surface "$reviewer_surface" --workspace "$ws_id" "cd $worktree_dir && claude --agent code-reviewer" 2>/dev/null
    cmux send-key --surface "$reviewer_surface" --workspace "$ws_id" Enter 2>/dev/null
  fi

  # Update sidebar status
  cmux set-status agents "explorer, architect, reviewer" --workspace "$ws_id" 2>/dev/null

  # Save surface refs to state
  _fleet_save_team_surfaces "$state_file" "$explorer_surface" "$architect_surface" "$reviewer_surface"

  echo "Agent team launched: explorer, architect, reviewer"
}

_fleet_status() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet status [branch]"
    echo ""
    echo "  Show cmux.dev sidebar state for a workspace."
    echo "  No args = detect from current worktree."
    return 0
  fi

  if ! _fleet_has_cmux; then
    echo "cmux.dev is not available."
    return 1
  fi

  local repo_root
  repo_root="$(_fleet_repo_root)" || { echo "Not in a git repo"; return 1; }

  local branch="$1"
  if [[ -z "$branch" ]]; then
    branch="$(_fleet_detect_worktree_branch "$repo_root")"
    if [[ -z "$branch" ]]; then
      echo "Usage: fleet status <branch>"
      echo "  (or run with no args from inside a worktree directory)"
      return 1
    fi
  fi

  local state_file
  state_file="$(_fleet_state_file "$repo_root" "$branch")"
  local ws_id
  ws_id="$(_fleet_read_state_field "$state_file" "workspace_id")"

  if [[ -z "$ws_id" ]]; then
    echo "No workspace found for branch: $branch"
    return 1
  fi

  echo "Branch:    $branch"
  echo "Workspace: $ws_id"
  echo ""
  cmux sidebar-state --workspace "$ws_id" 2>/dev/null
}

_fleet_update() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: fleet update"
    echo ""
    echo "  Update fleet to the latest version."
    return 0
  fi
  local install_path="$HOME/.fleet/fleet.sh"

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
  if curl -fsSL "${_FLEET_DOWNLOAD_URL}/fleet.sh" -o "$install_path"; then
    printf '%s' "$remote_version" > "$HOME/.fleet/VERSION"
    printf '%s' "$remote_version" > "$HOME/.fleet/.latest_version"
    source "$install_path"
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

if [[ -n "$ZSH_VERSION" ]]; then
  _fleet_zsh_complete() {
    local -a subcmds=(
      'new:New worktree + workspace, launch Claude'
      'start:Resume Claude in existing workspace'
      'cd:cd into worktree'
      'ls:List worktrees'
      'merge:Merge worktree branch into primary checkout'
      'rm:Remove worktree + workspace + branch'
      'init:Generate .fleet/setup hook'
      'config:View or set configuration'
      'focus:Switch to workspace'
      'team:Spawn agent team in split panes'
      'status:Show sidebar state'
      'update:Update fleet to latest version'
      'version:Show current version'
    )
    if (( CURRENT == 2 )); then
      _describe 'fleet command' subcmds
    elif (( CURRENT == 3 )); then
      case "${words[2]}" in
        start|cd|merge|focus|team|status)
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
          compadd -- --status
          ;;
      esac
    elif (( CURRENT == 4 )); then
      case "${words[2]}" in
        config)
          if [[ "${words[3]}" == "set" ]]; then
            compadd -- layout
          fi
          ;;
      esac
    elif (( CURRENT == 5 )); then
      case "${words[2]}" in
        config)
          if [[ "${words[3]}" == "set" && "${words[4]}" == "layout" ]]; then
            compadd -- nested outer-nested sibling
          fi
          ;;
      esac
    elif (( CURRENT == 6 )); then
      case "${words[2]}" in
        config)
          if [[ "${words[3]}" == "set" && "${words[4]}" == "layout" ]]; then
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
      COMPREPLY=( $(compgen -W "new start cd ls merge rm init config focus team status update version" -- "$cur") )
    elif (( COMP_CWORD == 2 )); then
      case "$prev" in
        start|cd|merge|focus|team|status)
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
          COMPREPLY=( $(compgen -W "--status" -- "$cur") )
          ;;
      esac
    elif (( COMP_CWORD == 3 )); then
      if [[ "${COMP_WORDS[1]}" == "config" && "${COMP_WORDS[2]}" == "set" ]]; then
        COMPREPLY=( $(compgen -W "layout" -- "$cur") )
      fi
    elif (( COMP_CWORD == 4 )); then
      if [[ "${COMP_WORDS[1]}" == "config" && "${COMP_WORDS[2]}" == "set" \
         && "${COMP_WORDS[3]}" == "layout" ]]; then
        COMPREPLY=( $(compgen -W "nested outer-nested sibling" -- "$cur") )
      fi
    elif (( COMP_CWORD == 5 )); then
      if [[ "${COMP_WORDS[1]}" == "config" && "${COMP_WORDS[2]}" == "set" \
         && "${COMP_WORDS[3]}" == "layout" ]]; then
        COMPREPLY=( $(compgen -W "--global" -- "$cur") )
      fi
    fi
  }
  complete -F _fleet_bash_complete fleet
fi
