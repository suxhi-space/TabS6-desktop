#!/usr/bin/env bash
# Verifies the scripts embedded in s6-migrate.sh match tools/migrate/lib (the copies the Android app ships).
cd "$(dirname "$0")" || exit 1
ok=0
for pair in scan:SCAN pack:PACK; do
  f=${pair%%:*}; tag=${pair##*:}
  sed -n "/^cat > \"\$W\/$f.sh\" <<'$tag'\$/,/^$tag\$/p" s6-migrate.sh | sed '1d;$d' | diff -q - "lib/$f.sh" >/dev/null \
    && echo "in sync: $f.sh" || { echo "OUT OF SYNC: $f.sh"; ok=1; }
done
exit $ok
