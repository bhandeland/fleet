#!/usr/bin/env bats
# Tests for fleet start

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
  mock_claude
}

teardown() {
  teardown_repo
}

@test "fleet start --help shows usage" {
  run fleet start --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet start"* ]]
}

@test "fleet start with no branch fails" {
  run fleet start
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet start with missing worktree fails" {
  run fleet start nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"Worktree not found"* ]]
}

@test "fleet start with existing worktree changes directory" {
  create_test_worktree "start-test"
  fleet start start-test
  [[ "$(pwd -P)" == *"start-test"* ]]
}

@test "fleet start suggests fleet new for missing worktree" {
  run fleet start nonexistent
  [[ "$output" == *"fleet new"* ]]
}

# ── cmux.dev mode ────────────────────────────────────────────────

@test "fleet start with cmux focuses workspace" {
  mock_cmux
  create_test_worktree "cmux-start"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "cmux-start")"
  _fleet_save_state "$REPO_DIR" "cmux-start" "$wt_dir" "workspace:5" "surface:5"

  run fleet start cmux-start
  [ "$status" -eq 0 ]
}

@test "fleet start with cmux but no state falls back to local" {
  mock_cmux
  create_test_worktree "no-state"
  run fleet start no-state
  [ "$status" -eq 0 ]
  [[ "$output" == *"No workspace state"* ]]
}
