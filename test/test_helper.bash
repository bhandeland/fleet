# test/test_helper.bash — shared setup/teardown for fleet tests

FLEET_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/fleet.sh"

# Create a temporary git repo for testing
setup_repo() {
  local raw_dir
  raw_dir="$(mktemp -d)"
  # Resolve symlinks (macOS /tmp -> /private/tmp)
  export TEST_DIR="$(cd "$raw_dir" && pwd -P)"
  export REPO_DIR="$TEST_DIR/repo"
  mkdir -p "$REPO_DIR"
  git -C "$REPO_DIR" init -b main --quiet
  git -C "$REPO_DIR" config user.name "test"
  git -C "$REPO_DIR" config user.email "test@test"
  git -C "$REPO_DIR" commit --allow-empty -m "initial" --quiet

  # Ensure fleet sees this as the repo root
  cd "$REPO_DIR"
}

# Tear down the temporary repo
teardown_repo() {
  cd /
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# Source fleet.sh for unit testing (main guard prevents execution)
load_fleet() {
  # Prevent update check from running
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.fleet"
  printf '0.0.0-test' > "$HOME/.fleet/VERSION"
  printf '%s' "$(date +%s)" > "$HOME/.fleet/.last_check"

  source "$FLEET_SH"
}

# Mock cmux as unavailable (default)
mock_no_cmux() {
  _fleet_has_cmux() { return 1; }
}

# Mock cmux as available with stub commands
mock_cmux() {
  _fleet_has_cmux() { return 0; }

  cmux() {
    local cmd="$1"; shift
    case "$cmd" in
      ping) return 0 ;;
      new-workspace)
        echo '{"workspace": "workspace:1", "surface": "surface:1"}'
        ;;
      current-workspace)
        echo '{"workspace": "workspace:1"}'
        ;;
      rename-workspace) return 0 ;;
      select-workspace) return 0 ;;
      close-workspace) return 0 ;;
      set-status) return 0 ;;
      notify) return 0 ;;
      send) return 0 ;;
      send-key) return 0 ;;
      new-split)
        echo '{"surface": "surface:'"$RANDOM"'"}'
        ;;
      list-pane-surfaces)
        echo '* surface:1  ⠐ Shell  [selected]'
        ;;
      rename-tab) return 0 ;;
      list-status) echo "task: test-branch"; echo "status: ready" ;;
      sidebar-state) echo "task: test-branch"; echo "status: ready" ;;
      *) return 0 ;;
    esac
  }
  export -f cmux
}

# Mock claude command
mock_claude() {
  claude() {
    echo "claude called: $*"
    return 0
  }
  export -f claude
}

# Create a worktree in the test repo
create_test_worktree() {
  local branch="$1"
  local repo_root
  repo_root="$(_fleet_repo_root)"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$repo_root" "$branch")"
  local base_dir
  base_dir="$(_fleet_worktree_base "$repo_root")"
  mkdir -p "$base_dir"
  git -C "$repo_root" worktree add "$wt_dir" -b "$branch" --quiet
}
