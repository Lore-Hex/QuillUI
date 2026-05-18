#!/usr/bin/env zsh
set -euo pipefail

APP_PATH="${CODEX_APP_PATH:-/Applications/Codex.app}"
DELAY_SECONDS="${CODEX_RESTART_DELAY_SECONDS:-2}"
LOG_PATH="${CODEX_RESTART_LOG:-/tmp/quillui-restart-codex.log}"

usage() {
  cat <<'USAGE'
usage: restart-codex-app.sh [--delay seconds] [--app-path /path/to/Codex.app]

Schedules a detached restart of the macOS Codex app. The helper first asks
Codex to quit, then force-kills remaining processes inside that app bundle,
then opens Codex again.

Environment:
  CODEX_APP_PATH                 Defaults to /Applications/Codex.app
  CODEX_RESTART_DELAY_SECONDS    Defaults to 2
  CODEX_RESTART_LOG              Defaults to /tmp/quillui-restart-codex.log
USAGE
}

while (($#)); do
  case "$1" in
    --delay)
      DELAY_SECONDS="${2:?missing value for --delay}"
      shift 2
      ;;
    --app-path)
      APP_PATH="${2:?missing value for --app-path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'restart-codex-app.sh: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ "$APP_PATH" != *.app || ! -d "$APP_PATH/Contents" ]]; then
  printf 'restart-codex-app.sh: Codex app bundle not found: %s\n' "$APP_PATH" >&2
  exit 66
fi

HELPER_PATH="/tmp/quillui-restart-codex-$$.zsh"
cat >"$HELPER_PATH" <<'HELPER'
#!/usr/bin/env zsh
set -u

app_path="$1"
delay_seconds="$2"
log_path="$3"
bundle_process_prefix="${app_path}/Contents/"

codex_pids() {
  /bin/ps -axo pid=,args= | /usr/bin/awk \
    -v prefix="$bundle_process_prefix" \
    -v self="$$" \
    '$1 != self && index($0, prefix) { print $1 }'
}

{
  printf '[%s] launchd helper scheduling Codex restart after %ss\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$delay_seconds"
  sleep "$delay_seconds"

  /usr/bin/osascript -e 'tell application "Codex" to quit' >/dev/null 2>&1 || true

  deadline=$((SECONDS + 10))
  while [[ -n "$(codex_pids)" ]] && ((SECONDS < deadline)); do
    sleep 0.5
  done

  pids="$(codex_pids)"
  if [[ -n "$pids" ]]; then
    printf '[%s] terminating remaining Codex bundle pids: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${pids//$'\n'/ }"
    /bin/kill -TERM ${(f)pids} >/dev/null 2>&1 || true
    sleep 2
  fi

  pids="$(codex_pids)"
  if [[ -n "$pids" ]]; then
    printf '[%s] force-killing remaining Codex bundle pids: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${pids//$'\n'/ }"
    /bin/kill -KILL ${(f)pids} >/dev/null 2>&1 || true
  fi

  sleep 1

  /usr/bin/open "$app_path"
  printf '[%s] reopened %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$app_path"
} >>"$log_path" 2>&1

rm -f "$0"
HELPER

chmod 700 "$HELPER_PATH"

LABEL="quillui.restart-codex.$$"
if /bin/launchctl submit -l "$LABEL" -- /bin/zsh "$HELPER_PATH" "$APP_PATH" "$DELAY_SECONDS" "$LOG_PATH" >/dev/null 2>&1; then
  printf 'scheduled Codex restart launchd job %s via %s; log: %s\n' "$LABEL" "$HELPER_PATH" "$LOG_PATH"
  exit 0
fi

nohup /bin/zsh "$HELPER_PATH" "$APP_PATH" "$DELAY_SECONDS" "$LOG_PATH" >/dev/null 2>&1 &
printf 'scheduled Codex restart via fallback nohup helper %s; log: %s\n' "$HELPER_PATH" "$LOG_PATH"
