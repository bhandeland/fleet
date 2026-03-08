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

@test "fleet status with no args outside worktree fails" {
  cd "$REPO_DIR"
  run fleet status
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet status with state shows info" {
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

@test "fleet status shows git info" {
  create_test_worktree "git-status"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "git-status")"
  _fleet_save_state "$REPO_DIR" "git-status" "$wt_dir" "" ""

  run fleet status git-status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Git:"* ]]
  [[ "$output" == *"commits ahead"* ]]
}

@test "fleet status --json outputs json" {
  create_test_worktree "json-status"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "json-status")"
  _fleet_save_state "$REPO_DIR" "json-status" "$wt_dir" "workspace:5" "surface:5"

  run fleet status json-status --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"branch": "json-status"'* ]]
  [[ "$output" == *'"workspace_id": "workspace:5"'* ]]
  [[ "$output" == *'"commits_ahead"'* ]]
}

@test "fleet status auto-detects from worktree" {
  create_test_worktree "auto-status"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "auto-status")"
  _fleet_save_state "$REPO_DIR" "auto-status" "$wt_dir" "workspace:6" "surface:6"

  cd "$wt_dir"
  run fleet status
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-status"* ]]
}

@test "fleet status with cmux shows agent liveness" {
  mock_cmux
  create_test_worktree "agent-status"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "agent-status")"
  _fleet_save_state "$REPO_DIR" "agent-status" "$wt_dir" "workspace:7" "surface:7"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "agent-status")"
  _fleet_save_team_surfaces "$sf" "explorer" "surface:10" "architect" "surface:11"

  run fleet status agent-status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agents:"* ]]
  [[ "$output" == *"explorer"* ]]
  [[ "$output" == *"architect"* ]]
}
