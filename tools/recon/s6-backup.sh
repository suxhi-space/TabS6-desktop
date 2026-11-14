#!/usr/bin/env bash
# s6-backup.sh - READ-ONLY partition backup of a Galaxy Tab S6 (SM-T860) to your computer.
#
# Streams each partition off the tablet with `dd if=<partition>` (reads only), then checks
# the SHA-256 computed on the tablet against the SHA-256 of the file on the computer.
# Nothing on the tablet is modified. Needs a rooted Android (Magisk) with adb root shell.
#
# Why: every later phase changes boot/vbmeta/cache (and eventually userdata). The only
# safe rollback for boot experiments is a byte-exact copy of what is there today, and
# efs/sec_efs/persist hold per-device calibration and identity that no firmware download
# can restore.
#
# PRIVACY: efs, sec_efs and persist contain your device identity (serial, MAC addresses,
# calibration). Store this backup privately, ideally in two places. Never commit it.
#
# Usage: tools/recon/s6-backup.sh [adb-serial]

set -u
ADB=(adb)
[ $# -ge 1 ] && ADB=(adb -s "$1")

# Small, critical partitions first. Large firmware partitions after. userdata is NOT
# backed up here (too large, and encrypted); back up your files separately.
PARTS="boot recovery vbmeta dtbo misc efs sec_efs persist param up_param keydata keyrefuge cache apnhlos modem dsp"

OUT="s6-backup/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

if command -v sha256sum >/dev/null; then HASH() { sha256sum "$1" | awk '{print $1}'; }
else HASH() { shasum -a 256 "$1" | awk '{print $1}'; }; fi

su_() { "${ADB[@]}" shell "su -c '$*'" 2>/dev/null | tr -d '\r'; }
[ "$(su_ id -u)" = "0" ] || { echo "Root shell not available (Magisk > Superuser > allow Shell)."; exit 1; }

BYNAME=$(su_ 'if [ -d /dev/block/by-name ]; then echo /dev/block/by-name; else echo /dev/block/bootdevice/by-name; fi')
"${ADB[@]}" shell getprop ro.boot.bootloader | tr -d '\r' > "$OUT/bootloader-version.txt"
su_ "ls -l $BYNAME/" > "$OUT/partitions-by-name.txt"

FAIL=0
for p in $PARTS; do
  if [ -z "$(su_ "ls $BYNAME/$p 2>/dev/null")" ]; then echo "skip $p (not present)"; continue; fi
  printf 'reading %-10s ... ' "$p"
  # exec-out keeps the byte stream binary-clean.
  "${ADB[@]}" exec-out "su -c 'dd if=$BYNAME/$p bs=4194304 2>/dev/null'" > "$OUT/$p.img"
  DEV_SUM=$(su_ "sha256sum $BYNAME/$p" | awk '{print $1}')
  HOST_SUM=$(HASH "$OUT/$p.img")
  if [ -n "$DEV_SUM" ] && [ "$DEV_SUM" = "$HOST_SUM" ]; then
    echo "ok  $(wc -c < "$OUT/$p.img") bytes"
    echo "$HOST_SUM  $p.img" >> "$OUT/SHA256SUMS"
  else
    echo "MISMATCH (device=$DEV_SUM host=$HOST_SUM) - re-run; do not rely on this copy"
    FAIL=1
  fi
done

echo
echo "Backup in $OUT/  (bootloader $(cat "$OUT/bootloader-version.txt"))"
[ $FAIL -eq 0 ] && echo "All copies verified." || echo "Some copies did not verify. Fix before any flashing."
echo "Also download the full stock firmware matching that bootloader version (BL/AP/CP/CSC)"
echo "for a complete Odin restore; see docs/phase1-test-plan.md."
