#!/usr/bin/env bash
# s6-restore - Tab S6 Migration Assistant, restore side (runs on Fedora, v0.2)
#
# Puts an S6Migrate package back together on the new system:
#   1. finds the package (USB drive, copied folder, or the path you give)
#   2. verifies it against SHA256SUMS
#   3. restores folders into your home (DCIM -> Pictures, Download -> Downloads, ...) without
#      overwriting anything: a name clash keeps both, the incoming file gets " (from Android)"
#   4. installs each app into Waydroid (split APKs included) and restores its data with the
#      new owner
#   5. makes Waydroid feel native: one window per app, Android's own system apps hidden from
#      the menu, your Linux folders shared into Android
#
# Usage: s6-restore [--dry-run] [--skip-verify] [--files-only|--apps-only] [--keystore-data] [--no-settings]
#                   [--yes] [PACKAGE_DIR]
#   --dry-run        show what would happen, change nothing
#   --keystore-data  also restore data of apps whose data was locked to the tablet's keystore
#                    (off by default: those apps usually need a fresh start and a new sign-in)
#
# Run it as your normal user inside the desktop session; it asks for sudo when it needs it.

set -u
VERSION=0.2.0
DRY=0; VERIFY=1; DO_FILES=1; DO_APPS=1; DO_SET=1; KS_DATA=0; YES=0; PKG=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --skip-verify) VERIFY=0 ;;
    --files-only) DO_APPS=0 ;;
    --apps-only) DO_FILES=0 ;;
    --keystore-data) KS_DATA=1 ;;
    --no-settings) DO_SET=0 ;;
    --yes|-y) YES=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) echo "Unknown option $a"; exit 2 ;;
    *) PKG="$a" ;;
  esac
done

WD=${S6R_WAYDROID_DATA:-$HOME/.local/share/waydroid/data}   # Waydroid's /data on the host
ETC=${S6R_ETC:-/etc}                                           # test hook
USER=${USER:-$(id -un)}
BTDIR=${S6R_BTDIR:-/var/lib/bluetooth}                         # test hook
SUDO=${S6R_SUDO-sudo}                                          # test hook
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$HOME/S6Migrate-restore-$STAMP.log"
STAGE="${XDG_CACHE_HOME:-$HOME/.cache}/s6migrate/stage-$STAMP"

say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
step() { printf '\n== %s ==\n' "$*" | tee -a "$LOG"; }
run()  { # run CMD... : execute, or only print in dry-run mode
  if [ $DRY = 1 ]; then printf '  would run: %s\n' "$*" | tee -a "$LOG"; return 0; fi
  "$@" >>"$LOG" 2>&1
}
ask() { [ $YES = 1 ] && return 0; local r; read -r -p "$1 [y/N] " r; [ "$r" = y ] || [ "$r" = Y ]; }
wd_sh() { # run a command inside the Waydroid container as root
  $SUDO waydroid shell -- sh -c "$1" </dev/null   # never let it read the caller's input
}

touch "$LOG" 2>/dev/null || LOG=/dev/null
say "Tab S6 Migration Assistant restore v$VERSION  $( [ $DRY = 1 ] && echo '(dry run: nothing is changed)')"
say "Log: $LOG"

# ------------------------------------------------------------------ 1. find the package
step "1/6 Find your package"
if [ -z "$PKG" ]; then
  mapfile -t found < <(ls -d /run/media/"$USER"/*/S6Migrate/*/ /media/"$USER"/*/S6Migrate/*/ \
      /var/lib/s6migrate/package*/ "$HOME"/S6Migrate/*/ ${S6R_SEARCH:-} 2>/dev/null \
      | while read -r d; do [ -f "$d/plan.txt" ] && echo "${d%/}"; done | sort -t/ -k1 | uniq)
  if [ ${#found[@]} -eq 0 ]; then
    say "No package found. Plug in the USB drive with the S6Migrate folder (or copy it to ~/S6Migrate/)"
    say "and run this again, or give the package folder:  s6-restore /path/to/S6Migrate/<date>"
    exit 1
  fi
  if [ ${#found[@]} -eq 1 ]; then PKG=${found[0]}
  else
    say "Packages found:"; for i in "${!found[@]}"; do say "  $((i+1)). ${found[$i]}"; done
    if [ $YES = 1 ]; then PKG=${found[-1]}
    else read -r -p "Which one? [1-${#found[@]}] " c; PKG=${found[$((c-1))]:-}; fi
  fi
fi
[ -f "$PKG/plan.txt" ] || { say "Not a package (no plan.txt): $PKG"; exit 1; }
NAPPS=$(grep -c '^APP|' "$PKG/plan.txt"); NDIRS=$(grep -c -E '^(DIR|TOP)\|' "$PKG/plan.txt")
say "Package: $PKG"
say "Contains $NAPPS apps and $NDIRS folders ($(du -sh "$PKG" 2>/dev/null | cut -f1)). Status: $(cat "$PKG/status.txt" 2>/dev/null || echo unknown)"

# ------------------------------------------------------------------ 2. verify
step "2/6 Check the package"
if [ $VERIFY = 1 ] && [ -f "$PKG/SHA256SUMS" ]; then
  total=$(grep -c . "$PKG/SHA256SUMS"); n=0; bad=0
  while read -r sum file; do
    n=$((n+1)); printf '\r  checking %d of %d' "$n" "$total"
    got=$(sha256sum "$PKG/${file#./}" 2>/dev/null | cut -d' ' -f1)
    [ "$got" = "$sum" ] || { bad=$((bad+1)); echo; say "  DAMAGED or missing: $file"; }
  done < "$PKG/SHA256SUMS"
  echo
  if [ $bad -gt 0 ]; then
    say "$bad file(s) failed the check. Items that use them may not restore correctly."
    ask "Continue anyway?" || exit 1
  else say "All $total files are intact."; fi
else
  say "Skipped."
fi

mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

# ------------------------------------------------------------------ 3. folders
xdg() { local d; d=$(xdg-user-dir "$1" 2>/dev/null); [ -n "$d" ] && [ "$d" != "$HOME" ] && echo "$d" || echo "$HOME/$2"; }
is_app_folder() { # folders that apps create in Android's shared storage (case-insensitive)
  local n; n=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$n" in
    .*|com.*|org.*|net.*|io.*|*.*.*) return 0 ;;
    telegram|telegram\ *|whatsapp|signal|snapchat|instagram|facebook|messenger|viber|discord|voxer*|\
    inshot|capcut|kinemaster|bluetooth|samsung*|soundcamp|walkband|twrp|temp|tmp|cache|backups|\
    tencent|miui|fonts|logs|log|android) return 0 ;;
  esac
  return 1
}
target_for() { # Android folder name -> Linux destination
  local over
  # The wizard can record the owner's own choice per folder: "<name>|<destination relative to ~>"
  if [ -f "$PKG/destinations.txt" ]; then
    over=$(grep -F -m1 "$1|" "$PKG/destinations.txt" | while IFS='|' read -r n d; do [ "$n" = "$1" ] && echo "$d"; done)
    [ -n "$over" ] && { echo "$HOME/${over#/}"; return; }
  fi
  case "$1" in
    DCIM)                         echo "$(xdg PICTURES Pictures)/DCIM" ;;
    Pictures|Screenshots)         echo "$(xdg PICTURES Pictures)" ;;
    Download|Downloads)           echo "$(xdg DOWNLOAD Downloads)" ;;
    Documents)                    echo "$(xdg DOCUMENTS Documents)" ;;
    Music)                        echo "$(xdg MUSIC Music)" ;;
    Movies|Videos)                echo "$(xdg VIDEOS Videos)" ;;
    Podcasts|Audiobooks|Recordings|Ringtones|Alarms|Notifications|"Voice Recorder"|"Sound recordings"|Call)
                                  echo "$(xdg MUSIC Music)/$1" ;;
    "(files directly in internal storage)") echo "$HOME/Android" ;;
    *) if is_app_folder "$1"; then echo "$HOME/Android/$1"   # made by an app: keep it out of the way
       else echo "$HOME/$1"; fi ;;                            # your own folder: top of your home, like on Android
  esac
}
merge_into() { # merge_into SRC_DIR DEST_DIR : move files, never overwrite; clash -> keep both
  local src=$1 dest=$2 moved=0 same=0 renamed=0 rel d
  while IFS= read -r -d '' f; do
    rel=${f#"$src"/}; d="$dest/$rel"
    mkdir -p "$(dirname "$d")"
    if [ ! -e "$d" ]; then mv "$f" "$d"; moved=$((moved+1))
    elif cmp -s "$f" "$d"; then same=$((same+1))
    else
      dn=${d%/*}; bn=${d##*/}
      case "$bn" in ?*.*) stem=${bn%.*}; ext=".${bn##*.}" ;; *) stem=$bn; ext="" ;; esac
      new="$dn/$stem (from Android)$ext"; k=2
      while [ -e "$new" ]; do new="$dn/$stem (from Android $k)$ext"; k=$((k+1)); done
      mv "$f" "$new"; renamed=$((renamed+1))
    fi
  done < <(find "$src" -type f -print0)
  say "    $moved new, $same already there, $renamed kept side by side (\"from Android\")"
}

if [ $DO_FILES = 1 ]; then
  step "3/6 Restore your folders"
  while IFS='|' read -r safe name; do
    [ -n "$safe" ] || continue
    ls "$PKG/files/$safe".tar.* >/dev/null 2>&1 || { say "  $name: archive missing, skipped"; continue; }
    dest=$(target_for "$name")
    say "  $name -> $dest"
    [ "$safe" != _loose_files ] && [ $DRY = 1 ] && echo "$dest|$name" >> "$STAGE/shares.list"
    [ $DRY = 1 ] && continue
    s="$STAGE/files/$safe"; mkdir -p "$s"
    if ! cat "$PKG/files/$safe".tar.* | tar -xf - -C "$s" 2>>"$LOG"; then say "    could not unpack, skipped"; continue; fi
    if [ "$safe" = _loose_files ]; then merge_into "$s" "$dest"
    else merge_into "$s/$name" "$dest"; echo "$dest|$name" >> "$STAGE/shares.list"; fi
    rm -rf "$s"
  done < "$PKG/files/index.txt"
else
  step "3/6 Restore your folders (skipped)"
fi

# ------------------------------------------------------------------ 4. settings
kwrite() { if command -v kwriteconfig6 >/dev/null; then kwriteconfig6 "$@"; else kwriteconfig5 "$@"; fi; }
apply_settings() {
  local S="$PKG/settings" val w f ext
  if [ -f "$S/settings.txt" ]; then
    val() { sed -n "s/^$1=//p" "$S/settings.txt" | head -1; }
    # Wallpapers (home and lock screen); Android stores them without a file extension.
    mkdir -p "$HOME/.local/share/wallpapers/S6Migrate"
    local home_wp="" lock_wp=""
    for w in wallpaper wallpaper_lock; do
      [ -s "$S/$w" ] || continue
      case "$(head -c 4 "$S/$w" | od -An -tx1 | tr -d ' \n')" in
        89504e47) ext=png ;; ffd8ff*) ext=jpg ;; 52494646) ext=webp ;; *) ext=jpg ;;
      esac
      f="$HOME/.local/share/wallpapers/S6Migrate/android-${w#wallpaper}.$ext"; f=${f/android-./android-home.}; f=${f/android-_lock/android-lock}
      [ $DRY = 1 ] || cp "$S/$w" "$f"
      [ "$w" = wallpaper ] && home_wp=$f || lock_wp=$f
    done
    [ -z "$lock_wp" ] && lock_wp=$home_wp
    if [ -n "$home_wp" ]; then
      run plasma-apply-wallpaperimage "$home_wp" && say "  wallpaper: set"
      run kwrite --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$lock_wp" \
        && say "  lock screen wallpaper: set"
    fi
    # Dark or light mode (Android: 2 = dark, 1 = light, 0 = automatic).
    case "$(val night_mode)" in
      2) run plasma-apply-lookandfeel -a org.kde.breezedark.desktop && say "  dark mode: on" ;;
      1) run plasma-apply-lookandfeel -a org.kde.breeze.desktop && say "  light mode: on" ;;
    esac
    # Time zone.
    local tz; tz=$(val timezone)
    if [ -n "$tz" ] && [ -f "/usr/share/zoneinfo/$tz" ]; then run $SUDO timedatectl set-timezone "$tz" && say "  time zone: $tz"; fi
    # Language and region (e.g. de-DE -> de_DE.UTF-8). English (US) is Fedora's default already.
    local loc; loc=$(val locale)
    if [ -n "$loc" ] && [ "$loc" != en-US ]; then
      local l=${loc%%-*} c=${loc#*-}; [ "$c" = "$loc" ] && c="" ; local lc="${l}${c:+_$c}.UTF-8"
      run kwrite --file plasma-localerc --group Formats --key LANG "$lc"
      run kwrite --file plasma-localerc --group Translations --key LANGUAGE "${l}${c:+_$c}:${l}" \
        && say "  language and region: $lc (applies at next login; more languages: sudo dnf install langpacks-$l)"
    fi
    # Device name.
    local dn; dn=$(val device_name)
    if [ -n "$dn" ] && [ "$dn" != null ]; then
      local hn; hn=$(printf '%s' "$dn" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9-' '-' | sed 's/^-*//; s/-*$//; s/--*/-/g')
      run $SUDO hostnamectl set-hostname --pretty "$dn" && run $SUDO hostnamectl set-hostname --static "${hn:-galaxy-tab-s6}" \
        && say "  device name: $dn"
    fi
  fi
  # Wi-Fi networks.
  if [ -f "$PKG/wifi/WifiConfigStore.xml" ]; then
    local added=0 skipped=0 manual=""
    while IFS=$'\x1f' read -r ssid sec psk hidden; do   # unit separator: empty fields survive
      [ -n "$ssid" ] || continue
      if nmcli -g NAME connection show 2>/dev/null | grep -Fxq "$ssid"; then skipped=$((skipped+1)); continue; fi
      case "$sec" in
        psk) run nmcli connection add type wifi con-name "$ssid" ssid "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" 802-11-wireless.hidden "$hidden" ;;
        sae) run nmcli connection add type wifi con-name "$ssid" ssid "$ssid" wifi-sec.key-mgmt sae wifi-sec.psk "$psk" 802-11-wireless.hidden "$hidden" ;;
        open) run nmcli connection add type wifi con-name "$ssid" ssid "$ssid" 802-11-wireless.hidden "$hidden" ;;
        *) manual="$manual${manual:+, }$ssid"; continue ;;
      esac && added=$((added+1))
    done < <(python3 - "$PKG/wifi/WifiConfigStore.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for net in root.iter('Network'):
    wc = net.find('WifiConfiguration')
    if wc is None:
        continue
    def get(name):
        e = wc.find("*[@name='%s']" % name)
        if e is None:
            return None
        return e.text if e.tag == 'string' else e.get('value')
    ssid, psk, key = get('SSID'), get('PreSharedKey'), get('ConfigKey') or ''
    if not ssid or not (ssid.startswith('"') and ssid.endswith('"')):
        continue                      # hex/unusual SSIDs: add by hand
    ssid = ssid[1:-1]
    if psk and psk.startswith('"') and psk.endswith('"'):
        psk = psk[1:-1]
    sec = ('sae' if key.endswith('SAE') else 'psk' if key.endswith('WPA_PSK') else 'open' if key.endswith('NONE')
           else 'eap' if 'EAP' in key else 'wep' if key.endswith('WEP') else 'owe' if key.endswith('OWE') else 'other')
    if sec in ('psk', 'sae') and not psk:
        sec = 'encrypted'
    print('\x1f'.join([ssid, sec, psk or '', 'yes' if get('HiddenSSID') == 'true' else 'no']))
PY
)
    say "  Wi-Fi: $added network(s) added, $skipped already there${manual:+; add these yourself (work, WEP or protected): $manual}"
  fi
  # Bluetooth pairings (experimental): only when the Bluetooth chip address is the same as on Android.
  if [ -f "$PKG/settings/bt_config.conf" ]; then
    local bstage="$STAGE/bluetooth"; mkdir -p "$bstage"
    local res; res=$(python3 - "$PKG/settings/bt_config.conf" "$BTDIR" "$bstage" <<'PY'
import sys, os, configparser
src, btdir, out = sys.argv[1:4]
cp = configparser.ConfigParser(strict=False, interpolation=None)
cp.optionxform = str
cp.read(src)
android = cp.get('Adapter', 'Address', fallback='').upper()
try:
    adapters = [a.upper() for a in os.listdir(btdir) if len(a) == 17]
except OSError:
    adapters = []
if not android or android not in adapters:
    print('skip:' + ('Bluetooth is not running yet' if not adapters else 'the Bluetooth address differs from Android'))
    sys.exit(0)
n = 0
for sec in cp.sections():
    if len(sec) != 17 or sec.count(':') != 5 or not cp.has_option(sec, 'LinkKey'):
        continue
    dev = sec.upper()
    if os.path.exists(os.path.join(btdir, android, dev)):
        continue                      # already paired on Fedora: keep it
    d = os.path.join(out, android, dev)
    os.makedirs(d, exist_ok=True)
    cls = cp.get(sec, 'DevClass', fallback='')
    with open(os.path.join(d, 'info'), 'w') as f:
        f.write('[General]\nName=%s\n' % cp.get(sec, 'Name', fallback=dev))
        if cls.isdigit():
            f.write('Class=0x%06x\n' % int(cls))
        f.write('SupportedTechnologies=BR/EDR;\nTrusted=true\nBlocked=false\n\n')
        f.write('[LinkKey]\nKey=%s\nType=%s\nPINLength=%s\n' % (cp.get(sec, 'LinkKey').upper(),
                cp.get(sec, 'LinkKeyType', fallback='4'), cp.get(sec, 'PinLength', fallback='0')))
    n += 1
print('ok:%d:%s' % (n, android))
PY
)
    case "$res" in
      ok:0:*) say "  Bluetooth: nothing new to add" ;;
      ok:*) local nb=${res#ok:}; nb=${nb%%:*}
            if [ $DRY = 1 ]; then say "  would add $nb Bluetooth pairing(s) (experimental)"
            else $SUDO cp -r "$bstage"/* "$BTDIR"/ && $SUDO chmod -R go-rwx "$BTDIR" \
                   && run $SUDO systemctl restart bluetooth \
                   && say "  Bluetooth: $nb pairing(s) added (experimental: if a device does not connect, pair it again once)"; fi ;;
      skip:*) say "  Bluetooth: not carried over (${res#skip:}); pair your devices again once" ;;
    esac
  fi
}

if [ $DO_FILES = 1 ] && [ $DO_SET = 1 ] && { [ -d "$PKG/settings" ] || [ -d "$PKG/wifi" ]; }; then
  step "4/6 Your settings"
  apply_settings
else
  step "4/6 Your settings (skipped)"
fi

# ------------------------------------------------------------------ 5. apps into Waydroid
install_apk_set() { # install_apk_set PKG : copy APKs into the container and install them as one session
  local pkg=$1 cdir="/data/local/tmp/s6m/$pkg" hdir="$WD/local/tmp/s6m/$pkg"
  run $SUDO mkdir -p "$hdir" || return 1
  run $SUDO cp "$PKG/apps/$pkg/apk/"*.apk "$hdir/" || return 1
  run $SUDO chmod -R a+rX "$WD/local/tmp/s6m" || return 1
  local script="sid=\$(pm install-create -r | sed -n 's/.*\\[\\([0-9]*\\)\\].*/\\1/p'); [ -n \"\$sid\" ] || exit 1;
    for f in $cdir/*.apk; do pm install-write -S \$(stat -c %s \"\$f\") \$sid \$(basename \"\$f\") \"\$f\" >/dev/null || exit 1; done;
    pm install-commit \$sid"
  if [ $DRY = 1 ]; then say "  would install $(ls "$PKG/apps/$pkg/apk/" | wc -l) APK file(s) in Waydroid"; return 0; fi
  wd_sh "$script" >>"$LOG" 2>&1
  local rc=$?
  $SUDO rm -rf "$hdir"
  return $rc
}
restore_tree() { # restore_tree ARCHIVE_BASENAME HOST_PARENT OWNER : unpack <pkg> dir into HOST_PARENT
  local base=$1 parent=$2 owner=$3 pkg=$4
  ls "$base".tar.* >/dev/null 2>&1 || return 0
  if [ $DRY = 1 ]; then say "    would restore $(basename "$base") -> ${parent#$WD} (owner $owner)"; return 0; fi
  local tmp="$WD/local/tmp/s6m/x-$pkg"
  $SUDO rm -rf "$tmp"; $SUDO mkdir -p "$tmp" "$parent"
  cat "$base".tar.* | $SUDO tar -xf - -C "$tmp" 2>>"$LOG" || { say "    could not unpack $(basename "$base")"; return 1; }
  $SUDO rm -rf "$parent/$pkg"
  $SUDO mv "$tmp/$pkg" "$parent/$pkg"
  $SUDO chown -R "$owner" "$parent/$pkg"
  $SUDO rm -rf "$tmp"
}

if [ $DO_APPS = 1 ] && [ "$NAPPS" -gt 0 ]; then
  step "5/6 Bring your apps into Waydroid"
  if ! command -v waydroid >/dev/null; then
    say "Waydroid is not installed. Install it with:  sudo dnf install waydroid  then run:  s6-restore --apps-only"
  elif [ ! -d "$WD" ]; then
    say "Waydroid is not set up yet. Run:  sudo waydroid init  (add -s GAPPS for Google Play),"
    say "start Waydroid once from the app menu, then run:  s6-restore --apps-only"
  elif ! waydroid status 2>/dev/null | grep -q 'Session:.*RUNNING'; then
    say "Waydroid is set up but not running. Open Waydroid from the app menu, wait for it to start,"
    say "then run:  s6-restore --apps-only"
  else
    ok=0; fail=0
    while IFS='|' read -r t pkg olduid ks; do
      [ "$t" = APP ] || continue
      [ -d "$PKG/apps/$pkg" ] || { say "  $pkg: not in the package, skipped"; continue; }
      say "  $pkg"
      if ! install_apk_set "$pkg"; then say "    install failed (see log)"; fail=$((fail+1)); continue; fi
      if [ "$ks" = keystore ] && [ $KS_DATA = 0 ]; then
        say "    installed fresh: its data was locked to the tablet (use --keystore-data to restore it anyway)"
        ok=$((ok+1)); continue
      fi
      if [ $DRY = 1 ]; then uid=NEWUID; else
        wd_sh "am force-stop $pkg" >/dev/null 2>&1
        uid=$($SUDO stat -c %u "$WD/data/$pkg" 2>/dev/null)
      fi
      if [ -z "$uid" ]; then say "    app installed, but its data folder was not found; data not restored"; fail=$((fail+1)); continue; fi
      restore_tree "$PKG/apps/$pkg/data"    "$WD/data"                  "$uid:$uid" "$pkg"
      restore_tree "$PKG/apps/$pkg/data_de" "$WD/user_de/0"             "$uid:$uid" "$pkg"
      restore_tree "$PKG/apps/$pkg/extdata" "$WD/media/0/Android/data"  "$uid:1078" "$pkg"   # ext_data_rw
      restore_tree "$PKG/apps/$pkg/obb"     "$WD/media/0/Android/obb"   "$uid:1079" "$pkg"   # ext_obb_rw
      if [ $DRY = 0 ] && [ -n "$uid" ]; then
        cg=$((uid - 10000 + 20000))   # u0_aNN_cache group for cache folders
        for c in cache code_cache; do [ -d "$WD/data/$pkg/$c" ] && $SUDO chown -R "$uid:$cg" "$WD/data/$pkg/$c"; done
        wd_sh "restorecon -RF /data/data/$pkg /data/user_de/0/$pkg 2>/dev/null; true" >/dev/null 2>&1
      fi
      [ $DRY = 1 ] && say "    (dry run)" || say "    restored"
      ok=$((ok+1))
    done < "$PKG/plan.txt"
    say "Apps: $ok done, $fail with problems."
  fi
else
  step "5/6 Bring your apps into Waydroid (skipped)"
fi

# ------------------------------------------------------------------ 6. make Waydroid feel native
step "6/6 Make Android apps feel native"
if command -v waydroid >/dev/null && [ -d "$WD" ]; then
  # One window per app instead of an Android home screen.
  run waydroid prop set persist.waydroid.multi_windows true && say "  Android apps open in their own windows"
  # Hide Android's own system apps from the app menu: Linux apps do these jobs.
  hidden=0
  for id in com.android.documentsui org.lineageos.jelly com.android.gallery3d org.lineageos.glimpse \
            com.android.contacts com.android.dialer com.android.messaging org.lineageos.etar \
            com.android.deskclock org.lineageos.recorder com.android.camera2 org.lineageos.aperture \
            com.android.settings; do
    f="$HOME/.local/share/applications/waydroid.$id.desktop"
    [ -f "$f" ] || continue
    grep -q '^NoDisplay=true' "$f" && continue
    if [ $DRY = 1 ]; then say "  would hide $id"; else echo 'NoDisplay=true' >> "$f"; fi
    hidden=$((hidden+1))
  done
  say "  $hidden Android system app(s) hidden from the menu (Waydroid's own Settings stays in its menu entry)"
  # Share the Linux folders with Android apps, so there is one set of files.
  SHARE="$ETC/s6migrate/waydroid-share.sh"
  LIST="$ETC/s6migrate/shares.list"   # "<Linux folder>|<name inside Android>", one per line
  if [ $DRY = 1 ]; then
    say "  would share with Android apps: Pictures, Downloads, Documents, Music, Videos"
    [ -f "$STAGE/shares.list" ] && while IFS='|' read -r d n; do
      case "$n" in Pictures|Download|Downloads|Documents|Music|Movies|Videos) continue ;; esac
      say "    and ${d/#$HOME/~} as /sdcard/$n"
    done < "$STAGE/shares.list"
  else
    $SUDO mkdir -p "$ETC/s6migrate"
    if [ -f "$STAGE/shares.list" ]; then   # merge with folders shared by earlier runs
      { [ -f "$LIST" ] && cat "$LIST"; cat "$STAGE/shares.list"; } | awk -F'|' '!seen[$2]++' > "$STAGE/shares.merged"
      $SUDO install -m 644 "$STAGE/shares.merged" "$LIST"
    fi
    tmp=$(mktemp)
    cat > "$tmp" <<EOF
#!/bin/sh
# Generated by s6-restore: show the Linux user folders inside Waydroid (Android sees them as its own).
WD="$WD"
share() { # share HOST_DIR ANDROID_NAME
  [ -d "\$1" ] || return 0
  mkdir -p "\$WD/media/0/\$2"
  mountpoint -q "\$WD/media/0/\$2" && return 0
  if command -v bindfs >/dev/null; then
    bindfs -u 1023 -g 1023 --create-for-user=$(id -u) --create-for-group=$(id -g) "\$1" "\$WD/media/0/\$2"
  else
    mount --bind "\$1" "\$WD/media/0/\$2"
  fi
}
share "$(xdg PICTURES Pictures)" Pictures
share "$(xdg DOWNLOAD Downloads)" Download
share "$(xdg DOCUMENTS Documents)" Documents
share "$(xdg MUSIC Music)" Music
share "$(xdg VIDEOS Videos)" Movies
# Every folder restored from the tablet, at the name Android apps knew it by
# (so e.g. the Android Telegram app finds ~/Android/Telegram as /sdcard/Telegram).
[ -f "$LIST" ] && while IFS='|' read -r d n; do
  case "\$n" in Pictures|Download|Downloads|Documents|Music|Movies|Videos|""|*/*) continue ;; esac
  share "\$d" "\$n"
done < "$LIST"
EOF
    $SUDO mkdir -p "$ETC/s6migrate" && $SUDO install -m 755 "$tmp" "$SHARE"
    rm -f "$tmp"
    unit=$(mktemp)
    cat > "$unit" <<EOF
[Unit]
Description=Share Linux user folders with Waydroid (S6 Migrate)
After=local-fs.target
Before=waydroid-container.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SHARE

[Install]
WantedBy=multi-user.target
EOF
    $SUDO mkdir -p "$ETC/systemd/system"
    $SUDO install -m 644 "$unit" "$ETC/systemd/system/s6migrate-waydroid-share.service"; rm -f "$unit"
    $SUDO systemctl daemon-reload >>"$LOG" 2>&1
    $SUDO systemctl enable --now s6migrate-waydroid-share.service >>"$LOG" 2>&1 \
      && say "  Pictures, Downloads, Documents, Music, Videos and $( [ -f "$LIST" ] && grep -c . "$LIST" || echo 0) restored folder(s) are shared with Android apps at their old names" \
      || say "  folder sharing could not start; see the log (bindfs gives the best results: sudo dnf install bindfs)"
    command -v bindfs >/dev/null || say "  tip: sudo dnf install bindfs  lets Android apps also save into those folders"
  fi
else
  say "  Waydroid not set up yet; run s6-restore again after it is."
fi

# Keep it working: the repair tool also installs a watcher that re-hides Android system apps if Waydroid
# recreates their menu entries.
if command -v s6-doctor >/dev/null && [ $DRY = 0 ]; then s6-doctor --fix >>"$LOG" 2>&1; say "  s6-doctor: checked and repaired (run 's6-doctor' any time)"; fi

step "Done"
say "Your package is untouched at $PKG; keep it until everything looks right."
say "Full log: $LOG"
