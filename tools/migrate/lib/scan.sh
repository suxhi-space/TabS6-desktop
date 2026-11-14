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
echo "INTFREE|$(df -k "$RP/data" 2>/dev/null | tail -1 | tr -s ' ' | cut -d' ' -f4)"
KS="$RP/data/misc/keystore/persistent.sqlite"
[ -n "$OUTDIR" ] && [ -f "$KS" ] && cp "$KS" "$OUTDIR/ks.sqlite" && chmod 644 "$OUTDIR/ks.sqlite"
