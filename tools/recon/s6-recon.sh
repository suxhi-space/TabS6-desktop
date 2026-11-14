#!/usr/bin/env bash
# s6-recon.sh - READ-ONLY hardware and boot-state survey of a Galaxy Tab S6 (SM-T860).
#
# Run on your computer with the tablet booted into Android (GSI or stock), USB debugging
# on, and Magisk root granted to the shell. Nothing is written to the tablet: every
# command reads (getprop, cat, ls, dd if=... to stdout). Output goes to ./recon-out/<time>/
# on the computer.
#
# PRIVACY: the output contains your serial number, the live device tree (which embeds
# the serial and bootloader args), and the kernel command line. Keep it local. Do not
# commit it or post it publicly without redacting. recon-out/ is in .gitignore.
#
# Usage: tools/recon/s6-recon.sh [adb-serial]

set -u
ADB=(adb)
[ $# -ge 1 ] && ADB=(adb -s "$1")

OUT="recon-out/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"

say() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }
sh_()  { "${ADB[@]}" shell "$@" 2>/dev/null | tr -d '\r'; }
su_()  { "${ADB[@]}" shell "su -c '$*'" 2>/dev/null | tr -d '\r'; }
bin_() { "${ADB[@]}" exec-out "su -c '$*'" 2>/dev/null; }   # binary-clean reads
grab() { # grab <file-in-OUT> <root-command>
  su_ "$2" > "$OUT/$1"
  [ -s "$OUT/$1" ] || echo "  (empty or unreadable: $2)" | tee -a "$SUMMARY"
}

"${ADB[@]}" get-state >/dev/null 2>&1 || { echo "No adb device. Enable USB debugging and authorize this computer."; exit 1; }
if [ "$(su_ id -u)" != "0" ]; then
  echo "Root shell not available. Open Magisk, allow Shell superuser, and re-run."; exit 1
fi

say "== Tab S6 recon $(date -u +%FT%TZ) =="
say ""
say "-- Identity --"
for p in ro.product.model ro.product.vendor.model ro.product.vendor.device ro.boot.bootloader \
         ro.build.version.release ro.build.fingerprint ro.vendor.build.fingerprint \
         ro.boot.verifiedbootstate ro.boot.flash.locked ro.boot.vbmeta.device_state \
         ro.boot.warranty_bit ro.boot.boot_recovery ro.boot.slot_suffix ro.boot.hardware; do
  say "$p = $(sh_ getprop "$p")"
done
MODEL=$(sh_ getprop ro.product.vendor.model)
case "$MODEL" in
  SM-T860*) say ">> Model OK (SM-T860, Wi-Fi). The reference Linux/UEFI work targets exactly this model." ;;
  *)        say ">> WARNING: vendor model is '$MODEL', not SM-T860. The Aloha UEFI target and every address in docs/hardware.md assume SM-T860." ;;
esac
say "kernel: $(sh_ uname -a)"
say ""

say "-- CPU features (pointer authentication decides macOS/iPadOS-27 feasibility) --"
sh_ cat /proc/cpuinfo > "$OUT/cpuinfo.txt"
FEAT=$(grep -m1 '^Features' "$OUT/cpuinfo.txt")
say "$FEAT"
if echo "$FEAT" | grep -qw paca; then
  say ">> PAC present (paca). Unexpected for Kryo 485; re-check docs/macos-feasibility.md."
else
  say ">> No 'paca'/'pacg': no pointer authentication. arm64e (macOS, iPadOS 27) cannot run natively; arm64 iPadOS 17/18 is the ceiling."
fi
grep -E '^CPU (implementer|part|variant|revision)' "$OUT/cpuinfo.txt" | sort | uniq -c | tee -a "$SUMMARY"
say ""

say "-- Exception level at kernel entry (decides whether an EL2 hypervisor approach is possible) --"
grab dmesg.txt "dmesg"
EL=$(grep -m1 -iE 'started at EL[0-9]' "$OUT/dmesg.txt")
say "${EL:-  (line not found; dmesg may have rotated, reboot and re-run soon after boot)}"
say ""

say "-- Boot control block in misc (Magisk-in-recovery trap, see docs/phase1-test-plan.md) --"
MISC=$(su_ 'ls /dev/block/by-name/misc /dev/block/bootdevice/by-name/misc 2>/dev/null | head -1')
if [ -n "$MISC" ]; then
  # First 32 bytes of the BCB are the 'command' field. Read only.
  BCB=$(bin_ "dd if=$MISC bs=32 count=1 2>/dev/null" | tr -d '\000' | tr -c '[:print:]' '.')
  say "misc command field: '${BCB}'"
  case "$BCB" in
    *boot-recovery*) say ">> ATTENTION: BCB = boot-recovery. ABL boots the RECOVERY partition every time and ignores 'boot'. Any boot-image experiment will silently do nothing. Read the BCB section of the test plan before changing anything." ;;
    "")              say ">> BCB command empty: normal, ABL boots the boot partition." ;;
    *)               say ">> Non-empty BCB command. Note it and read the test plan." ;;
  esac
else
  say "  misc partition not found under by-name"
fi
say ""

say "-- Partition map --"
grab partitions-by-name.txt 'ls -l /dev/block/by-name/ 2>/dev/null || ls -l /dev/block/bootdevice/by-name/'
grab proc-partitions.txt 'cat /proc/partitions'
for n in boot recovery vbmeta dtbo cache misc userdata efs sec_efs persist; do
  L=$(grep -E " $n -> " "$OUT/partitions-by-name.txt" | awk '{print $NF}')
  if [ -n "$L" ]; then
    DEV=$(basename "$L")
    BLK=$(awk -v d="$DEV" '$4==d{print $3}' "$OUT/proc-partitions.txt")
    say "$(printf '%-9s %-12s %s KiB' "$n" "$DEV" "${BLK:-?}")"
  fi
done
say ""

say "-- vbmeta flags (3 = verification + hashtree disabled) --"
VB=$(su_ 'ls /dev/block/by-name/vbmeta /dev/block/bootdevice/by-name/vbmeta 2>/dev/null | head -1')
if [ -n "$VB" ]; then
  # AvbVBMetaImageHeader: magic 'AVB0' at 0, flags (big-endian u32) at offset 120.
  HDR=$(bin_ "dd if=$VB bs=128 count=1 2>/dev/null" | od -v -An -tx1 | tr -d ' \n')
  MAGIC=${HDR:0:8}; FLAGS=${HDR:240:8}
  say "magic=$MAGIC (41564230 = AVB0)  flags=0x$FLAGS"
fi
say ""

say "-- What is in boot and recovery? (Magisk location) --"
for n in boot recovery; do
  P=$(su_ "ls /dev/block/by-name/$n /dev/block/bootdevice/by-name/$n 2>/dev/null | head -1")
  [ -z "$P" ] && continue
  # Android boot image header: 'ANDROID!' at 0, kernel_size @8, ramdisk_size @16, header_version @40 (LE u32).
  bin_ "dd if=$P bs=4096 count=1 2>/dev/null" > "$OUT/$n-header.bin"
  MAGIC=$(head -c 8 "$OUT/$n-header.bin")
  RD=$(od -An -tu4 -j16 -N4 "$OUT/$n-header.bin" | tr -d ' ')
  VER=$(od -An -tu4 -j40 -N4 "$OUT/$n-header.bin" | tr -d ' ')
  say "$n: magic='$MAGIC' header_version=$VER ramdisk_size=$RD"
done
say ">> boot ramdisk_size=0 means a ramdisk-less boot image: on a rooted unit Magisk then lives in RECOVERY,"
say ">> which usually goes together with BCB=boot-recovery above. The test plan explains why that matters."
say ""

say "-- Data partition: encryption, filesystem, free space (decides the in-place migration design) --"
for p in ro.crypto.state ro.crypto.type ro.crypto.volume.filenames_mode ro.crypto.dm_default_key.options_format.version; do
  say "$p = $(sh_ getprop "$p")"
done
grab fstab-userdata.txt 'grep -h -E "[[:space:]]/data[[:space:]]" /vendor/etc/fstab.* /system/etc/fstab.* 2>/dev/null'
say "fstab /data line(s):"; cat "$OUT/fstab-userdata.txt" | tee -a "$SUMMARY"
if grep -q metadata_encryption "$OUT/fstab-userdata.txt"; then
  say ">> metadata_encryption present: the whole userdata block device is encrypted. Linux could not mount it at all; in-place design B is ruled out."
elif grep -q fileencryption "$OUT/fstab-userdata.txt"; then
  say ">> File-based encryption without metadata encryption: the filesystem itself is readable by Linux, only file contents are encrypted. In-place design B is possible in principle."
fi
say "mounted: $(su_ 'grep -E " /data " /proc/mounts' | head -1)"
say "free on /data: $(su_ 'df -h /data' | tail -1)"
grab data-toplevel.txt 'ls -la /data/'
say ""

say "-- Memory --"
grab meminfo.txt 'cat /proc/meminfo'
say "$(grep MemTotal "$OUT/meminfo.txt")"
grab iomem.txt 'cat /proc/iomem'
say "System RAM ranges:"; grep 'System RAM' "$OUT/iomem.txt" | tee -a "$SUMMARY"
say ""

say "-- Live device tree (from ABL) --"
bin_ 'cat /sys/firmware/fdt' > "$OUT/fdt.dtb"
say "model: $(su_ cat /sys/firmware/devicetree/base/model | tr -d '\000')"
say "compatible: $(su_ cat /sys/firmware/devicetree/base/compatible | tr '\000' ' ')"
say "qcom,msm-id: $(bin_ cat /sys/firmware/devicetree/base/qcom,msm-id | od -v -An -tx1 | tr -s ' ')"
say "qcom,board-id: $(bin_ cat /sys/firmware/devicetree/base/qcom,board-id | od -v -An -tx1 | tr -s ' ')"
say "Decompile on your computer with: dtc -I dtb -O dts -o $OUT/fdt.dts $OUT/fdt.dtb"
grab cmdline.txt 'cat /proc/cmdline'
say ""

say "-- Display (bootloader framebuffer handoff) --"
grab fb.txt 'for f in /sys/class/graphics/fb0/*; do [ -f "$f" ] && echo "$(basename $f): $(cat $f 2>/dev/null)"; done'
grep -E '^(virtual_size|bits_per_pixel|stride|name):' "$OUT/fb.txt" | tee -a "$SUMMARY"
grab lcd.txt 'for f in /sys/class/lcd/panel/lcd_type /sys/class/lcd/panel/window_type /sys/class/lcd/panel/manufacture_code; do [ -f $f ] && echo "$f: $(cat $f)"; done'
cat "$OUT/lcd.txt" | tee -a "$SUMMARY"
grep -iE 'ana38401|amsa05|cont_splash|splash' "$OUT/dmesg.txt" | head -5 | tee -a "$SUMMARY"
say ""

say "-- I2C / SPI devices seen by the Android kernel --"
grab i2c.txt 'for d in /sys/bus/i2c/devices/*; do n=$(cat $d/name 2>/dev/null); echo "$(basename $d) $n"; done'
grab spi.txt 'for d in /sys/bus/spi/devices/*; do echo "$(basename $d) $(cat $d/modalias 2>/dev/null)"; done'
cat "$OUT/i2c.txt" "$OUT/spi.txt" | tee -a "$SUMMARY"
say ""

say "-- Firmware file names (names only, no contents) --"
grab firmware-list.txt 'ls -la /vendor/firmware /vendor/firmware_mnt/image /vendor/dsp 2>/dev/null'
grep -iE 'a640|zap|gmu|sqe|wlan|bdwlan|crbtfw|crnv|adsp|slpi|cdsp|modem|mba|cs35l41|fts|wacom' "$OUT/firmware-list.txt" | awk '{print $NF}' | sort -u | tee -a "$SUMMARY"
say ""

say "-- Kernel driver hints (touch, pen, Wi-Fi, fuel gauge) --"
grep -iE 'fts1ba90a|sec_ts|wacom|w902|wcn3990|ath10k|icnss|sm5705|cs35l41|cs48l3' "$OUT/dmesg.txt" | head -20 | tee -a "$SUMMARY"
say ""
say "Done. Full output: $OUT/"
say "Next: read summary.txt and fill the 'Measured on my unit' column in docs/hardware.md."
