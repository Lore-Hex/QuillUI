#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null
  pwd
)"
cd "$ROOT_DIR"

SCREENSHOT_PATH="${1:-$ROOT_DIR/.qa/icecubes-linux-add-account.png}"
SCRATCH_PATH="${QUILLUI_ICECUBES_SCRATCH_PATH:-.build-linux-icecubes-app}"
APP_LOG_PATH="${QUILLUI_ICECUBES_VISUAL_APP_LOG:-/tmp/quillui-icecubes-app.log}"
SCREEN_SIZE="${QUILLUI_ICECUBES_VISUAL_SCREEN_SIZE:-1000x980x24}"
SCROLL_CLICKS="${QUILLUI_ICECUBES_VISUAL_SCROLL_CLICKS:-0}"
SCROLL_X="${QUILLUI_ICECUBES_VISUAL_SCROLL_X:-520}"
SCROLL_Y="${QUILLUI_ICECUBES_VISUAL_SCROLL_Y:-760}"
INTERACTION="${QUILLUI_ICECUBES_VISUAL_INTERACTION:-suggestions}"
TYPE_X="${QUILLUI_ICECUBES_VISUAL_TYPE_X:-390}"
TYPE_Y="${QUILLUI_ICECUBES_VISUAL_TYPE_Y:-220}"
TYPE_KEYS="${QUILLUI_ICECUBES_VISUAL_TYPE_INSTANCE_KEYS:-m a s t o d o n period s o c i a l}"
TYPE_FOCUS_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_TYPE_FOCUS_SETTLE_SECONDS:-0.6}"
TYPE_KEY_DELAY_MS="${QUILLUI_ICECUBES_VISUAL_TYPE_KEY_DELAY_MS:-25}"
TYPE_INSTANCE_READY_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_TYPE_INSTANCE_READY_TIMEOUT_SECONDS:-20}"
SIGN_IN_X="${QUILLUI_ICECUBES_VISUAL_SIGN_IN_X:-410}"
SIGN_IN_Y="${QUILLUI_ICECUBES_VISUAL_SIGN_IN_Y:-256}"
AUTH_TRENDING_X="${QUILLUI_ICECUBES_VISUAL_AUTH_TRENDING_X:-82}"
AUTH_TRENDING_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_TRENDING_Y:-117}"
AUTH_LOCAL_X="${QUILLUI_ICECUBES_VISUAL_AUTH_LOCAL_X:-82}"
AUTH_LOCAL_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_LOCAL_Y:-156}"
AUTH_FEDERATED_X="${QUILLUI_ICECUBES_VISUAL_AUTH_FEDERATED_X:-82}"
AUTH_FEDERATED_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_FEDERATED_Y:-195}"
AUTH_EXPLORE_X="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_X:-82}"
AUTH_EXPLORE_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_Y:-273}"
AUTH_EXPLORE_SEARCH_X="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_X:-520}"
AUTH_EXPLORE_SEARCH_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_Y:-68}"
AUTH_EXPLORE_SEARCH_TEXT="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_TEXT:-quill}"
AUTH_EXPLORE_SEARCH_KEYS="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_KEYS:-q u i l l}"
AUTH_EXPLORE_SEARCH_FOCUS_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_FOCUS_SETTLE_SECONDS:-0.6}"
AUTH_EXPLORE_SEARCH_TYPE_DELAY_MS="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_TYPE_DELAY_MS:-25}"
AUTH_EXPLORE_SEARCH_AFTER_TYPE_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_AFTER_TYPE_SETTLE_SECONDS:-1.5}"
AUTH_EXPLORE_LINKS_X="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_LINKS_X:-308}"
AUTH_EXPLORE_LINKS_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_LINKS_Y:-128}"
AUTH_EXPLORE_POSTS_X="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_POSTS_X:-406}"
AUTH_EXPLORE_POSTS_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_POSTS_Y:-128}"
AUTH_EXPLORE_SUGGESTED_USERS_X="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SUGGESTED_USERS_X:-545}"
AUTH_EXPLORE_SUGGESTED_USERS_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SUGGESTED_USERS_Y:-128}"
AUTH_EXPLORE_TAGS_X="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_TAGS_X:-682}"
AUTH_EXPLORE_TAGS_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_TAGS_Y:-128}"
AUTH_EXPLORE_SUGGESTED_RELATIONSHIPS_ENDPOINT="/api/v1/accounts/relationships?id%5B%5D=suggested-account-1&id%5B%5D=suggested-account-2"
AUTH_NOTIFICATIONS_X="${QUILLUI_ICECUBES_VISUAL_AUTH_NOTIFICATIONS_X:-82}"
AUTH_NOTIFICATIONS_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_NOTIFICATIONS_Y:-312}"
AUTH_NOTIFICATIONS_INITIAL_ENDPOINT="/api/v2/notifications?grouped_types%5B%5D=favourite&grouped_types%5B%5D=follow&grouped_types%5B%5D=reblog&expand_accounts=full"
AUTH_NOTIFICATIONS_REFRESH_ENDPOINT="/api/v2/notifications?since_id=1002&grouped_types%5B%5D=favourite&grouped_types%5B%5D=follow&grouped_types%5B%5D=reblog&expand_accounts=full"
AUTH_MESSAGES_X="${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_X:-82}"
AUTH_MESSAGES_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_Y:-390}"
AUTH_MESSAGES_ENDPOINT="/api/v1/conversations"
AUTH_MESSAGES_DETAIL_X="${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_DETAIL_X:-360}"
AUTH_MESSAGES_DETAIL_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_DETAIL_Y:-92}"
AUTH_MESSAGES_DETAIL_READ_LOG="[QuillURLSessionFixtures] direct POST https://mastodon.social/api/v1/conversations/conversation-1001/read"
AUTH_MESSAGES_DETAIL_CONTEXT_LOG="[QuillURLSessionFixtures] direct GET https://mastodon.social/api/v1/statuses/conversation-status-1001/context"
AUTH_MESSAGES_CLICK_RETRIES="${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_CLICK_RETRIES:-5}"
AUTH_MESSAGES_CLICK_RETRY_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_CLICK_RETRY_SECONDS:-0.75}"
AUTH_PROFILE_X="${QUILLUI_ICECUBES_VISUAL_AUTH_PROFILE_X:-82}"
AUTH_PROFILE_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_PROFILE_Y:-430}"
AUTH_PROFILE_STATUSES_ENDPOINT="/api/v1/accounts/quill-account/statuses"
AUTH_PROFILE_CLICK_RETRIES="${QUILLUI_ICECUBES_VISUAL_AUTH_PROFILE_CLICK_RETRIES:-5}"
AUTH_PROFILE_CLICK_RETRY_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_PROFILE_CLICK_RETRY_SECONDS:-0.75}"
AUTH_SETTINGS_X="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_X:-82}"
AUTH_SETTINGS_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_Y:-625}"
AUTH_SETTINGS_SCROLL_X="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_SCROLL_X:-520}"
AUTH_SETTINGS_SCROLL_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_SCROLL_Y:-610}"
AUTH_SETTINGS_DISPLAY_SCROLL_CLICKS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_SCROLL_CLICKS:-6}"
AUTH_SETTINGS_DISPLAY_X="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_X:-405}"
AUTH_SETTINGS_DISPLAY_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_Y:-325}"
AUTH_SETTINGS_DISPLAY_ROUTE_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_ROUTE_SETTLE_SECONDS:-0.6}"
AUTH_SETTINGS_DISPLAY_CONTROLS_SCROLL_KEYS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_CONTROLS_SCROLL_KEYS:-Page_Down}"
AUTH_SETTINGS_DISPLAY_CONTROLS_KEY_DELAY_MS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_CONTROLS_KEY_DELAY_MS:-80}"
AUTH_SETTINGS_CHILD_CLICK_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_CHILD_CLICK_SETTLE_SECONDS:-0.25}"
AUTH_SETTINGS_DISPLAY_FONT_SCALE_START_X="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_SCALE_START_X:-526}"
AUTH_SETTINGS_DISPLAY_FONT_SCALE_END_X="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_SCALE_END_X:-720}"
AUTH_SETTINGS_DISPLAY_FONT_SCALE_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_SCALE_Y:-582}"
AUTH_SETTINGS_DISPLAY_FONT_SCALE_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_SCALE_SETTLE_SECONDS:-0.8}"
AUTH_SETTINGS_DISPLAY_FONT_PICKER_X="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_X:-420}"
AUTH_SETTINGS_DISPLAY_FONT_PICKER_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_Y:-532}"
AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEYS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEYS:-End Return}"
AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEY_DELAY_MS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEY_DELAY_MS:-80}"
AUTH_SETTINGS_DISPLAY_FONT_PICKER_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_SETTLE_SECONDS:-0.8}"
AUTH_SETTINGS_DISPLAY_FONT_PICKER_INTER_X="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_INTER_X:-282}"
AUTH_SETTINGS_DISPLAY_FONT_PICKER_INTER_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_INTER_Y:-216}"
AUTH_SETTINGS_DISPLAY_FONT_PICKER_SELECT_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_SELECT_SETTLE_SECONDS:-0.8}"
AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_X="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_X:-289}"
AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_Y:-278}"
AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_SETTLE_SECONDS:-0.8}"
AUTH_LIST_X="${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_X:-32}"
AUTH_LIST_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_Y:-586}"
AUTH_LIST_REPAINT_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_REPAINT_SETTLE_SECONDS:-8}"
AUTH_LIST_CLICK_RETRIES="${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_CLICK_RETRIES:-5}"
AUTH_LIST_CLICK_RETRY_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_CLICK_RETRY_SECONDS:-0.75}"
AUTH_LIST_ENDPOINT="/api/v1/timelines/list/list-quill-core"
AUTH_LIST_PAGINATION_ENDPOINT="${AUTH_LIST_ENDPOINT}?max_id=list-9002"
AUTH_TIMELINE_PAGINATION_SCROLL_X="${QUILLUI_ICECUBES_VISUAL_AUTH_TIMELINE_PAGINATION_SCROLL_X:-520}"
AUTH_TIMELINE_PAGINATION_SCROLL_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_TIMELINE_PAGINATION_SCROLL_Y:-760}"
AUTH_TIMELINE_PAGINATION_SCROLL_CLICKS="${QUILLUI_ICECUBES_VISUAL_AUTH_TIMELINE_PAGINATION_SCROLL_CLICKS:-12}"
AUTH_TIMELINE_PAGINATION_SCROLL_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_TIMELINE_PAGINATION_SCROLL_SETTLE_SECONDS:-0.1}"
AUTH_REFRESH_KEY_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_REFRESH_KEY_SETTLE_SECONDS:-0.25}"
AUTH_REFRESH_KEY_RETRIES="${QUILLUI_ICECUBES_VISUAL_AUTH_REFRESH_KEY_RETRIES:-5}"
AUTH_REFRESH_KEY_RETRY_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_REFRESH_KEY_RETRY_SECONDS:-0.75}"
AUTH_STATUS_DETAIL_REFRESH_KEY_RETRIES="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_REFRESH_KEY_RETRIES:-5}"
AUTH_STATUS_DETAIL_REFRESH_KEY_RETRY_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_REFRESH_KEY_RETRY_SECONDS:-0.75}"
AUTH_COMPOSE_X="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSE_X:-663}"
AUTH_COMPOSE_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSE_Y:-28}"
AUTH_COMPOSE_WINDOW_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSE_WINDOW_TIMEOUT_SECONDS:-20}"
AUTH_COMPOSE_CLICK_RETRIES="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSE_CLICK_RETRIES:-3}"
AUTH_COMPOSE_CLICK_RETRY_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSE_CLICK_RETRY_SECONDS:-0.75}"
AUTH_COMPOSER_TYPE_TEXT="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_TEXT:-hello from linux}"
AUTH_COMPOSER_TYPE_DELAY_MS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_DELAY_MS:-25}"
AUTH_COMPOSER_TYPE_X="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_X:-320}"
AUTH_COMPOSER_TYPE_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_Y:-180}"
AUTH_COMPOSER_TYPE_POINTS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_POINTS:-$AUTH_COMPOSER_TYPE_X,$AUTH_COMPOSER_TYPE_Y 320,150 320,285}"
AUTH_COMPOSER_TYPE_FOCUS_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_FOCUS_SETTLE_SECONDS:-0.5}"
AUTH_COMPOSER_AFTER_TYPE_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_AFTER_TYPE_SETTLE_SECONDS:-2.5}"
AUTH_COMPOSER_TYPED_CHANGE_MIN_PIXELS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPED_CHANGE_MIN_PIXELS:-80}"
AUTH_COMPOSER_SEND_X="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_X:-672}"
AUTH_COMPOSER_SEND_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_Y:-60}"
AUTH_COMPOSER_SEND_POINTS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_POINTS:-$AUTH_COMPOSER_SEND_X,$AUTH_COMPOSER_SEND_Y 606,93 755,111}"
AUTH_COMPOSER_SEND_CLICK_RETRY_POLLS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_CLICK_RETRY_POLLS:-20}"
AUTH_COMPOSER_SEND_CLICK_RETRY_POLL_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_CLICK_RETRY_POLL_SECONDS:-0.25}"
AUTH_COMPOSER_DISMISS_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_DISMISS_TIMEOUT_SECONDS:-12}"
AUTH_STATUS_DETAIL_X="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_X:-360}"
AUTH_STATUS_DETAIL_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_Y:-92}"
AUTH_STATUS_DETAIL_PRE_CLICK_DELAY_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_PRE_CLICK_DELAY_SECONDS:-0.2}"
AUTH_STATUS_DETAIL_ROW_READY_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_ROW_READY_TIMEOUT_SECONDS:-20}"
AUTH_STATUS_DETAIL_NAVIGATION_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_NAVIGATION_TIMEOUT_SECONDS:-20}"
AUTH_ROUTE_VISUAL_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_ROUTE_VISUAL_TIMEOUT_SECONDS:-20}"
AUTH_STATUS_DETAIL_CLICK_RETRIES="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_CLICK_RETRIES:-5}"
AUTH_STATUS_DETAIL_CLICK_RETRY_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_CLICK_RETRY_SECONDS:-0.75}"
AUTH_STATUS_DETAIL_CLICK_RETRY_POLLS="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_CLICK_RETRY_POLLS:-8}"
AUTH_STATUS_DETAIL_CLICK_RETRY_POLL_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_CLICK_RETRY_POLL_SECONDS:-0.25}"
AUTH_STATUS_DETAIL_GET_LOG="[QuillURLSessionFixtures] direct GET https://mastodon.social/api/v1/statuses/1003"
AUTH_STATUS_DETAIL_CONTEXT_GET_LOG="[QuillURLSessionFixtures] direct GET https://mastodon.social/api/v1/statuses/1003/context"
AUTH_STATUS_DETAIL_FAVORITED_BY_GET_LOG="[QuillURLSessionFixtures] direct GET https://mastodon.social/api/v1/statuses/1003/favourited_by"
AUTH_STATUS_DETAIL_REBLOGGED_BY_GET_LOG="[QuillURLSessionFixtures] direct GET https://mastodon.social/api/v1/statuses/1003/reblogged_by"
AUTH_STATUS_DETAIL_BOOKMARK_POST_LOG="POST https://mastodon.social/api/v1/statuses/1003/bookmark"
AUTH_STATUS_DETAIL_SECONDARY_BOOKMARK_POST_LOG="POST https://mastodon.social/api/v1/statuses/1001/bookmark"
AUTH_STATUS_DETAIL_REPLY_X="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_REPLY_X:-272}"
AUTH_STATUS_DETAIL_REPLY_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_REPLY_Y:-444}"
AUTH_STATUS_DETAIL_BOOST_X="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_BOOST_X:-335}"
AUTH_STATUS_DETAIL_BOOST_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_BOOST_Y:-462}"
AUTH_STATUS_DETAIL_BOOST_MENU_X="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_BOOST_MENU_X:-335}"
AUTH_STATUS_DETAIL_BOOST_MENU_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_BOOST_MENU_Y:-505}"
AUTH_STATUS_DETAIL_QUOTE_MENU_X="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_QUOTE_MENU_X:-335}"
AUTH_STATUS_DETAIL_QUOTE_MENU_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_QUOTE_MENU_Y:-557}"
AUTH_STATUS_DETAIL_FAVORITE_X="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_FAVORITE_X:-398}"
AUTH_STATUS_DETAIL_FAVORITE_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_FAVORITE_Y:-462}"
AUTH_STATUS_DETAIL_SECONDARY_BOOKMARK_X="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_SECONDARY_BOOKMARK_X:-584}"
AUTH_STATUS_DETAIL_SECONDARY_BOOKMARK_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_SECONDARY_BOOKMARK_Y:-462}"
AUTH_MEDIA_VIEWER_X="${QUILLUI_ICECUBES_VISUAL_AUTH_MEDIA_VIEWER_X:-520}"
AUTH_MEDIA_VIEWER_Y="${QUILLUI_ICECUBES_VISUAL_AUTH_MEDIA_VIEWER_Y:-330}"
AUTH_MEDIA_VIEWER_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_AUTH_MEDIA_VIEWER_TIMEOUT_SECONDS:-20}"
CLICK_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_CLICK_SETTLE_SECONDS:-0.15}"
CLICK_HOLD_SECONDS="${QUILLUI_ICECUBES_VISUAL_CLICK_HOLD_SECONDS:-0.08}"
CLICK_FOCUS_PRIME="${QUILLUI_ICECUBES_VISUAL_CLICK_FOCUS_PRIME:-1}"
CLICK_FOCUS_PRIME_X="${QUILLUI_ICECUBES_VISUAL_CLICK_FOCUS_PRIME_X:-260}"
CLICK_FOCUS_PRIME_Y="${QUILLUI_ICECUBES_VISUAL_CLICK_FOCUS_PRIME_Y:-30}"
CLICK_TRACE="${QUILLUI_ICECUBES_VISUAL_TRACE_CLICKS:-0}"
WINDOW_TRACE="${QUILLUI_ICECUBES_VISUAL_TRACE_WINDOWS:-0}"
FINAL_CAPTURE_RETRY_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_FINAL_CAPTURE_RETRY_TIMEOUT_SECONDS:-8}"
SIGN_IN_OPEN_TIMEOUT_SECONDS="${QUILLUI_ICECUBES_VISUAL_SIGN_IN_OPEN_TIMEOUT_SECONDS:-25}"
OPEN_URL_LOG_PATH="${QUILLUI_ICECUBES_VISUAL_OPEN_URL_LOG:-$(dirname "$SCREENSHOT_PATH")/icecubes-open-url.log}"
SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_SETTLE_SECONDS:-}"
INITIAL_SETTLE_SECONDS="${QUILLUI_ICECUBES_VISUAL_INITIAL_SETTLE_SECONDS:-}"
DEFAULT_URLSESSION_FIXTURES_FILE="$ROOT_DIR/Tests/Fixtures/IceCubes/mastodon-fixtures.json"

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

DISPLAY_ID="$(quillui_normalize_x_display_id "${QUILLUI_ICECUBES_VISUAL_DISPLAY:-:97}")"

trace_visual_window() {
  [[ "$WINDOW_TRACE" == "1" ]] || return 0

  local label="$1"
  local window="${2:-}"
  local name geometry

  if [[ -z "$window" ]]; then
    echo "IceCubes visual window: $label id=<none>" >&2
    return 0
  fi

  name="$(DISPLAY="$DISPLAY_ID" xdotool getwindowname "$window" 2>/dev/null || true)"
  geometry="$(DISPLAY="$DISPLAY_ID" xdotool getwindowgeometry --shell "$window" 2>/dev/null | tr '\n' ' ' || true)"
  echo "IceCubes visual window: $label id=$window name=${name:-<unnamed>} $geometry" >&2
}

trace_visual_windows_for_pid() {
  [[ "$WINDOW_TRACE" == "1" ]] || return 0

  local label="$1"
  local window found=0

  while read -r window; do
    [[ -n "$window" ]] || continue
    found=1
    trace_visual_window "$label" "$window"
  done < <(DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --pid "$app_pid" 2>/dev/null || true)

  if [[ "$found" == "0" ]]; then
    trace_visual_window "$label" ""
  fi
}

quillui_install_linux_backend_smoke_packages

if [[ ! -d "$ROOT_DIR/.upstream/icecubes/Packages/Models/Sources/Models" ]]; then
  echo "IceCubes upstream source is missing; run scripts/fetch-upstream.sh icecubes first." >&2
  exit 66
fi

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

"$ROOT_DIR/scripts/prepare-linux-build-backend.sh" \
  --backend gtk \
  --scratch-path "$SCRATCH_PATH"

QUILLUI_LINUX_BACKEND=gtk \
QUILLUI_ICECUBES=1 \
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
  swift build --disable-index-store --scratch-path "$SCRATCH_PATH" --product icecubes-linux-app

if [[ "$INTERACTION" == seeded-authenticated-* ]]; then
  QUILLUI_LINUX_BACKEND=gtk \
  QUILLUI_ICECUBES=1 \
    "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift build --disable-index-store --scratch-path "$SCRATCH_PATH" --product icecubes-seed-account
fi

BIN_PATH="$(
  QUILLUI_LINUX_BACKEND=gtk \
  QUILLUI_ICECUBES=1 \
    "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift build --disable-index-store --scratch-path "$SCRATCH_PATH" --show-bin-path
)"
APP_EXECUTABLE="$BIN_PATH/icecubes-linux-app"
SEED_EXECUTABLE="$BIN_PATH/icecubes-seed-account"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Built IceCubes executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi
if [[ "$INTERACTION" == seeded-authenticated-* && ! -x "$SEED_EXECUTABLE" ]]; then
  echo "Built IceCubes seed executable is missing or not executable: $SEED_EXECUTABLE" >&2
  exit 1
fi

xvfb_pid=""
quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" /tmp/quillui-icecubes-xvfb.log xvfb_pid

cleanup() {
  quillui_stop_process_if_running "${app_pid:-}"
  quillui_stop_process_if_running "$xvfb_pid"
}
trap cleanup EXIT

DEFAULT_QUILLDATA_HOME_NAME="$(
  basename "${SCREENSHOT_PATH%.*}" | tr -c 'A-Za-z0-9_.-' '_'
)"
QUILLDATA_HOME="${QUILLUI_ICECUBES_DATA_HOME:-$ROOT_DIR/.qa/icecubes-linux-data/$DEFAULT_QUILLDATA_HOME_NAME}"
KEYCHAIN_STORE_PATH="${QUILLUI_ICECUBES_VISUAL_KEYCHAIN_STORE:-$QUILLDATA_HOME/keychain.json}"
APP_HOME="$QUILLDATA_HOME/home"
APP_CONFIG_HOME="$APP_HOME/.config"
rm -rf "$QUILLDATA_HOME"
mkdir -p "$QUILLDATA_HOME" "$APP_CONFIG_HOME"

if [[ "$INTERACTION" == seeded-authenticated-* ]]; then
  seed_env=()
  if [[ "$INTERACTION" == "seeded-authenticated-status-detail-bookmark" ]]; then
    seed_env+=("QUILLUI_ICECUBES_SEED_STATUS_ACTION_SECONDARY=bookmark")
  fi
  mkdir -p "$(dirname "$KEYCHAIN_STORE_PATH")"
  rm -f "$KEYCHAIN_STORE_PATH"
  env \
    QUILLDATA_HOME="$QUILLDATA_HOME" \
    HOME="$APP_HOME" \
    XDG_CONFIG_HOME="$APP_CONFIG_HOME" \
    QUILLUI_KEYCHAINSWIFT_STORE_PATH="$KEYCHAIN_STORE_PATH" \
    QUILLUI_LINUX_BACKEND=gtk \
    QUILLUI_ICECUBES=1 \
    "${seed_env[@]}" \
    "$SEED_EXECUTABLE"
fi

app_env=()
if [[ -z "${QUILLUI_URLSESSION_FIXTURES_FILE:-}" && -f "$DEFAULT_URLSESSION_FIXTURES_FILE" ]]; then
  app_env+=(
    "QUILLUI_URLSESSION_FIXTURES_FILE=$DEFAULT_URLSESSION_FIXTURES_FILE"
  )
fi
if [[ -z "${QUILLUI_URLSESSION_FIXTURES_DEBUG:-}" ]]; then
  app_env+=(
    "QUILLUI_URLSESSION_FIXTURES_DEBUG=1"
  )
fi
if [[ "$INTERACTION" == "sign-in-open" ]]; then
  mkdir -p "$(dirname "$OPEN_URL_LOG_PATH")"
  rm -f "$OPEN_URL_LOG_PATH"
  app_env+=(
    "QUILLUI_OPEN_URL_LOG_FILE=$OPEN_URL_LOG_PATH"
    "QUILLUI_OPEN_URL_LOG_ASSUME_HANDLED=1"
  )
fi
if [[ "$INTERACTION" == seeded-authenticated-* ]]; then
  app_env+=(
    "QUILLUI_KEYCHAINSWIFT_STORE_PATH=$KEYCHAIN_STORE_PATH"
  )
fi
if [[ "$INTERACTION" == "seeded-authenticated-media-viewer" ]]; then
  app_env+=(
    "QUILLUI_GTK_DEBUG_ACTIONS=${QUILLUI_GTK_DEBUG_ACTIONS:-1}"
  )
fi
if [[ "$INTERACTION" == seeded-authenticated-*-refresh ]]; then
  app_env+=(
    "QUILLUI_GTK_DEBUG_REFRESHABLE=${QUILLUI_GTK_DEBUG_REFRESHABLE:-1}"
  )
fi

env \
  DISPLAY="$DISPLAY_ID" \
  GTK_A11Y=none \
  GSK_RENDERER=cairo \
  HOME="$APP_HOME" \
  XDG_CONFIG_HOME="$APP_CONFIG_HOME" \
  QUILLUI_BACKEND=gtk \
  QUILLDATA_HOME="$QUILLDATA_HOME" \
  "${app_env[@]}" \
  "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

window_id=""
for _ in $(seq 1 60); do
  if ! kill -0 "$app_pid" >/dev/null 2>&1; then
    echo "IceCubes app exited before a window was visible." >&2
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
    exit 1
  fi
  window_id="$(quillui_find_visible_window_for_pid "$DISPLAY_ID" "$app_pid")"
  [[ -n "$window_id" ]] && break
  sleep 0.5
done

if [[ -z "$window_id" ]]; then
  echo "IceCubes app did not map a visible window." >&2
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
  exit 1
fi

quillui_move_window_to_origin "$DISPLAY_ID" "$window_id"
capture_window_id="$window_id"
trace_visual_window "initial-main" "$window_id"
trace_visual_windows_for_pid "initial-visible"
if [[ -z "$INITIAL_SETTLE_SECONDS" ]]; then
  if [[ -n "$SETTLE_SECONDS" ]]; then
    INITIAL_SETTLE_SECONDS="$SETTLE_SECONDS"
  elif [[ "$INTERACTION" == seeded-authenticated-* ]]; then
    # Fixture-backed URLProtocol tasks can trip a Linux FoundationNetworking
    # cancel-after-completion assertion if we idle on the initial route before
    # navigating. Wait for the specific API activity below instead.
    INITIAL_SETTLE_SECONDS="0.5"
  else
    INITIAL_SETTLE_SECONDS="8"
  fi
fi
sleep "$INITIAL_SETTLE_SECONDS"

case "$SCROLL_CLICKS" in
  ''|*[!0-9]*)
    echo "QUILLUI_ICECUBES_VISUAL_SCROLL_CLICKS must be a non-negative integer, got: $SCROLL_CLICKS" >&2
    exit 2
    ;;
esac

if (( SCROLL_CLICKS > 0 )); then
  for _ in $(seq 1 "$SCROLL_CLICKS"); do
    DISPLAY="$DISPLAY_ID" xdotool mousemove "$SCROLL_X" "$SCROLL_Y" click 5
    sleep 0.1
  done
  sleep "${QUILLUI_ICECUBES_VISUAL_AFTER_SCROLL_SETTLE_SECONDS:-1}"
fi

click_focus_primed=0

click_screen_point() {
  local x="$1"
  local y="$2"
  local label="${3:-screen}"

  if [[ "$CLICK_TRACE" == "1" ]]; then
    echo "IceCubes visual click: $label screen=${x},${y}" >&2
  fi
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$x" "$y"
  sleep "$CLICK_SETTLE_SECONDS"
  DISPLAY="$DISPLAY_ID" xdotool mousedown 1
  sleep "$CLICK_HOLD_SECONDS"
  DISPLAY="$DISPLAY_ID" xdotool mouseup 1
}

click_app_window_point() {
  local x="$1"
  local y="$2"
  local key value window_x=0 window_y=0 screen_x screen_y

  DISPLAY="$DISPLAY_ID" xdotool windowraise "$window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$window_id" 2>/dev/null || true

  while IFS='=' read -r key value; do
    case "$key" in
      X) window_x="$value" ;;
      Y) window_y="$value" ;;
    esac
  done < <(DISPLAY="$DISPLAY_ID" xdotool getwindowgeometry --shell "$window_id")

  if [[ "$CLICK_FOCUS_PRIME" == "1" && "$click_focus_primed" == "0" ]]; then
    click_screen_point \
      "$((window_x + CLICK_FOCUS_PRIME_X))" \
      "$((window_y + CLICK_FOCUS_PRIME_Y))" \
      "focus-prime window@${CLICK_FOCUS_PRIME_X},${CLICK_FOCUS_PRIME_Y}"
    click_focus_primed=1
    sleep 0.1
  fi

  # Use absolute screen coordinates after resolving the app window geometry.
  # Xvfb/openbox can swallow or misroute window-relative click chains after a
  # rebuild; explicit motion plus down/up matches the generic backend harness.
  screen_x="$((window_x + x))"
  screen_y="$((window_y + y))"
  click_screen_point "$screen_x" "$screen_y" "window@${x},${y}"
}

click_app_window_relative_screen_point() {
  local x="$1"
  local y="$2"
  local key value window_x=0 window_y=0

  while IFS='=' read -r key value; do
    case "$key" in
      X) window_x="$value" ;;
      Y) window_y="$value" ;;
    esac
  done < <(DISPLAY="$DISPLAY_ID" xdotool getwindowgeometry --shell "$window_id")

  # Menu popovers are focus-sensitive: raising/focusing the main window for
  # the second click can dismiss the popover before the item receives it.
  click_screen_point "$((window_x + x))" "$((window_y + y))" "relative-screen@${x},${y}"
}

click_capture_window_point() {
  local x="$1"
  local y="$2"
  local key value window_x=0 window_y=0

  DISPLAY="$DISPLAY_ID" xdotool windowraise "$capture_window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$capture_window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$capture_window_id" 2>/dev/null || true

  while IFS='=' read -r key value; do
    case "$key" in
      X) window_x="$value" ;;
      Y) window_y="$value" ;;
    esac
  done < <(DISPLAY="$DISPLAY_ID" xdotool getwindowgeometry --shell "$capture_window_id")

  click_screen_point "$((window_x + x))" "$((window_y + y))" "capture-window@${x},${y}"
}

type_instance_name() {
  click_app_window_point "$TYPE_X" "$TYPE_Y"
  sleep "$TYPE_FOCUS_SETTLE_SECONDS"
  read -r -a type_key_sequence <<<"$TYPE_KEYS"
  if ((${#type_key_sequence[@]} == 0)); then
    echo "QUILLUI_ICECUBES_VISUAL_TYPE_INSTANCE_KEYS must contain at least one xdotool key name." >&2
    exit 2
  fi
  DISPLAY="$DISPLAY_ID" xdotool key --delay "$TYPE_KEY_DELAY_MS" --clearmodifiers "${type_key_sequence[@]}"
  sleep "${QUILLUI_ICECUBES_VISUAL_AFTER_TYPE_SETTLE_SECONDS:-6}"
}

wait_for_add_account_selected_instance_visual() {
  case "$TYPE_INSTANCE_READY_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_TYPE_INSTANCE_READY_TIMEOUT_SECONDS must be a non-negative integer, got: $TYPE_INSTANCE_READY_TIMEOUT_SECONDS" >&2
      exit 2
      ;;
  esac

  local deadline output probe_path
  deadline="$((SECONDS + TYPE_INSTANCE_READY_TIMEOUT_SECONDS))"
  output=""
  probe_path="${SCREENSHOT_PATH%.*}.selected-instance-ready.png"

  while true; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for selected-instance Add Account pixels." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    if DISPLAY="$DISPLAY_ID" timeout 10 import -window "$window_id" "$probe_path"; then
      if output="$("$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "icecubes-linux-add-account-instance" 2>&1)"; then
        printf '%s\n' "$output"
        return 0
      fi
    else
      output="IceCubes selected-instance readiness screenshot capture failed: $probe_path"
    fi

    if ((SECONDS >= deadline)); then
      echo "Timed out waiting for IceCubes selected-instance Add Account pixels." >&2
      printf '%s\n' "$output" >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.5
  done
}

composer_typed_change_pixels() {
  local before_path="$1"
  local after_path="$2"

  python3 - "$before_path" "$after_path" <<'PY'
import subprocess
import sys
from pathlib import Path

before_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])
geometry = subprocess.run(
    ["identify", "-format", "%w %h", str(after_path)],
    check=True,
    text=True,
    stdout=subprocess.PIPE,
).stdout.split()
width, height = int(geometry[0]), int(geometry[1])
before_geometry = subprocess.run(
    ["identify", "-format", "%w %h", str(before_path)],
    check=True,
    text=True,
    stdout=subprocess.PIPE,
).stdout.split()
if before_geometry != geometry:
    print(0)
    raise SystemExit

x0 = 0
x1 = max(0, min(width, width - 40))
y0 = min(height, 84)
y1 = min(height, 260)
crop_width = x1 - x0
crop_height = y1 - y0
if crop_width <= 0 or crop_height <= 0:
    print(0)
    raise SystemExit
crop = f"{crop_width}x{crop_height}+{x0}+{y0}"
before_bytes = subprocess.run(
    ["convert", str(before_path), "-crop", crop, "rgb:-"],
    check=True,
    stdout=subprocess.PIPE,
).stdout
after_bytes = subprocess.run(
    ["convert", str(after_path), "-crop", crop, "rgb:-"],
    check=True,
    stdout=subprocess.PIPE,
).stdout
if len(before_bytes) != len(after_bytes):
    print(0)
    raise SystemExit

changed = 0
for offset in range(0, len(after_bytes), 3):
    br, bg, bb = before_bytes[offset], before_bytes[offset + 1], before_bytes[offset + 2]
    ar, ag, ab = after_bytes[offset], after_bytes[offset + 1], after_bytes[offset + 2]
    if (br + bg + bb) - (ar + ag + ab) >= 45 and (ar + ag + ab) <= 560:
        changed += 1
print(changed)
PY
}

type_authenticated_composer_text() {
  if [[ -z "$AUTH_COMPOSER_TYPE_TEXT" ]]; then
    echo "QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_TEXT must not be empty." >&2
    exit 2
  fi
  case "$AUTH_COMPOSER_TYPED_CHANGE_MIN_PIXELS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPED_CHANGE_MIN_PIXELS must be a non-negative integer, got: $AUTH_COMPOSER_TYPED_CHANGE_MIN_PIXELS" >&2
      exit 2
      ;;
  esac

  local baseline_path probe_path point point_x point_y change_pixels
  baseline_path="${SCREENSHOT_PATH%.*}.composer-before-type.png"
  probe_path="${SCREENSHOT_PATH%.*}.composer-typed-probe.png"
  mkdir -p "$(dirname "$baseline_path")"
  if ! DISPLAY="$DISPLAY_ID" timeout 10 import -window "$capture_window_id" "$baseline_path"; then
    echo "IceCubes authenticated composer pre-type screenshot capture failed: $baseline_path" >&2
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
    exit 1
  fi

  for point in $AUTH_COMPOSER_TYPE_POINTS; do
    if [[ "$point" != *,* ]]; then
      echo "Invalid QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_POINTS entry: $point" >&2
      exit 2
    fi
    point_x="${point%,*}"
    point_y="${point#*,}"
    case "$point_x" in
      ''|*[!0-9]*)
        echo "Invalid QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_POINTS entry: $point" >&2
        exit 2
        ;;
    esac
    case "$point_y" in
      ''|*[!0-9]*)
        echo "Invalid QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_TYPE_POINTS entry: $point" >&2
        exit 2
        ;;
    esac

    click_capture_window_point "$point_x" "$point_y"
    sleep "$AUTH_COMPOSER_TYPE_FOCUS_SETTLE_SECONDS"
    DISPLAY="$DISPLAY_ID" xdotool type --delay "$AUTH_COMPOSER_TYPE_DELAY_MS" --clearmodifiers "$AUTH_COMPOSER_TYPE_TEXT"
    sleep "$AUTH_COMPOSER_AFTER_TYPE_SETTLE_SECONDS"
    if ! DISPLAY="$DISPLAY_ID" timeout 10 import -window "$capture_window_id" "$probe_path"; then
      echo "IceCubes authenticated composer post-type screenshot capture failed: $probe_path" >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    change_pixels="$(composer_typed_change_pixels "$baseline_path" "$probe_path")"
    echo "IceCubes authenticated composer typed text change pixels at $point: $change_pixels"
    if ((change_pixels >= AUTH_COMPOSER_TYPED_CHANGE_MIN_PIXELS)); then
      return 0
    fi
  done

  echo "IceCubes authenticated composer did not visibly accept typed text at any configured point." >&2
  echo "Minimum changed pixels: $AUTH_COMPOSER_TYPED_CHANGE_MIN_PIXELS" >&2
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
  exit 1
}

type_authenticated_explore_search_text() {
  if [[ -z "$AUTH_EXPLORE_SEARCH_TEXT" ]]; then
    echo "QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_TEXT must not be empty." >&2
    exit 2
  fi

  click_app_window_point "$AUTH_EXPLORE_SEARCH_X" "$AUTH_EXPLORE_SEARCH_Y"
  sleep "$AUTH_EXPLORE_SEARCH_FOCUS_SETTLE_SECONDS"
  DISPLAY="$DISPLAY_ID" xdotool key --delay "$AUTH_EXPLORE_SEARCH_TYPE_DELAY_MS" --clearmodifiers ctrl+a BackSpace
  read -r -a search_key_sequence <<<"$AUTH_EXPLORE_SEARCH_KEYS"
  if ((${#search_key_sequence[@]} == 0)); then
    DISPLAY="$DISPLAY_ID" xdotool type --delay "$AUTH_EXPLORE_SEARCH_TYPE_DELAY_MS" --clearmodifiers "$AUTH_EXPLORE_SEARCH_TEXT"
  else
    DISPLAY="$DISPLAY_ID" xdotool key --delay "$AUTH_EXPLORE_SEARCH_TYPE_DELAY_MS" --clearmodifiers "${search_key_sequence[@]}"
  fi
  sleep "$AUTH_EXPLORE_SEARCH_AFTER_TYPE_SETTLE_SECONDS"
  if [[ -n "${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_TYPED_SCREENSHOT:-}" ]]; then
    mkdir -p "$(dirname "$QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_TYPED_SCREENSHOT")"
    DISPLAY="$DISPLAY_ID" import -window "$window_id" "$QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_TYPED_SCREENSHOT"
  fi
}

wait_for_authenticated_composer_dismissal() {
  case "$AUTH_COMPOSER_DISMISS_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_DISMISS_TIMEOUT_SECONDS must be a non-negative integer, got: $AUTH_COMPOSER_DISMISS_TIMEOUT_SECONDS" >&2
      exit 2
      ;;
  esac

  local deadline candidate
  deadline="$(($(date +%s) + AUTH_COMPOSER_DISMISS_TIMEOUT_SECONDS))"
  while true; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for authenticated composer dismissal." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    candidate="$(quillui_find_visible_window_for_pid_except "$DISPLAY_ID" "$app_pid" "$window_id")"
    trace_visual_window "composer-dismiss-candidate" "$candidate"
    if ! quillui_window_is_plausible_capture_target "$DISPLAY_ID" "$candidate" "$window_id"; then
      capture_window_id="$window_id"
      DISPLAY="$DISPLAY_ID" xdotool windowraise "$window_id" 2>/dev/null || true
      DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$window_id" 2>/dev/null || true
      DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$window_id" 2>/dev/null || true
      trace_visual_window "composer-dismiss-main-capture" "$capture_window_id"
      trace_visual_windows_for_pid "composer-dismiss-visible"
      return 0
    fi

    if (($(date +%s) >= deadline)); then
      echo "Timed out waiting for IceCubes authenticated composer dismissal." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.25
  done
}

wait_for_authenticated_composer_submit_after_click() {
  local min_count="$1"
  local polls="$AUTH_COMPOSER_SEND_CLICK_RETRY_POLLS"

  case "$polls" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_CLICK_RETRY_POLLS must be a non-negative integer, got: $polls" >&2
      exit 2
      ;;
  esac

  if ((polls == 0)); then
    polls=1
  fi

  for _ in $(seq 1 "$polls"); do
    if (( $(count_app_log_occurrences "POST https://mastodon.social/api/v1/statuses") >= min_count )); then
      return 0
    fi
    sleep "$AUTH_COMPOSER_SEND_CLICK_RETRY_POLL_SECONDS"
  done

  (( $(count_app_log_occurrences "POST https://mastodon.social/api/v1/statuses") >= min_count ))
}

click_authenticated_composer_send_button() {
  local min_count="$1"
  local point point_x point_y

  for point in $AUTH_COMPOSER_SEND_POINTS; do
    if [[ "$point" != *,* ]]; then
      echo "Invalid QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_POINTS entry: $point" >&2
      exit 2
    fi
    point_x="${point%,*}"
    point_y="${point#*,}"
    case "$point_x" in
      ''|*[!0-9]*)
        echo "Invalid QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_POINTS entry: $point" >&2
        exit 2
        ;;
    esac
    case "$point_y" in
      ''|*[!0-9]*)
        echo "Invalid QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_POINTS entry: $point" >&2
        exit 2
        ;;
    esac

    click_capture_window_point "$point_x" "$point_y"
    if wait_for_authenticated_composer_submit_after_click "$min_count"; then
      return 0
    fi
  done

  echo "Timed out waiting for IceCubes authenticated composer status create activity." >&2
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
  exit 1
}

submit_authenticated_composer_text() {
  local previous_submit_count
  previous_submit_count="$(count_app_log_occurrences "POST https://mastodon.social/api/v1/statuses")"
  type_authenticated_composer_text
  click_authenticated_composer_send_button "$((previous_submit_count + 1))"
  wait_for_authenticated_composer_dismissal
}

verify_oauth_open_url_log() {
  python3 - "$OPEN_URL_LOG_PATH" <<'PY'
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

path = Path(sys.argv[1])
if not path.exists() or path.stat().st_size == 0:
    raise SystemExit(f"IceCubes OAuth open URL log was not written: {path}")

urls = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
if not urls:
    raise SystemExit(f"IceCubes OAuth open URL log is empty: {path}")

url = urls[-1]
parsed = urlparse(url)
query = parse_qs(parsed.query)

def require(condition, message):
    if not condition:
        raise SystemExit(message)

require(parsed.scheme == "https", f"OAuth URL scheme mismatch: {url}")
require(parsed.netloc == "mastodon.social", f"OAuth URL host mismatch: {url}")
require(parsed.path == "/oauth/authorize", f"OAuth URL path mismatch: {url}")
require(query.get("response_type") == ["code"], f"OAuth response_type missing/mismatched: {query}")
require(query.get("redirect_uri") == ["icecubesapp://"], f"OAuth redirect_uri missing/mismatched: {query}")
require(query.get("client_id", [""])[0], f"OAuth client_id missing: {query}")
scope = query.get("scope", [""])[0].split()
require({"read", "write", "follow", "push"}.issubset(scope), f"OAuth scope incomplete: {scope}")
print(f"IceCubes OAuth open URL: {url}")
PY
}

wait_for_oauth_open_url_log() {
  local retry_click="${1:-0}"
  case "$SIGN_IN_OPEN_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_SIGN_IN_OPEN_TIMEOUT_SECONDS must be a non-negative integer, got: $SIGN_IN_OPEN_TIMEOUT_SECONDS" >&2
      exit 2
      ;;
  esac

  local deadline next_retry_click output
  deadline="$(($(date +%s) + SIGN_IN_OPEN_TIMEOUT_SECONDS))"
  next_retry_click=$((SECONDS + 2))
  output=""
  while true; do
    if output="$(verify_oauth_open_url_log 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    fi
    if [[ "$retry_click" == "retry-click" ]] && ((SECONDS >= next_retry_click)); then
      echo "IceCubes OAuth open URL log is not ready yet; retrying Sign In click." >&2
      click_app_window_point "$SIGN_IN_X" "$SIGN_IN_Y"
      next_retry_click=$((SECONDS + 2))
    fi
    if (($(date +%s) >= deadline)); then
      printf '%s\n' "$output" >&2
      return 1
    fi
    sleep 0.5
  done
}

wait_for_authenticated_timeline_activity() {
  wait_for_authenticated_api_activity "/api/v1/timelines/home" "authenticated timeline" 1
}

count_app_log_occurrences() {
  local pattern="$1"
  if [[ -f "$APP_LOG_PATH" ]]; then
    grep -F -c "$pattern" "$APP_LOG_PATH" || true
  else
    echo 0
  fi
}

count_app_log_exact_occurrences() {
  local line="$1"
  if [[ -f "$APP_LOG_PATH" ]]; then
    grep -F -x -c "$line" "$APP_LOG_PATH" || true
  else
    echo 0
  fi
}

count_authenticated_status_detail_bookmark_actions() {
  local primary_count secondary_count
  primary_count="$(count_app_log_occurrences "$AUTH_STATUS_DETAIL_BOOKMARK_POST_LOG")"
  secondary_count="$(count_app_log_occurrences "$AUTH_STATUS_DETAIL_SECONDARY_BOOKMARK_POST_LOG")"
  echo "$((primary_count + secondary_count))"
}

wait_for_authenticated_status_detail_bookmark_action() {
  local expected_bookmark_count="$1"
  local deadline=$((SECONDS + ${QUILLUI_ICECUBES_VISUAL_AUTH_WAIT_SECONDS:-12}))
  while true; do
    if (( $(count_authenticated_status_detail_bookmark_actions) >= expected_bookmark_count )); then
      return 0
    fi
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for authenticated status bookmark action activity." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for IceCubes authenticated status bookmark action activity." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.25
  done
}

wait_for_app_log_activity() {
  local pattern="$1"
  local label="$2"
  local min_count="${3:-1}"
  local deadline=$((SECONDS + ${QUILLUI_ICECUBES_VISUAL_AUTH_WAIT_SECONDS:-12}))
  while true; do
    if (( $(count_app_log_occurrences "$pattern") >= min_count )); then
      return 0
    fi
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for $label activity." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for IceCubes $label activity." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.25
  done
}

wait_for_app_log_exact_activity() {
  local line="$1"
  local label="$2"
  local min_count="${3:-1}"
  local deadline=$((SECONDS + ${QUILLUI_ICECUBES_VISUAL_AUTH_WAIT_SECONDS:-12}))
  while true; do
    if (( $(count_app_log_exact_occurrences "$line") >= min_count )); then
      return 0
    fi
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for $label activity." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for IceCubes $label activity." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.25
  done
}

wait_for_authenticated_api_activity() {
  local pattern="$1"
  local label="$2"
  local min_count="${3:-1}"
  wait_for_app_log_activity "$pattern" "$label" "$min_count"
}

wait_for_authenticated_compose_surface() {
  case "$AUTH_COMPOSE_WINDOW_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSE_WINDOW_TIMEOUT_SECONDS must be a non-negative integer, got: $AUTH_COMPOSE_WINDOW_TIMEOUT_SECONDS" >&2
      exit 2
      ;;
  esac

  local deadline candidate output probe_path
  deadline="$(($(date +%s) + AUTH_COMPOSE_WINDOW_TIMEOUT_SECONDS))"
  output=""
  probe_path="${SCREENSHOT_PATH%.*}.composer-ready.png"
  while true; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for authenticated composer surface." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    candidate="$(quillui_find_visible_window_for_pid_except "$DISPLAY_ID" "$app_pid" "$window_id")"
    trace_visual_window "compose-surface-candidate" "$candidate"
    if quillui_window_is_plausible_capture_target "$DISPLAY_ID" "$candidate" "$window_id"; then
      capture_window_id="$candidate"
      DISPLAY="$DISPLAY_ID" xdotool windowraise "$capture_window_id" 2>/dev/null || true
      DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$capture_window_id" 2>/dev/null || true
      DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$capture_window_id" 2>/dev/null || true
      trace_visual_window "compose-surface-capture" "$capture_window_id"
      trace_visual_windows_for_pid "compose-surface-visible"
      return 0
    fi

    if DISPLAY="$DISPLAY_ID" timeout 10 import -window "$window_id" "$probe_path"; then
      if output="$("$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "icecubes-linux-authenticated-composer" 2>&1)"; then
        printf '%s\n' "$output"
        capture_window_id="$window_id"
        trace_visual_window "compose-surface-main-capture" "$capture_window_id"
        trace_visual_windows_for_pid "compose-surface-visible"
        return 0
      fi
    else
      output="IceCubes authenticated composer readiness screenshot capture failed: $probe_path"
    fi

    if (($(date +%s) >= deadline)); then
      # Some GTK sheet modes present in the main window. Keep the original
      # capture target and let the visual verifier diagnose stale content.
      capture_window_id="$window_id"
      if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >&2
      fi
      trace_visual_window "compose-surface-main-capture" "$capture_window_id"
      trace_visual_windows_for_pid "compose-surface-visible"
      return 1
    fi
    sleep 0.25
  done
}

open_authenticated_composer_surface() {
  case "$AUTH_COMPOSE_CLICK_RETRIES" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSE_CLICK_RETRIES must be a positive integer, got: $AUTH_COMPOSE_CLICK_RETRIES" >&2
      exit 2
      ;;
  esac
  if ((AUTH_COMPOSE_CLICK_RETRIES <= 0)); then
    echo "QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSE_CLICK_RETRIES must be a positive integer, got: $AUTH_COMPOSE_CLICK_RETRIES" >&2
    exit 2
  fi

  wait_for_authenticated_timeline_activity

  local attempt=1
  while true; do
    click_app_window_point "$AUTH_COMPOSE_X" "$AUTH_COMPOSE_Y"
    if wait_for_authenticated_compose_surface; then
      return 0
    fi

    if ((attempt >= AUTH_COMPOSE_CLICK_RETRIES)); then
      echo "IceCubes authenticated compose button did not open the composer after $attempt attempts." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    attempt="$((attempt + 1))"
    sleep "$AUTH_COMPOSE_CLICK_RETRY_SECONDS"
  done
}

click_authenticated_list_sidebar_row() {
  local expected_count="$1"
  local attempt

  for attempt in $(seq 1 "$AUTH_LIST_CLICK_RETRIES"); do
    click_app_window_point "$AUTH_LIST_X" "$AUTH_LIST_Y"
    sleep "$AUTH_LIST_CLICK_RETRY_SECONDS"
    if (( $(count_app_log_occurrences "$AUTH_LIST_ENDPOINT") >= expected_count )); then
      return 0
    fi
  done
}

click_authenticated_messages_sidebar_row() {
  local expected_count="$1"
  local attempt

  for attempt in $(seq 1 "$AUTH_MESSAGES_CLICK_RETRIES"); do
    click_app_window_point "$AUTH_MESSAGES_X" "$AUTH_MESSAGES_Y"
    sleep "$AUTH_MESSAGES_CLICK_RETRY_SECONDS"
    if (( $(count_app_log_occurrences "$AUTH_MESSAGES_ENDPOINT") >= expected_count )); then
      return 0
    fi
  done

  return 1
}

click_authenticated_profile_sidebar_row() {
  local expected_count="$1"
  local attempt

  for attempt in $(seq 1 "$AUTH_PROFILE_CLICK_RETRIES"); do
    click_app_window_point "$AUTH_PROFILE_X" "$AUTH_PROFILE_Y"
    sleep "$AUTH_PROFILE_CLICK_RETRY_SECONDS"
    if (( $(count_app_log_occurrences "$AUTH_PROFILE_STATUSES_ENDPOINT") >= expected_count )); then
      return 0
    fi
  done

  return 1
}

wait_for_authenticated_route_visual() {
  local product="$1"
  local label="$2"

  case "$AUTH_ROUTE_VISUAL_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_ROUTE_VISUAL_TIMEOUT_SECONDS must be a non-negative integer, got: $AUTH_ROUTE_VISUAL_TIMEOUT_SECONDS" >&2
      exit 2
      ;;
  esac

  local deadline output probe_path
  deadline="$(($(date +%s) + AUTH_ROUTE_VISUAL_TIMEOUT_SECONDS))"
  output=""
  probe_path="${SCREENSHOT_PATH%.*}.${product}-ready.png"

  while true; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for $label pixels." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    if DISPLAY="$DISPLAY_ID" timeout 10 import -window "$window_id" "$probe_path"; then
      if output="$("$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "$product" 2>&1)"; then
        printf '%s\n' "$output"
        return 0
      fi
    else
      output="IceCubes $label readiness screenshot capture failed: $probe_path"
    fi

    if (($(date +%s) >= deadline)); then
      echo "Timed out waiting for IceCubes $label pixels." >&2
      printf '%s\n' "$output" >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.5
  done
}

should_retry_final_visual_capture() {
  case "$INTERACTION" in
    seeded-authenticated-explore|seeded-authenticated-explore-links|seeded-authenticated-explore-posts|seeded-authenticated-explore-tags|seeded-authenticated-explore-suggested-users|seeded-authenticated-explore-search)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

capture_and_verify_final_visual() {
  local retry="$1"
  local deadline output verify_status traced
  output=""
  verify_status=1
  traced=0

  if [[ "$retry" == "1" ]]; then
    case "$FINAL_CAPTURE_RETRY_TIMEOUT_SECONDS" in
      ''|*[!0-9]*)
        echo "QUILLUI_ICECUBES_VISUAL_FINAL_CAPTURE_RETRY_TIMEOUT_SECONDS must be a non-negative integer, got: $FINAL_CAPTURE_RETRY_TIMEOUT_SECONDS" >&2
        exit 2
        ;;
    esac
    deadline="$(($(date +%s) + FINAL_CAPTURE_RETRY_TIMEOUT_SECONDS))"
  else
    deadline="$(date +%s)"
  fi

  while true; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited before screenshot capture." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    if [[ "$traced" == "0" ]]; then
      trace_visual_window "final-capture" "$capture_window_id"
      trace_visual_windows_for_pid "final-visible"
      traced=1
    fi

    if ! DISPLAY="$DISPLAY_ID" timeout 10 import -window "$capture_window_id" "$SCREENSHOT_PATH"; then
      echo "IceCubes screenshot capture failed." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    if output="$("$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT" 2>&1)"; then
      printf '%s\n' "$output"
      echo "IceCubes visual screenshot: $SCREENSHOT_PATH"
      return 0
    else
      verify_status=$?
    fi

    if [[ "$retry" != "1" || $(date +%s) -ge "$deadline" ]]; then
      printf '%s\n' "$output" >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit "$verify_status"
    fi

    sleep 0.5
  done
}

wait_for_authenticated_home_row_visual() {
  case "$AUTH_STATUS_DETAIL_ROW_READY_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_ROW_READY_TIMEOUT_SECONDS must be a non-negative integer, got: $AUTH_STATUS_DETAIL_ROW_READY_TIMEOUT_SECONDS" >&2
      exit 2
      ;;
  esac

  local deadline output probe_path
  deadline="$(($(date +%s) + AUTH_STATUS_DETAIL_ROW_READY_TIMEOUT_SECONDS))"
  output=""
  probe_path="${SCREENSHOT_PATH%.*}.home-row-ready.png"

  while true; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for authenticated home row pixels." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    if DISPLAY="$DISPLAY_ID" timeout 10 import -window "$window_id" "$probe_path"; then
      if output="$("$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "icecubes-linux-authenticated-home-row-ready" 2>&1)"; then
        printf '%s\n' "$output"
        return 0
      fi
    else
      output="IceCubes authenticated home row readiness screenshot capture failed: $probe_path"
    fi

    if (($(date +%s) >= deadline)); then
      echo "Timed out waiting for IceCubes authenticated home row pixels." >&2
      printf '%s\n' "$output" >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.5
  done
}

wait_for_authenticated_status_detail_visual() {
  local deadline output probe_path
  deadline="$(($(date +%s) + AUTH_STATUS_DETAIL_NAVIGATION_TIMEOUT_SECONDS))"
  output=""
  probe_path="${SCREENSHOT_PATH%.*}.status-detail-ready.png"

  while true; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for authenticated status detail pixels." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    if DISPLAY="$DISPLAY_ID" timeout 10 import -window "$window_id" "$probe_path"; then
      if output="$("$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "icecubes-linux-authenticated-status-detail" 2>&1)"; then
        printf '%s\n' "$output"
        return 0
      fi
    else
      output="IceCubes authenticated status detail readiness screenshot capture failed: $probe_path"
    fi

    if (($(date +%s) >= deadline)); then
      echo "Timed out waiting for IceCubes authenticated status detail pixels." >&2
      printf '%s\n' "$output" >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.5
  done
}

wait_for_authenticated_media_viewer_visual() {
  case "$AUTH_MEDIA_VIEWER_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_MEDIA_VIEWER_TIMEOUT_SECONDS must be a non-negative integer, got: $AUTH_MEDIA_VIEWER_TIMEOUT_SECONDS" >&2
      exit 2
      ;;
  esac

  local deadline candidate output probe_path
  deadline="$(($(date +%s) + AUTH_MEDIA_VIEWER_TIMEOUT_SECONDS))"
  output=""
  probe_path="${SCREENSHOT_PATH%.*}.media-viewer-ready.png"

  while true; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      echo "IceCubes app exited while waiting for authenticated media viewer pixels." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi

    candidate="$(quillui_find_visible_window_for_pid_except "$DISPLAY_ID" "$app_pid" "$window_id")"
    trace_visual_window "media-viewer-candidate" "$candidate"
    if quillui_window_is_plausible_capture_target "$DISPLAY_ID" "$candidate" "$window_id"; then
      if DISPLAY="$DISPLAY_ID" timeout 10 import -window "$candidate" "$probe_path"; then
        if output="$("$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "icecubes-linux-authenticated-media-viewer" 2>&1)"; then
          printf '%s\n' "$output"
          capture_window_id="$candidate"
          trace_visual_window "media-viewer-window-capture" "$capture_window_id"
          trace_visual_windows_for_pid "media-viewer-visible"
          return 0
        fi
      fi
    fi

    if DISPLAY="$DISPLAY_ID" timeout 10 import -window "$window_id" "$probe_path"; then
      if output="$("$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "icecubes-linux-authenticated-media-viewer" 2>&1)"; then
        printf '%s\n' "$output"
        capture_window_id="$window_id"
        trace_visual_window "media-viewer-main-capture" "$capture_window_id"
        trace_visual_windows_for_pid "media-viewer-visible"
        return 0
      fi
    else
      output="IceCubes authenticated media viewer readiness screenshot capture failed: $probe_path"
    fi

    if (($(date +%s) >= deadline)); then
      echo "Timed out waiting for IceCubes authenticated media viewer pixels." >&2
      printf '%s\n' "$output" >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    sleep 0.5
  done
}

wait_for_status_detail_request_after_click() {
  local target_status_count="$1"
  local target_context_count="$2"
  local poll_count="$AUTH_STATUS_DETAIL_CLICK_RETRY_POLLS"

  case "$poll_count" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_CLICK_RETRY_POLLS must be a non-negative integer, got: $poll_count" >&2
      exit 2
      ;;
  esac

  if (( poll_count == 0 )); then
    poll_count=1
  fi

  for _ in $(seq 1 "$poll_count"); do
    if (( $(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_GET_LOG") >= target_status_count )) \
      && (( $(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_CONTEXT_GET_LOG") >= target_context_count )); then
      return 0
    fi
    sleep "$AUTH_STATUS_DETAIL_CLICK_RETRY_POLL_SECONDS"
  done

  (( $(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_GET_LOG") >= target_status_count )) \
    && (( $(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_CONTEXT_GET_LOG") >= target_context_count ))
}

click_authenticated_status_detail_row() {
  local target_status_count="$1"
  local target_context_count="$2"
  local retries="$AUTH_STATUS_DETAIL_CLICK_RETRIES"

  case "$retries" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_CLICK_RETRIES must be a non-negative integer, got: $retries" >&2
      exit 2
      ;;
  esac

  if (( retries == 0 )); then
    retries=1
  fi

  for _ in $(seq 1 "$retries"); do
    click_app_window_point "$AUTH_STATUS_DETAIL_X" "$AUTH_STATUS_DETAIL_Y"
    if wait_for_status_detail_request_after_click "$target_status_count" "$target_context_count"; then
      return 0
    fi
    sleep "$AUTH_STATUS_DETAIL_CLICK_RETRY_SECONDS"
  done

  return 1
}

click_authenticated_status_detail_boost_action() {
  local expected_boost_count="$1"
  local y menu_y

  for layout in media legacy; do
    if [[ "$layout" == "media" ]]; then
      y="$AUTH_STATUS_DETAIL_BOOST_Y"
      menu_y="$AUTH_STATUS_DETAIL_BOOST_MENU_Y"
    else
      y="170"
      menu_y="215"
    fi

    click_app_window_point "$AUTH_STATUS_DETAIL_BOOST_X" "$y"
    sleep "${QUILLUI_ICECUBES_VISUAL_BOOST_MENU_OPEN_SETTLE_SECONDS:-0.2}"
    if [[ -n "${QUILLUI_ICECUBES_VISUAL_BOOST_MENU_OPEN_SCREENSHOT:-}" ]]; then
      DISPLAY="$DISPLAY_ID" import -window root "$QUILLUI_ICECUBES_VISUAL_BOOST_MENU_OPEN_SCREENSHOT"
    fi
    if [[ "${QUILLUI_ICECUBES_VISUAL_EXIT_AFTER_BOOST_MENU_OPEN:-0}" == "1" ]]; then
      exit 0
    fi
    click_app_window_relative_screen_point "$AUTH_STATUS_DETAIL_BOOST_MENU_X" "$menu_y"
    sleep "${QUILLUI_ICECUBES_VISUAL_STATUS_ACTION_SETTLE_SECONDS:-0.75}"
    if (( $(count_app_log_occurrences "POST https://mastodon.social/api/v1/statuses/1003/reblog") >= expected_boost_count )); then
      return 0
    fi
  done

  return 1
}

click_authenticated_status_detail_quote_action() {
  local y menu_y

  for layout in media legacy; do
    if [[ "$layout" == "media" ]]; then
      y="$AUTH_STATUS_DETAIL_BOOST_Y"
      menu_y="$AUTH_STATUS_DETAIL_QUOTE_MENU_Y"
    else
      y="170"
      menu_y="258"
    fi

    click_app_window_point "$AUTH_STATUS_DETAIL_BOOST_X" "$y"
    sleep "${QUILLUI_ICECUBES_VISUAL_BOOST_MENU_OPEN_SETTLE_SECONDS:-0.2}"
    click_app_window_relative_screen_point "$AUTH_STATUS_DETAIL_QUOTE_MENU_X" "$menu_y"
    if wait_for_authenticated_compose_surface; then
      return 0
    fi
  done

  return 1
}

click_authenticated_status_detail_reply_action() {
  for y in "$AUTH_STATUS_DETAIL_REPLY_Y" 462 170; do
    click_app_window_point "$AUTH_STATUS_DETAIL_REPLY_X" "$y"
    if wait_for_authenticated_compose_surface; then
      return 0
    fi
    DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Escape 2>/dev/null || true
    sleep "${QUILLUI_ICECUBES_VISUAL_STATUS_ACTION_SETTLE_SECONDS:-0.75}"
  done

  return 1
}

click_authenticated_status_detail_favorite_action() {
  local expected_favorite_count="$1"

  for y in "$AUTH_STATUS_DETAIL_FAVORITE_Y" 170; do
    click_app_window_point "$AUTH_STATUS_DETAIL_FAVORITE_X" "$y"
    sleep "${QUILLUI_ICECUBES_VISUAL_STATUS_ACTION_SETTLE_SECONDS:-0.75}"
    if (( $(count_app_log_occurrences "POST https://mastodon.social/api/v1/statuses/1003/favourite") >= expected_favorite_count )); then
      return 0
    fi
  done

  return 1
}

click_authenticated_status_detail_bookmark_action() {
  local expected_bookmark_count="$1"

  for y in "$AUTH_STATUS_DETAIL_SECONDARY_BOOKMARK_Y" 170; do
    click_app_window_point "$AUTH_STATUS_DETAIL_SECONDARY_BOOKMARK_X" "$y"
    sleep "${QUILLUI_ICECUBES_VISUAL_STATUS_ACTION_SETTLE_SECONDS:-0.75}"
    if (( $(count_authenticated_status_detail_bookmark_actions) >= expected_bookmark_count )); then
      return 0
    fi
  done

  return 1
}

open_authenticated_status_detail() {
  wait_for_authenticated_timeline_activity
  local previous_status_count previous_context_count target_status_count target_context_count
  previous_status_count="$(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_GET_LOG")"
  previous_context_count="$(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_CONTEXT_GET_LOG")"
  target_status_count="$((previous_status_count + 1))"
  target_context_count="$((previous_context_count + 1))"
  sleep "$AUTH_STATUS_DETAIL_PRE_CLICK_DELAY_SECONDS"

  case "$AUTH_STATUS_DETAIL_NAVIGATION_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_NAVIGATION_TIMEOUT_SECONDS must be a non-negative integer, got: $AUTH_STATUS_DETAIL_NAVIGATION_TIMEOUT_SECONDS" >&2
      exit 2
      ;;
  esac

  wait_for_authenticated_home_row_visual
  if ! click_authenticated_status_detail_row "$target_status_count" "$target_context_count"; then
    echo "Timed out waiting for IceCubes authenticated status detail navigation after row click." >&2
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
    exit 1
  fi

  wait_for_app_log_exact_activity "$AUTH_STATUS_DETAIL_GET_LOG" "authenticated status detail fetch" "$target_status_count"
  wait_for_app_log_exact_activity "$AUTH_STATUS_DETAIL_CONTEXT_GET_LOG" "authenticated status context fetch" "$target_context_count"
  wait_for_authenticated_status_detail_visual
  if [[ -n "${QUILLUI_ICECUBES_VISUAL_STATUS_DETAIL_OPEN_SCREENSHOT:-}" ]]; then
    DISPLAY="$DISPLAY_ID" import -window "$window_id" "$QUILLUI_ICECUBES_VISUAL_STATUS_DETAIL_OPEN_SCREENSHOT"
  fi
  if [[ "${QUILLUI_ICECUBES_VISUAL_EXIT_AFTER_STATUS_DETAIL_OPEN:-0}" == "1" ]]; then
    exit 0
  fi
}

wait_for_authenticated_status_detail_action_accounts() {
  local target_favorited_by_count="$1"
  local target_reblogged_by_count="${2:-}"

  wait_for_app_log_exact_activity \
    "$AUTH_STATUS_DETAIL_FAVORITED_BY_GET_LOG" \
    "authenticated status detail favorited-by fetch" \
    "$target_favorited_by_count"

  if [[ -n "$target_reblogged_by_count" ]]; then
    wait_for_app_log_exact_activity \
      "$AUTH_STATUS_DETAIL_REBLOGGED_BY_GET_LOG" \
      "authenticated status detail reblogged-by fetch" \
      "$target_reblogged_by_count"
  fi
}

open_authenticated_explore_route() {
  wait_for_authenticated_timeline_activity
  wait_for_authenticated_home_row_visual
  local previous_suggestions_count previous_tags_count previous_trending_statuses_count previous_links_count previous_suggested_relationships_count
  previous_suggestions_count="$(count_app_log_occurrences "/api/v1/suggestions")"
  previous_tags_count="$(count_app_log_occurrences "/api/v1/trends/tags")"
  previous_trending_statuses_count="$(count_app_log_occurrences "/api/v1/trends/statuses")"
  previous_links_count="$(count_app_log_occurrences "/api/v1/trends/links")"
  previous_suggested_relationships_count="$(count_app_log_occurrences "$AUTH_EXPLORE_SUGGESTED_RELATIONSHIPS_ENDPOINT")"
  click_app_window_point "$AUTH_EXPLORE_X" "$AUTH_EXPLORE_Y"
  wait_for_authenticated_api_activity "/api/v1/suggestions" "authenticated Explore suggestions" "$((previous_suggestions_count + 1))"
  wait_for_authenticated_api_activity "/api/v1/trends/tags" "authenticated Explore trending tags" "$((previous_tags_count + 1))"
  wait_for_authenticated_api_activity "/api/v1/trends/statuses" "authenticated Explore trending posts" "$((previous_trending_statuses_count + 1))"
  wait_for_authenticated_api_activity "/api/v1/trends/links" "authenticated Explore trending links" "$((previous_links_count + 1))"
  wait_for_authenticated_api_activity "$AUTH_EXPLORE_SUGGESTED_RELATIONSHIPS_ENDPOINT" "authenticated Explore suggested account relationships" "$((previous_suggested_relationships_count + 1))"
  wait_for_authenticated_route_visual "icecubes-linux-authenticated-explore" "authenticated Explore route"
}

open_authenticated_notifications_route() {
  wait_for_authenticated_timeline_activity
  wait_for_authenticated_home_row_visual
  local previous_notifications_count previous_notifications_refresh_count
  previous_notifications_count="$(count_app_log_occurrences "$AUTH_NOTIFICATIONS_INITIAL_ENDPOINT")"
  previous_notifications_refresh_count="$(count_app_log_occurrences "$AUTH_NOTIFICATIONS_REFRESH_ENDPOINT")"
  click_app_window_point "$AUTH_NOTIFICATIONS_X" "$AUTH_NOTIFICATIONS_Y"
  wait_for_authenticated_api_activity "$AUTH_NOTIFICATIONS_INITIAL_ENDPOINT" "authenticated Notifications sidebar navigation" "$((previous_notifications_count + 1))"
  wait_for_authenticated_api_activity "$AUTH_NOTIFICATIONS_REFRESH_ENDPOINT" "authenticated Notifications display refresh" "$((previous_notifications_refresh_count + 1))"
}

open_authenticated_messages_route() {
  wait_for_authenticated_timeline_activity
  wait_for_authenticated_home_row_visual
  local previous_conversations_count expected_conversations_count
  previous_conversations_count="$(count_app_log_occurrences "$AUTH_MESSAGES_ENDPOINT")"
  expected_conversations_count="$((previous_conversations_count + 1))"
  if ! click_authenticated_messages_sidebar_row "$expected_conversations_count"; then
    wait_for_authenticated_api_activity "$AUTH_MESSAGES_ENDPOINT" "authenticated Messages sidebar navigation" "$expected_conversations_count"
  fi
}

open_authenticated_messages_detail_route() {
  open_authenticated_messages_route
  wait_for_authenticated_route_visual "icecubes-linux-authenticated-messages" "authenticated Messages route"
  local previous_read_count previous_context_count
  previous_read_count="$(count_app_log_exact_occurrences "$AUTH_MESSAGES_DETAIL_READ_LOG")"
  previous_context_count="$(count_app_log_exact_occurrences "$AUTH_MESSAGES_DETAIL_CONTEXT_LOG")"
  click_app_window_point "$AUTH_MESSAGES_DETAIL_X" "$AUTH_MESSAGES_DETAIL_Y"
  wait_for_app_log_exact_activity "$AUTH_MESSAGES_DETAIL_READ_LOG" "authenticated Messages detail mark-read" "$((previous_read_count + 1))"
  wait_for_app_log_exact_activity "$AUTH_MESSAGES_DETAIL_CONTEXT_LOG" "authenticated Messages detail context fetch" "$((previous_context_count + 1))"
}

open_authenticated_list_route() {
  wait_for_authenticated_timeline_activity
  wait_for_authenticated_home_row_visual
  wait_for_authenticated_api_activity "/api/v1/lists" "authenticated Lists bootstrap" 1
  sleep "$AUTH_LIST_REPAINT_SETTLE_SECONDS"
  local previous_list_timeline_count expected_list_timeline_count
  previous_list_timeline_count="$(count_app_log_occurrences "$AUTH_LIST_ENDPOINT")"
  expected_list_timeline_count="$((previous_list_timeline_count + 1))"
  if ! click_authenticated_list_sidebar_row "$expected_list_timeline_count"; then
    wait_for_authenticated_api_activity "$AUTH_LIST_ENDPOINT" "authenticated List sidebar navigation" "$expected_list_timeline_count"
  fi
}

open_authenticated_settings_route() {
  wait_for_authenticated_timeline_activity
  wait_for_authenticated_home_row_visual
  click_app_window_point "$AUTH_SETTINGS_X" "$AUTH_SETTINGS_Y"
  wait_for_authenticated_route_visual "icecubes-linux-authenticated-settings" "authenticated Settings route"
}

scroll_authenticated_settings_content() {
  local clicks="$1"
  local label="${2:-QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_SCROLL_CLICKS}"

  case "$clicks" in
    ''|*[!0-9]*)
      echo "$label must be a non-negative integer, got: $clicks" >&2
      exit 2
      ;;
  esac

  if (( clicks <= 0 )); then
    return 0
  fi

  for _ in $(seq 1 "$clicks"); do
    DISPLAY="$DISPLAY_ID" xdotool mousemove "$AUTH_SETTINGS_SCROLL_X" "$AUTH_SETTINGS_SCROLL_Y" click 5
    sleep 0.1
  done
  sleep "$AUTH_SETTINGS_CHILD_CLICK_SETTLE_SECONDS"
}

open_authenticated_settings_display_route() {
  open_authenticated_settings_route
  scroll_authenticated_settings_content "$AUTH_SETTINGS_DISPLAY_SCROLL_CLICKS"
  click_app_window_point "$AUTH_SETTINGS_DISPLAY_X" "$AUTH_SETTINGS_DISPLAY_Y"
  sleep "$AUTH_SETTINGS_DISPLAY_ROUTE_SETTLE_SECONDS"
  read -r -a settings_display_scroll_keys <<<"$AUTH_SETTINGS_DISPLAY_CONTROLS_SCROLL_KEYS"
  if ((${#settings_display_scroll_keys[@]} == 0)); then
    echo "QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_CONTROLS_SCROLL_KEYS must contain at least one xdotool key name." >&2
    exit 1
  fi
  DISPLAY="$DISPLAY_ID" xdotool key \
    --delay "$AUTH_SETTINGS_DISPLAY_CONTROLS_KEY_DELAY_MS" \
    --clearmodifiers "${settings_display_scroll_keys[@]}"
  wait_for_authenticated_route_visual "icecubes-linux-authenticated-settings-display" "authenticated Settings Display route"
}

drag_authenticated_settings_display_font_scale() {
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$AUTH_SETTINGS_DISPLAY_FONT_SCALE_START_X" "$AUTH_SETTINGS_DISPLAY_FONT_SCALE_Y"
  sleep "$CLICK_HOLD_SECONDS"
  DISPLAY="$DISPLAY_ID" xdotool mousedown 1
  sleep "$CLICK_HOLD_SECONDS"
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$AUTH_SETTINGS_DISPLAY_FONT_SCALE_END_X" "$AUTH_SETTINGS_DISPLAY_FONT_SCALE_Y"
  sleep "$CLICK_HOLD_SECONDS"
  DISPLAY="$DISPLAY_ID" xdotool mouseup 1
  sleep "$AUTH_SETTINGS_DISPLAY_FONT_SCALE_SETTLE_SECONDS"
}

toggle_authenticated_settings_display_system_color() {
  click_app_window_point "$AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_X" "$AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_Y"
  sleep "$AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_SETTLE_SECONDS"
}

select_authenticated_settings_display_font_picker() {
  click_app_window_point "$AUTH_SETTINGS_DISPLAY_FONT_PICKER_X" "$AUTH_SETTINGS_DISPLAY_FONT_PICKER_Y"
  read -r -a font_picker_keys <<<"$AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEYS"
  if ((${#font_picker_keys[@]} == 0)); then
    echo "QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEYS must contain at least one xdotool key name." >&2
    exit 1
  fi
  DISPLAY="$DISPLAY_ID" xdotool key --delay "$AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEY_DELAY_MS" --clearmodifiers "${font_picker_keys[@]}"
  sleep "$AUTH_SETTINGS_DISPLAY_FONT_PICKER_SETTLE_SECONDS"
}

select_authenticated_settings_display_font_picker_inter() {
  select_authenticated_settings_display_font_picker
  wait_for_authenticated_route_visual "icecubes-linux-authenticated-settings-display-font-picker" "authenticated Settings Display font-picker route"
  click_app_window_point "$AUTH_SETTINGS_DISPLAY_FONT_PICKER_INTER_X" "$AUTH_SETTINGS_DISPLAY_FONT_PICKER_INTER_Y"
  sleep "$AUTH_SETTINGS_DISPLAY_FONT_PICKER_SELECT_SETTLE_SECONDS"
}

scroll_authenticated_timeline_for_pagination() {
  local clicks="$AUTH_TIMELINE_PAGINATION_SCROLL_CLICKS"
  local target_x="$AUTH_TIMELINE_PAGINATION_SCROLL_X"
  local target_y="$AUTH_TIMELINE_PAGINATION_SCROLL_Y"
  local key value window_x=0 window_y=0 window_width=0 window_height=0
  local max_x max_y screen_x screen_y

  case "$clicks" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_TIMELINE_PAGINATION_SCROLL_CLICKS must be a non-negative integer, got: $clicks" >&2
      exit 2
      ;;
  esac
  case "$target_x" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_TIMELINE_PAGINATION_SCROLL_X must be a non-negative integer, got: $target_x" >&2
      exit 2
      ;;
  esac
  case "$target_y" in
    ''|*[!0-9]*)
      echo "QUILLUI_ICECUBES_VISUAL_AUTH_TIMELINE_PAGINATION_SCROLL_Y must be a non-negative integer, got: $target_y" >&2
      exit 2
      ;;
  esac

  if (( clicks <= 0 )); then
    return 0
  fi

  DISPLAY="$DISPLAY_ID" xdotool windowraise "$window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$window_id" 2>/dev/null || true

  while IFS='=' read -r key value; do
    case "$key" in
      X) window_x="$value" ;;
      Y) window_y="$value" ;;
      WIDTH) window_width="$value" ;;
      HEIGHT) window_height="$value" ;;
    esac
  done < <(DISPLAY="$DISPLAY_ID" xdotool getwindowgeometry --shell "$window_id")

  max_x=$((window_width > 48 ? window_width - 24 : window_width))
  max_y=$((window_height > 96 ? window_height - 40 : window_height))
  if (( target_x > max_x )); then
    target_x="$max_x"
  fi
  if (( target_y > max_y )); then
    target_y="$max_y"
  fi
  screen_x="$((window_x + target_x))"
  screen_y="$((window_y + target_y))"

  for _ in $(seq 1 "$clicks"); do
    DISPLAY="$DISPLAY_ID" xdotool mousemove "$screen_x" "$screen_y" click 5
    sleep "$AUTH_TIMELINE_PAGINATION_SCROLL_SETTLE_SECONDS"
  done
}

trigger_authenticated_refresh_shortcut() {
  local endpoint_pattern="$1"
  local label="$2"
  local expected_count="$3"
  local previous_refresh_trigger_count expected_refresh_trigger_count attempt

  previous_refresh_trigger_count="$(count_app_log_occurrences "[QuillUI GTK Refreshable] trigger source=keyboard")"
  expected_refresh_trigger_count="$((previous_refresh_trigger_count + 1))"

  for attempt in $(seq 1 "$AUTH_REFRESH_KEY_RETRIES"); do
    DISPLAY="$DISPLAY_ID" xdotool windowraise "$window_id" 2>/dev/null || true
    DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$window_id" 2>/dev/null || true
    DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$window_id" 2>/dev/null || true
    DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+r
    sleep "$AUTH_REFRESH_KEY_SETTLE_SECONDS"

    if (( $(count_app_log_occurrences "$endpoint_pattern") >= expected_count )) \
      && (( $(count_app_log_occurrences "[QuillUI GTK Refreshable] trigger source=keyboard") >= expected_refresh_trigger_count )); then
      return 0
    fi
    sleep "$AUTH_REFRESH_KEY_RETRY_SECONDS"
  done

  wait_for_authenticated_api_activity "$endpoint_pattern" "$label" "$expected_count"
  wait_for_app_log_activity "[QuillUI GTK Refreshable] trigger source=keyboard" "$label shortcut" "$expected_refresh_trigger_count"
}

trigger_authenticated_home_refresh() {
  local expected_count="$1"

  trigger_authenticated_refresh_shortcut \
    "/api/v1/timelines/home?limit=50" \
    "authenticated Home refresh" \
    "$expected_count"
}

trigger_authenticated_status_detail_refresh() {
  local expected_status_count="$1"
  local expected_context_count="$2"
  local attempt

  for attempt in $(seq 1 "$AUTH_STATUS_DETAIL_REFRESH_KEY_RETRIES"); do
    DISPLAY="$DISPLAY_ID" xdotool windowraise "$window_id" 2>/dev/null || true
    DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$window_id" 2>/dev/null || true
    DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$window_id" 2>/dev/null || true
    DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+r
    sleep "$AUTH_REFRESH_KEY_SETTLE_SECONDS"
    if (( $(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_GET_LOG") >= expected_status_count )) \
      && (( $(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_CONTEXT_GET_LOG") >= expected_context_count )); then
      return 0
    fi
    sleep "$AUTH_STATUS_DETAIL_REFRESH_KEY_RETRY_SECONDS"
  done

  wait_for_app_log_exact_activity "$AUTH_STATUS_DETAIL_GET_LOG" "authenticated Status detail refresh" "$expected_status_count"
  wait_for_app_log_exact_activity "$AUTH_STATUS_DETAIL_CONTEXT_GET_LOG" "authenticated Status detail context refresh" "$expected_context_count"
}

VERIFY_PRODUCT="icecubes-linux-add-account"
case "$INTERACTION" in
  suggestions|'')
    ;;
  type-instance)
    type_instance_name
    VERIFY_PRODUCT="icecubes-linux-add-account-instance"
    wait_for_add_account_selected_instance_visual
    ;;
  sign-in-open)
    type_instance_name
    wait_for_add_account_selected_instance_visual
    click_app_window_point "$SIGN_IN_X" "$SIGN_IN_Y"
    wait_for_oauth_open_url_log retry-click
    VERIFY_PRODUCT="icecubes-linux-add-account-instance"
    ;;
  seeded-authenticated-shell)
    VERIFY_PRODUCT="icecubes-linux-authenticated-shell"
    wait_for_authenticated_timeline_activity
    wait_for_authenticated_home_row_visual
    ;;
  seeded-authenticated-home-pagination)
    VERIFY_PRODUCT="icecubes-linux-authenticated-home-pagination"
    wait_for_authenticated_timeline_activity
    wait_for_authenticated_home_row_visual
    scroll_authenticated_timeline_for_pagination
    wait_for_authenticated_api_activity "/api/v1/timelines/home?max_id=1001&limit=40" "authenticated Home timeline pagination"
    scroll_authenticated_timeline_for_pagination
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Home timeline pagination"
    ;;
  seeded-authenticated-home-refresh)
    VERIFY_PRODUCT="icecubes-linux-authenticated-home-refresh"
    wait_for_authenticated_timeline_activity
    wait_for_authenticated_home_row_visual
    previous_home_first_page_count="$(count_app_log_occurrences "/api/v1/timelines/home?limit=50")"
    trigger_authenticated_home_refresh "$((previous_home_first_page_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Home refresh"
    ;;
  seeded-authenticated-trending)
    VERIFY_PRODUCT="icecubes-linux-authenticated-trending"
    wait_for_authenticated_timeline_activity
    wait_for_authenticated_home_row_visual
    previous_trending_count="$(count_app_log_occurrences "/api/v1/trends/statuses")"
    click_app_window_point "$AUTH_TRENDING_X" "$AUTH_TRENDING_Y"
    wait_for_authenticated_api_activity "/api/v1/trends/statuses" "authenticated Trending sidebar navigation" "$((previous_trending_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Trending route"
    ;;
  seeded-authenticated-local)
    VERIFY_PRODUCT="icecubes-linux-authenticated-local"
    wait_for_authenticated_timeline_activity
    wait_for_authenticated_home_row_visual
    previous_local_count="$(count_app_log_occurrences "/api/v1/timelines/public?local=true&limit=50")"
    click_app_window_point "$AUTH_LOCAL_X" "$AUTH_LOCAL_Y"
    wait_for_authenticated_api_activity "/api/v1/timelines/public?local=true&limit=50" "authenticated Local sidebar navigation" "$((previous_local_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Local route"
    ;;
  seeded-authenticated-federated)
    VERIFY_PRODUCT="icecubes-linux-authenticated-federated"
    wait_for_authenticated_timeline_activity
    wait_for_authenticated_home_row_visual
    previous_federated_count="$(count_app_log_occurrences "/api/v1/timelines/public?local=false&limit=50")"
    click_app_window_point "$AUTH_FEDERATED_X" "$AUTH_FEDERATED_Y"
    wait_for_authenticated_api_activity "/api/v1/timelines/public?local=false&limit=50" "authenticated Federated sidebar navigation" "$((previous_federated_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Federated route"
    ;;
  seeded-authenticated-explore)
    VERIFY_PRODUCT="icecubes-linux-authenticated-explore"
    open_authenticated_explore_route
    ;;
  seeded-authenticated-explore-links)
    VERIFY_PRODUCT="icecubes-linux-authenticated-explore-links"
    open_authenticated_explore_route
    click_app_window_point "$AUTH_EXPLORE_LINKS_X" "$AUTH_EXPLORE_LINKS_Y"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Explore Links quick-access route"
    ;;
  seeded-authenticated-explore-posts)
    VERIFY_PRODUCT="icecubes-linux-authenticated-explore-posts"
    open_authenticated_explore_route
    click_app_window_point "$AUTH_EXPLORE_POSTS_X" "$AUTH_EXPLORE_POSTS_Y"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Explore Trending Posts quick-access route"
    ;;
  seeded-authenticated-explore-tags)
    VERIFY_PRODUCT="icecubes-linux-authenticated-explore-tags"
    open_authenticated_explore_route
    click_app_window_point "$AUTH_EXPLORE_TAGS_X" "$AUTH_EXPLORE_TAGS_Y"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Explore Tags quick-access route"
    ;;
  seeded-authenticated-explore-suggested-users)
    VERIFY_PRODUCT="icecubes-linux-authenticated-explore-suggested-users"
    open_authenticated_explore_route
    previous_suggested_relationships_count="$(count_app_log_occurrences "$AUTH_EXPLORE_SUGGESTED_RELATIONSHIPS_ENDPOINT")"
    click_app_window_point "$AUTH_EXPLORE_SUGGESTED_USERS_X" "$AUTH_EXPLORE_SUGGESTED_USERS_Y"
    wait_for_authenticated_api_activity "$AUTH_EXPLORE_SUGGESTED_RELATIONSHIPS_ENDPOINT" "authenticated Explore Suggested Users relationships" "$((previous_suggested_relationships_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Explore Suggested Users quick-access route"
    ;;
  seeded-authenticated-explore-search)
    VERIFY_PRODUCT="icecubes-linux-authenticated-explore-search"
    open_authenticated_explore_route
    previous_search_count="$(count_app_log_occurrences "/api/v2/search?q=quill&resolve=true")"
    previous_search_relationships_count="$(count_app_log_occurrences "/api/v1/accounts/relationships?id%5B%5D=search-account-1")"
    type_authenticated_explore_search_text
    wait_for_authenticated_api_activity "/api/v2/search?q=quill&resolve=true" "authenticated Explore search request" "$((previous_search_count + 1))"
    wait_for_authenticated_api_activity "/api/v1/accounts/relationships?id%5B%5D=search-account-1" "authenticated Explore search account relationships" "$((previous_search_relationships_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Explore search results"
    ;;
  seeded-authenticated-notifications)
    VERIFY_PRODUCT="icecubes-linux-authenticated-notifications"
    open_authenticated_notifications_route
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Notifications route"
    ;;
  seeded-authenticated-notifications-refresh)
    VERIFY_PRODUCT="icecubes-linux-authenticated-notifications-refresh"
    open_authenticated_notifications_route
    previous_notifications_refresh_count="$(count_app_log_occurrences "$AUTH_NOTIFICATIONS_REFRESH_ENDPOINT")"
    trigger_authenticated_refresh_shortcut \
      "$AUTH_NOTIFICATIONS_REFRESH_ENDPOINT" \
      "authenticated Notifications refresh" \
      "$((previous_notifications_refresh_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Notifications refresh"
    ;;
  seeded-authenticated-profile)
    VERIFY_PRODUCT="icecubes-linux-authenticated-profile"
    wait_for_authenticated_timeline_activity
    previous_profile_statuses_count="$(count_app_log_occurrences "$AUTH_PROFILE_STATUSES_ENDPOINT")"
    expected_profile_statuses_count="$((previous_profile_statuses_count + 1))"
    if ! click_authenticated_profile_sidebar_row "$expected_profile_statuses_count"; then
      echo "IceCubes authenticated Profile sidebar click did not trigger $AUTH_PROFILE_STATUSES_ENDPOINT after $AUTH_PROFILE_CLICK_RETRIES attempts" >&2
    fi
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Profile route"
    ;;
  seeded-authenticated-messages)
    VERIFY_PRODUCT="icecubes-linux-authenticated-messages"
    open_authenticated_messages_route
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Messages route"
    ;;
  seeded-authenticated-messages-refresh)
    VERIFY_PRODUCT="icecubes-linux-authenticated-messages-refresh"
    open_authenticated_messages_route
    previous_conversations_count="$(count_app_log_occurrences "$AUTH_MESSAGES_ENDPOINT")"
    trigger_authenticated_refresh_shortcut \
      "$AUTH_MESSAGES_ENDPOINT" \
      "authenticated Messages refresh" \
      "$((previous_conversations_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Messages refresh"
    ;;
  seeded-authenticated-messages-detail)
    VERIFY_PRODUCT="icecubes-linux-authenticated-messages-detail"
    open_authenticated_messages_detail_route
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Messages detail route"
    ;;
  seeded-authenticated-list)
    VERIFY_PRODUCT="icecubes-linux-authenticated-list"
    open_authenticated_list_route
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated List route"
    ;;
  seeded-authenticated-list-refresh)
    VERIFY_PRODUCT="icecubes-linux-authenticated-list"
    open_authenticated_list_route
    previous_list_timeline_count="$(count_app_log_occurrences "$AUTH_LIST_ENDPOINT")"
    trigger_authenticated_refresh_shortcut \
      "$AUTH_LIST_ENDPOINT" \
      "authenticated List refresh" \
      "$((previous_list_timeline_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated List refresh"
    ;;
  seeded-authenticated-list-pagination)
    VERIFY_PRODUCT="icecubes-linux-authenticated-list"
    open_authenticated_list_route
    wait_for_authenticated_api_activity "$AUTH_LIST_PAGINATION_ENDPOINT" "authenticated List timeline pagination" 1
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated List timeline pagination"
    ;;
  seeded-authenticated-settings)
    VERIFY_PRODUCT="icecubes-linux-authenticated-settings"
    open_authenticated_settings_route
    ;;
  seeded-authenticated-settings-display)
    VERIFY_PRODUCT="icecubes-linux-authenticated-settings-display"
    open_authenticated_settings_display_route
    ;;
  seeded-authenticated-settings-display-font-scale)
    open_authenticated_settings_display_route
    drag_authenticated_settings_display_font_scale
    VERIFY_PRODUCT="icecubes-linux-authenticated-settings-display-font-scale"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Settings Display font-scale mutation"
    ;;
  seeded-authenticated-settings-display-font-picker)
    open_authenticated_settings_display_route
    select_authenticated_settings_display_font_picker
    VERIFY_PRODUCT="icecubes-linux-authenticated-settings-display-font-picker"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Settings Display font-picker route"
    ;;
  seeded-authenticated-settings-display-font-picker-select)
    open_authenticated_settings_display_route
    select_authenticated_settings_display_font_picker_inter
    VERIFY_PRODUCT="icecubes-linux-authenticated-settings-display-font-picker-selected"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Settings Display font-picker selected dismissal"
    ;;
  seeded-authenticated-settings-display-system-color)
    open_authenticated_settings_display_route
    toggle_authenticated_settings_display_system_color
    VERIFY_PRODUCT="icecubes-linux-authenticated-settings-display-system-color"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Settings Display system-color mutation"
    ;;
  seeded-authenticated-composer)
    VERIFY_PRODUCT="icecubes-linux-authenticated-composer"
    open_authenticated_composer_surface
    ;;
  seeded-authenticated-composer-type)
    VERIFY_PRODUCT="icecubes-linux-authenticated-composer-typed"
    open_authenticated_composer_surface
    type_authenticated_composer_text
    ;;
  seeded-authenticated-composer-submit)
    VERIFY_PRODUCT="icecubes-linux-authenticated-composer-submitted"
    open_authenticated_composer_surface
    submit_authenticated_composer_text
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated composer submitted shell"
    ;;
  seeded-authenticated-status-detail)
    VERIFY_PRODUCT="icecubes-linux-authenticated-status-detail"
    open_authenticated_status_detail
    ;;
  seeded-authenticated-status-detail-refresh)
    VERIFY_PRODUCT="icecubes-linux-authenticated-status-detail-refresh"
    open_authenticated_status_detail
    previous_status_count="$(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_GET_LOG")"
    previous_context_count="$(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_CONTEXT_GET_LOG")"
    trigger_authenticated_status_detail_refresh "$((previous_status_count + 1))" "$((previous_context_count + 1))"
    wait_for_authenticated_route_visual "$VERIFY_PRODUCT" "authenticated Status detail refresh"
    ;;
  seeded-authenticated-status-detail-reply)
    VERIFY_PRODUCT="icecubes-linux-authenticated-reply-composer"
    open_authenticated_status_detail
    if ! click_authenticated_status_detail_reply_action; then
      echo "IceCubes authenticated status reply action did not open the composer." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    ;;
  seeded-authenticated-status-detail-boost)
    VERIFY_PRODUCT="icecubes-linux-authenticated-status-detail-boost"
    previous_favorited_by_count="$(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_FAVORITED_BY_GET_LOG")"
    previous_reblogged_by_count="$(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_REBLOGGED_BY_GET_LOG")"
    open_authenticated_status_detail
    previous_boost_count="$(count_app_log_occurrences "POST https://mastodon.social/api/v1/statuses/1003/reblog")"
    if ! click_authenticated_status_detail_boost_action "$((previous_boost_count + 1))"; then
      wait_for_authenticated_api_activity "POST https://mastodon.social/api/v1/statuses/1003/reblog" "authenticated status boost action" "$((previous_boost_count + 1))"
    fi
    wait_for_authenticated_status_detail_action_accounts "$((previous_favorited_by_count + 1))" "$((previous_reblogged_by_count + 1))"
    ;;
  seeded-authenticated-status-detail-quote)
    VERIFY_PRODUCT="icecubes-linux-authenticated-composer"
    open_authenticated_status_detail
    if ! click_authenticated_status_detail_quote_action; then
      echo "IceCubes authenticated status quote action did not open the composer." >&2
      quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
      exit 1
    fi
    ;;
  seeded-authenticated-status-detail-favorite)
    VERIFY_PRODUCT="icecubes-linux-authenticated-status-detail-favorite"
    previous_favorited_by_count="$(count_app_log_exact_occurrences "$AUTH_STATUS_DETAIL_FAVORITED_BY_GET_LOG")"
    open_authenticated_status_detail
    previous_favorite_count="$(count_app_log_occurrences "POST https://mastodon.social/api/v1/statuses/1003/favourite")"
    if ! click_authenticated_status_detail_favorite_action "$((previous_favorite_count + 1))"; then
      wait_for_authenticated_api_activity "POST https://mastodon.social/api/v1/statuses/1003/favourite" "authenticated status favorite action" "$((previous_favorite_count + 1))"
    fi
    wait_for_authenticated_status_detail_action_accounts "$((previous_favorited_by_count + 1))"
    ;;
  seeded-authenticated-status-detail-bookmark)
    VERIFY_PRODUCT="icecubes-linux-authenticated-status-detail-bookmark"
    open_authenticated_status_detail
    previous_bookmark_count="$(count_authenticated_status_detail_bookmark_actions)"
    if ! click_authenticated_status_detail_bookmark_action "$((previous_bookmark_count + 1))"; then
      wait_for_authenticated_status_detail_bookmark_action "$((previous_bookmark_count + 1))"
    fi
    ;;
  seeded-authenticated-media-viewer)
    VERIFY_PRODUCT="icecubes-linux-authenticated-media-viewer"
    wait_for_authenticated_timeline_activity
    wait_for_authenticated_home_row_visual
    click_app_window_point "$AUTH_MEDIA_VIEWER_X" "$AUTH_MEDIA_VIEWER_Y"
    wait_for_authenticated_media_viewer_visual
    ;;
  *)
    echo "Unknown QUILLUI_ICECUBES_VISUAL_INTERACTION: $INTERACTION" >&2
    exit 2
    ;;
esac

if [[ -z "$SETTLE_SECONDS" ]]; then
  case "$INTERACTION" in
    seeded-authenticated-local|seeded-authenticated-federated|seeded-authenticated-trending|seeded-authenticated-list-pagination)
      # Capture immediately after the route-specific fixture activity wait.
      # Idling after completed URLProtocol-backed URLSession tasks can trip a
      # Linux FoundationNetworking cancel-after-completion assertion.
      SETTLE_SECONDS="0"
      ;;
    seeded-authenticated-home-pagination|seeded-authenticated-home-refresh|seeded-authenticated-explore|seeded-authenticated-explore-links|seeded-authenticated-explore-posts|seeded-authenticated-explore-tags|seeded-authenticated-explore-suggested-users|seeded-authenticated-explore-search|seeded-authenticated-notifications|seeded-authenticated-notifications-refresh|seeded-authenticated-profile|seeded-authenticated-messages|seeded-authenticated-messages-refresh|seeded-authenticated-messages-detail|seeded-authenticated-list|seeded-authenticated-list-refresh|seeded-authenticated-settings|seeded-authenticated-settings-display|seeded-authenticated-settings-display-font-scale|seeded-authenticated-settings-display-font-picker|seeded-authenticated-settings-display-font-picker-select|seeded-authenticated-settings-display-system-color|seeded-authenticated-composer|seeded-authenticated-composer-type|seeded-authenticated-composer-submit|seeded-authenticated-status-detail|seeded-authenticated-status-detail-refresh|seeded-authenticated-status-detail-reply|seeded-authenticated-status-detail-boost|seeded-authenticated-status-detail-quote|seeded-authenticated-status-detail-favorite|seeded-authenticated-status-detail-bookmark|seeded-authenticated-media-viewer)
      # Notifications has a separate data-source repaint after selection. The
      # route-specific wait above observes IceCubes' post-display refresh (or
      # status-detail/context fetch), so
      # only leave enough time for GTK to paint the populated row.
      SETTLE_SECONDS="0.5"
      ;;
    seeded-authenticated-*)
      SETTLE_SECONDS="3"
      ;;
  esac
fi
if [[ -n "$SETTLE_SECONDS" && "$SETTLE_SECONDS" != "0" ]]; then
  sleep "$SETTLE_SECONDS"
fi

if should_retry_final_visual_capture; then
  capture_and_verify_final_visual 1
else
  capture_and_verify_final_visual 0
fi
