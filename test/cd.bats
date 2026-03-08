#!/usr/bin/env bats
# Tests for fleet cd

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet cd --help shows usage" {
  run fleet cd --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet cd"* ]]
}

@test "fleet cd with no args prints repo root" {
  create_test_worktree "some-branch"
  cd "$REPO_DIR/.worktrees/some-branch"
  run fleet cd
  [ "$status" -eq 0 ]
  [[ "$output" == "$(cd "$REPO_DIR" && pwd -P)" ]]
}

@test "fleet cd with branch prints worktree path" {
  create_test_worktree "cd-target"
  run fleet cd cd-target
  [ "$status" -eq 0 ]
  [[ "$output" == *"cd-target"* ]]
}

@test "fleet cd with missing worktree fails" {
  run fleet cd nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"Worktree not found"* ]]
}

@test "fleet cd outside git repo fails" {
  cd /tmp
  run fleet cd
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not in a git repo"* ]]
}
