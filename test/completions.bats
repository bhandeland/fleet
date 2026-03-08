#!/usr/bin/env bats
# Tests for _fleet_worktree_names (used by completions)

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "_fleet_worktree_names returns empty with no worktrees" {
  run _fleet_worktree_names
  [ "$output" = "" ]
}

@test "_fleet_worktree_names lists branch names" {
  create_test_worktree "comp-a"
  create_test_worktree "comp-b"
  run _fleet_worktree_names
  [[ "$output" == *"comp-a"* ]]
  [[ "$output" == *"comp-b"* ]]
}

@test "_fleet_worktree_names does not include main branch" {
  create_test_worktree "only-worktree"
  run _fleet_worktree_names
  [[ "$output" != *"main"* ]]
}

@test "_fleet_worktree_names returns silently outside repo" {
  cd /tmp
  run _fleet_worktree_names
  # May return non-zero since _fleet_repo_root fails, but should not crash
  [ -z "$output" ]
}
