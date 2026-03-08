#!/usr/bin/env bats
# Tests for fleet focus

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet focus --help shows usage" {
  run fleet focus --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet focus"* ]]
}

@test "fleet focus with no args fails" {
  run fleet focus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet focus without cmux fails" {
  run fleet focus some-branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"cmux.dev is not available"* ]]
}

@test "fleet focus without cmux suggests fleet cd" {
  run fleet focus some-branch
  [[ "$output" == *"fleet cd"* ]]
}

@test "fleet focus with cmux but no state fails" {
  mock_cmux
  run fleet focus nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"No workspace found"* ]]
}

@test "fleet focus with cmux and state succeeds" {
  mock_cmux
  create_test_worktree "focus-me"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "focus-me")"
  _fleet_save_state "$REPO_DIR" "focus-me" "$wt_dir" "workspace:3" "surface:3"

  run fleet focus focus-me
  [ "$status" -eq 0 ]
}
