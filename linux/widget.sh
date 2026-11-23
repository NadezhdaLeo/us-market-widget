#!/usr/bin/env bash
# Control script for the US Market Widget (Ubuntu / GNOME).
#   ./widget.sh install        install deps, enable autostart, start now
#   ./widget.sh start|stop|restart|status
#   ./widget.sh autostart-on|autostart-off
#   ./widget.sh uninstall      stop + disable autostart (files are left in place)
#   ./widget.sh test           print computed NYSE calendar and phase checks
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/us_market_widget.py"
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART="$AUTOSTART_DIR/us-market-widget.desktop"
PATTERN="python3 .*us_market_widget.py"

deps() {
  if python3 -c 'import gi; gi.require_version("Gtk","3.0"); gi.require_version("AyatanaAppIndicator3","0.1")' 2>/dev/null; then
    echo "Dependencies already installed."
    return
  fi
  echo "Installing dependencies (sudo required)..."
  if command -v apt-get >/dev/null; then
    sudo apt-get install -y python3-gi gir1.2-ayatanaappindicator3-0.1
  elif command -v dnf >/dev/null; then
    sudo dnf install -y python3-gobject gtk3 libayatana-appindicator-gtk3
  elif command -v pacman >/dev/null; then
    sudo pacman -S --needed --noconfirm python-gobject gtk3 libayatana-appindicator
  else
    echo "Unknown package manager. Install PyGObject, GTK 3 and Ayatana AppIndicator 3 manually."
    exit 1
  fi
}

is_running() { pgrep -f "$PATTERN" >/dev/null; }

start() {
  if is_running; then echo "Already running."; return; fi
  nohup python3 "$SCRIPT" >/dev/null 2>&1 &
  disown
  sleep 1
  if is_running; then echo "Started."; else echo "Failed to start. Try: python3 $SCRIPT"; exit 1; fi
}

stop() {
  if is_running; then pkill -f "$PATTERN"; echo "Stopped."; else echo "Not running."; fi
}

status() { if is_running; then echo "Running (PID $(pgrep -f "$PATTERN" | head -n1))."; else echo "Not running."; fi; }

autostart_on() {
  mkdir -p "$AUTOSTART_DIR"
  cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=US Market Widget
Comment=US stock market session indicator
Exec=/usr/bin/python3 "$SCRIPT"
Icon=utilities-system-monitor
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  echo "Autostart enabled: $AUTOSTART"
}

autostart_off() {
  rm -f "$AUTOSTART"
  echo "Autostart disabled."
}

case "${1:-}" in
  install)        deps; autostart_on; start ;;
  uninstall)      stop; autostart_off ;;
  start)          start ;;
  stop)           stop ;;
  restart)        stop; start ;;
  status)         status ;;
  autostart-on)   autostart_on ;;
  autostart-off)  autostart_off ;;
  deps)           deps ;;
  test)           python3 "$SCRIPT" --test ;;
  *)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
