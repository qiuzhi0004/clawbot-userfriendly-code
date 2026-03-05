#!/usr/bin/env bash
set -euo pipefail

SCRIPT="./install-web-v2-mac.sh"

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

main() {
  local output=""
  output="$("$SCRIPT" --help 2>&1)"
  assert_contains "$output" "Usage: ./install-web-v2-mac.sh [options]"
  assert_contains "$output" "curl -fsSL https://raw.githubusercontent.com/qiuzhi0004/clawbot-userfriendly-code/main/install-web-v2-mac.sh | bash"
  echo "PASS: install-web-v2-mac help tests"
}

main "$@"
