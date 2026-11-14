#!/usr/bin/env bash
# s6-plaintext-probe.sh - tests whether Linux could read a file that Android stores in userdata.
#
# This answers the key question for Migration Assistant design B (Linux living in an image
# file next to Android). Unlike the other recon scripts it WRITES one small file:
#   /data/linux-probe/probe.bin  (1 MiB of random bytes)
# Nothing else is changed. `remove` deletes it again.
#
# How the test works:
#   1. `create` (Android running, rooted): writes the file and prints its SHA-256.
#   2. Later, in TWRP, when it asks for your PIN to decrypt data, press Cancel. TWRP then sees
#      userdata the way Linux would: file contents Android encrypted are unreadable.
#      In TWRP's terminal (Advanced > Terminal) or via `adb shell`, run:
#          sha256sum /data/linux-probe/probe.bin
#      Same hash as step 1  -> the file is plaintext on disk: design B is possible.
#      Error or other hash  -> it was encrypted: design B needs another location (or is out).
#
# Usage: tools/recon/s6-plaintext-probe.sh create|check|remove [adb-serial]

set -u
MODE=${1:-}
ADB=(adb); [ $# -ge 2 ] && ADB=(adb -s "$2")
su_() { "${ADB[@]}" shell "su -c '$*'" 2>/dev/null | tr -d '\r'; }
DIR=/data/linux-probe
F=$DIR/probe.bin

[ "$(su_ id -u)" = "0" ] || { echo "Root shell not available (Magisk > Superuser > allow Shell)."; exit 1; }

case "$MODE" in
  create)
    su_ "mkdir -p $DIR && head -c 1048576 /dev/urandom > $F && sync"
    SUM=$(su_ "sha256sum $F" | awk '{print $1}')
    [ -n "$SUM" ] || { echo "Could not create $F"; exit 1; }
    mkdir -p recon-out
    echo "$SUM  probe.bin  (created $(date -u +%FT%TZ))" | tee recon-out/plaintext-probe.sha256
    echo
    echo "Saved the expected hash to recon-out/plaintext-probe.sha256."
    echo "Next: in TWRP, Cancel the decrypt prompt, then run: sha256sum $F"
    ;;
  check)
    su_ "ls -la $DIR; sha256sum $F"
    ;;
  remove)
    su_ "rm -rf $DIR" && echo "Removed $DIR"
    ;;
  *)
    echo "Usage: $0 create|check|remove [adb-serial]"; exit 1 ;;
esac
