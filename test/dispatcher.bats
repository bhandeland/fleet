#!/usr/bin/env bats
# Tests for the main fleet() dispatcher

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

@test "fleet with no args shows help" {
  run fleet
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet"* ]]
}

@test "fleet --help shows help" {
  run fleet --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet"* ]]
}

@test "fleet -h shows help" {
  run fleet -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: fleet"* ]]
}

@test "fleet version shows version" {
  run fleet version
  [ "$status" -eq 0 ]
  [[ "$output" == *"fleet"* ]]
}

@test "fleet unknown command fails" {
  run fleet bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command: bogus"* ]]
}

@test "fleet routes to all known subcommands" {
  # Test that each subcommand is recognized (not "Unknown command")
  for cmd in new start cd ls merge rm init config focus team status update version; do
    run fleet "$cmd" --help
    [[ "$output" != *"Unknown command"* ]]
  done
}
