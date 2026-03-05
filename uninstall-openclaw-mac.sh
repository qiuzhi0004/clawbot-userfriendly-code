#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
KEEP_APP=0

log_info() {
  printf '\033[36m%s\033[0m\n' "$1"
}

log_warn() {
  printf '\033[33m%s\033[0m\n' "$1"
}

log_error() {
  printf '\033[31m%s\033[0m\n' "$1" >&2
}

print_cmd() {
  local rendered=""
  local arg
  for arg in "$@"; do
    if [[ -z "$rendered" ]]; then
      rendered="$(printf '%q' "$arg")"
    else
      rendered="${rendered} $(printf '%q' "$arg")"
    fi
  done
  printf '  -> %s\n' "$rendered"
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_cmd "$@"
    return 0
  fi
  "$@"
}

remove_path() {
  local target="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_cmd rm -rf "$target"
    return 0
  fi
  rm -rf "$target"
}

usage() {
  cat <<'EOF'
Usage: ./uninstall-openclaw-mac.sh [options]

Options:
  --dry-run      Print actions only, do not change system
  --keep-app     Keep /Applications/OpenClaw.app
  -h, --help     Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --keep-app)
        KEEP_APP=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

require_macos() {
  if [[ "${OSTYPE:-}" != darwin* ]]; then
    log_error "This uninstall script is for macOS only."
    exit 1
  fi
}

run_official_uninstall() {
  log_info "Step 1/5: run official OpenClaw uninstall"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_cmd openclaw uninstall --all --yes --non-interactive --dry-run
    return 0
  fi

  if command -v openclaw >/dev/null 2>&1; then
    if openclaw uninstall --all --yes --non-interactive; then
      log_info "Official uninstall completed."
      return 0
    fi
    log_warn "Official uninstall failed, continuing with manual cleanup fallback."
    return 1
  fi

  log_warn "openclaw command not found, using manual cleanup fallback."
  return 1
}

manual_launchagent_cleanup() {
  log_info "Step 2/5: remove launch agents (fallback)"

  local agent_dir="$HOME/Library/LaunchAgents"
  local patterns=(
    "$agent_dir"/bot.molt.gateway.plist
    "$agent_dir"/bot.molt.*.plist
    "$agent_dir"/com.openclaw.*.plist
  )

  local plist
  for plist in "${patterns[@]}"; do
    [[ -e "$plist" ]] || continue
    local label
    label="$(basename "$plist" .plist)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      print_cmd launchctl bootout "gui/$UID/$label"
      print_cmd rm -f "$plist"
      continue
    fi
    launchctl bootout "gui/$UID/$label" >/dev/null 2>&1 || true
    rm -f "$plist" >/dev/null 2>&1 || true
  done
}

manual_state_cleanup() {
  log_info "Step 3/5: remove state and workspace"

  remove_path "${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
  remove_path "$HOME/.openclaw/workspace"

  local profile_dir
  for profile_dir in "$HOME"/.openclaw-*; do
    [[ -d "$profile_dir" ]] || continue
    remove_path "$profile_dir"
  done

  if [[ -n "${OPENCLAW_CONFIG_PATH:-}" ]]; then
    remove_path "$OPENCLAW_CONFIG_PATH"
  fi
}

manual_cli_cleanup() {
  log_info "Step 4/5: remove CLI installs"

  if command -v npm >/dev/null 2>&1 || [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd npm rm -g openclaw || true
  fi
  if command -v pnpm >/dev/null 2>&1 || [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd pnpm remove -g openclaw || true
  fi
  if command -v bun >/dev/null 2>&1 || [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd bun remove -g openclaw || true
  fi

  remove_path "$HOME/.local/bin/openclaw"
}

manual_app_cleanup() {
  log_info "Step 5/5: remove macOS app bundle"
  if [[ "$KEEP_APP" -eq 1 ]]; then
    log_warn "Keeping /Applications/OpenClaw.app (--keep-app)."
    return
  fi
  remove_path "/Applications/OpenClaw.app"
}

final_summary() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_warn "DRY RUN MODE: no changes were applied."
    return
  fi

  if command -v openclaw >/dev/null 2>&1; then
    log_warn "openclaw is still on PATH. It may come from another install location."
  else
    log_info "OpenClaw CLI is no longer on PATH (or was already absent)."
  fi
}

main() {
  parse_args "$@"
  require_macos

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "DRY RUN MODE: previewing uninstall actions only."
  fi

  run_official_uninstall || true
  manual_launchagent_cleanup
  manual_state_cleanup
  manual_cli_cleanup
  manual_app_cleanup
  final_summary
}

main "$@"
