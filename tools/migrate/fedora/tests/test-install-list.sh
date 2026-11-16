#!/bin/bash
# Every file S6 Setup / S6 Companion load, and every system file, must be in install.list (CI). Picker.qml was
# once left out: the app ran fine from the repo, but on the tablet S6 Setup crashed at its start.
here=$(cd "$(dirname "$0")/.." && pwd); fail=0
cd "$here"
for f in app/*.py app/qml/*.qml app/qml/qmldir system/* s6-* plasmoid/*/metadata.json plasmoid/*/contents/ui/*.qml; do
  case "$f" in *__pycache__*) continue ;; esac
  grep -q "^fedora/$f|" install.list || { echo "MISSING from install.list: $f"; fail=1; }
done
# and every QML type named in qmldir has its file installed
while read -r name ver file; do
  [ "$name" = singleton ] && file=$(echo "$ver $file" | awk '{print $3}')
  [ -n "$file" ] && { grep -q "app/qml/$file|" install.list || { echo "qmldir names $file, not installed"; fail=1; }; }
done < app/qml/qmldir
[ $fail = 0 ] && echo "install.list: ok"; exit $fail
