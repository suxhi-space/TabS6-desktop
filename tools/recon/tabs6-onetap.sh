#!/usr/bin/env bash
# tabs6-onetap.sh - run ON THE TABLET (in Termux). Surveys the Tab S6, builds a scrubbed
# report, shows it to you, and after you type "yes" uploads only that report to the
# temporary branch `recon-upload` of your private repository. Leaves no files behind.
#
# Start it with the one-line command in README.md. It needs:
#   - Termux, with root granted to it by Magisk when asked
#   - a GitHub fine-grained token limited to this one repository (Contents: read and write)
#
# Privacy:
#   - The survey prints only allow-listed hardware and boot fields. It never copies the raw
#     device tree, kernel command line, full kernel log, partition contents or efs.
#   - Serial numbers, MAC addresses and e-mail addresses are scrubbed; the upload is refused
#     if a serial survives. The commit uses a generic author, not your name or e-mail.
#   - The token is only held in memory; it is never written to disk.
#   - All working files live in one temporary folder that is deleted on exit, even on error.
#     The only exception is the optional Design B test file, which you must opt in to.

set -u
REPO="suxhi-space/TabS6-desktop"
BRANCH="recon-upload"
API="https://api.github.com/repos/$REPO"

W=$(mktemp -d "${TMPDIR:-/data/local/tmp}/tabs6.XXXXXX") || { echo "Cannot create a temp folder"; exit 1; }
cleanup() { rm -rf "$W"; unset GH_TOKEN; }
trap cleanup EXIT INT TERM
exec 3<"${TABS6_TTY:-/dev/tty}" || { echo "No terminal to read answers from"; exit 1; }
ask() { local a; read -r -u 3 -p "$1" a; printf '%s' "$a"; }

echo "== Tab S6 one-tap recon =="
for c in curl base64 su; do
  command -v "$c" >/dev/null || { echo "Missing '$c'. In Termux run: pkg install -y curl   (and make sure the tablet is rooted)"; exit 1; }
done
if [ -z "${GH_TOKEN:-}" ]; then
  read -r -s -u 3 -p "GitHub token (input hidden): " GH_TOKEN; echo
fi
[ -n "$GH_TOKEN" ] || { echo "No token given."; exit 1; }

PROBE=0
case "$(ask 'Also run the Design B test? It writes ONE 1 MiB test file to /data/linux-probe that stays until removed. [y/N] ')" in
  y|Y) PROBE=1 ;;
esac

# ---------------------------------------------------------------- survey (runs as root)
cat > "$W/survey.sh" <<'SURVEY'
# Android /system/bin/sh. Prints allow-listed fields only. Reads only, except the opt-in probe.
bn() { for d in /dev/block/by-name /dev/block/bootdevice/by-name; do [ -e "$d/$1" ] && { echo "$d/$1"; return; }; done; }
u32() { dd if="$1" bs=1 skip="$2" count=4 2>/dev/null | od -An -tu4 | tr -d ' '; }
h() { echo; echo "-- $1 --"; }

echo "SERIALS: $(getprop ro.serialno) $(getprop ro.boot.serialno) $(getprop ril.serialnumber)"

h "Identity"
for p in ro.product.model ro.product.vendor.model ro.product.vendor.device ro.boot.bootloader \
         ro.build.version.release ro.build.fingerprint ro.vendor.build.fingerprint \
         ro.boot.verifiedbootstate ro.boot.flash.locked ro.boot.vbmeta.device_state \
         ro.boot.warranty_bit ro.boot.boot_recovery ro.boot.hardware; do
  echo "$p = $(getprop $p)"
done
echo "kernel: $(uname -r) $(uname -m)"

h "CPU"
grep -E '^(Features|CPU implementer|CPU part)' /proc/cpuinfo | sort | uniq -c
grep -q -w paca /proc/cpuinfo && echo ">> PAC present" || echo ">> no PAC (paca/pacg absent)"

h "Exception level"
dmesg 2>/dev/null | grep -m1 -i 'started at EL' || echo "(not in kernel log)"

h "Boot control block (misc)"
M=$(bn misc)
[ -n "$M" ] && echo "misc command field: '$(dd if=$M bs=32 count=1 2>/dev/null | tr -d '\000' | sed 's/[^[:print:]]/./g')'"

h "vbmeta"
V=$(bn vbmeta)
[ -n "$V" ] && echo "magic=$(dd if=$V bs=4 count=1 2>/dev/null) flags=$(dd if=$V bs=1 skip=120 count=4 2>/dev/null | od -An -tx1 | tr -d ' ')"

h "boot / recovery headers"
for n in boot recovery; do
  P=$(bn $n); [ -z "$P" ] && continue
  echo "$n: magic=$(dd if=$P bs=8 count=1 2>/dev/null) header_version=$(u32 $P 40) ramdisk_size=$(u32 $P 16)"
done

h "Partitions (name -> device)"
ls -l "$(dirname "$(bn boot)")" 2>/dev/null | sed -n 's/.* \([^ ]*\) -> \(.*\)$/\1 -> \2/p'
h "Partition sizes"
cat /proc/partitions

h "Data partition"
for p in ro.crypto.state ro.crypto.type ro.crypto.volume.filenames_mode ro.crypto.dm_default_key.options_format.version; do
  echo "$p = $(getprop $p)"
done
echo "fstab /data:"; grep -h -E '[[:space:]]/data[[:space:]]' /vendor/etc/fstab.* 2>/dev/null
echo "mounted: $(grep -E ' /data ' /proc/mounts | head -1 | cut -d' ' -f1-3)"
echo "free: $(df -h /data | tail -1)"
echo "top-level: $(ls /data | tr '\n' ' ')"

h "Memory"
grep MemTotal /proc/meminfo
grep -v '^ ' /proc/iomem

h "Device tree"
echo "model: $(tr -d '\000' < /proc/device-tree/model 2>/dev/null)"
echo "compatible: $(tr '\000' ' ' < /proc/device-tree/compatible 2>/dev/null)"
echo "msm-id: $(od -An -tx1 /proc/device-tree/qcom,msm-id 2>/dev/null | tr -s ' ')"
echo "board-id: $(od -An -tx1 /proc/device-tree/qcom,board-id 2>/dev/null | tr -s ' ')"

h "Display"
for f in virtual_size bits_per_pixel stride name; do
  [ -f /sys/class/graphics/fb0/$f ] && echo "fb0 $f: $(cat /sys/class/graphics/fb0/$f)"
done
for f in lcd_type window_type; do
  [ -f /sys/class/lcd/panel/$f ] && echo "panel $f: $(cat /sys/class/lcd/panel/$f)"
done

h "I2C / SPI devices"
for d in /sys/bus/i2c/devices/*; do echo "i2c $(basename $d) $(cat $d/name 2>/dev/null)"; done
for d in /sys/bus/spi/devices/*; do [ -e "$d" ] && echo "spi $(basename $d) $(cat $d/modalias 2>/dev/null)"; done

h "Firmware file names"
ls /vendor/firmware /vendor/firmware_mnt/image /vendor/dsp 2>/dev/null | \
  grep -i -E 'a640|zap|gmu|sqe|wlan|bdwlan|crbtfw|crnv|adsp|slpi|cdsp|modem|mba|cs35l41|fts|wacom' | sort -u

h "Driver hints"
dmesg 2>/dev/null | grep -i -E 'fts1ba90a|sec_ts|wacom|wcn3990|ath10k|icnss|sm5705|cs35l41|cs48l3' | head -20

if [ "${PROBE:-0}" = 1 ]; then
  h "Design B probe"
  mkdir -p /data/linux-probe && head -c 1048576 /dev/urandom > /data/linux-probe/probe.bin && sync
  echo "probe.bin sha256: $(sha256sum /data/linux-probe/probe.bin | cut -d' ' -f1)"
fi
SURVEY

echo
echo "Running the survey as root (allow Termux in the Magisk prompt)..."
if ! su -c "PROBE=$PROBE sh $W/survey.sh" > "$W/raw.txt" 2>/dev/null || [ ! -s "$W/raw.txt" ]; then
  echo "Root survey failed. Open Magisk > Superuser, allow Termux, and run the command again."; exit 1
fi

# ---------------------------------------------------------------- scrub
SERIALS=$(sed -n 's/^SERIALS: //p' "$W/raw.txt" | tr ' ' '\n' | grep -v -E '^(|unknown)$' | sort -u)
{
  echo "# Tab S6 recon report (scrubbed, on-device)"
  echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  grep -v '^SERIALS: ' "$W/raw.txt" | grep -v -i -E 'serial|androidboot|imei|bt_addr|ssid|@'
} > "$W/report.txt"
for s in $SERIALS; do
  [ ${#s} -ge 6 ] && sed -i "s/$s/[SERIAL]/g" "$W/report.txt"
done
sed -i -E 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/[MAC]/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[EMAIL]/g' "$W/report.txt"
for s in $SERIALS; do
  if [ ${#s} -ge 6 ] && grep -q -- "$s" "$W/report.txt"; then
    echo "Serial number still present after scrubbing. Not uploading."; exit 1
  fi
done

# ---------------------------------------------------------------- review
echo
echo "------------------------------- report -------------------------------"
cat "$W/report.txt"
echo "----------------------------------------------------------------------"
echo "Above is EVERYTHING that would be uploaded (scroll up to read it all)."
[ "$(ask 'Upload it to the recon-upload branch of your private repo? Type yes: ')" = "yes" ] || { echo "Not uploaded. Nothing kept."; exit 0; }

# ---------------------------------------------------------------- upload (GitHub git-data API)
api() { # api METHOD PATH JSONFILE -> body in $W/resp, prints HTTP status
  curl -sS -o "$W/resp" -w '%{http_code}' -X "$1" \
       -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
       "$API/$2" --data-binary "@$3"
}
sha_of() { grep -o '"sha": *"[0-9a-f]\{40\}"' "$W/resp" | head -1 | grep -o '[0-9a-f]\{40\}'; }
fail() { echo "Upload failed at $1 (HTTP $2): $(head -c 300 "$W/resp")"; echo "Check the token has Contents: read and write on $REPO."; exit 1; }

printf '{"content":"%s","encoding":"base64"}' "$(base64 -w0 "$W/report.txt")" > "$W/j"
code=$(api POST git/blobs "$W/j"); [ "$code" = 201 ] || fail blob "$code"; BLOB=$(sha_of)

printf '{"tree":[{"path":"report.txt","mode":"100644","type":"blob","sha":"%s"}]}' "$BLOB" > "$W/j"
code=$(api POST git/trees "$W/j"); [ "$code" = 201 ] || fail tree "$code"; TREE=$(sha_of)

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"message":"Scrubbed Tab S6 recon report (temporary)","tree":"%s","parents":[],"author":{"name":"tabs6-recon","email":"recon@localhost","date":"%s"},"committer":{"name":"tabs6-recon","email":"recon@localhost","date":"%s"}}' "$TREE" "$NOW" "$NOW" > "$W/j"
code=$(api POST git/commits "$W/j"); [ "$code" = 201 ] || fail commit "$code"; COMMIT=$(sha_of)

printf '{"sha":"%s","force":true}' "$COMMIT" > "$W/j"
code=$(api PATCH "git/refs/heads/$BRANCH" "$W/j")
if [ "$code" != 200 ]; then
  printf '{"ref":"refs/heads/%s","sha":"%s"}' "$BRANCH" "$COMMIT" > "$W/j"
  code=$(api POST git/refs "$W/j"); [ "$code" = 201 ] || fail ref "$code"
fi

echo
echo "Uploaded. Tell Claude: \"recon uploaded\"."
echo "Cleaning up: temporary files are deleted now; the token was never saved."
echo "To leave nothing behind: delete the token on github.com, and uninstall Termux if you no longer need it."
if [ "$PROBE" = 1 ]; then echo "Note: the Design B test file /data/linux-probe/probe.bin stays until you check it in TWRP."; fi
