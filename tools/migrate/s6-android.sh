#!/usr/bin/env bash
# s6-android - run Android apps (Waydroid) only while you use them.
#
#   s6-android status          is Android running, how much memory, which app windows are open
#   s6-android stop            stop Android now and free its memory
#   s6-android start           start Android in the background (opening an Android app also does this)
#   s6-android auto            watcher (runs as a user service): stops Android after it has had no
#                              app window open for S6A_IDLE_MIN minutes (default 5)
#   s6-android install         install the watcher service and the "Stop Android apps" menu entry
#
# Android app windows are found through KWin (Plasma's window manager); Waydroid gives each Android
# app window a class starting with "waydroid". Waydroid's own background session has no window.

set -u
IDLE_MIN=${S6A_IDLE_MIN:-5}
INTERVAL=${S6A_INTERVAL:-30}            # seconds between checks
CFG="$HOME/.config/s6migrate/android.conf"
[ -f "$CFG" ] && . "$CFG"               # may set IDLE_MIN=...

running() { waydroid status 2>/dev/null | grep -q 'Session:.*RUNNING'; }

android_windows() { # number of open Android app windows (KWin); -1 if it cannot tell
  local q info
  q=$(command -v qdbus6 || command -v qdbus || true)
  [ -n "$q" ] || { echo -1; return; }
  info=$("$q" org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null) || { echo -1; return; }
  printf '%s\n' "$info" | grep -i -c -E '^ *(resourceClass|desktopFile|appId|resourceName): *waydroid' || true
}

mem_mb() { # memory used by the Android container, in MB (cgroup when available)
  local f
  for f in /sys/fs/cgroup/lxc.payload.waydroid/memory.current /sys/fs/cgroup/lxc/waydroid/memory.current \
           /sys/fs/cgroup/lxc.payload.waydroid2/memory.current; do
    [ -r "$f" ] && { echo $(( $(cat "$f") / 1048576 )); return; }
  done
  echo "?"
}

case "${1:-status}" in
  status)
    if running; then
      w=$(android_windows)
      echo "Android: running, using about $(mem_mb) MB"
      [ "$w" -ge 0 ] 2>/dev/null && echo "Open Android app windows: $w" || echo "Open Android app windows: unknown"
      echo "Stop it with:  s6-android stop"
    else
      echo "Android: stopped (not using memory). It starts when you open an Android app."
    fi
    ;;
  stop)
    if running; then waydroid session stop && echo "Android stopped; its memory is free again."
    else echo "Android is already stopped."; fi
    ;;
  start)
    running && { echo "Android is already running."; exit 0; }
    (waydroid session start >/dev/null 2>&1 &)
    for _ in $(seq 1 40); do running && { echo "Android started."; exit 0; }; sleep 2; done
    echo "Android did not start; run s6-doctor."; exit 1
    ;;
  auto)
    idle=0
    while true; do
      if running; then
        w=$(android_windows)
        if [ "$w" = 0 ]; then
          idle=$((idle + INTERVAL))
          if [ $idle -ge $((IDLE_MIN * 60)) ]; then
            waydroid session stop >/dev/null 2>&1
            command -v notify-send >/dev/null && notify-send -a "S6 Migrate" -i waydroid \
              "Android apps stopped" "No Android app was open for $IDLE_MIN minutes, so Android was stopped to free memory."
            idle=0
          fi
        else
          idle=0   # an app window is open, or windows cannot be counted: never stop on a guess
        fi
      else
        idle=0
      fi
      [ "${S6A_ONCE:-0}" = 1 ] && { echo "idle=$idle"; exit 0; }
      sleep "$INTERVAL"
    done
    ;;
  install)
    mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/share/applications" "$(dirname "$CFG")"
    [ -f "$CFG" ] || echo "IDLE_MIN=5   # minutes without an Android app window before Android is stopped" > "$CFG"
    me=$(command -v s6-android || echo /usr/local/bin/s6-android)
    cat > "$HOME/.config/systemd/user/s6migrate-android-idle.service" <<EOF
[Unit]
Description=Stop Android apps (Waydroid) when none is open (S6 Migrate)
After=graphical-session.target

[Service]
ExecStart=$me auto
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF
    cat > "$HOME/.local/share/applications/s6migrate-stop-android.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Stop Android apps
Comment=Stop Android (Waydroid) now and free its memory
Exec=sh -c '$me stop; notify-send -a "S6 Migrate" "Android apps stopped" "Memory freed."'
Icon=process-stop
Categories=System;
Keywords=waydroid;android;memory;
EOF
    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable --now s6migrate-android-idle.service 2>/dev/null \
      && echo "Installed: Android stops by itself after $IDLE_MIN idle minutes; 'Stop Android apps' is in the menu." \
      || echo "Installed; the watcher starts at next login."
    # If a login autostart for the Waydroid session exists, turn it off: on-demand is the point.
    systemctl --user disable --now waydroid-session.service 2>/dev/null || true
    ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
