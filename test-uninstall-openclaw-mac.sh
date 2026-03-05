#!/usr/bin/env bash
set -euo pipefail

SCRIPT="./uninstall-openclaw-mac.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "expected output to contain: $needle"
  fi
}

test_help_output() {
  local output=""
  output="$("$SCRIPT" --help 2>&1)"
  assert_contains "$output" "Usage: ./uninstall-openclaw-mac.sh"
  assert_contains "$output" "--dry-run"
}

test_dry_run_output() {
  local output=""
  output="$("$SCRIPT" --dry-run 2>&1)"
  assert_contains "$output" "DRY RUN MODE"
  assert_contains "$output" "openclaw uninstall --all --yes --non-interactive"
  assert_contains "$output" "npm rm -g openclaw"
  assert_contains "$output" "rm -rf ${HOME}/.openclaw"
}

main() {
  test_help_output
  test_dry_run_output
  echo "PASS: uninstall-openclaw-mac tests"
}

main "$@"
