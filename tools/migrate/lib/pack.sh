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
  LINUX)
    # "Linux only": the Android app and its data are not stored; s6-restore installs the Linux version.
    echo "[$n] app $a: Linux version only (${b:-see list}), nothing stored"
    rm -rf "$OUT/apps/$a"
    ;;
  SET)
    # Wallpapers, dark mode, time zone, language, device name, Bluetooth pairings. Small: always re-captured.
    echo "[$n] settings (wallpaper, dark mode, time zone, language, device name, Bluetooth)"
    new="$OUT/.new-settings"; rm -rf "$new"; mkdir -p "$new"
    {
      echo "timezone=$(getprop persist.sys.timezone </dev/null)"
      echo "locale=$(getprop persist.sys.locale </dev/null)"
      echo "night_mode=$(settings get secure ui_night_mode </dev/null 2>/dev/null)"
      echo "device_name=$(settings get global device_name </dev/null 2>/dev/null)"
      echo "time_12_24=$(settings get system time_12_24 </dev/null 2>/dev/null)"
      echo "screen_off_timeout=$(settings get system screen_off_timeout </dev/null 2>/dev/null)"
      echo "auto_rotate=$(settings get system accelerometer_rotation </dev/null 2>/dev/null)"
    } > "$new/settings.txt"
    for w in wallpaper wallpaper_lock; do
      [ -f "$RP/data/system/users/0/$w" ] && cp "$RP/data/system/users/0/$w" "$new/$w"
    done
    [ -f "$RP/data/misc/bluedroid/bt_config.conf" ] && cp "$RP/data/misc/bluedroid/bt_config.conf" "$new/bt_config.conf"
    touch "$new/stamp"
    rm -rf "$OUT/settings"; mv "$new" "$OUT/settings"
    echo "  ok: settings ($(ls "$OUT/settings" | grep -c -E '^wallpaper') wallpaper(s)$( [ -f "$OUT/settings/bt_config.conf" ] && echo ', Bluetooth pairings'))"
    ;;
  WIFI)
    # Saved Wi-Fi networks with their passwords (Android keeps them readable to root on most devices).
    echo "[$n] Wi-Fi networks and passwords"
    src=""
    for f in "$RP/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml" "$RP/data/misc/wifi/WifiConfigStore.xml"; do
      [ -f "$f" ] && { src=$f; break; }
    done
    if [ -n "$src" ]; then
      new="$OUT/.new-wifi"; rm -rf "$new"; mkdir -p "$new"
      cp "$src" "$new/WifiConfigStore.xml" && chmod 600 "$new/WifiConfigStore.xml" && touch "$new/stamp"
      rm -rf "$OUT/wifi"; mv "$new" "$OUT/wifi"
      echo "  ok: $(grep -c '<Network>' "$OUT/wifi/WifiConfigStore.xml") saved network(s)"
    else
      echo "  no saved Wi-Fi networks found"
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
  cat "$PLAN" "$OUT/plan.txt" | awk -F'|' '{ k = ($1 == "LINUX" ? "APP" : $1) "|" $2 } !seen[k]++' > "$OUT/plan.tmp" && mv "$OUT/plan.tmp" "$OUT/plan.txt"
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
settings/                           wallpapers, settings.txt (time zone, language, dark mode...), Bluetooth pairings
wifi/WifiConfigStore.xml            saved Wi-Fi networks WITH PASSWORDS: keep this drive private
SHA256SUMS                          checksums of every file

Archives are split into parts; join them with:  cat NAME.tar.* | tar -xf -
EOF2
# Checksums: on an update, reuse the existing checksum of every file that has not changed since the
# last SHA256SUMS was written; only new or re-packed files are read again (fast even for big packages).
echo "Updating checksums..."
(
  cd "$OUT" || exit 1
  old=SHA256SUMS; [ -f "$old" ] || old=""
  find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.new ! -name status.txt | sort | while read -r f; do
    line=""
    if [ -n "$old" ] && [ ! "$f" -nt "$old" ]; then
      line=$(grep -F "  $f" "$old" | while IFS= read -r l; do [ "${l#*  }" = "$f" ] && { echo "$l"; break; }; done)
    fi
    if [ -n "$line" ]; then echo "$line"; else sha256sum "$f"; fi
  done > SHA256SUMS.new && mv SHA256SUMS.new SHA256SUMS
)
# Internal storage files must belong to media_rw (1023) to stay readable over MTP/adb; no-op on FAT/exFAT cards.
chown -R 1023:1023 "${OUT%/*}" 2>/dev/null
if [ $bad = 0 ]; then echo complete > "$OUT/status.txt"; echo "PACK-OK"; else echo errors > "$OUT/status.txt"; echo "PACK-HAD-ERRORS"; fi
