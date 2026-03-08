#!/usr/bin/env bats
# Tests for fleet merge (push + PR/MR creation)

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

# Mock gh and glab as unavailable by default
mock_no_forge() {
  gh() { return 127; }
  glab() { return 127; }
  export -f gh glab
}

# Mock gh as available
mock_gh() {
  gh() {
    echo "gh called: $*"
    echo "https://github.com/test/repo/pull/1"
    return 0
  }
  export -f gh
}

# Mock glab as available
mock_glab() {
  glab() {
    echo "glab called: $*"
    echo "https://gitlab.com/test/repo/-/merge_requests/1"
    return 0
  }
  export -f glab
}

@test "fleet merge --help shows usage" {
  run fleet merge --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet merge"* ]]
  [[ "$output" == *"--title"* ]]
}

@test "fleet merge with no args outside worktree fails" {
  cd "$REPO_DIR"
  run fleet merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
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

@test "fleet merge pushes branch" {
  # Set up a bare remote to push to
  local remote_dir="$TEST_DIR/remote.git"
  git init --bare "$remote_dir" --quiet
  git -C "$REPO_DIR" remote add origin "$remote_dir"
  git -C "$REPO_DIR" push -u origin main --quiet

  create_test_worktree "push-test"
  local wt_dir="$REPO_DIR/.worktrees/push-test"
  touch "$wt_dir/new-file.txt"
  git -C "$wt_dir" add new-file.txt
  git -C "$wt_dir" commit -m "add file" --quiet

  cd "$REPO_DIR"
  # No forge tools available — should push but report no CLI
  run fleet merge push-test
  [[ "$output" == *"Pushing"* ]]
  [[ "$output" == *"No CLI tool found"* ]]

  # Verify branch was pushed
  run git -C "$remote_dir" branch --list push-test
  [[ "$output" == *"push-test"* ]]
}

@test "fleet merge uses gh when available" {
  local remote_dir="$TEST_DIR/remote.git"
  git init --bare "$remote_dir" --quiet
  git -C "$REPO_DIR" remote add origin "$remote_dir"
  git -C "$REPO_DIR" push -u origin main --quiet

  create_test_worktree "gh-test"
  local wt_dir="$REPO_DIR/.worktrees/gh-test"
  touch "$wt_dir/new-file.txt"
  git -C "$wt_dir" add new-file.txt
  git -C "$wt_dir" commit -m "add file" --quiet

  mock_gh
  cd "$REPO_DIR"
  run fleet merge gh-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"Creating pull request"* ]]
  [[ "$output" == *"gh called"* ]]
}

@test "fleet merge uses glab when gh not available" {
  local remote_dir="$TEST_DIR/remote.git"
  git init --bare "$remote_dir" --quiet
  git -C "$REPO_DIR" remote add origin "$remote_dir"
  git -C "$REPO_DIR" push -u origin main --quiet

  create_test_worktree "glab-test"
  local wt_dir="$REPO_DIR/.worktrees/glab-test"
  touch "$wt_dir/new-file.txt"
  git -C "$wt_dir" add new-file.txt
  git -C "$wt_dir" commit -m "add file" --quiet

  # Make sure gh is not available, but glab is
  unset -f gh 2>/dev/null
  # Hide system gh from PATH
  local saved_path="$PATH"
  PATH="$(echo "$PATH" | tr ':' '\n' | grep -v "$(dirname "$(command -v gh 2>/dev/null)")" | tr '\n' ':')"
  mock_glab
  cd "$REPO_DIR"
  run fleet merge glab-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"Creating merge request"* ]]
  [[ "$output" == *"glab called"* ]]
}

@test "fleet merge uses stored base_branch as target" {
  local remote_dir="$TEST_DIR/remote.git"
  git init --bare "$remote_dir" --quiet
  git -C "$REPO_DIR" remote add origin "$remote_dir"
  git -C "$REPO_DIR" push -u origin main --quiet

  create_test_worktree "base-test"
  local wt_dir="$REPO_DIR/.worktrees/base-test"
  _fleet_save_state "$REPO_DIR" "base-test" "$wt_dir" "" "" "development"
  touch "$wt_dir/new-file.txt"
  git -C "$wt_dir" add new-file.txt
  git -C "$wt_dir" commit -m "add file" --quiet

  mock_gh
  cd "$REPO_DIR"
  run fleet merge base-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"development"* ]]
}

@test "fleet merge --title sets PR title" {
  local remote_dir="$TEST_DIR/remote.git"
  git init --bare "$remote_dir" --quiet
  git -C "$REPO_DIR" remote add origin "$remote_dir"
  git -C "$REPO_DIR" push -u origin main --quiet

  create_test_worktree "title-test"
  local wt_dir="$REPO_DIR/.worktrees/title-test"
  touch "$wt_dir/new-file.txt"
  git -C "$wt_dir" add new-file.txt
  git -C "$wt_dir" commit -m "add file" --quiet

  mock_gh
  cd "$REPO_DIR"
  run fleet merge title-test --title "My custom PR title"
  [ "$status" -eq 0 ]
  [[ "$output" == *"My custom PR title"* ]]
}

@test "fleet merge auto-detects branch from worktree" {
  local remote_dir="$TEST_DIR/remote.git"
  git init --bare "$remote_dir" --quiet
  git -C "$REPO_DIR" remote add origin "$remote_dir"
  git -C "$REPO_DIR" push -u origin main --quiet

  create_test_worktree "auto-detect"
  local wt_dir="$REPO_DIR/.worktrees/auto-detect"
  touch "$wt_dir/detect-file.txt"
  git -C "$wt_dir" add detect-file.txt
  git -C "$wt_dir" commit -m "detect commit" --quiet

  cd "$wt_dir"
  run fleet merge
  [[ "$output" == *"Pushing"* ]]
  [[ "$output" == *"auto-detect"* ]]
}
