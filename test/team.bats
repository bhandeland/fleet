#!/usr/bin/env bats
# Tests for fleet team

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet team --help shows usage" {
  run fleet team --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet team"* ]]
}

@test "fleet team with no args fails" {
  run fleet team
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet team without cmux fails" {
  run fleet team some-branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"require cmux.dev"* ]]
}

@test "fleet team with cmux but no state fails" {
  mock_cmux
  run fleet team nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"No workspace found"* ]]
}

@test "fleet team with cmux and state creates agents" {
  mock_cmux
  create_test_worktree "team-test"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "team-test")"
  _fleet_save_state "$REPO_DIR" "team-test" "$wt_dir" "workspace:2" "surface:2"

  run fleet team team-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"explorer"* ]]
  [[ "$output" == *"architect"* ]]
  [[ "$output" == *"reviewer"* ]]
}

@test "fleet team saves surface refs to state" {
  mock_cmux
  create_test_worktree "team-state"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "team-state")"
  _fleet_save_state "$REPO_DIR" "team-state" "$wt_dir" "workspace:2" "surface:2"

  fleet team team-state

  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "team-state")"
  run _fleet_read_state_field "$sf" "explorer_surface"
  [ -n "$output" ]
  run _fleet_read_state_field "$sf" "architect_surface"
  [ -n "$output" ]
  run _fleet_read_state_field "$sf" "reviewer_surface"
  [ -n "$output" ]
}
