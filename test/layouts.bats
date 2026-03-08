#!/usr/bin/env bats
# Tests for different layout modes across commands

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

# ── outer-nested layout ──────────────────────────────────────────

@test "fleet new with outer-nested layout creates worktree outside repo" {
  fleet config set layout outer-nested
  fleet new outer-test
  [ -d "$(dirname "$REPO_DIR")/repo.worktrees/outer-test" ]
}

@test "fleet cd with outer-nested layout" {
  fleet config set layout outer-nested
  fleet new cd-outer
  fleet cd cd-outer
  [ "$PWD" = "$(dirname "$REPO_DIR")/repo.worktrees/cd-outer" ]
}

@test "fleet ls with outer-nested layout" {
  fleet config set layout outer-nested
  fleet new ls-outer
  run fleet ls
  [[ "$output" == *"ls-outer"* ]]
}

@test "fleet rm with outer-nested layout" {
  fleet config set layout outer-nested
  fleet new rm-outer
  cd "$REPO_DIR"
  fleet rm rm-outer
  [ ! -d "$(dirname "$REPO_DIR")/repo.worktrees/rm-outer" ]
}

# ── sibling layout ───────────────────────────────────────────────

@test "fleet new with sibling layout creates sibling directory" {
  fleet config set layout sibling
  fleet new sib-test
  [ -d "$(dirname "$REPO_DIR")/repo-sib-test" ]
}

@test "fleet cd with sibling layout" {
  fleet config set layout sibling
  fleet new cd-sib
  fleet cd cd-sib
  [ "$PWD" = "$(dirname "$REPO_DIR")/repo-cd-sib" ]
}

@test "fleet ls with sibling layout" {
  fleet config set layout sibling
  fleet new ls-sib
  run fleet ls
  [[ "$output" == *"ls-sib"* ]]
}

@test "fleet rm with sibling layout" {
  fleet config set layout sibling
  fleet new rm-sib
  cd "$REPO_DIR"
  fleet rm rm-sib
  [ ! -d "$(dirname "$REPO_DIR")/repo-rm-sib" ]
}

# ── detect worktree branch across layouts ────────────────────────

@test "detect worktree branch in outer-nested layout" {
  fleet config set layout outer-nested
  create_test_worktree "detect-outer"
  cd "$(dirname "$REPO_DIR")/repo.worktrees/detect-outer"
  run _fleet_detect_worktree_branch "$REPO_DIR"
  [ "$output" = "detect-outer" ]
}

@test "detect worktree branch in sibling layout" {
  fleet config set layout sibling
  create_test_worktree "detect-sib"
  cd "$(dirname "$REPO_DIR")/repo-detect-sib"
  run _fleet_detect_worktree_branch "$REPO_DIR"
  [ "$output" = "detect-sib" ]
}
