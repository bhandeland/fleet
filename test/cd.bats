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

@test "fleet cd prints only the path when an update is available" {
  # The init-shell wrapper does `dir="$(command fleet cd ...)" && cd "$dir"`,
  # so anything else on stdout is what the user's shell tries to cd into.
  printf '99.99.99' > "$HOME/.fleet/.latest_version"
  create_test_worktree "cd-target"
  local dir
  dir="$(fleet cd cd-target 2>/dev/null)"
  [[ "$dir" != *"update available"* ]]
  [ -d "$dir" ]
}
