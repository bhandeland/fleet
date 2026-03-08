#!/usr/bin/env bats
# Tests for fleet init

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
  mock_claude
}

teardown() {
  teardown_repo
}

@test "fleet init --help shows usage" {
  run fleet init --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet init"* ]]
}

@test "fleet init outside git repo fails" {
  cd /tmp
  run fleet init
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not in a git repo"* ]]
}

@test "fleet init fails when claude not installed" {
  # Temporarily hide claude
  claude() { return 127; }
  command() {
    if [[ "$1" == "-v" && "$2" == "claude" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  run fleet init
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude CLI not found"* ]]
  unset -f command
}

@test "fleet init refuses when setup already exists" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '#!/bin/bash\necho setup\n' > "$REPO_DIR/.fleet/setup"
  run fleet init
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "fleet init --replace allowed when setup exists" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '#!/bin/bash\necho setup\n' > "$REPO_DIR/.fleet/setup"
  # This will try to run claude which will fail, but the --replace check passes
  run fleet init --replace
  # It shouldn't fail with "already exists"
  [[ "$output" != *"already exists"* ]]
}

@test "fleet init adds .worktrees/ to .gitignore" {
  # fleet init will add .worktrees/ before trying to run claude
  run fleet init
  # Check .gitignore was created with .worktrees/
  grep -qxF '.worktrees/' "$REPO_DIR/.gitignore"
}

@test "fleet init does not duplicate .worktrees/ in .gitignore" {
  printf '.worktrees/\n' > "$REPO_DIR/.gitignore"
  run fleet init
  local count
  count="$(grep -cxF '.worktrees/' "$REPO_DIR/.gitignore")"
  [ "$count" -eq 1 ]
}
