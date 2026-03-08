#!/usr/bin/env bats
# Tests for state management functions

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

# ── _fleet_repo_hash ─────────────────────────────────────────────

@test "_fleet_repo_hash produces consistent hash" {
  local h1 h2
  h1="$(_fleet_repo_hash "/some/path")"
  h2="$(_fleet_repo_hash "/some/path")"
  [ "$h1" = "$h2" ]
}

@test "_fleet_repo_hash produces different hashes for different paths" {
  local h1 h2
  h1="$(_fleet_repo_hash "/path/one")"
  h2="$(_fleet_repo_hash "/path/two")"
  [ "$h1" != "$h2" ]
}

@test "_fleet_repo_hash is non-empty" {
  local h
  h="$(_fleet_repo_hash "/some/path")"
  [ -n "$h" ]
}

# ── _fleet_state_dir ─────────────────────────────────────────────

@test "_fleet_state_dir returns path under ~/.fleet/state/" {
  run _fleet_state_dir "$REPO_DIR"
  [[ "$output" == "$HOME/.fleet/state/"* ]]
}

@test "_fleet_state_dir is consistent for same repo" {
  local d1 d2
  d1="$(_fleet_state_dir "$REPO_DIR")"
  d2="$(_fleet_state_dir "$REPO_DIR")"
  [ "$d1" = "$d2" ]
}

# ── _fleet_state_file ────────────────────────────────────────────

@test "_fleet_state_file returns .json file" {
  run _fleet_state_file "$REPO_DIR" "my-branch"
  [[ "$output" == *.json ]]
}

@test "_fleet_state_file sanitizes branch name" {
  run _fleet_state_file "$REPO_DIR" "feature/auth"
  [[ "$output" == *"feature-auth.json" ]]
}

# ── _fleet_save_state / _fleet_read_state_field ──────────────────

@test "_fleet_save_state creates state file" {
  _fleet_save_state "$REPO_DIR" "test-br" "/path/to/wt" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "test-br")"
  [ -f "$sf" ]
}

@test "_fleet_read_state_field reads branch" {
  _fleet_save_state "$REPO_DIR" "test-br" "/path/to/wt" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "test-br")"
  run _fleet_read_state_field "$sf" "branch"
  [ "$output" = "test-br" ]
}

@test "_fleet_read_state_field reads worktree_dir" {
  _fleet_save_state "$REPO_DIR" "test-br" "/path/to/wt" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "test-br")"
  run _fleet_read_state_field "$sf" "worktree_dir"
  [ "$output" = "/path/to/wt" ]
}

@test "_fleet_read_state_field reads workspace_id" {
  _fleet_save_state "$REPO_DIR" "test-br" "/path/to/wt" "workspace:5" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "test-br")"
  run _fleet_read_state_field "$sf" "workspace_id"
  [ "$output" = "workspace:5" ]
}

@test "_fleet_read_state_field reads main_surface" {
  _fleet_save_state "$REPO_DIR" "test-br" "/path/to/wt" "workspace:1" "surface:9"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "test-br")"
  run _fleet_read_state_field "$sf" "main_surface"
  [ "$output" = "surface:9" ]
}

@test "_fleet_read_state_field returns failure for missing file" {
  run _fleet_read_state_field "/nonexistent/file.json" "branch"
  [ "$status" -ne 0 ]
}

@test "_fleet_read_state_field returns empty for missing field" {
  _fleet_save_state "$REPO_DIR" "test-br" "/path/to/wt" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "test-br")"
  run _fleet_read_state_field "$sf" "nonexistent_field"
  [ "$output" = "" ]
}

# ── _fleet_rm_state ──────────────────────────────────────────────

@test "_fleet_rm_state removes state file" {
  _fleet_save_state "$REPO_DIR" "rm-me" "/path/to/wt" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "rm-me")"
  [ -f "$sf" ]
  _fleet_rm_state "$REPO_DIR" "rm-me"
  [ ! -f "$sf" ]
}

@test "_fleet_rm_state is safe on missing file" {
  run _fleet_rm_state "$REPO_DIR" "never-existed"
  [ "$status" -eq 0 ]
}

# ── _fleet_save_team_surfaces ────────────────────────────────────

@test "_fleet_save_team_surfaces adds surface refs" {
  _fleet_save_state "$REPO_DIR" "team-br" "/path/to/wt" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "team-br")"
  _fleet_save_team_surfaces "$sf" "surface:10" "surface:11" "surface:12"

  run _fleet_read_state_field "$sf" "explorer_surface"
  [ "$output" = "surface:10" ]
  run _fleet_read_state_field "$sf" "architect_surface"
  [ "$output" = "surface:11" ]
  run _fleet_read_state_field "$sf" "reviewer_surface"
  [ "$output" = "surface:12" ]
}

@test "_fleet_save_team_surfaces preserves existing fields" {
  _fleet_save_state "$REPO_DIR" "team-br" "/path/to/wt" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "team-br")"
  _fleet_save_team_surfaces "$sf" "surface:10" "surface:11" "surface:12"

  run _fleet_read_state_field "$sf" "branch"
  [ "$output" = "team-br" ]
  run _fleet_read_state_field "$sf" "workspace_id"
  [ "$output" = "workspace:1" ]
}

@test "_fleet_save_team_surfaces fails on missing file" {
  run _fleet_save_team_surfaces "/nonexistent/file.json" "s:1" "s:2" "s:3"
  [ "$status" -ne 0 ]
}
