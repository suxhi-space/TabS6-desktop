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
[ $bad = 0 ] && echo "PACK-OK" || echo "PACK-HAD-ERRORS"
