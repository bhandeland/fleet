#!/usr/bin/env bats
# Tests for fleet update

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet update --help shows usage" {
  run fleet update --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet update"* ]]
}

# Note: actual update tests are skipped since they require network access.
# We test the _fleet_check_update helper behavior instead.

@test "_fleet_check_update skips when recently checked" {
  printf '%s' "$(date +%s)" > "$HOME/.fleet/.last_check"
  # Should return quickly without errors
  run _fleet_check_update
  [ "$status" -eq 0 ]
}

@test "_fleet_check_update shows update notice when new version cached" {
  printf '99.99.99' > "$HOME/.fleet/.latest_version"
  run _fleet_check_update
  [[ "$output" == *"update available"* ]]
}

@test "_fleet_check_update shows nothing when version matches" {
  printf '%s' "$FLEET_VERSION" > "$HOME/.fleet/.latest_version"
  run _fleet_check_update
  [ "$output" = "" ]
}
