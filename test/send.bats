#!/usr/bin/env bats
# Tests for fleet send

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet send --help shows usage" {
  run fleet send --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet send"* ]]
}

@test "fleet send without cmux fails" {
  run fleet send some-branch "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires cmux.dev"* ]]
}

@test "fleet send with no args fails" {
  mock_cmux
  run fleet send
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet send with no message fails" {
  mock_cmux
  run fleet send some-branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet send to main pane succeeds" {
  mock_cmux
  create_test_worktree "send-test"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "send-test")"
  _fleet_save_state "$REPO_DIR" "send-test" "$wt_dir" "workspace:1" "surface:1"

  run fleet send send-test "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to send-test"* ]]
}

@test "fleet send --role to agent pane succeeds" {
  mock_cmux
  create_test_worktree "send-role"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "send-role")"
  _fleet_save_state "$REPO_DIR" "send-role" "$wt_dir" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "send-role")"
  _fleet_save_team_surfaces "$sf" "explorer" "surface:10"

  run fleet send send-role --role explorer "check the code"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to explorer"* ]]
}

@test "fleet send --role with unknown role fails" {
  mock_cmux
  create_test_worktree "send-bad-role"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "send-bad-role")"
  _fleet_save_state "$REPO_DIR" "send-bad-role" "$wt_dir" "workspace:1" "surface:1"

  run fleet send send-bad-role --role nonexistent "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No agent surface found"* ]]
}

@test "fleet send to unknown branch fails" {
  mock_cmux
  run fleet send nonexistent "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No workspace found"* ]]
}
