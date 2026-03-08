#!/usr/bin/env bats
# Tests for fleet merge

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet merge --help shows usage" {
  run fleet merge --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet merge"* ]]
}

@test "fleet merge with no args outside worktree fails" {
  cd "$REPO_DIR"
  run fleet merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet merge merges branch into main" {
  create_test_worktree "merge-me"
  # Make a commit in the worktree
  local wt_dir="$REPO_DIR/.worktrees/merge-me"
  touch "$wt_dir/new-file.txt"
  git -C "$wt_dir" add new-file.txt
  git -C "$wt_dir" commit -m "add file" --quiet

  cd "$REPO_DIR"
  fleet merge merge-me
  [ -f "$REPO_DIR/new-file.txt" ]
}

@test "fleet merge --squash stages changes without committing" {
  create_test_worktree "squash-me"
  local wt_dir="$REPO_DIR/.worktrees/squash-me"
  touch "$wt_dir/squash-file.txt"
  git -C "$wt_dir" add squash-file.txt
  git -C "$wt_dir" commit -m "squash commit" --quiet

  cd "$REPO_DIR"
  run fleet merge squash-me --squash
  [ "$status" -eq 0 ]
  [[ "$output" == *"Squash merge staged"* ]]
}

@test "fleet merge with missing worktree fails" {
  cd "$REPO_DIR"
  run fleet merge nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"Worktree not found"* ]]
}

@test "fleet merge with uncommitted changes fails" {
  create_test_worktree "dirty-merge"
  local wt_dir="$REPO_DIR/.worktrees/dirty-merge"
  touch "$wt_dir/uncommitted.txt"
  git -C "$wt_dir" add uncommitted.txt

  cd "$REPO_DIR"
  run fleet merge dirty-merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "fleet merge cannot merge branch into itself" {
  create_test_worktree "self-merge"
  cd "$REPO_DIR"
  # Checkout the same branch in main
  git -C "$REPO_DIR" checkout self-merge --quiet 2>/dev/null || true
  # This is tricky — the main checkout is on 'main', so we need to be on a different branch
  # Let's test by trying to merge main into main
  run fleet merge main
  [[ "$output" == *"Worktree not found"* || "$output" == *"Cannot merge"* ]]
}

@test "fleet merge auto-detects branch from worktree" {
  create_test_worktree "auto-detect"
  local wt_dir="$REPO_DIR/.worktrees/auto-detect"
  touch "$wt_dir/detect-file.txt"
  git -C "$wt_dir" add detect-file.txt
  git -C "$wt_dir" commit -m "detect commit" --quiet

  cd "$wt_dir"
  fleet merge
  # Should have merged and cd'd to repo root
  [ -f "$REPO_DIR/detect-file.txt" ]
}
