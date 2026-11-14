#!/usr/bin/env bash
# s6-migrate - Tab S6 Migration Assistant (runs in Termux, needs Magisk root)
#
# v0.1: PACK. Pick the apps (with their data) and folders you want to keep; the assistant
# packs them onto the microSD card (or a folder in internal storage), verifies the result,
# and writes a manifest that later versions use to restore everything into Fedora/Waydroid.
#
# v0.1 does not change Android: it only reads your apps and files and writes the package to
# the destination you choose. Apps are force-stopped for a moment while their data is copied.
#
# Roadmap: v0.2 restore on Fedora (apps into Waydroid, files into ~/), v0.3 one-button switch
# (download Fedora, install from TWRP, carry the package across). See docs/migration-assistant.md.

set -u
VERSION=0.1
RP=${S6M_ROOT:-}            # test hook: prefix for Android paths; empty on a real tablet
MEDIA="$RP/data/media/0"    # what apps see as /sdcard
PART_SIZE=${S6M_PART_SIZE:-1000m}   # split archives so FAT32 cards (4 GB file limit) work

W=$(mktemp -d "${TMPDIR:-/data/local/tmp}/s6m.XXXXXX") || { echo "Cannot create temp folder"; exit 1; }
trap 'rm -rf "$W"' EXIT INT TERM
exec 3<"${S6M_TTY:-/dev/tty}" || { echo "No terminal for input"; exit 1; }
ask() { local a; read -r -u 3 -p "$1" a; printf '%s' "$a"; }
hr() { # human-readable size from KiB (pure bash, no awk)
  local k=${1:-0}
  if [ "$k" -ge 1048576 ]; then printf '%d.%d GB' $((k/1048576)) $(((k%1048576)*10/1048576))
  elif [ "$k" -ge 1024 ]; then printf '%d MB' $((k/1024))
  else printf '%d KB' "$k"; fi; }
line() { printf '%s\n' "----------------------------------------------------------------"; }
root() { su -c "$*"; }

echo "Tab S6 Migration Assistant v$VERSION"
line
command -v su >/dev/null || { echo "Root (Magisk) is required."; exit 1; }
[ "$(root id -u 2>/dev/null)" = 0 ] || { echo "Root was not granted. Allow Termux in Magisk > Superuser and retry."; exit 1; }
MODEL=$(getprop ro.product.vendor.model 2>/dev/null)
case "$MODEL" in SM-T860*) ;; *) echo "Warning: this is '$MODEL', not an SM-T860."; [ "$(ask 'Continue anyway? [y/N] ')" = y ] || exit 1 ;; esac

# ------------------------------------------------------------------ scan (root, read-only)
cat > "$W/scan.sh" <<'SCAN'
# scan.sh RP [OUTDIR] - read-only inventory for the Migration Assistant (Android sh, run as root)
RP="$1"; MEDIA="$RP/data/media/0"; OUTDIR="${2:-}"
kb() { du -sk "$1" 2>/dev/null | cut -f1; }
pm list packages -3 -U 2>/dev/null | while read -r a b; do
  pkg=${a#package:}; uid=${b#uid:}
  apk=0
  for p in $(pm path "$pkg" 2>/dev/null | sed 's/^package://'); do s=$(kb "$RP$p"); apk=$((apk+${s:-0})); done
  dat=0
  for d in "$RP/data/data/$pkg" "$RP/data/user_de/0/$pkg" "$MEDIA/Android/data/$pkg" "$MEDIA/Android/obb/$pkg"; do
    [ -d "$d" ] && { s=$(kb "$d"); dat=$((dat+${s:-0})); }
  done
  echo "APP|$pkg|$uid|$apk|$dat"
done
for d in "$MEDIA"/*; do
  [ -d "$d" ] || continue
  n=${d##*/}; [ "$n" = Android ] && continue
  echo "DIR|$n|$(kb "$d")"
done
for m in "$RP"/mnt/media_rw/*; do
  [ -d "$m" ] || continue
  free=$(df -k "$m" 2>/dev/null | tail -1 | tr -s ' ' | cut -d' ' -f4)
  mnt=$(grep " ${m#$RP} " /proc/mounts 2>/dev/null | head -1)
  fs=$(echo "$mnt" | cut -d' ' -f3); src=$(echo "$mnt" | cut -d' ' -f1)
  case "$src" in *public:179,*) kind=microSD ;; *public:8,*|*public:259,*) kind=USB ;; *) kind=external ;; esac
  echo "VOL|$m|${free:-0}|${fs:-?}|$kind"
done
fst=$(grep -h -E '[[:space:]]/data[[:space:]]' "$RP"/vendor/etc/fstab.* 2>/dev/null | grep -v '^[[:space:]]*#' | head -1)
case "$fst" in *metadata_encryption*) me=yes ;; *) me=no ;; esac
echo "CRYPTO|$(getprop ro.crypto.state)|$(getprop ro.crypto.volume.filenames_mode)|$me"
PR="$RP/data/linux-probe/probe.bin"
[ -f "$PR" ] && echo "PROBE|$(sha256sum "$PR" | cut -d' ' -f1)"
for base in "$RP"/mnt/media_rw/* "$MEDIA"; do
  for pk in "$base"/S6Migrate/*; do
    [ -f "$pk/plan.txt" ] || continue
    st=unknown; [ -f "$pk/status.txt" ] && st=$(head -1 "$pk/status.txt"); [ "$st" = unknown ] && [ -f "$pk/SHA256SUMS" ] && st=complete
    echo "PKG|$pk|$(grep -c . "$pk/plan.txt")|$(du -sk "$pk" 2>/dev/null | cut -f1)|$st"
  done
done
echo "INTFREE|$(df -k "$RP/data" 2>/dev/null | tail -1 | tr -s ' ' | cut -d' ' -f4)"
KS="$RP/data/misc/keystore/persistent.sqlite"
[ -n "$OUTDIR" ] && [ -f "$KS" ] && cp "$KS" "$OUTDIR/ks.sqlite" && chmod 644 "$OUTDIR/ks.sqlite"
SCAN

echo "Scanning apps and folders (read-only, can take a minute)..."
root "sh '$W/scan.sh' '$RP' '$W'" > "$W/scan.txt" 2>/dev/null
grep -q '^APP|' "$W/scan.txt" || { echo "No apps found. Is root working?"; exit 1; }

# Apps with keys in the Android Keystore usually cannot restore their data elsewhere.
KEYUIDS=" "
if [ -f "$W/ks.sqlite" ] && command -v sqlite3 >/dev/null; then
  KEYUIDS=" $(sqlite3 "$W/ks.sqlite" 'select distinct namespace from keyentry where domain=0;' 2>/dev/null | tr '\n' ' ') "
  KSNOTE=""
else
  KSNOTE="(Keystore check skipped: run 'pkg install sqlite' for warnings about apps whose data cannot move.)"
fi

# Never offer these: they are tools for the migration itself or system-ish helpers.
SKIP_RE='^(com\.termux.*|com\.topjohnwu\.magisk|io\.github\.huskydg\.magisk|me\.phh\..*|com\.android\..*|com\.google\.android\.gms|com\.samsung\..*|com\.sec\..*)$'

APP_PKG=(); APP_UID=(); APP_KB=(); APP_WARN=(); APP_SEL=()
while IFS='|' read -r t pkg uid apk dat; do
  [ "$t" = APP ] || continue
  [[ "$pkg" =~ $SKIP_RE ]] && continue
  APP_PKG+=("$pkg"); APP_UID+=("$uid"); APP_KB+=($((apk+dat))); APP_SEL+=(0)
  case "$KEYUIDS" in *" $uid "*) APP_WARN+=("keystore") ;; *) APP_WARN+=("") ;; esac
done < "$W/scan.txt"

DIR_NAME=(); DIR_KB=(); DIR_SEL=()
while IFS='|' read -r t name kb; do
  [ "$t" = DIR ] || continue
  DIR_NAME+=("$name"); DIR_KB+=("${kb:-0}"); DIR_SEL+=(0)
done < "$W/scan.txt"

# ------------------------------------------------------------------ pickers
toggle_menu() { # toggle_menu TITLE arrayname-prefix (APP|DIR)
  local title=$1 kind=$2 i n ans
  while true; do
    clear 2>/dev/null; echo "$title"; line
    if [ "$kind" = APP ]; then n=${#APP_PKG[@]}; else n=${#DIR_NAME[@]}; fi
    for ((i=0; i<n; i++)); do
      if [ "$kind" = APP ]; then
        mark=$([ "${APP_SEL[$i]}" = 1 ] && echo x || echo " ")
        warn=$([ -n "${APP_WARN[$i]}" ] && echo "  ! data may not move (Keystore)")
        printf '%3d [%s] %-45s %8s%s\n' $((i+1)) "$mark" "${APP_PKG[$i]}" "$(hr "${APP_KB[$i]}")" "$warn"
      else
        mark=$([ "${DIR_SEL[$i]}" = 1 ] && echo x || echo " ")
        printf '%3d [%s] %-45s %8s\n' $((i+1)) "$mark" "${DIR_NAME[$i]}" "$(hr "${DIR_KB[$i]}")"
      fi
    done
    line
    [ "$kind" = APP ] && [ -n "${KSNOTE:-}" ] && echo "$KSNOTE"
    ans=$(ask "Numbers to toggle (e.g. 1 4 7), a = all, n = none, Enter = done: ")
    case "$ans" in
      "") return ;;
      a) for ((i=0; i<n; i++)); do if [ "$kind" = APP ]; then APP_SEL[$i]=1; else DIR_SEL[$i]=1; fi; done ;;
      n) for ((i=0; i<n; i++)); do if [ "$kind" = APP ]; then APP_SEL[$i]=0; else DIR_SEL[$i]=0; fi; done ;;
      *) for i in $ans; do
           [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le "$n" ] || continue
           i=$((i-1))
           if [ "$kind" = APP ]; then APP_SEL[$i]=$((1-APP_SEL[$i])); else DIR_SEL[$i]=$((1-DIR_SEL[$i])); fi
         done ;;
    esac
  done
}

toggle_menu "Step 1/4: apps to take along (your own apps only; Google/Samsung apps are not listed)" APP
toggle_menu "Step 2/4: folders from internal storage to take along" DIR

TOTAL=0; NAPPS=0; NDIRS=0
for ((i=0; i<${#APP_PKG[@]}; i++)); do [ "${APP_SEL[$i]}" = 1 ] && { TOTAL=$((TOTAL+APP_KB[$i])); NAPPS=$((NAPPS+1)); }; done
for ((i=0; i<${#DIR_NAME[@]}; i++)); do [ "${DIR_SEL[$i]}" = 1 ] && { TOTAL=$((TOTAL+DIR_KB[$i])); NDIRS=$((NDIRS+1)); }; done
[ $((NAPPS+NDIRS)) -gt 0 ] || { echo "Nothing selected."; exit 0; }

# ------------------------------------------------------------------ space check
FEDORA_IMAGE_KB=18874368      # installed Fedora root (t860-fedora v2026.10.29), 18 GiB
FEDORA_DOWNLOAD_KB=5254172    # compressed download incl. installer, 5.0 GiB
FEDORA_HEADROOM_KB=4194304    # working room for Linux, 4 GiB
MARGIN=$((TOTAL/20 + 102400))
INTFREE=$(sed -n 's/^INTFREE|//p' "$W/scan.txt"); INTFREE=${INTFREE:-0}
IFS='|' read -r _ CSTATE CMODE CMETA < <(grep '^CRYPTO|' "$W/scan.txt")
PROBE_SUM=$(sed -n 's/^PROBE|//p' "$W/scan.txt")
fits() { [ "$1" -ge "$2" ] && echo "fits" || echo "short by $(hr $(($2-$1)))"; }
clear 2>/dev/null; echo "Space check"; line
echo "Selected: $NAPPS apps, $NDIRS folders = $(hr $TOTAL)"
echo
echo "Plan A (pack to a card or USB drive):"
while IFS='|' read -r t m free fs kind; do
  [ "$t" = VOL ] || continue
  echo "  $kind ${m##*/}: $(hr "$free") free"
  echo "     pack only:                $(fits "$free" $((TOTAL+MARGIN)))"
  echo "     pack + Fedora download:   $(fits "$free" $((TOTAL+MARGIN+FEDORA_DOWNLOAD_KB)))   (needed for the one-button switch)"
done < "$W/scan.txt"
grep -q '^VOL|' "$W/scan.txt" || echo "  No microSD card or USB drive found. Plug one in for Plan A."
echo
NEEDB=$((FEDORA_IMAGE_KB + TOTAL + MARGIN + FEDORA_HEADROOM_KB))
echo "Plan B (Linux next to Android, inside internal storage):"
echo "  internal free $(hr "$INTFREE"), needs $(hr $NEEDB) (Fedora 18 GB + selection + 4 GB room): $(fits "$INTFREE" $NEEDB)"
if [ "${CMETA:-no}" = yes ]; then echo "  encryption: whole-partition (metadata) encryption -> Plan B is NOT possible on this tablet"
else echo "  encryption: file-based (${CMODE:-unknown}) -> Plan B possible in principle"; fi
if [ -n "$PROBE_SUM" ]; then echo "  TWRP test file present (hash ${PROBE_SUM:0:8}); confirm it in TWRP to finish the Plan B check"
else echo "  TWRP test not set up yet: run tools/recon/s6-plaintext-probe.sh create"; fi
line
ask "Press Enter to choose where to pack... " >/dev/null

# ------------------------------------------------------------------ destination
clear 2>/dev/null; echo "Step 3/4: where to put the package"; line
echo "Selected: $NAPPS apps, $NDIRS folders, about $(hr $TOTAL)"
echo
DEST_PATH=(); DEST_FREE=(); DEST_LABEL=()
while IFS='|' read -r t m free fs kind; do
  [ "$t" = VOL ] || continue
  case "$kind" in microSD) lab="microSD card" ;; USB) lab="USB drive" ;; *) lab="External storage" ;; esac
  DEST_PATH+=("$m/S6Migrate"); DEST_FREE+=("$free"); DEST_LABEL+=("$lab ($fs, ${m##*/}), $(hr "$free") free. Only an S6Migrate folder is added; nothing is erased")
done < "$W/scan.txt"
DEST_PATH+=("$MEDIA/S6Migrate"); DEST_FREE+=("${INTFREE:-0}")
DEST_LABEL+=("Internal storage, $(hr "${INTFREE:-0}") free (you must copy it to a computer before switching OS: internal storage is erased)")
for ((i=0; i<${#DEST_PATH[@]}; i++)); do echo "  $((i+1)). ${DEST_LABEL[$i]}"; done
echo
d=$(ask "Choose 1-${#DEST_PATH[@]}: ")
[[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -ge 1 ] && [ "$d" -le "${#DEST_PATH[@]}" ] || { echo "Cancelled."; exit 0; }
d=$((d-1))
NEED=$((TOTAL + TOTAL/20 + 102400))   # selection + 5% + 100 MB margin
if [ "${DEST_FREE[$d]}" -lt "$NEED" ]; then
  echo "Not enough space: need about $(hr $NEED), only $(hr "${DEST_FREE[$d]}") free. Deselect something or free space."
  exit 1
fi
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="${DEST_PATH[$d]}/$STAMP"

# ------------------------------------------------------------------ plan + confirm
{
  for ((i=0; i<${#APP_PKG[@]}; i++)); do [ "${APP_SEL[$i]}" = 1 ] && echo "APP|${APP_PKG[$i]}|${APP_UID[$i]}|${APP_WARN[$i]}"; done
  for ((i=0; i<${#DIR_NAME[@]}; i++)); do [ "${DIR_SEL[$i]}" = 1 ] && echo "DIR|${DIR_NAME[$i]}"; done
} > "$W/plan.txt"

clear 2>/dev/null; echo "Step 4/4: confirm"; line
sed -e 's/^APP|\([^|]*\)|[^|]*|keystore$/  app     \1   (! may not restore its data)/' \
    -e 's/^APP|\([^|]*\)|.*/  app     \1/' -e 's/^DIR|/  folder  /' "$W/plan.txt"
line
echo "Destination: $OUT"
echo "Apps are force-stopped briefly while their data is copied. Nothing is deleted."
[ "$(ask 'Start packing? Type yes: ')" = yes ] || { echo "Cancelled. Nothing written."; exit 0; }

# ------------------------------------------------------------------ pack (root)
cat > "$W/pack.sh" <<'PACK'
# pack.sh RP PLAN OUT PART - packs the plan into OUT (Android sh, run as root). Reads Android data only.
RP="$1"; MEDIA="$RP/data/media/0"; PLAN="$2"; OUT="$3"; PART="$4"
fail() { echo "ERROR: $*"; exit 1; }
mkdir -p "$OUT/apps" "$OUT/files" || fail "cannot create $OUT"
# pack_tar NAME DIR-ARGS... : tar the given -C/path pairs into NAME.tar.NNN parts
pack_tar() {
  name="$1"; shift
  tar -cf - "$@" 2>>"$OUT/pack-warnings.log" | split -b "$PART" -a 3 - "$name.tar." || return 1
  # verify: the parts must read back as a complete archive with the same entry count
  want=$(tar -cf - "$@" 2>/dev/null | tar -tf - | wc -l)
  got=$(cat "$name".tar.* | tar -tf - 2>/dev/null | wc -l)
  [ "$want" = "$got" ] || { echo "VERIFY-FAIL $name ($got of $want entries)"; return 1; }
  echo "  ok: ${name##*/} ($got entries)"
}
n=0; bad=0
while IFS='|' read -r t a b c; do
  n=$((n+1))
  case "$t" in
  APP)
    pkg="$a"; dir="$OUT/apps/$pkg"; mkdir -p "$dir/apk"
    echo "[$n] app $pkg"
    for p in $(pm path "$pkg" | sed 's/^package://'); do cp "$RP$p" "$dir/apk/" || bad=1; done
    ver=$(dumpsys package "$pkg" 2>/dev/null | grep -m1 versionName | sed 's/.*versionName=//')
    printf 'package=%s\nuid=%s\nversion=%s\nkeystore=%s\n' "$pkg" "$b" "$ver" "$c" > "$dir/meta.txt"
    am force-stop "$pkg" 2>/dev/null
    [ -d "$RP/data/data/$pkg" ]          && { pack_tar "$dir/data" -C "$RP/data/data" "$pkg" || bad=1; }
    [ -d "$RP/data/user_de/0/$pkg" ]     && { pack_tar "$dir/data_de" -C "$RP/data/user_de/0" "$pkg" || bad=1; }
    [ -d "$MEDIA/Android/data/$pkg" ]    && { pack_tar "$dir/extdata" -C "$MEDIA/Android/data" "$pkg" || bad=1; }
    [ -d "$MEDIA/Android/obb/$pkg" ]     && { pack_tar "$dir/obb" -C "$MEDIA/Android/obb" "$pkg" || bad=1; }
    ;;
  DIR)
    echo "[$n] folder $a"
    safe=$(printf '%s' "$a" | tr -c 'A-Za-z0-9._-' '_')
    pack_tar "$OUT/files/$safe" -C "$MEDIA" "$a" || bad=1
    printf '%s|%s\n' "$safe" "$a" >> "$OUT/files/index.txt"
    ;;
  esac
done < "$PLAN"
cp "$PLAN" "$OUT/plan.txt"
cat > "$OUT/README.txt" <<'EOF2'
Tab S6 Migration Assistant package

apps/<package>/apk/*.apk            the app (base + split APKs)
apps/<package>/data.tar.aaa...      app private data (/data/data/<package>)
apps/<package>/data_de.tar.aaa...   device-encrypted data (/data/user_de/0/<package>)
apps/<package>/extdata.tar.aaa...   /sdcard/Android/data/<package>
apps/<package>/obb.tar.aaa...       /sdcard/Android/obb/<package>
apps/<package>/meta.txt             package, uid, version, keystore warning
files/<name>.tar.aaa...             folders from internal storage (index.txt maps names)
SHA256SUMS                          checksums of every file

Archives are split into parts; join them with:  cat NAME.tar.* | tar -xf -
EOF2
( cd "$OUT" && find . -type f ! -name SHA256SUMS | sort | while read -r f; do sha256sum "$f"; done > SHA256SUMS )
# Internal storage files must belong to media_rw (1023) to stay readable over MTP/adb; no-op on FAT/exFAT cards.
chown -R 1023:1023 "${OUT%/*}" 2>/dev/null
if [ $bad = 0 ]; then echo complete > "$OUT/status.txt"; echo "PACK-OK"; else echo errors > "$OUT/status.txt"; echo "PACK-HAD-ERRORS"; fi
PACK

echo
echo "Packing..."
root "sh '$W/pack.sh' '$RP' '$W/plan.txt' '$OUT' '$PART_SIZE'" | tee "$W/pack.log"
STATUS=$(tail -1 "$W/pack.log")


line
if [ "$STATUS" = PACK-OK ]; then
  echo "Done. Package written and verified: $OUT"
  echo "Size: $(hr "$(root "du -sk '$OUT'" | cut -f1)")"
  echo "Nothing on Android was changed. Keep the card in the tablet (or copy the folder to a computer)."
else
  echo "Packing finished WITH ERRORS. See the lines marked VERIFY-FAIL above and"
  echo "$OUT/pack-warnings.log. Nothing on Android was changed."
  exit 1
fi
