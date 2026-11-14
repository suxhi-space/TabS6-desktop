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
  label=${name##*/}; echo "  ok: ${label#.new-} ($got entries)"
}
n=0; bad=0
# Each item is packed into a ".new-" staging copy and only replaces an existing copy once it
# verifies, so updating a package never loses the previous copy of an item.
while IFS='|' read -r t a b c; do
  n=$((n+1))
  case "$t" in
  APP)
    pkg="$a"; final="$OUT/apps/$pkg"; dir="$OUT/apps/.new-$pkg"
    rm -rf "$dir"; mkdir -p "$dir/apk"
    echo "[$n] app $pkg"
    ok=1
    for p in $(pm path "$pkg" </dev/null | sed 's/^package://'); do cp "$RP$p" "$dir/apk/" || ok=0; done
    ver=$(dumpsys package "$pkg" </dev/null 2>/dev/null | grep -m1 versionName | sed 's/.*versionName=//')
    printf 'package=%s\nuid=%s\nversion=%s\nkeystore=%s\n' "$pkg" "$b" "$ver" "$c" > "$dir/meta.txt"
    am force-stop "$pkg" </dev/null 2>/dev/null
    [ -d "$RP/data/data/$pkg" ]          && { pack_tar "$dir/data" -C "$RP/data/data" "$pkg" || ok=0; }
    [ -d "$RP/data/user_de/0/$pkg" ]     && { pack_tar "$dir/data_de" -C "$RP/data/user_de/0" "$pkg" || ok=0; }
    [ -d "$MEDIA/Android/data/$pkg" ]    && { pack_tar "$dir/extdata" -C "$MEDIA/Android/data" "$pkg" || ok=0; }
    [ -d "$MEDIA/Android/obb/$pkg" ]     && { pack_tar "$dir/obb" -C "$MEDIA/Android/obb" "$pkg" || ok=0; }
    if [ $ok = 1 ]; then rm -rf "$final"; mv "$dir" "$final"
    else bad=1; rm -rf "$dir"; [ -d "$final" ] && echo "  kept the previous copy of $pkg"; fi
    ;;
  DIR)
    echo "[$n] folder $a"
    safe=$(printf '%s' "$a" | tr -c 'A-Za-z0-9._-' '_')
    new="$OUT/files/.new-$safe"
    rm -f "$new".tar.* "$new.stamp"; touch "$new.stamp"
    if pack_tar "$new" -C "$MEDIA" "$a"; then
      rm -f "$OUT/files/$safe".tar.*
      for f in "$new".tar.*; do mv "$f" "$OUT/files/$safe${f#$new}"; done
      mv "$new.stamp" "$OUT/files/$safe.stamp"
      printf '%s|%s\n' "$safe" "$a" >> "$OUT/files/index.txt"
    else
      bad=1; rm -f "$new".tar.* "$new.stamp"
      ls "$OUT/files/$safe".tar.* >/dev/null 2>&1 && echo "  kept the previous copy of $a"
    fi
    ;;
  TOP)
    echo "[$n] files directly in internal storage"
    safe=_loose_files; new="$OUT/files/.new-$safe"; list="$OUT/files/.new-$safe.list"
    rm -f "$new".tar.* "$new.stamp" "$list"; touch "$new.stamp"
    ( cd "$MEDIA" && for f in * .[!.]*; do [ -f "$f" ] && echo "$f"; done ) > "$list"
    if [ -s "$list" ] && pack_tar "$new" -C "$MEDIA" -T "$list"; then
      rm -f "$OUT/files/$safe".tar.*
      for f in "$new".tar.*; do mv "$f" "$OUT/files/$safe${f#$new}"; done
      mv "$new.stamp" "$OUT/files/$safe.stamp"; rm -f "$list"
      printf '%s|%s\n' "$safe" "(files directly in internal storage)" >> "$OUT/files/index.txt"
    elif [ ! -s "$list" ]; then
      echo "  no loose files any more"; rm -f "$new.stamp" "$list"
    else
      bad=1; rm -f "$new".tar.* "$new.stamp" "$list"
      ls "$OUT/files/$safe".tar.* >/dev/null 2>&1 && echo "  kept the previous copy"
    fi
    ;;
  esac
done < "$PLAN"
# Merge this run's items into the package's item list (an update adds to it).
if [ -f "$OUT/plan.txt" ]; then
  cat "$PLAN" "$OUT/plan.txt" | awk -F'|' '!seen[$1 "|" $2]++' > "$OUT/plan.tmp" && mv "$OUT/plan.tmp" "$OUT/plan.txt"
else
  cp "$PLAN" "$OUT/plan.txt"
fi
[ -f "$OUT/files/index.txt" ] && sort -u -o "$OUT/files/index.txt" "$OUT/files/index.txt"
cat > "$OUT/README.txt" <<'EOF2'
Tab S6 Migration Assistant package

apps/<package>/apk/*.apk            the app (base + split APKs)
apps/<package>/data.tar.aaa...      app private data (/data/data/<package>)
apps/<package>/data_de.tar.aaa...   device-encrypted data (/data/user_de/0/<package>)
apps/<package>/extdata.tar.aaa...   /sdcard/Android/data/<package>
apps/<package>/obb.tar.aaa...       /sdcard/Android/obb/<package>
apps/<package>/meta.txt             package, uid, version, keystore warning
files/<name>.tar.aaa...             folders from internal storage (index.txt maps names)
files/_loose_files.tar.aaa...       files directly in internal storage, not in a folder
SHA256SUMS                          checksums of every file

Archives are split into parts; join them with:  cat NAME.tar.* | tar -xf -
EOF2
( cd "$OUT" && find . -type f ! -name SHA256SUMS ! -name status.txt | sort | while read -r f; do sha256sum "$f"; done > SHA256SUMS )
# Internal storage files must belong to media_rw (1023) to stay readable over MTP/adb; no-op on FAT/exFAT cards.
chown -R 1023:1023 "${OUT%/*}" 2>/dev/null
if [ $bad = 0 ]; then echo complete > "$OUT/status.txt"; echo "PACK-OK"; else echo errors > "$OUT/status.txt"; echo "PACK-HAD-ERRORS"; fi
