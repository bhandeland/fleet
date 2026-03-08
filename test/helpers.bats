#!/usr/bin/env bats
# Tests for helper functions

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

# ── _fleet_repo_root ─────────────────────────────────────────────

@test "_fleet_repo_root returns repo root from inside repo" {
  run _fleet_repo_root
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO_DIR" ]
}

@test "_fleet_repo_root returns repo root from subdirectory" {
  mkdir -p "$REPO_DIR/sub/deep"
  cd "$REPO_DIR/sub/deep"
  run _fleet_repo_root
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO_DIR" ]
}

@test "_fleet_repo_root returns repo root from worktree" {
  create_test_worktree "test-wt"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "test-wt")"
  cd "$wt_dir"
  run _fleet_repo_root
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO_DIR" ]
}

@test "_fleet_repo_root fails outside git repo" {
  cd /tmp
  run _fleet_repo_root
  [ "$status" -ne 0 ]
}

# ── _fleet_safe_name ─────────────────────────────────────────────

@test "_fleet_safe_name converts slashes to hyphens" {
  run _fleet_safe_name "feature/auth"
  [ "$output" = "feature-auth" ]
}

@test "_fleet_safe_name leaves simple names unchanged" {
  run _fleet_safe_name "my-branch"
  [ "$output" = "my-branch" ]
}

@test "_fleet_safe_name handles multiple slashes" {
  run _fleet_safe_name "a/b/c/d"
  [ "$output" = "a-b-c-d" ]
}

@test "_fleet_safe_name handles empty string" {
  run _fleet_safe_name ""
  [ "$output" = "" ]
}

# ── _fleet_default_branch ────────────────────────────────────────

@test "_fleet_default_branch detects main branch" {
  run _fleet_default_branch "$REPO_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "_fleet_default_branch detects master branch" {
  # Create a repo with master as default
  local master_dir="$TEST_DIR/master-repo"
  mkdir -p "$master_dir"
  git -C "$master_dir" init -b master --quiet
  git -C "$master_dir" commit --allow-empty -m "initial" --quiet

  run _fleet_default_branch "$master_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "master" ]
}

# ── _fleet_has_cmux ──────────────────────────────────────────────

@test "_fleet_has_cmux returns false when cmux not available" {
  mock_no_cmux
  run _fleet_has_cmux
  [ "$status" -ne 0 ]
}

@test "_fleet_has_cmux returns true when mocked available" {
  mock_cmux
  run _fleet_has_cmux
  [ "$status" -eq 0 ]
}

# ── _fleet_extract_ref ───────────────────────────────────────────

@test "_fleet_extract_ref extracts workspace ref" {
  run _fleet_extract_ref '{"workspace": "workspace:5", "surface": "surface:3"}' "workspace"
  [ "$output" = "workspace:5" ]
}

@test "_fleet_extract_ref extracts surface ref" {
  run _fleet_extract_ref '{"workspace": "workspace:5", "surface": "surface:3"}' "surface"
  [ "$output" = "surface:3" ]
}

@test "_fleet_extract_ref returns empty for missing ref" {
  run _fleet_extract_ref '{"other": "value"}' "workspace"
  [ "$output" = "" ]
}

# ── _fleet_get_layout ────────────────────────────────────────────

@test "_fleet_get_layout defaults to nested" {
  run _fleet_get_layout "$REPO_DIR"
  [ "$output" = "nested" ]
}

@test "_fleet_get_layout reads per-project config" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '{\n  "layout": "sibling"\n}\n' > "$REPO_DIR/.fleet/config.json"
  run _fleet_get_layout "$REPO_DIR"
  [ "$output" = "sibling" ]
}

@test "_fleet_get_layout reads global config" {
  mkdir -p "$HOME/.fleet"
  printf '{\n  "layout": "outer-nested"\n}\n' > "$HOME/.fleet/config.json"
  run _fleet_get_layout "$REPO_DIR"
  [ "$output" = "outer-nested" ]
}

@test "_fleet_get_layout prefers per-project over global" {
  mkdir -p "$REPO_DIR/.fleet" "$HOME/.fleet"
  printf '{\n  "layout": "sibling"\n}\n' > "$REPO_DIR/.fleet/config.json"
  printf '{\n  "layout": "outer-nested"\n}\n' > "$HOME/.fleet/config.json"
  run _fleet_get_layout "$REPO_DIR"
  [ "$output" = "sibling" ]
}

# ── _fleet_worktree_base ─────────────────────────────────────────

@test "_fleet_worktree_base nested layout" {
  run _fleet_worktree_base "$REPO_DIR"
  [ "$output" = "$REPO_DIR/.worktrees" ]
}

@test "_fleet_worktree_base outer-nested layout" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '{\n  "layout": "outer-nested"\n}\n' > "$REPO_DIR/.fleet/config.json"
  run _fleet_worktree_base "$REPO_DIR"
  [ "$output" = "$(dirname "$REPO_DIR")/repo.worktrees" ]
}

@test "_fleet_worktree_base sibling layout" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '{\n  "layout": "sibling"\n}\n' > "$REPO_DIR/.fleet/config.json"
  run _fleet_worktree_base "$REPO_DIR"
  [ "$output" = "$(dirname "$REPO_DIR")" ]
}

# ── _fleet_worktree_dir ──────────────────────────────────────────

@test "_fleet_worktree_dir nested layout" {
  run _fleet_worktree_dir "$REPO_DIR" "my-branch"
  [ "$output" = "$REPO_DIR/.worktrees/my-branch" ]
}

@test "_fleet_worktree_dir sanitizes branch name" {
  run _fleet_worktree_dir "$REPO_DIR" "feature/auth"
  [ "$output" = "$REPO_DIR/.worktrees/feature-auth" ]
}

@test "_fleet_worktree_dir outer-nested layout" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '{\n  "layout": "outer-nested"\n}\n' > "$REPO_DIR/.fleet/config.json"
  run _fleet_worktree_dir "$REPO_DIR" "my-branch"
  [ "$output" = "$(dirname "$REPO_DIR")/repo.worktrees/my-branch" ]
}

@test "_fleet_worktree_dir sibling layout" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '{\n  "layout": "sibling"\n}\n' > "$REPO_DIR/.fleet/config.json"
  run _fleet_worktree_dir "$REPO_DIR" "my-branch"
  [ "$output" = "$(dirname "$REPO_DIR")/repo-my-branch" ]
}

# ── _fleet_detect_worktree_branch ────────────────────────────────

@test "_fleet_detect_worktree_branch detects branch in nested worktree" {
  create_test_worktree "detect-me"
  cd "$REPO_DIR/.worktrees/detect-me"
  run _fleet_detect_worktree_branch "$REPO_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "detect-me" ]
}

@test "_fleet_detect_worktree_branch fails outside worktree" {
  cd "$REPO_DIR"
  run _fleet_detect_worktree_branch "$REPO_DIR"
  [ "$status" -ne 0 ]
}

@test "_fleet_detect_worktree_branch detects from subdirectory" {
  create_test_worktree "deep-detect"
  mkdir -p "$REPO_DIR/.worktrees/deep-detect/sub/dir"
  cd "$REPO_DIR/.worktrees/deep-detect/sub/dir"
  run _fleet_detect_worktree_branch "$REPO_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "deep-detect" ]
}

# ── _fleet_find_hook ─────────────────────────────────────────────

@test "_fleet_find_hook finds executable hook" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '#!/bin/bash\necho hi\n' > "$REPO_DIR/.fleet/setup"
  chmod +x "$REPO_DIR/.fleet/setup"
  run _fleet_find_hook "$REPO_DIR" "setup"
  [ "$output" = "$REPO_DIR/.fleet/setup" ]
}

@test "_fleet_find_hook returns empty for non-executable" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '#!/bin/bash\necho hi\n' > "$REPO_DIR/.fleet/setup"
  chmod -x "$REPO_DIR/.fleet/setup"
  run _fleet_find_hook "$REPO_DIR" "setup"
  [ "$output" = "" ]
}

@test "_fleet_find_hook returns empty when missing" {
  run _fleet_find_hook "$REPO_DIR" "setup"
  [ "$output" = "" ]
}
