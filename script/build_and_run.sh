#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$PROJECT_ROOT/mac-duo-status.xcodeproj"
SCHEME="mac-duo-status"
APP_NAME="mac-duo-status"
BUNDLE_ID="com.shishishi3.mac-duo-status"
DERIVED_DATA_DIR="/tmp/mac-duo-status-derived-data"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"

resolve_development_team() {
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    printf '%s\n' "$DEVELOPMENT_TEAM"
    return
  fi

  xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/DEVELOPMENT_TEAM = / && !found { print $2; found = 1 }'
}

DEVELOPMENT_TEAM="$(resolve_development_team)"
if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "No Apple Development signing team was found." >&2
  echo "Set DEVELOPMENT_TEAM=<Team ID> or add an Apple Development identity in Xcode." >&2
  exit 1
fi

echo "Using local development team: $DEVELOPMENT_TEAM"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  build

signature_team() {
  codesign -dvvv "$1" 2>&1 \
    | sed -n 's/^TeamIdentifier=//p'
}

verify_local_signatures() {
  local expected_team
  expected_team="$(signature_team "$APP_PATH")"
  if [[ -z "$expected_team" || "$expected_team" == "not set" ]]; then
    echo "The local app is not signed with a development team." >&2
    exit 1
  fi

  local signed_path actual_team
  for signed_path in \
    "$APP_PATH/Contents/PlugIns/DuoStatusWidget.appex" \
    "$APP_PATH/Contents/MacOS/com.shishishi3.duo-status.power-helper"
  do
    actual_team="$(signature_team "$signed_path")"
    if [[ "$actual_team" != "$expected_team" ]]; then
      echo "Signature team mismatch: $signed_path" >&2
      echo "Expected $expected_team, got ${actual_team:-not set}." >&2
      exit 1
    fi
  done
}

verify_local_signatures

open_app() {
  /usr/bin/open -n "$APP_PATH"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
