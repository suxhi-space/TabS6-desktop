# compare.sh RP PKG - what changed on the tablet since the package PKG was made.
# Android sh, run as root, read-only. Prints one line per item in the package:
#   CMP|APP|<package>|same|changed|gone|unknown|<changed files>
#   CMP|DIR|<folder>|same|changed|gone|unknown|<changed files>
# Cache folders are ignored: they change constantly and are not worth re-packing for.
RP="$1"; MEDIA="$RP/data/media/0"; PKG="$2"
newer() { # newer REF PATH... -> number of files changed after REF (counting stops at 1000 per path)
  ref="$1"; shift; n=0
  for d in "$@"; do
    [ -e "$d" ] || continue
    c=$(find "$d" -type f -newer "$ref" ! -path '*/cache/*' ! -path '*/code_cache/*' ! -name cache ! -name code_cache 2>/dev/null | head -1000 | wc -l)
    n=$((n + c))
  done
  echo "$n"
}
while IFS='|' read -r t a rest; do
  case "$t" in
  APP)
    pkg="$a"; ref="$PKG/apps/$pkg/meta.txt"
    paths=$(pm path "$pkg" </dev/null 2>/dev/null | sed 's/^package://')
    if [ -z "$paths" ]; then echo "CMP|APP|$pkg|gone|0"; continue; fi
    [ -f "$ref" ] || { echo "CMP|APP|$pkg|unknown|0"; continue; }
    n=$(newer "$ref" "$RP/data/data/$pkg" "$RP/data/user_de/0/$pkg" "$MEDIA/Android/data/$pkg" "$MEDIA/Android/obb/$pkg")
    for p in $paths; do [ "$RP$p" -nt "$ref" ] && n=$((n + 1)); done
    [ "$n" -gt 0 ] && echo "CMP|APP|$pkg|changed|$n" || echo "CMP|APP|$pkg|same|0"
    ;;
  DIR)
    name="$a"; safe=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')
    if [ ! -d "$MEDIA/$name" ]; then echo "CMP|DIR|$name|gone|0"; continue; fi
    ref="$PKG/files/$safe.stamp"; [ -f "$ref" ] || ref="$PKG/files/$safe.tar.aaa"
    [ -f "$ref" ] || { echo "CMP|DIR|$name|unknown|0"; continue; }
    n=$(newer "$ref" "$MEDIA/$name")
    [ "$n" -gt 0 ] && echo "CMP|DIR|$name|changed|$n" || echo "CMP|DIR|$name|same|0"
    ;;
  esac
done < "$PKG/plan.txt"
echo "CMP-DONE"
