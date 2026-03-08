#!/usr/bin/env bats
# Tests for fleet new

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

@test "fleet new --help shows usage" {
  run fleet new --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet new"* ]]
}

@test "fleet new with no branch fails" {
  run fleet new
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet new creates worktree and branch" {
  fleet new test-branch < /dev/null
  local wt_dir="$REPO_DIR/.worktrees/test-branch"
  [ -d "$wt_dir" ]
  run git -C "$REPO_DIR" branch --list test-branch
  [[ "$output" == *"test-branch"* ]]
}

@test "fleet new creates .worktrees directory" {
  fleet new test-branch < /dev/null
  [ -d "$REPO_DIR/.worktrees" ]
}

@test "fleet new with existing worktree is idempotent" {
  fleet new test-branch < /dev/null
  run fleet new test-branch < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "fleet new with -p passes prompt" {
  fleet new prompt-test -p "do stuff" < /dev/null
  [ -d "$REPO_DIR/.worktrees/prompt-test" ]
}

@test "fleet new with multi-word branch joins with hyphens" {
  fleet new my cool feature < /dev/null
  [ -d "$REPO_DIR/.worktrees/my-cool-feature" ]
}

@test "fleet new runs setup hook if present" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '#!/bin/bash\ntouch "$PWD/.setup-ran"\n' > "$REPO_DIR/.fleet/setup"
  chmod +x "$REPO_DIR/.fleet/setup"
  git -C "$REPO_DIR" add .fleet/setup
  git -C "$REPO_DIR" commit -m "add setup" --quiet

  fleet new hook-test < /dev/null
  [ -f "$REPO_DIR/.worktrees/hook-test/.setup-ran" ]
}

@test "fleet new shows message when no setup hook exists" {
  run fleet new no-hook-test < /dev/null
  [[ "$output" == *".fleet/setup"* ]]
}

@test "fleet new outside git repo fails" {
  cd /tmp
  run fleet new test-branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not in a git repo"* ]]
}

# ── cmux.dev mode ────────────────────────────────────────────────

@test "fleet new with cmux creates workspace and saves state" {
  mock_cmux
  fleet new cmux-test < /dev/null
  [ -d "$REPO_DIR/.worktrees/cmux-test" ]

  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "cmux-test")"
  [ -f "$sf" ]
  run _fleet_read_state_field "$sf" "branch"
  [ "$output" = "cmux-test" ]
}

@test "fleet new with cmux and existing worktree focuses workspace" {
  mock_cmux
  fleet new focus-test < /dev/null
  # Second call should focus existing workspace, not error
  run fleet new focus-test
  [ "$status" -eq 0 ]
}

@test "fleet new --team without cmux still creates worktree" {
  mock_no_cmux
  fleet new team-no-cmux --team < /dev/null
  [ -d "$REPO_DIR/.worktrees/team-no-cmux" ]
}
