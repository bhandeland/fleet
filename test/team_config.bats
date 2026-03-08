#!/usr/bin/env bats
# Tests for custom team roles via .fleet/team.json

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

# ── _fleet_load_team_roles ──────────────────────────────────────

@test "_fleet_load_team_roles returns defaults when no config" {
  run _fleet_load_team_roles "$REPO_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"explorer|code-explorer|right"* ]]
  [[ "$output" == *"architect|code-architect|down"* ]]
  [[ "$output" == *"reviewer|code-reviewer|down"* ]]
}

@test "_fleet_load_team_roles reads project config" {
  mkdir -p "$REPO_DIR/.fleet"
  cat > "$REPO_DIR/.fleet/team.json" <<'EOF'
{
  "roles": [
    { "name": "coder", "agent": "code-writer", "split": "right" },
    { "name": "tester", "agent": "test-runner", "split": "down" }
  ]
}
EOF

  run _fleet_load_team_roles "$REPO_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"coder|code-writer|right"* ]]
  [[ "$output" == *"tester|test-runner|down"* ]]
  # Should NOT include defaults
  [[ "$output" != *"explorer"* ]]
}

@test "_fleet_load_team_roles reads global config" {
  mkdir -p "$HOME/.fleet"
  cat > "$HOME/.fleet/team.json" <<'EOF'
{
  "roles": [
    { "name": "analyst", "agent": "data-analyst", "split": "right" }
  ]
}
EOF

  run _fleet_load_team_roles "$REPO_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"analyst|data-analyst|right"* ]]
}

@test "_fleet_load_team_roles prefers project over global" {
  mkdir -p "$REPO_DIR/.fleet"
  cat > "$REPO_DIR/.fleet/team.json" <<'EOF'
{
  "roles": [
    { "name": "project-role", "agent": "project-agent", "split": "right" }
  ]
}
EOF
  cat > "$HOME/.fleet/team.json" <<'EOF'
{
  "roles": [
    { "name": "global-role", "agent": "global-agent", "split": "right" }
  ]
}
EOF

  run _fleet_load_team_roles "$REPO_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"project-role"* ]]
  [[ "$output" != *"global-role"* ]]
}

# ── fleet team with custom roles ────────────────────────────────

@test "fleet team with custom roles spawns configured agents" {
  mock_cmux
  create_test_worktree "custom-team"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "custom-team")"
  _fleet_save_state "$REPO_DIR" "custom-team" "$wt_dir" "workspace:1" "surface:1"

  mkdir -p "$REPO_DIR/.fleet"
  cat > "$REPO_DIR/.fleet/team.json" <<'EOF'
{
  "roles": [
    { "name": "coder", "agent": "code-writer", "split": "right" },
    { "name": "tester", "agent": "test-runner", "split": "down" }
  ]
}
EOF

  run fleet team custom-team
  [ "$status" -eq 0 ]
  [[ "$output" == *"coder"* ]]
  [[ "$output" == *"tester"* ]]
  [[ "$output" != *"explorer"* ]]
}

# ── fleet team --add / --rm ─────────────────────────────────────

@test "fleet team --add adds a single agent" {
  mock_cmux
  create_test_worktree "add-agent"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "add-agent")"
  _fleet_save_state "$REPO_DIR" "add-agent" "$wt_dir" "workspace:1" "surface:1"

  run fleet team add-agent --add explorer
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added agent: explorer"* ]]

  # Verify surface saved to state
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "add-agent")"
  run _fleet_read_state_field "$sf" "team_explorer_surface"
  [ -n "$output" ]
}

@test "fleet team --add with unknown role fails" {
  mock_cmux
  create_test_worktree "bad-add"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "bad-add")"
  _fleet_save_state "$REPO_DIR" "bad-add" "$wt_dir" "workspace:1" "surface:1"

  run fleet team bad-add --add nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "fleet team --rm removes an agent" {
  mock_cmux
  create_test_worktree "rm-agent"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "rm-agent")"
  _fleet_save_state "$REPO_DIR" "rm-agent" "$wt_dir" "workspace:1" "surface:1"
  local sf
  sf="$(_fleet_state_file "$REPO_DIR" "rm-agent")"
  _fleet_save_team_surfaces "$sf" "explorer" "surface:10"

  run fleet team rm-agent --rm explorer
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed agent: explorer"* ]]
}

@test "fleet team --rm with unknown role fails" {
  mock_cmux
  create_test_worktree "rm-bad"
  local wt_dir
  wt_dir="$(_fleet_worktree_dir "$REPO_DIR" "rm-bad")"
  _fleet_save_state "$REPO_DIR" "rm-bad" "$wt_dir" "workspace:1" "surface:1"

  run fleet team rm-bad --rm nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"No agent found"* ]]
}
