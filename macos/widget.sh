#!/usr/bin/env bash
# Control script for the US Market Widget (macOS).
#   ./widget.sh install        build the .app, enable autostart at login, start now
#   ./widget.sh build          build "US Market Widget.app" (needs Xcode Command Line Tools)
#   ./widget.sh shortcut       put an alias of the .app on the Desktop (double-click to start)
#   ./widget.sh start|stop|restart|status
#   ./widget.sh autostart-on|autostart-off
#   ./widget.sh uninstall      stop + disable autostart (files are left in place)
#   ./widget.sh test           print computed NYSE calendar and phase checks
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/us_market_widget.swift"
APP="$HERE/US Market Widget.app"
BIN="$APP/Contents/MacOS/us-market-widget"
LABEL="local.us-market-widget"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

build() {
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are missing. Run: xcode-select --install"; exit 1
  fi
  if [ -x "$BIN" ] && [ "$BIN" -nt "$SRC" ]; then echo "Already built."; return; fi
  echo "Building..."
  mkdir -p "$APP/Contents/MacOS"
  swiftc -O -o "$BIN" "$SRC"
  cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>US Market Widget</string>
  <key>CFBundleDisplayName</key><string>US Market Widget</string>
  <key>CFBundleExecutable</key><string>us-market-widget</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PL
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  echo "Built: $APP"
}

shortcut() {
  build
  osascript -e "tell application \"Finder\" to make alias file to (POSIX file \"$APP\") at desktop" >/dev/null
  echo "Alias created on the Desktop: US Market Widget"
}

is_running() { pgrep -x us-market-widget >/dev/null; }

start() {
  build
  if is_running; then echo "Already running."; return; fi
  open -g "$APP"
  sleep 1
  if is_running; then echo "Started."; else echo "Failed to start. Try: $BIN"; exit 1; fi
}

stop() {
  if is_running; then pkill -x us-market-widget; echo "Stopped."; else echo "Not running."; fi
}

status() { if is_running; then echo "Running (PID $(pgrep -x us-market-widget | head -n1))."; else echo "Not running."; fi; }

autostart_on() {
  build
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PL
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  echo "Autostart enabled: $PLIST"
}

autostart_off() {
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Autostart disabled."
}

case "${1:-}" in
  install)        autostart_on; start ;;
  uninstall)      stop; autostart_off ;;
  build)          build ;;
  shortcut)       shortcut ;;
  start)          start ;;
  stop)           stop ;;
  restart)        stop; start ;;
  status)         status ;;
  autostart-on)   autostart_on ;;
  autostart-off)  autostart_off ;;
  test)           build; "$BIN" --test ;;
  *)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
