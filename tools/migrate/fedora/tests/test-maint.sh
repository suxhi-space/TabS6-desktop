#!/bin/bash
# Runs s6-maint end to end with stand-ins for dnf, curl, rpm and ldd (CI). Checks: a single queued job really runs
# (fix 10's version silently exited when not every job type was queued), a failed download round is retried,
# installing happens only from the cache, the job is cleared, and nothing runs without a job.
set -e
here=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state/maint"; date > "$T/state/maint/repair"
cat > "$T/bin/dnf" <<EOF
#!/bin/bash
echo "dnf \$*" >> "$T/dnf.calls"
# Like dnf5: --downloadonly is an option of the command, so it must come after the command word.
pre=""; for a in "\$@"; do case "\$a" in distro-sync|install|reinstall|upgrade|remove) break ;; --downloadonly) echo "Unknown argument \"--downloadonly\" for command \"dnf5\""; exit 2 ;; esac; done
case "\$*" in *distro-sync*--downloadonly*) n=\$(cat "$T/round" 2>/dev/null || echo 0); echo \$((n+1)) > "$T/round"; [ \$n -ge 1 ] || exit 1 ;; esac
exit 0
EOF
for c in chvt rpm sleep; do printf '#!/bin/sh\nexit 0\n' > "$T/bin/$c"; done
printf '#!/bin/sh\ncase "$*" in *-sI*) printf "Date: Mon, 16 Nov 2026 15:20:00 GMT\\r\\n";; esac\nexit 0\n' > "$T/bin/curl"
printf '#!/bin/sh\n[ "$1" = -s ] && exit 0\nexec /bin/date "$@"\n' > "$T/bin/date"
printf '#!/bin/sh\necho "	libkwin.so.6 => /lib64/libkwin.so.6 (0x1)"\n' > "$T/bin/ldd"
chmod +x "$T/bin/"*
sed 's#/usr/bin/kwin_wayland#/bin/true#g' "$here/../system/s6-maint" > "$T/s6-maint"
env -i PATH="$T/bin:/usr/bin:/bin" S6M_STATE="$T/state" S6M_TTY="$T/tty" bash "$T/s6-maint"
grep -q 'Round 1 stopped' "$T/tty" || { echo "FAIL: no retry"; exit 1; }
grep -q -- '-C .*distro-sync' "$T/dnf.calls" || { echo "FAIL: did not install from the cache"; exit 1; }
grep -q 'All done' "$T/tty" || { echo "FAIL: not finished"; exit 1; }
[ ! -e "$T/state/maint/repair" ] || { echo "FAIL: job not cleared"; exit 1; }
rm -f "$T/tty"; env -i PATH="$T/bin:/usr/bin:/bin" S6M_STATE="$T/state" S6M_TTY="$T/tty" bash "$T/s6-maint"
[ ! -e "$T/tty" ] || { echo "FAIL: ran without a job"; exit 1; }
echo "s6-maint: ok"
