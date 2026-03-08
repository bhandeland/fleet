#!/usr/bin/env bats
# Tests for fleet rm

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet rm --help shows usage" {
  run fleet rm --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet rm"* ]]
}

@test "fleet rm removes worktree and branch" {
  create_test_worktree "rm-test"
  [ -d "$REPO_DIR/.worktrees/rm-test" ]

  cd "$REPO_DIR"
  fleet rm rm-test
  [ ! -d "$REPO_DIR/.worktrees/rm-test" ]

  run git -C "$REPO_DIR" branch --list rm-test
  [ "$output" = "" ]
}

@test "fleet rm with missing worktree fails" {
  run fleet rm nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"Worktree not found"* ]]
}

@test "fleet rm with uncommitted changes fails without -f" {
  create_test_worktree "dirty-rm"
  touch "$REPO_DIR/.worktrees/dirty-rm/uncommitted.txt"

  cd "$REPO_DIR"
  run fleet rm dirty-rm
  [ "$status" -eq 1 ]
  [[ "$output" == *"fleet rm -f"* ]]
}

@test "fleet rm -f removes worktree with uncommitted changes" {
  create_test_worktree "force-rm"
  touch "$REPO_DIR/.worktrees/force-rm/uncommitted.txt"

  cd "$REPO_DIR"
  fleet rm force-rm -f
  [ ! -d "$REPO_DIR/.worktrees/force-rm" ]
}

@test "fleet rm --force is same as -f" {
  create_test_worktree "force-long"
  touch "$REPO_DIR/.worktrees/force-long/uncommitted.txt"

  cd "$REPO_DIR"
  fleet rm force-long --force
  [ ! -d "$REPO_DIR/.worktrees/force-long" ]
}

@test "fleet rm auto-detects branch from worktree" {
  create_test_worktree "auto-rm"
  cd "$REPO_DIR/.worktrees/auto-rm"
  run fleet rm
  [ "$status" -eq 0 ]
  [ ! -d "$REPO_DIR/.worktrees/auto-rm" ]
}

@test "fleet rm with no args outside worktree fails" {
  cd "$REPO_DIR"
  run fleet rm
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet rm runs teardown hook" {
  create_test_worktree "teardown-test"
  mkdir -p "$REPO_DIR/.worktrees/teardown-test/.fleet"
  printf '#!/bin/bash\ntouch "%s/.teardown-ran"\n' "$TEST_DIR" > "$REPO_DIR/.worktrees/teardown-test/.fleet/teardown"
  chmod +x "$REPO_DIR/.worktrees/teardown-test/.fleet/teardown"

  cd "$REPO_DIR"
  fleet rm teardown-test -f
  [ -f "$TEST_DIR/.teardown-ran" ]
}

# ── fleet rm with cmux ───────────────────────────────────────────

@test "fleet rm with cmux closes workspace and removes state" {
  mock_cmux
  create_test_worktree "cmux-rm"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "cmux-rm")"
  _fleet_save_state "$REPO_DIR" "cmux-rm" "$wt_dir" "workspace:7" "surface:7"

  cd "$REPO_DIR"
  fleet rm cmux-rm

  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "cmux-rm")"
  [ ! -f "$sf" ]
}

# ── fleet rm --all ───────────────────────────────────────────────

@test "fleet rm cleans state without cmux" {
  create_test_worktree "state-rm"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "state-rm")"
  _fleet_save_state "$REPO_DIR" "state-rm" "$wt_dir" "workspace:99" "surface:99"

  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "state-rm")"
  [ -f "$sf" ]

  cd "$REPO_DIR"
  fleet rm state-rm
  [ ! -f "$sf" ]
  [ ! -d "$wt_dir" ]
}

# ── fleet rm --all ───────────────────────────────────────────────

@test "fleet rm --all with no worktrees succeeds" {
  run fleet rm --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"No"*"worktrees"* ]]
}
