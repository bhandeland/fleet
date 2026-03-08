#!/usr/bin/env bats
# Tests for fleet config

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet config shows default layout" {
  run fleet config
  [ "$status" -eq 0 ]
  [[ "$output" == *"layout=nested"* ]]
  [[ "$output" == *"default"* ]]
}

@test "fleet config shows per-project layout" {
  mkdir -p "$REPO_DIR/.fleet"
  printf '{\n  "layout": "sibling"\n}\n' > "$REPO_DIR/.fleet/config.json"
  run fleet config
  [ "$status" -eq 0 ]
  [[ "$output" == *"layout=sibling"* ]]
}

@test "fleet config shows global layout" {
  printf '{\n  "layout": "outer-nested"\n}\n' > "$HOME/.fleet/config.json"
  run fleet config
  [ "$status" -eq 0 ]
  [[ "$output" == *"layout=outer-nested"* ]]
}

@test "fleet config set layout nested" {
  fleet config set layout nested
  run fleet config
  [[ "$output" == *"layout=nested"* ]]
}

@test "fleet config set layout sibling" {
  fleet config set layout sibling
  run fleet config
  [[ "$output" == *"layout=sibling"* ]]
}

@test "fleet config set layout outer-nested" {
  fleet config set layout outer-nested
  run fleet config
  [[ "$output" == *"layout=outer-nested"* ]]
}

@test "fleet config set layout invalid fails" {
  run fleet config set layout bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid layout"* ]]
}

@test "fleet config set layout --global writes to global config" {
  fleet config set layout sibling --global
  [ -f "$HOME/.fleet/config.json" ]
  run grep '"layout"' "$HOME/.fleet/config.json"
  [[ "$output" == *"sibling"* ]]
}

@test "fleet config set layout per-project writes to repo" {
  fleet config set layout outer-nested
  [ -f "$REPO_DIR/.fleet/config.json" ]
  run grep '"layout"' "$REPO_DIR/.fleet/config.json"
  [[ "$output" == *"outer-nested"* ]]
}

@test "fleet config set layout updates existing config" {
  fleet config set layout sibling
  fleet config set layout nested
  run fleet config
  [[ "$output" == *"layout=nested"* ]]
}

@test "fleet config set without key fails" {
  run fleet config set
  [ "$status" -eq 1 ]
}

@test "fleet config bogus subcommand shows usage" {
  run fleet config bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fleet config set layout --global outside repo succeeds" {
  cd /tmp
  run bash -c 'source "'"$FLEET_SH"'" && export HOME="'"$HOME"'"; printf "%s" "$(date +%s)" > "$HOME/.fleet/.last_check"; fleet config set layout sibling --global'
  [ "$status" -eq 0 ]
}

@test "fleet config set layout without repo and without --global fails" {
  cd /tmp
  run bash -c 'source "'"$FLEET_SH"'" && export HOME="'"$HOME"'"; printf "%s" "$(date +%s)" > "$HOME/.fleet/.last_check"; fleet config set layout sibling'
  [ "$status" -eq 1 ]
  [[ "$output" == *"--global"* ]]
}
