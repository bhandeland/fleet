#!/usr/bin/env bats
# Tests for fleet ls --all (cross-repo dashboard)

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet ls --all with no state shows no worktrees" {
  run fleet ls --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"No fleet"* ]]
}

@test "fleet ls --all shows worktrees from state" {
  create_test_worktree "all-test"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "all-test")"
  _fleet_save_state "$REPO_DIR" "all-test" "$wt_dir" "" ""

  run fleet ls --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"$REPO_DIR"* ]]
  [[ "$output" == *"all-test"* ]]
  [[ "$output" == *"worktree"* ]]
}

@test "fleet ls --all works outside any git repo" {
  create_test_worktree "outside-test"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "outside-test")"
  _fleet_save_state "$REPO_DIR" "outside-test" "$wt_dir" "" ""

  cd /tmp
  run fleet ls --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"outside-test"* ]]
}

@test "fleet ls --all groups by repo" {
  create_test_worktree "branch-a"
  create_test_worktree "branch-b"
  local wt_a wt_b
  wt_a="$(_fleet_worktree_dir "$REPO_DIR" "branch-a")"
  wt_b="$(_fleet_worktree_dir "$REPO_DIR" "branch-b")"
  _fleet_save_state "$REPO_DIR" "branch-a" "$wt_a" "" ""
  _fleet_save_state "$REPO_DIR" "branch-b" "$wt_b" "" ""

  run fleet ls --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 worktrees"* ]]
  [[ "$output" == *"branch-a"* ]]
  [[ "$output" == *"branch-b"* ]]
}

@test "fleet ls --all shows gone for missing worktrees" {
  _fleet_save_state "$REPO_DIR" "gone-branch" "/nonexistent/path" "" ""

  run fleet ls --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone"* ]]
}

# ── fleet ls --prune ────────────────────────────────────────────

@test "fleet ls --prune with nothing to prune" {
  create_test_worktree "live-branch"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "live-branch")"
  _fleet_save_state "$REPO_DIR" "live-branch" "$wt_dir" "" ""

  run fleet ls --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to prune"* ]]
}

@test "fleet ls --prune removes stale state" {
  _fleet_save_state "$REPO_DIR" "stale-branch" "/nonexistent/path" "" ""
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "stale-branch")"
  [ -f "$sf" ]

  run fleet ls --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pruned"* ]]
  [[ "$output" == *"stale-branch"* ]]
  [ ! -f "$sf" ]
}

@test "fleet ls --prune keeps live state" {
  create_test_worktree "keep-me"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "keep-me")"
  _fleet_save_state "$REPO_DIR" "keep-me" "$wt_dir" "" ""
  _fleet_save_state "$REPO_DIR" "remove-me" "/nonexistent/path" "" ""

  run fleet ls --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pruned: remove-me"* ]]

  local sf_kept sf_removed
  sf_kept="$(_fleet_state_file "$REPO_DIR" "keep-me")"
  sf_removed="$(_fleet_state_file "$REPO_DIR" "remove-me")"
  [ -f "$sf_kept" ]
  [ ! -f "$sf_removed" ]
}

@test "fleet ls --prune with no state directory" {
  rm -rf "$HOME/.fleet/state"
  run fleet ls --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"No fleet state"* ]]
}
