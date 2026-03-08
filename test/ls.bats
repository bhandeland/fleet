#!/usr/bin/env bats
# Tests for fleet ls

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet ls --help shows usage" {
  run fleet ls --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet ls"* ]]
}

@test "fleet ls with no worktrees shows nothing" {
  run fleet ls
  # grep returns 1 when no matches, so status may be non-zero
  [ -z "$output" ]
}

@test "fleet ls lists created worktrees" {
  create_test_worktree "branch-a"
  create_test_worktree "branch-b"
  run fleet ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch-a"* ]]
  [[ "$output" == *"branch-b"* ]]
}

@test "fleet ls does not list main checkout" {
  create_test_worktree "only-this"
  run fleet ls
  # Output should contain the worktree but not the bare repo root
  local line_count
  line_count="$(echo "$output" | grep -c '\.worktrees/')"
  [ "$line_count" -eq 1 ]
}

@test "fleet ls outside git repo fails" {
  cd /tmp
  run fleet ls
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not in a git repo"* ]]
}

# ── --status flag ────────────────────────────────────────────────

@test "fleet ls --status without cmux shows plain list" {
  create_test_worktree "status-test"
  run fleet ls --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"status-test"* ]]
}

@test "fleet ls --status with cmux shows workspace info" {
  mock_cmux
  create_test_worktree "status-cmux"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "status-cmux")"
  _fleet_save_state "$REPO_DIR" "status-cmux" "$wt_dir" "workspace:3" "surface:3"

  run fleet ls --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"workspace:3"* ]]
}
