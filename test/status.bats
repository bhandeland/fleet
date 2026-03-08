#!/usr/bin/env bats
# Tests for fleet status

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet status --help shows usage" {
  run fleet status --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet status"* ]]
}

@test "fleet status without cmux fails" {
  run fleet status some-branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"cmux.dev is not available"* ]]
}

@test "fleet status with no args outside worktree fails" {
  mock_cmux
  cd "$REPO_DIR"
  run fleet status
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet status with cmux and state shows info" {
  mock_cmux
  create_test_worktree "status-test"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "status-test")"
  _fleet_save_state "$REPO_DIR" "status-test" "$wt_dir" "workspace:4" "surface:4"

  run fleet status status-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"Branch:"* ]]
  [[ "$output" == *"status-test"* ]]
  [[ "$output" == *"Workspace:"* ]]
  [[ "$output" == *"workspace:4"* ]]
}

@test "fleet status with no workspace state fails" {
  mock_cmux
  run fleet status no-state-branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"No workspace found"* ]]
}

@test "fleet status auto-detects from worktree" {
  mock_cmux
  create_test_worktree "auto-status"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "auto-status")"
  _fleet_save_state "$REPO_DIR" "auto-status" "$wt_dir" "workspace:6" "surface:6"

  cd "$wt_dir"
  run fleet status
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-status"* ]]
}
