#!/usr/bin/env bats
# Tests for fleet register

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet register --help shows usage" {
  run fleet register --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet register"* ]]
}

@test "fleet register from main checkout fails" {
  cd "$REPO_DIR"
  run fleet register
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not in a worktree"* ]]
}

@test "fleet register from worktree succeeds" {
  create_test_worktree "register-test"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "register-test")"
  cd "$wt_dir"
  run fleet register
  [ "$status" -eq 0 ]
  [[ "$output" == *"Registered worktree"* ]]
  [[ "$output" == *"register-test"* ]]
}

@test "fleet register creates state file" {
  create_test_worktree "reg-state"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "reg-state")"
  cd "$wt_dir"
  fleet register

  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "reg-state")"
  [ -f "$sf" ]
  run _fleet_read_state_field "$sf" "branch"
  [ "$output" = "reg-state" ]
  run _fleet_read_state_field "$sf" "worktree_dir"
  [ "$output" = "$wt_dir" ]
}

@test "fleet register refuses duplicate registration" {
  create_test_worktree "dup-reg"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "dup-reg")"
  _fleet_save_state "$REPO_DIR" "dup-reg" "$wt_dir" "" ""
  cd "$wt_dir"
  run fleet register
  [ "$status" -eq 1 ]
  [[ "$output" == *"already registered"* ]]
}

@test "fleet register outside git repo fails" {
  cd /tmp
  run fleet register
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not in a git repo"* ]]
}
