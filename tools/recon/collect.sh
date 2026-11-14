#!/usr/bin/env bash
# collect.sh - ONE COMMAND: survey the tablet, build a privacy-scrubbed report, and (after you
# approve it) upload only that report to a temporary branch of this repository.
#
#   ./tools/recon/collect.sh
#
# Needs: the tablet booted into Android with USB debugging on and Magisk root for the shell,
#        adb on PATH, and this repository cloned with push access (git push must work).
#        On Windows, run it from "Git Bash" (installed with Git for Windows).
#
# What gets uploaded: ONE file, report.txt, on its own branch `recon-upload` (no shared
# history with the project, so deleting that branch removes it). The report is built from
# an allow-list of hardware/boot fields. It never includes the raw device tree, kernel command
# line, full kernel log, partition images or anything from efs. Your serial number, MAC
# addresses and e-mail addresses are scrubbed, and the upload is refused if the serial still
# appears anywhere. You see the full report and must type "yes" before anything leaves your computer.
#
# Everything else (full raw output) stays local in recon-out/, which git ignores.

set -u
cd "$(dirname "$0")/../.." || exit 1
ADB=(adb); [ $# -ge 1 ] && ADB=(adb -s "$1")
su_() { "${ADB[@]}" shell "su -c '$*'" 2>/dev/null | tr -d '\r'; }

command -v adb >/dev/null || { echo "adb not found. Install Android platform-tools and add it to PATH."; exit 1; }
command -v git >/dev/null || { echo "git not found."; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Run this from inside the cloned repository."; exit 1; }

echo "== Step 1/4: survey (read-only) =="
before=$(ls -d recon-out/2* 2>/dev/null | tail -1)
bash tools/recon/s6-recon.sh "$@" || exit 1
RUN=$(ls -d recon-out/2* 2>/dev/null | tail -1)
[ -n "$RUN" ] && [ "$RUN" != "$before" ] || { echo "Survey produced no output."; exit 1; }

echo
read -r -p "Also run the Design B test (writes ONE 1 MiB test file to /data/linux-probe)? [y/N] " PROBE
if [ "${PROBE:-n}" = "y" ] || [ "${PROBE:-n}" = "Y" ]; then
  bash tools/recon/s6-plaintext-probe.sh create "$@" | tail -4
fi

echo
echo "== Step 2/4: build the scrubbed report =="
REPORT="$RUN/report.txt"
{
  echo "# Tab S6 recon report (scrubbed)"
  echo "generated: $(date -u +%FT%TZ)"
  echo
  echo "## Summary"
  # The summary is written from allow-listed fields; drop any line that could carry identity.
  grep -v -i -E 'serial|cmdline|androidboot|imei|bt_addr|wlan_mac|ssid|@' "$RUN/summary.txt"
  echo
  echo "## Partitions (name -> block device)"
  awk '{print $(NF-2), $(NF-1), $NF}' "$RUN/partitions-by-name.txt" 2>/dev/null | grep -- '->'
  echo
  echo "## Partition sizes (/proc/partitions)"
  cat "$RUN/proc-partitions.txt" 2>/dev/null
  echo
  echo "## Physical memory map (/proc/iomem, top level)"
  grep -v '^ ' "$RUN/iomem.txt" 2>/dev/null
  echo
  echo "## /data top-level directories (names only)"
  awk '{print $NF}' "$RUN/data-toplevel.txt" 2>/dev/null | grep -v -E '^\.\.?$'
  echo
  echo "## CPU (/proc/cpuinfo without serial)"
  grep -v -i -E 'serial' "$RUN/cpuinfo.txt" 2>/dev/null | sort | uniq -c
  if [ -f recon-out/plaintext-probe.sha256 ]; then
    echo
    echo "## Design B probe"
    cat recon-out/plaintext-probe.sha256
  fi
} > "$REPORT.tmp"

# Scrub: the real serial number(s), MAC addresses, e-mail addresses.
SERIALS=$( { "${ADB[@]}" get-serialno 2>/dev/null; for p in ro.serialno ro.boot.serialno ril.serialnumber; do "${ADB[@]}" shell getprop "$p" 2>/dev/null; done; } | tr -d '\r' | grep -v -E '^(|unknown)$' | sort -u)
cp "$REPORT.tmp" "$REPORT"
for s in $SERIALS; do
  [ ${#s} -ge 6 ] || continue
  sed -i.bak "s/$s/[SERIAL]/g" "$REPORT"
done
sed -i.bak -E 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/[MAC]/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[EMAIL]/g' "$REPORT"
rm -f "$REPORT.tmp" "$REPORT.bak"

# Hard stop if any serial survived.
for s in $SERIALS; do
  if [ ${#s} -ge 6 ] && grep -q -- "$s" "$REPORT"; then
    echo "Serial number still present in the report. Not uploading. Report kept locally at $REPORT"; exit 1
  fi
done

echo
echo "== Step 3/4: review =="
echo "----------------------------------------------------------------------"
cat "$REPORT"
echo "----------------------------------------------------------------------"
echo "That is the complete content that would be uploaded (also saved at $REPORT)."
read -r -p "Upload it to branch 'recon-upload' of your repository? Type yes: " OK
[ "$OK" = "yes" ] || { echo "Not uploaded. You can still copy $REPORT by hand."; exit 0; }

echo
echo "== Step 4/4: upload =="
# Build a stand-alone commit containing only report.txt, with a generic author so your git
# name and e-mail are not attached, and push it as its own branch.
BLOB=$(git hash-object -w "$REPORT")
TREE=$(printf '100644 blob %s\treport.txt\n' "$BLOB" | git mktree)
COMMIT=$(GIT_AUTHOR_NAME=tabs6-recon GIT_AUTHOR_EMAIL=recon@localhost \
         GIT_COMMITTER_NAME=tabs6-recon GIT_COMMITTER_EMAIL=recon@localhost \
         git commit-tree "$TREE" -m "Scrubbed Tab S6 recon report (temporary)")
PUSHED=0
for i in 1 2 3 4; do
  if git push -f origin "$COMMIT:refs/heads/recon-upload"; then PUSHED=1; break; fi
  echo "Push failed, retrying in $((2**i)) s..."; sleep $((2**i))
done
[ $PUSHED -eq 1 ] || { echo "Upload failed. Report kept at $REPORT"; exit 1; }

echo
echo "Uploaded. Tell Claude: \"recon uploaded\"."
echo "To remove it later: git push origin --delete recon-upload"
