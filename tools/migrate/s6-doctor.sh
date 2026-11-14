#!/usr/bin/env bash
# s6-doctor - keeps Android apps (Waydroid) working on Fedora after the move.
#
#   s6-doctor            check everything, change nothing
#   s6-doctor --fix      check and repair what can be repaired
#   s6-doctor --update   also install updates: Fedora's Waydroid package and Waydroid's Android system
#   s6-doctor --launchers  only re-hide Android's own system apps from the menu (used by the watcher)
#
# Checks: kernel support (binder), Waydroid installed, its service running, its Android system present,
# one window per app, Android system apps hidden, shared folders mounted, graphics mode.
# Exit code: 0 all good, 1 something needs attention.

set -u
FIX=0; UPDATE=0; ONLY_LAUNCHERS=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    --update) FIX=1; UPDATE=1 ;;
    --launchers) ONLY_LAUNCHERS=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
  esac
done
SUDO=${S6D_SUDO-sudo}                                     # test hooks
APPS=${S6D_APPS:-$HOME/.local/share/applications}
WDLIB=${S6D_WDLIB:-/var/lib/waydroid}
WD=${S6D_WAYDROID_DATA:-$HOME/.local/share/waydroid/data}
ETC=${S6D_ETC:-/etc}
PROC=${S6D_PROC:-/proc}
BAD=0

ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mFIX\033[0m   %s\n' "$*"; BAD=1; }
info() { printf '        %s\n' "$*"; }

# Android's own apps that duplicate Linux ones: hidden from the app menu (still inside Waydroid).
HIDE="com.android.documentsui org.lineageos.jelly com.android.gallery3d org.lineageos.glimpse
com.android.contacts com.android.dialer com.android.messaging org.lineageos.etar com.android.deskclock
org.lineageos.recorder com.android.camera2 org.lineageos.aperture com.android.settings"

hide_launchers() { # prints how many it hid
  local n=0 id f
  for id in $HIDE; do
    f="$APPS/waydroid.$id.desktop"
    [ -f "$f" ] || continue
    grep -q '^NoDisplay=true' "$f" && continue
    if [ $FIX = 1 ] || [ $ONLY_LAUNCHERS = 1 ]; then echo 'NoDisplay=true' >> "$f"; fi
    n=$((n+1))
  done
  echo $n
}

if [ $ONLY_LAUNCHERS = 1 ]; then hide_launchers >/dev/null; exit 0; fi

echo "S6 Doctor: checking Android app support"
echo

# 1. Kernel support: Android needs binder (binderfs) in the kernel.
if grep -q binder "$PROC/filesystems" 2>/dev/null || [ -e /dev/binder ] || [ -d /dev/binderfs ]; then
  ok "Kernel supports Android apps (binder)"
else
  warn "The running kernel has no binder support: Android apps cannot start."
  info "This usually means a kernel update left it out. Start the previous kernel: tabs6-kernel rollback"
fi

# 2. Waydroid installed.
if command -v waydroid >/dev/null; then
  ok "Waydroid installed ($(rpm -q waydroid 2>/dev/null || echo 'version unknown'))"
else
  warn "Waydroid is not installed."
  if [ $FIX = 1 ]; then $SUDO dnf install -y waydroid && ok "Waydroid installed" || info "Install failed; check Wi-Fi."; fi
  command -v waydroid >/dev/null || { echo; echo "Install Waydroid first:  sudo dnf install waydroid"; exit 1; }
fi

# 3. Its background service.
if systemctl is-active --quiet waydroid-container.service; then
  ok "Waydroid service running"
else
  warn "Waydroid service is not running."
  if [ $FIX = 1 ]; then $SUDO systemctl enable --now waydroid-container.service && ok "Waydroid service started"; fi
fi

# 4. Its Android system images.
if [ -f "$WDLIB/images/system.img" ] && [ -f "$WDLIB/images/vendor.img" ]; then
  ver=$(sed -n 's/^ro.lineage.display.version=//p; s/^ro.build.version.release=//p' "$WDLIB/waydroid_base.prop" 2>/dev/null | head -1)
  ok "Android system present${ver:+ ($ver)}"
else
  warn "Waydroid's Android system is not downloaded yet."
  if [ $FIX = 1 ]; then
    info "Downloading it (about 1 GB, needs Wi-Fi)..."
    $SUDO waydroid init && ok "Android system downloaded"
  fi
fi

# 5. Updates.
if [ $UPDATE = 1 ]; then
  info "Checking for updates..."
  $SUDO dnf upgrade -y waydroid >/dev/null 2>&1 && ok "Waydroid package up to date"
  $SUDO waydroid upgrade && ok "Android system up to date (restart Waydroid to use a new version)"
fi

# 6. One window per app.
if [ "$(waydroid prop get persist.waydroid.multi_windows 2>/dev/null)" = true ]; then
  ok "Android apps open in their own windows"
elif waydroid status 2>/dev/null | grep -q 'Session:.*RUNNING'; then
  warn "Android apps open inside one big window."
  [ $FIX = 1 ] && waydroid prop set persist.waydroid.multi_windows true && ok "Switched to one window per app"
else
  info "Start Waydroid once to check window mode."
fi

# 7. Android's duplicate system apps hidden (Waydroid can recreate their menu entries).
n=$(hide_launchers)
if [ "$n" = 0 ]; then ok "Android's own system apps are hidden from the menu"
else
  if [ $FIX = 1 ]; then ok "Hid $n Android system app(s) from the menu again"
  else warn "$n Android system app(s) are back in the menu"; fi
fi
if [ -f "$HOME/.config/systemd/user/s6migrate-hide.path" ]; then ok "Watcher that keeps them hidden is installed"
else
  warn "The watcher that keeps them hidden is not installed."
  if [ $FIX = 1 ]; then
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/s6migrate-hide.path" <<EOF
[Unit]
Description=Keep Android system apps hidden from the menu (S6 Migrate)

[Path]
PathChanged=$APPS

[Install]
WantedBy=default.target
EOF
    cat > "$HOME/.config/systemd/user/s6migrate-hide.service" <<EOF
[Unit]
Description=Hide Android system apps from the menu (S6 Migrate)

[Service]
Type=oneshot
ExecStart=$(command -v s6-doctor || echo /usr/local/bin/s6-doctor) --launchers
EOF
    systemctl --user daemon-reload 2>/dev/null; systemctl --user enable --now s6migrate-hide.path 2>/dev/null \
      && ok "Watcher installed" || info "Could not start the watcher (it will start at next login)."
  fi
fi

# 8. Shared folders.
LIST="$ETC/s6migrate/shares.list"
if [ -f "$ETC/systemd/system/s6migrate-waydroid-share.service" ] || [ -f "$ETC/s6migrate/waydroid-share.sh" ]; then
  missing=0
  for pair in "Pictures:Pictures" "Download:Download" "Documents:Documents" "Music:Music" "Movies:Movies"; do
    t="$WD/media/0/${pair#*:}"
    [ -d "$t" ] && ! mountpoint -q "$t" 2>/dev/null && missing=$((missing+1))
  done
  if [ -f "$LIST" ]; then
    while IFS='|' read -r d n; do
      [ -n "$n" ] && [ -d "$d" ] && ! mountpoint -q "$WD/media/0/$n" 2>/dev/null && missing=$((missing+1))
    done < "$LIST"
  fi
  if [ $missing = 0 ]; then ok "Your folders are shared with Android apps"
  else
    warn "$missing shared folder(s) are not connected."
    [ $FIX = 1 ] && $SUDO systemctl restart s6migrate-waydroid-share.service && ok "Shared folders reconnected"
  fi
else
  info "Folder sharing is not set up (s6-restore sets it up)."
fi

# 9. Graphics: hardware (Adreno via Mesa) or software rendering.
if [ -f "$WDLIB/waydroid_base.prop" ]; then
  if grep -q '^ro.hardware.gralloc=default' "$WDLIB/waydroid_base.prop" || grep -q '^ro.hardware.egl=swiftshader' "$WDLIB/waydroid_base.prop"; then
    info "Graphics: software rendering (works, but slower). Hardware graphics need Waydroid to detect the GPU."
  else
    ok "Graphics: hardware accelerated"
  fi
fi

echo
if [ $BAD = 0 ]; then echo "Everything looks good."
elif [ $FIX = 0 ]; then echo "Some things need attention. Run:  s6-doctor --fix"
else echo "Repairs done. Run s6-doctor again to confirm."; fi
exit $BAD
