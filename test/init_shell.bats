#!/usr/bin/env bats
# Tests for fleet init-shell

setup() {
  load test_helper
  setup_repo
  load_fleet
  mock_no_cmux
}

teardown() {
  teardown_repo
}

@test "fleet init-shell outputs fleet wrapper function" {
  run fleet init-shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"fleet()"* ]]
  [[ "$output" == *"command fleet"* ]]
}

@test "fleet init-shell wrapper handles cd subcommand" {
  run fleet init-shell
  [ "$status" -eq 0 ]
  [[ "$output" == *'"cd"'* ]]
  [[ "$output" == *'cd "$dir"'* ]]
}

@test "fleet init-shell includes bash completions in bash" {
  # _fleet_init_shell checks BASH_VERSION which is set in bats (bash-based)
  run fleet init-shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"_fleet_bash_complete"* ]]
  [[ "$output" == *"complete -F"* ]]
}

@test "fleet init-shell output is valid bash" {
  local init_output
  init_output="$(fleet init-shell)"
  # Eval it in a subshell — should not error
  run bash -c "$init_output"
  [ "$status" -eq 0 ]
}
