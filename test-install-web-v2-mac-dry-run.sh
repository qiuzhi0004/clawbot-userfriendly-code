#!/usr/bin/env bash
set -euo pipefail

SCRIPT="./install-web-v2-mac-dry-run.sh"

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

test_missing_required_config_no_web() {
  local output=""
  local code=0
  set +e
  output="$("$SCRIPT" --no-web 2>&1)"
  code=$?
  set -e

  if [[ $code -eq 0 ]]; then
    fail "expected non-zero exit when required config is missing"
  fi
  assert_contains "$output" "Missing required config"
}

test_full_dry_run_from_env() {
  local output=""
  output="$(
    OPENCLAW_API_KEY="test-api-key" \
    OPENCLAW_FEISHU_APP_ID="cli_test" \
    OPENCLAW_FEISHU_APP_SECRET="secret_test" \
    OPENCLAW_FEISHU_GROUP_POLICY="allowlist" \
    OPENCLAW_FEISHU_GROUP_ALLOW_FROM="oc_a,oc_b" \
    OPENCLAW_PROVIDER="moonshot" \
    OPENCLAW_SKILLS="web-search autonomy bad-skill" \
    OPENCLAW_HOOKS="session-memory command-logger unknown-hook" \
    "$SCRIPT" --no-web 2>&1
  )"

  assert_contains "$output" "DRY RUN MODE"
  assert_contains "$output" "Dry-run wizard opened:"
  assert_contains "$output" "curl -fsSL https://raw.githubusercontent.com/qiuzhi0004/clawbot-userfriendly-code/main/install-web-v2-mac-dry-run.sh | bash"
  assert_contains "$output" "xcode-select --install"
  assert_contains "$output" "softwareupdate --list | grep -i \"Command Line Tools\""
  assert_contains "$output" "brew install python"
  assert_contains "$output" "curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh | bash -s -- --no-onboard"
  assert_contains "$output" "openclaw onboard --non-interactive --accept-risk --mode local --auth-choice moonshot-api-key --moonshot-api-key ***REDACTED***"
  assert_contains "$output" "openclaw config set channels.feishu.groupPolicy allowlist"
  assert_contains "$output" "openclaw config set channels.feishu.groupAllowFrom [\"oc_a\", \"oc_b\"] --strict-json"
  assert_contains "$output" "Selected Skills: web-search,autonomy"
  assert_contains "$output" "Selected Hooks: session-memory,command-logger"

  local wizard_path=""
  wizard_path="$(printf '%s\n' "$output" | sed -n 's/.*Dry-run wizard opened: //p' | head -n1)"
  if [[ -z "$wizard_path" ]]; then
    fail "expected a wizard path in output"
  fi
  if [[ ! -f "$wizard_path" ]]; then
    fail "expected wizard html file to exist after script exits: $wizard_path"
  fi
}

main() {
  test_missing_required_config_no_web
  test_full_dry_run_from_env
  echo "PASS: install-web-v2-mac-dry-run tests"
}

main "$@"
