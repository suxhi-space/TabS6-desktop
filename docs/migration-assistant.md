# Migration Assistant: move from Android to Linux without manual backups

**Goal:** a program that works like a desktop OS upgrade. You pick which files, apps and app
data to keep, it installs Linux, moves your selection over, and removes the old OS, without
you managing backups yourself.

**Status: v0.1 (Pack) built** as `tools/migrate/s6-migrate.sh`. It runs in Termux with root and does
not change Android. v0.2 (restore on Fedora) and v0.3 (one-button switch) are next.

| Version | Does | State |
|---|---|---|
| v0.1 Pack | Menus to pick your own apps (with data) and internal-storage folders; packs them to the microSD card or internal storage as split, checksummed archives; flags apps with Android Keystore keys | Built, tested against a simulated tablet |
| v0.2 Restore | Fedora side: installs the packed apps into Waydroid with their data, unpacks folders into `~/`, sets up the native-feel integration below | Planned |
| v0.3 Switch | Downloads Fedora to the card, writes a TWRP script, installs from TWRP (the t860-fedora installer reads the image from a stream), copies the package into the new system, boots Fedora | Planned |

### Installing and running v0.1

In Termux (needs a GitHub token with Contents: read on this repo, see README):

```bash
pkg install -y sqlite; read -rsp 'GitHub token: ' T; echo; curl -fsSL -H "Authorization: Bearer $T" -H 'Accept: application/vnd.github.raw' 'https://api.github.com/repos/suxhi-space/TabS6-desktop/contents/tools/migrate/s6-migrate.sh?ref=claude/android-tablet-desktop-ui-755uqh' -o $PREFIX/bin/s6-migrate && chmod +x $PREFIX/bin/s6-migrate; unset T; echo 'Installed. Run: s6-migrate'
```

Then run `s6-migrate` any time. Package layout: `S6Migrate/<date>/apps/<package>/{apk/,data.tar.*,data_de.tar.*,extdata.tar.*,obb.tar.*,meta.txt}`,
`files/<folder>.tar.*`, `SHA256SUMS`, `README.txt`.

## The constraint that shapes everything

On a Mac or PC, the new OS can read the old OS's files straight off the disk. **Android
cannot be migrated that way.** Its data partition uses file-based encryption with keys bound
to the tablet's security hardware, unlocked only by a running Android after you enter your
PIN. Linux, or an installer in TWRP, sees encrypted file contents it cannot read.

So the copying has to happen **while Android is running**. And because Fedora's
installer overwrites `userdata` (the only large partition), the selected data needs
somewhere to wait unless Linux can live alongside Android. That gives two designs.

## Design A: guided migration with temporary staging (buildable now)

```text
Android (running, rooted)                TWRP (installer)                  Fedora first boot
┌────────────────────────────┐           ┌──────────────────────────┐      ┌──────────────────────────┐
│ Migration Assistant        │           │ t860-fedora installer    │      │ restore service          │
│ 1. pick files / apps / data│──stage──▶ │ 3. writes Fedora         │────▶ │ 5. waydroid init         │
│ 2. export to PC (USB) or   │           │ 4. copies staged files   │      │ 6. restores apps + data  │
│    microSD, with checksums │           │    into /home            │      │    into Waydroid         │
└────────────────────────────┘           └──────────────────────────┘      └──────────────────────────┘
```

- **What you do:** tick boxes, plug in the USB cable (or insert a microSD card), confirm.
- **What it does:** stages your selection with checksums, runs the installer, copies files
  into your Linux home during install, and on first boot sets up Waydroid and restores the
  chosen apps with their data.
- **Needs:** temporary space equal to your selection, on a computer or a microSD card.
  Android can write the card; TWRP can read it.
- **Risk:** same as the plan in [`linux-install-plan.md`](linux-install-plan.md), which this
  automates. Your data exists in two places before anything is erased.
- **Effort:** moderate. Mostly scripting around tools that already exist: Neo Backup's
  format or plain `tar`, the t860-fedora installer, Waydroid.

## Design B: Linux next to Android, then retire Android (true in-place, research)

```text
userdata partition (Android's, stays as is)
├── Android data (encrypted, untouched)
└── /data/<plaintext dir>/linux-root.img   ← Fedora lives in this file
        ▲
        │ Android (rooted) loop-mounts it and copies your picks in,
        │ already decrypted, because Android is the one reading them
        ▼
Boot menu: [Fedora] [Android]   ← Android stays bootable until you choose to remove it
```

1. While Android runs, the assistant creates a large image file in a directory Android
   leaves unencrypted. Android's own Dynamic System Updates keep GSI images in such a place,
   `/data/gsi`. It writes Fedora into that file.
2. Android loop-mounts the image and copies your selected files and app data into it. No
   external storage needed.
3. The UEFI boot gets two entries: Fedora (its initramfs mounts `userdata` and boots from
   the image file) and Android (the stock kernel).
4. You use both for as long as you like. **"Remove old OS"** deletes Android's data to free
   space, then grows the Linux image into it.

**Why it is research, not a plan yet:**

| Open question | How we find out |
|---|---|
| Does your vendor fstab use **metadata encryption**? If so, the whole partition is encrypted and Linux cannot even mount it, which rules out B | `s6-recon.sh` now prints the `/data` fstab line and says which case you are in |
| Is there a plaintext directory where the image stays readable to Linux? | `s6-plaintext-probe.sh` (see "How we will know" below) |
| Is it safe for mainline Linux to mount Samsung's `userdata` (f2fs or ext4) read-write? A mistake here could damage Android's data | Read-only mount tests first; Android stays the fallback |
| Can Aloha UEFI boot the stock Android kernel as a second entry? | UEFI experiment; otherwise switch by swapping boot images from TWRP |
| Fedora needs ~20-30 GB inside the image | Recon prints free space on `/data` |
| Final step: Linux inside an image file on an f2fs partition is slower than a real ext4 partition. Converting in place needs a careful copy-out, reformat, copy-back | Accept the image-file layout, or do the conversion as a separate guided step |

## What can move, in either design

| Moves with data | Moves, log in again | Will not move |
|---|---|---|
| Photos, videos, music, documents, downloads; most games and offline apps (into Waydroid); Wi-Fi networks (converted to NetworkManager) | Cloud-synced apps, browsers (use their sync) | 2FA authenticator secrets, banking apps, apps needing Play Integrity, Samsung-only apps (export Samsung Notes first) |

The assistant warns about each app in the third column before anything is erased.

## Scope: your own apps only

The picker lists only apps **you installed** (`pm list packages -3`). Google and Samsung
system apps are hidden and never moved; their Linux equivalents take over: Dolphin for files,
Gwenview for photos, Firefox for the web, and so on. Google services, if you want any of them,
come from Waydroid's own Google image, not from Android.

## Making Waydroid feel native

The goal: Android apps behave like Linux apps, and Linux apps do the system jobs.

| Feature | How | Status |
|---|---|---|
| Each Android app in its own KDE window, no Android home screen | Waydroid multi-window mode (`waydroid prop set persist.waydroid.multi_windows true`) | Built into Waydroid |
| Android apps in the KDE app menu and taskbar, with their icons | Waydroid creates a `.desktop` launcher per installed app | Built into Waydroid |
| Android's own system apps (Files, Gallery, Browser, Launcher) hidden from the menu | The assistant marks those launchers hidden | To build |
| One set of folders: Android apps see your Linux `~/Pictures`, `~/Documents`, `~/Downloads`, etc. | Bind-mount the Linux XDG folders into Android's shared storage, so there is no separate Android "Internal storage" | To build and verify on the device |
| Open a file from **Dolphin** in an Android app ("Open with…") | Generate KDE file associations that call `waydroid app intent android.intent.action.VIEW <file>` for apps that handle that file type | To build |
| Copy and paste between Linux and Android apps | Waydroid clipboard sharing (needs `wl-clipboard`) | Built into Waydroid; verify |
| Files picked inside an Android app | Android's file picker still appears, but it shows your Linux folders because they are shared | Limitation: Android apps cannot call Dolphin's picker directly |
| Android notifications in KDE | Not supported by Waydroid today | Not available |

## How we will know which design works on your tablet

Two checks, both before anything is erased.

| Step | What | Result |
|---|---|---|
| 1 | Run `tools/recon/s6-recon.sh` and read the **Data partition** section | `metadata_encryption` present: **only Design A** is possible. `fileencryption` only: go to step 2 |
| 2 | Run `tools/recon/s6-plaintext-probe.sh create`. It writes one 1 MiB test file and records its hash | Hash saved |
| 3 | Later, in TWRP, press **Cancel** at the decrypt prompt and run `sha256sum /data/linux-probe/probe.bin` | **Same hash: Design B is possible.** Different or unreadable: Design A |
| 4 | Recon also prints free space on `/data` | Design B needs roughly 30 GB free for the Linux image |

The assistant runs these same checks itself and offers Design B only when they pass.
Otherwise it uses Design A automatically. Both designs share the picker and the restore
code; only where the data waits in between differs.

## Order matters on your tablet

On the SM-T860, Magisk (your root) normally lives in the **recovery** partition, and copying
app data off Android needs root. Installing TWRP replaces recovery, which removes root.
So the assistant's Android step (picking and copying apps and data) **must run before TWRP
is installed**. For Design B, which keeps Android, how to switch between the two systems at
boot also depends on this. The recon output (BCB line, boot `ramdisk_size`) tells us which
case you are in.

## Plan

1. **Build Design A first.** It delivers what you described (pick what to keep, automatic
   move, automatic app restore, native-feeling Waydroid) with the risk profile already
   understood.
2. **Add Design B** if your checks pass. The picker, Waydroid integration and restore code
   from Design A carry over unchanged.

Either way, the first input needed is `tools/recon/s6-recon.sh` output from your tablet.

## Final app look (concept)

Mockup: https://claude.ai/artifact/YR2y4ZwEGa9dpSFCFb8Act (private to the owner).

A guided upgrade wizard in the spirit of desktop OS upgrade assistants, with original artwork
(no Microsoft, Apple or Fedora logos). **Fedora-themed**: Fedora's blue palette (#3C6EB4 for
light mode, #51A2DA for dark) and the open-licensed Red Hat Display / Red Hat Text fonts.
**Follows the tablet's light/dark setting.**

1. **Welcome**: "Move this tablet to Fedora", readiness checklist (model, bootloader, TWRP,
   battery, pre-release note).
2. **Choose what to keep**: three choices (selected apps and files / files only / start fresh),
   app and folder lists with sizes and Keystore warnings, live space bar.
3. **Apps on Fedora**: for each app you bring, choose *Keep Android app* (Waydroid, with its data),
   *Use the Linux alternative*, or *Both*. Apps without a Linux version are kept automatically.
   A second list shows the Google/Samsung apps that stay behind and their Fedora replacements
   (Chrome to Firefox, Gallery/Photos to Gwenview, My Files to Dolphin, phone link to KDE Connect,
   Gmail to Thunderbird, Samsung Notes to Joplin with an "export first" warning), with install
   toggles for those not preinstalled.
4. **Space check**: Plan A (replace Android, carry the package on a USB drive or card, with and
   without the Fedora download) and Plan B (keep Android alongside), each showing fit or shortfall;
   Plan B locked until there is room and the TWRP check passes.
5. **Ready to upgrade**: summary (what is kept, which Android apps stay and which Linux apps are
   added), what gets erased, what doesn't work in Fedora yet, a confirmation checkbox for exported
   authenticator codes.
6. **Upgrading**: full-screen progress with stages (pack, download, install, restore and set up
   chosen Linux apps, first start).

Layout: step sidebar on the left (steps 1-5), content panel, 48 px touch targets, landscape tablet
first.

### App replacement map (first version)

A small built-in table maps Android package names to Linux alternatives; unknown apps default to
"Keep Android app". Examples: `com.android.chrome` / browsers -> Firefox; gallery and photo apps ->
Gwenview; file managers -> Dolphin; music players -> Elisa; video players -> Haruna or VLC; mail ->
Thunderbird; note apps -> Joplin; office apps -> LibreOffice; PDF readers -> Okular. The map lives in
the app so it can grow without changing the restore logic.

## v0.2 Restore (`tools/migrate/s6-restore.sh`)

Runs on Fedora as your user, inside the desktop session (it asks for sudo when needed):

```bash
s6-restore --dry-run     # show everything it would do, change nothing
s6-restore               # do it
```

| Step | What it does |
|---|---|
| Find | Looks for `S6Migrate/<date>` on plugged-in drives (`/run/media/$USER/*`), `/var/lib/s6migrate/package*` (where v0.3 will copy it) and `~/S6Migrate/`; or pass the folder |
| Check | Verifies every file against `SHA256SUMS` (`--skip-verify` to skip) |
| Folders | DCIM -> `~/Pictures/DCIM`, Pictures -> `~/Pictures`, Download -> `~/Downloads`, Documents, Music, Movies -> `~/Videos`, recordings, ringtones and Voice Recorder -> `~/Music/<name>`, **your own folders (e.g. ArtStuff) -> the top of your home (`~/ArtStuff`), like on Android**, folders apps made (Telegram, TWRP, InShot, `com.*` names, hidden and temp folders) -> `~/Android/<name>`, loose files -> `~/Android/`. A `destinations.txt` in the package (written by the wizard's per-folder choice) overrides any of these. Never overwrites: identical files are skipped, different files with the same name are kept side by side as `name (from Android).ext` |
| Apps | Installs each app into Waydroid (all split APKs in one install session), force-stops it, then restores `data`, `data_de`, `Android/data` and `Android/obb` with the new app's owner (and Android's `ext_data_rw`/`ext_obb_rw`/cache groups). Apps flagged for the Android Keystore are installed fresh unless `--keystore-data` |
| Native feel | Waydroid multi-window mode; hides Android's own Files, Browser, Gallery, Contacts, Dialer, Messages, Calendar, Clock, Recorder, Camera and Settings from the KDE menu; installs `s6migrate-waydroid-share.service`, which shows Pictures, Downloads, Documents, Music and Videos inside Android, **plus every restored folder at the name Android knew it by** (`~/Android/Telegram` is `/sdcard/Telegram` again, `~/ArtStuff` is `/sdcard/ArtStuff`, `~/Pictures/DCIM` is `/sdcard/DCIM`), so Android apps you kept find their files where they left them. Same files on both sides; bindfs when installed, so Android apps can also write there |

Tested against a simulated Fedora home and a simulated Waydroid. **To confirm on the real tablet**
(the first Fedora boot): the `waydroid shell -- sh -c` form on the installed Waydroid version, `pm`
install sessions inside the Waydroid image, file ownership seen through Android's storage layer for
`Android/data`, `obb` and the shared folders, and SELinux relabelling inside the container.

## v0.3 Switch (in progress)

| Piece | File | State |
|---|---|---|
| Recovery side: a TWRP flashable ZIP script that finds the drive, verifies the Fedora download, runs the t860-fedora installer's `prepare` / `write-root` / `finish` from the drive (no computer), saves the Android boot backup to the drive, installs `s6-restore` and the first-start assistant into the new system, copies the package in when it is on the microSD card (Fedora cannot read the card yet), and reboots only when everything succeeded | `tools/migrate/switch/update-binary` | Built; simulated success, damaged download, failed checks and failure after erase |
| First start in Fedora: opens a terminal once, restores your files, asks for Wi-Fi, sets up Waydroid (optional Google Play), restores your apps | `tools/migrate/switch/s6-firstrun`, `s6migrate-firstrun.desktop` | Built |
| Android side (app 0.2.0, "Switch to Fedora…" on the home screen): pre-flight checks (model, battery, package, download, TWRP and authenticator confirmations), resumable Fedora download straight from the t860-fedora release to `S6Migrate/fedora/` with SHA-256 checks and `s6-download.env` + `SHA256SUMS`, final confirmation (type SWITCH), builds the ZIP from the app's bundled tools, queues it in `/cache/recovery/openrecoveryscript`, restarts into TWRP; "Cancel switch" removes the queue | app | Built |

Failure behaviour: anything that fails before the `write-root` step stops in TWRP with "Nothing was erased. You can reboot to Android normally." A failure after it stops in TWRP with "Android was already replaced. Do NOT reboot yet" and the log saved on the drive.

## Settings carried over (v0.1.7 pack, restore step 4/6)

| Setting | Captured from Android | Applied on Fedora |
|---|---|---|
| Home and lock wallpaper | `/data/system/users/0/wallpaper{,_lock}` | `plasma-apply-wallpaperimage`; lock screen via `kscreenlockerrc` |
| Dark / light mode | `settings get secure ui_night_mode` | Breeze Dark / Breeze look-and-feel |
| Time zone | `persist.sys.timezone` | `timedatectl set-timezone` |
| Language and region | `persist.sys.locale` | `plasma-localerc` (next login; langpacks hint) |
| Device name | `settings get global device_name` | `hostnamectl` pretty + static name |
| Wi-Fi networks | `WifiConfigStore.xml` (WPA2, WPA3, open) | NetworkManager connections; existing ones skipped; enterprise/WEP/encrypted listed to add by hand. **Passwords are stored in the package: keep the drive private** |
| Bluetooth pairings (experimental) | `bt_config.conf` link keys | BlueZ `/var/lib/bluetooth/<adapter>/<device>/info`, only when the adapter address matches Android's; otherwise re-pair once |

## Keeping Android apps working (`tools/migrate/s6-doctor.sh`)

No custom Waydroid build is needed: Fedora packages Waydroid, and Waydroid fetches and updates its
own Android system (LineageOS). `s6-doctor` looks after everything around it:

| Check | Repair (`--fix`) |
|---|---|
| Kernel has binder (Android apps need it) | Explains `tabs6-kernel rollback` if a kernel update dropped it |
| Waydroid installed | `dnf install waydroid` |
| `waydroid-container` service running | enable and start it |
| Android system images present (shows the LineageOS version) | `waydroid init` |
| One window per app | `waydroid prop set persist.waydroid.multi_windows true` |
| Android's duplicate system apps hidden | re-hides them, and installs a user path watcher (`s6migrate-hide.path`) that re-hides them whenever Waydroid recreates menu entries |
| Shared folders mounted | restarts `s6migrate-waydroid-share.service` |
| Graphics hardware or software | reports |

`s6-doctor --update` also updates Fedora's Waydroid package and Waydroid's Android system
(`waydroid upgrade`). Restore runs `s6-doctor --fix` at the end, and the switch installs it.
The companion app will put these behind buttons and notify when something needs attention.

## Making Android apps feel native: what works and what is planned

| Topic | State |
|---|---|
| Copy and paste text between Linux and Android apps | Works (Waydroid clipboard sharing) |
| Drag and drop between Linux and Android apps | Not supported by Waydroid. Workaround: drop into a shared folder; Android apps see it at once |
| Android apps see your Linux folders | Done (s6-restore folder sharing) |
| **Memory: Android only while you use it** | Done: `tools/migrate/s6-android.sh`. Starts with the first Android app, stops after `IDLE_MIN` minutes (default 5) without an Android window (counted through KWin; if windows cannot be counted it never stops on a guess), "Stop Android apps" in the menu, `s6-android status` shows memory use. Installed by restore |
| Open a Linux file in an Android app (Dolphin "Open with") | Planned: generate MIME associations from each Android app's VIEW intent filters, launching `waydroid app intent android.intent.action.VIEW <file in shared folder>` |
| KDE file dialog when an Android app asks for a file | Planned research: a small "picker bridge" Android app inside Waydroid that takes over GET_CONTENT / OPEN_DOCUMENT and asks the host's KDE file dialog (xdg-desktop-portal) over the Waydroid network bridge, returning the file through a shared folder |

**Rehearsal (app 0.2.1):** "Rehearse first" queues the same ZIP with a `REHEARSAL` marker. In TWRP it
finds the drive, verifies the Fedora download, runs the installer's `prepare` (no partition writes),
saves the boot backup, writes `S6MIGRATE-REHEARSAL-PASSED` to `S6Migrate/switch-log.txt`, resets the
bootloader control block and restarts into Android. The app's switch screen shows the last result.
Do a rehearsal before the real switch: it proves TWRP runs the queued ZIP, has the needed tools, and
can read the drive, without erasing anything.

## Linux versions: hand-picked list plus Flathub (app 0.2.3)

1. **Hand-picked** (`tools/migrate/lib/alternatives.tsv`): checked to run on ARM64; installed by restore.
2. **Flathub lookup** for every other app: the app sends the app's *name* to Flathub's public search
   (`POST https://flathub.org/api/v2/search`), keeps only desktop apps whose `arches` include
   `aarch64`, and scores them (exact name or "<name> Desktop", name in the description, verified
   developer, installs). Exact, non-generic matches are **high** and installed by restore (Flatpak);
   others are **maybe** and only suggested in restore's summary. If the official app exists only for
   x86_64 (Spotify, Discord, Steam, Zoom, Blender), the app says so and still offers ARM alternatives
   (e.g. Riff for Spotify, Vesktop for Discord). Results are cached for 14 days and saved in the
   package as `alternatives-found.tsv`. Offline, the lookup is skipped.

## Per-app choice, Fedora download drive (app 0.2.4)

- **Each app with a Linux version gets a choice:** both, only the Linux version, or only the Android app.
  - *Only the Linux version* writes a `LINUX|pkg|name` line to the plan. Nothing is packed for it, and it counts 0 toward the space needed.
  - Updating a package removes data that was stored earlier for an app now set to Linux only.
  - The choices are saved in `choices.txt` in the package, and `s6-restore` follows them.
  - A less certain Flathub match is installed when you picked its Linux version yourself.
- **Hand-picked list is fetched live:** the app reads `alternatives.tsv` from GitHub on each start, once the repository is public. It falls back to the copy built into the app.
- **Download drive is your choice:** the switch screen lists every card and USB drive with its own free space, and you choose where the Fedora download goes.
  - Internal storage is never offered, because the switch erases it while TWRP reads the download.
  - TWRP uses the drive with a *finished* download (`s6-download.env` present). An unfinished download on another drive is ignored.
  - The package and the download may be on different drives.
- **TWRP step 5 problems no longer stop the switch:** a problem installing the S6 Migrate tools on Fedora is logged as a warning, and the switch still finishes so the tablet boots.

## The upgrade wizard (app 0.3.0)

The app follows the concept design: a sidebar with six steps on the tablet (a step bar in narrow windows), Fedora blue, Red Hat fonts, light or dark to match the tablet.

1. **Introduction:** readiness checks (model, root, card or drive, battery, pre-release note) and your saved packages, each with *Check for changes*.
2. **What to keep:** choose *Selected apps and files*, *Files only* or *Start fresh*, then pick apps and folders. The footer shows the space left on the drive as you pick. Each folder shows where it goes on Fedora; tap *Change* to choose another place (saved as `destinations.txt`).
3. **Apps on Fedora:** the Flathub lookup runs here, and **only for the apps you chose** (cached 14 days, *Skip* allowed).
   - Each app with a Linux version offers *Keep Android app*, *Use <Linux app>* or *Both*.
   - Apps staying behind that have a Linux version on the hand-picked list can still get it: tick *Install* (a `LINUX` plan line, nothing packed).
4. **Space check:** Plan A lists every card or USB drive with a bar for your stuff plus the Fedora download, and you pick the drive. Plan B (Linux next to Android) shows what it would need; it is not built yet.
5. **Summary:** what is kept, which Android and Linux apps you get, where folders go, and what Fedora sets up. *Pack now* packs and verifies.
6. **Upgrade:** checks, Fedora download drive and download, rehearsal, and the typed SWITCH confirmation.

**Manual start in TWRP.** Some TWRP builds (seen with 3.7.0_9-15_mentalmuso on a GSI) open their main menu instead of running `/cache/recovery/openrecoveryscript`.
- The app now also puts the ZIP on the card or drive as `S6Migrate/S6Migrate-rehearsal.zip` or `S6Migrate-UPGRADE.zip`, and shows the steps: Install, Select Storage, S6Migrate folder, the ZIP, then swipe.
- When the app opens again and finds the old request still queued from before the restart, it says TWRP didn't run it and removes the request.

**TWRP output fix (app 0.3.1).** On the tablet, TWRP ran the ZIP but showed no lines, only "Updater process ended with ERROR: 1".
- **Cause:** TWRP passes a two-digit output descriptor (for example 54), and mksh (TWRP's shell) rejects `>&54` ("illegal file descriptor name"). Every message was lost, and the real stop reason was hidden.
- **Fix:** the script now writes through `/proc/self/fd/$OUTFD`, as Magisk does. The rehearsal and the full switch pass the mocked tests under mksh, busybox ash, dash and bash.
- **Guard:** CI checks that the old redirect doesn't come back.

**No unzip or awk in TWRP (app 0.3.2).** On TWRP 3.7.0_9-15_mentalmuso (Android 9 base) the rehearsal then stopped at "could not unpack the switch package": this TWRP has no `unzip`.
- **Embedded files:** the app now embeds S6 Migrate's files (restore tool, doctor, Android helper, first-start assistant, Linux list, autostart entry) into `update-binary` as here-documents, at the `# @S6_EMBED@` marker, together with `S6_MODE=rehearsal|switch`. TWRP only needs `cat`.
- **No awk:** drive detection reads `/proc/mounts` in plain shell.
- **Fallbacks:** `tar`, `sha256sum`, `gzip` and `unzip` fall back to busybox or toybox applets.
- **Tested:** rehearsal and full switch pass the mocked tests under mksh with only basic busybox applets (no unzip, awk or plain tar).

**First real rehearsal passed (14 Nov 2026, app 0.3.2, TWRP 3.7.0_9-15_mentalmuso).**
- Started automatically through OpenRecoveryScript.
- Found the Fedora download on `/usb-otg` and the package on `/external_sd`.
- Checked the 5 GB download against its checksums.
- The t860-fedora installer's `prepare` passed, and the Android boot backup was saved to the drive.
- Restarted into Android. Nothing was written to the tablet's partitions.

Not covered by a rehearsal: `write-root`, `finish`, first boot, and the restore on Fedora.

**First real switch (15 Nov 2026) and fixes in app 0.4.6.** The switch got Fedora onto the tablet, but three steps stopped and were finished by hand from TWRP's terminal. Each one is now handled by the app and script:

| What stopped | Why | Now |
|---|---|---|
| Step 4 `write-root` when started from `/cache` | The installer must unmount and overwrite the cache partition, and the ZIP it was running from was open there | The app queues `install /external_sd/...` (or `/usb-otg/...`) instead, using the ZIP copy on the drive. Before anything is erased, the script refuses a ZIP on internal storage or the cache, and checks that TWRP can unmount `/sdcard`, `/data` and `/cache` |
| Step 5: copying the package from the microSD card | The new filesystem is only as big as the image until Fedora's first start grows it | The script checks free space and grows the filesystem with TWRP's `e2fsck` and `resize2fs` if needed. If it still doesn't fit, it doesn't copy at all (a full disk can stop the desktop from starting), removes any half copy, and says to bring the package on a USB stick |
| Step 6: writing vbmeta (`Read-only file system`) | Samsung write-protects the storage unit (LUN) that holds vbmeta | Step 6 now runs in the script itself. It writes and verifies the cache image as before. It skips vbmeta when verification is already off (flags at byte 120 equal to the new image, or bit 2 set, as on rooted tablets). It then writes and verifies the boot image |

- **Checked before erasing (rehearsal too):** vbmeta. If verification is still on and TWRP can't write vbmeta, the switch stops with "nothing was erased" and explains how to flash a verification-off vbmeta from a computer.
- **Real reasons on screen:** when the script stops, it shows the installer's own `ERROR:` line. It only says "Android was already replaced" once the installer has actually started writing.
- **Tested (mocked partitions, mksh, TWRP's basic toolset):**
  - Rehearsal and switch with verification off, with verification on and writable, and with verification on and read-only.
  - An installer that can't free `/data`.

## Never change the desktop while it runs (0.4.7)

On the first real switch, the tablet froze while S6 Companion was installing Better Blur DX, which pulled in a whole Plasma update (6.7.5 to 6.8.3) under the running session. The forced restart that followed cut `libkwin.so.6` short and left the package database half-updated, so the login screen could no longer start.

The freeze itself has no known cause. The install is a suspect, but the tablet had also hung once before, at its first start, with nothing installing. Possible causes include the port's graphics or display stack and memory pressure. Restart-time installs make any freeze harmless to the system, whatever its cause.

To find the cause, `s6-selfcheck` checks at every start whether the previous session shut down cleanly. If it didn't, it saves that session's final warnings and log lines to `/var/lib/s6migrate/freeze-reports/` (the 5 newest are kept). S6 Companion's Fixes page then shows "The tablet didn't shut down cleanly", with the report. Two Fedora-side services now prevent and repair this. The switch installs both, and S6Migrate-FIX.zip installs them on tablets switched earlier.

**`s6-selfcheck`** runs at every start, before the login screen, in a few seconds and without internet:
- empty login-rule files are regenerated with `authselect`
- a `kwin_wayland` whose libraries don't load, or packages left with two copies, queue a repair

**`s6-maint`** runs before the login screen when a job is waiting in `/var/lib/s6migrate/maint`:
- the jobs are `repair`, `update` and `extras`
- it downloads everything first, in up to 30 resumable rounds, then installs from the downloaded files only
- kernel packages, `sddm` and `iio-sensor-proxy` are never touched
- progress shows on the screen, the log is in `/var/lib/s6migrate/maint.log`, and an unfinished job continues at the next start

**What schedules a job:**
- **S6 Setup**, when online, queues `update` (plus `extras` if effects are on) as it finishes. The restart then brings Fedora up to date before the first login, so the first desktop is complete.
- **S6 Companion's** "Update at the next restart" and "Add them at the next restart" buttons do the same, with a **Restart now** button. Fedora updates no longer go through Discover, which could also install Fedora's own kernel packages, and this tablet boots its own kernel.
- **The "protect" tune-up** now holds back `sddm`, `iio-sensor-proxy` and `kernel*`. It no longer holds back `sddm-wayland-plasma`, which has to match the installed Plasma.

**Wi-Fi:**
- NetworkManager power saving is off (`/etc/NetworkManager/conf.d/60-s6migrate-wifi.conf`). With it on, the tablet's ath10k Wi-Fi was slow enough on a fast network that every mirror timed out.
- The Wi-Fi country comes from the chosen region (`options cfg80211 ieee80211_regdom=XX`).
- Saved Android networks come over during the switch: TWRP converts the package's `WifiConfigStore.xml` to NetworkManager keyfiles (root-only, 600), so Fedora connects on its own at the first start, before S6 Setup. It converts WPA/WPA2-personal, WPA3 (SAE) and open networks, hidden ones included. Enterprise networks and networks with hex-encoded names are skipped.

## Your desktop is ready at the first login (0.4.7)

S6 Setup prepares the new account's desktop before anyone logs in (`s6-helper prepare-look`, which runs `s6-look prepare` as the user):
- installs the S6 layouts as Global Themes in the account
- names the chosen one in `kdeglobals` (`LookAndFeelPackage`), so Plasma builds the very first desktop from that layout
- writes the colours and icons, window borders, Dolphin style, effects settings and touch mode

Two things need the running desktop, so `s6-look heal` does them the moment you log in:
- the screen scale
- panel see-through

At that point `heal` also checks the panels match the chosen layout, and applies the layout if Plasma didn't.

With Wi-Fi, the restart after S6 Setup installs these before the first login, so the first desktop is up to date and complete:
- Fedora updates
- Better Blur DX and Darkly
- the RPM Fusion codecs, whose drivers can require matching graphics libraries

S6 Setup's progress page now has two parts, "Setting up your tablet" and "Moving your things in".

**Still planned:** the Android app could download these extras together with Fedora, so a tablet with no Wi-Fi at first start is complete too. The build system would produce a list of exact Fedora 44 aarch64 package URLs and checksums, the app would download them to the drive, and the switch would hand them to `s6-maint` as a local repository.

## Region before installing (app 0.4.7)

Like other installers (PikaOS's asks before it installs), the app's last page before the switch has a **Your region** card:
- **Time zone:** a searchable list of every time zone, labelled like "Chicago, America (UTC-06:00)".
- **Language and region:** searchable, in each language's own name.
- **Device name.**

All three are pre-filled from Android and saved across visits.

The switch writes them into Fedora: `/etc/localtime`, `/etc/locale.conf`, `/etc/hostname` and `/etc/machine-info`. It also sets the date of `/var/lib/systemd/timesync/clock` to the time the switch was prepared. systemd never starts the clock earlier than that file's date, so Fedora's clock can't begin a month behind (it did on the first real switch, which broke secure downloads). S6 Setup shows the same choices again, with searchable pickers instead of a typed "Region/City".

## Recovering by hand: what the first real switch taught us

These facts about the tablet under t860-fedora cost an evening to learn. The scripts now avoid every problem listed below. Keep this page for anyone who still ends up recovering by hand.

**Buttons and boot**
- **Power off restarts the tablet.** Under this Fedora, shutting down restarts it.
- **Force restart:** hold Power + Volume Down for about 10 seconds. This is the hardware reset and works even when Fedora is frozen. Let go as soon as the screen goes black. If Volume Down is still held while the tablet starts, the UEFI boot menu opens ("Power off", Device Info, "Device State - unlocked"). The Power button doesn't select anything there, so force-restart again.
- **TWRP:** connect a USB cable first; with this Samsung bootloader, the recovery combination only works with a cable plugged in. Hold Power + Volume Down until the screen goes black. Keep holding Power, slide the other finger to Volume Up, and hold both until TWRP appears.
- **A black screen with a static `_` cursor** means the login screen never took over the display. Common causes: a long first-start job (such as an SELinux relabel, now skipped because t860-fedora boots with `selinux=0`), or the desktop failing to start.

**Logging in**
- **The image's own account is `fedora` / `fedora`.** S6 Setup removes it by default.
- **The on-screen keyboard capitalises the first letter** in SDDM's built-in theme, so "fedora" can fail. S6 Setup's own fields now ask the keyboard not to capitalise or predict passwords and user names. A proper S6 login theme is planned.
- **USB-C under Fedora gives no power** to a bus-powered device: the SM5705 VBUS boost has no driver (see the note in t860-fedora's device tree). USB keyboards and USB sticks only work through a **powered** USB-C hub. That's why the switch now copies every part of the package into Fedora.

**Fixing the setup start from TWRP** (Advanced > Terminal). The first lines open Fedora's disk and add the line that was missing from the automatic-login file before 0.4.6:
```
mkdir -p /tmp/r
mount -t ext4 /dev/block/by-name/userdata /tmp/r
echo Session=plasma.desktop >> /tmp/r/etc/sddm.conf.d/zz-s6migrate.conf
rm -f /tmp/r/.autorelabel
cat /tmp/r/etc/sddm.conf.d/zz-s6migrate.conf
grep -n '^s6setup:' /tmp/r/etc/shadow
df -h /tmp/r
```
- The `cat` line should end with `User=s6setup` and `Session=plasma.desktop`.
- `grep` should print the setup account on a line of its own.
- `df` shows whether Fedora's disk has grown to its full size (about 108 GB).

<a id="package-left-on-the-card"></a>**Package left on the card.** If the switch couldn't copy the package into Fedora, copy it from TWRP with the disk opened as above. Use your package's folder name in place of `ID`:
```
P=/tmp/r/var/lib/s6migrate/package-ID-part1
rm -rf $P
cp -a /external_sd/S6Migrate/ID $P
find /external_sd/S6Migrate/ID -type f | wc -l
find $P -type f | wc -l
chmod -R a+rX $P
sync; umount /tmp/r; reboot
```
- The two counts must match before you reboot.
- S6 Setup finds the package in `/var/lib/s6migrate`.

**S6Migrate-FIX.zip** (`tools/migrate/fix/`, build with `build-zip.py`). For a tablet that shows a login screen instead of S6 Setup: put the ZIP on a USB stick or the card and install it from TWRP. It erases nothing. It:
- shows why logins fail: from Fedora's log, and from its own boot check's report on the next run
- gives the temporary `s6setup` and `fedora` accounts the password 123456 (S6 Setup removes both)
- refills Fedora's core login files if they are empty (`system-auth`, `password-auth`, `postlogin`, `fingerprint-auth`, `smartcard-auth`, `nsswitch.conf`, `authselect.conf`), in place so authselect's links stay; empty login-rule files make libpam refuse every account with "Permission denied" (seen on the first real switch, probably from a forced restart while they were being rewritten). Lists every empty file in `/etc`
- checks Fedora's login rules (PAM): restores missing `system-auth`, `password-auth` or `postlogin` files, and marks rule lines naming uninstalled modules as skippable (originals kept in `/var/lib/s6migrate/pam.before-fix`)
- rewrites the automatic-login file and removes stale blockers (`/etc/nologin`, `.autorelabel`)
- keeps logs on disk
- runs Fedora's own login checks (PAM) inside Fedora from TWRP, the way SDDM does, for the setup and fedora accounts; when one fails it tests each rule alone and names the one that refuses (`s6pamtest.py`)
- checks packages: two copies of one package, or desktop parts at different versions, mean an update was cut off (a freeze or forced restart). It then schedules `s6-repair` for the next start, before the login screen: wait for Wi-Fi, clock set from the internet, `dnf remove --duplicates`, `dnf distro-sync` with kernel packages excluded, downloaded first in up to 30 resumable rounds with patient settings and only then installed from the cache (a Wi-Fi drop can never interrupt installing), missing desktop packages put back, packages with damaged files (`rpm -Va`) reinstalled, no time limit (this tablet boots its own kernel), progress shown on screen, log in `/var/lib/s6migrate/repair.log`
- adds a boot check that, 90 seconds after the login screen starts, writes a report and retries automatic login once if logins are still blocked

Everything it shows is saved as `fix-report.txt` next to the ZIP.

### How PikaOS does first setup (and how S6 Setup compares)

PikaOS's first-setup app is [pika-first-setup](https://github.com/PikaOS-Linux/pkg-pika-first-setup) (Rust, GTK4 and libadwaita; the repository is archived, so the current release may differ). Its source shows this flow:

1. **Temporary account:** the installer creates `pikaos` and logs it in automatically through `/etc/sddm.conf.d/zautologin.conf`.
2. **First setup starts:** an autostart entry starts first setup, and the app refuses to run as any other user.
3. **Pages:** welcome, internet, user (full name, user name, password and host name: `adduser`, groups, `chpasswd`, removes the auto-login file, `hostnamectl`), updates, codecs, drivers, gaming tools, then finish.
4. **Finish:** removes the temporary account and restarts the tablet (`userdel -r -f pikaos; reboot`). You arrive at the login screen with your own account, and the welcome app takes over.

S6 Setup uses the same design: a temporary `s6setup` account, automatic login, a full-screen assistant, your own account, then the temporary account removed. As of 0.4.6 it also ends the same way: a full restart into your account, instead of restarting the login manager under a running session.

What S6 Setup does differently:
- **Root actions:** a polkit rule for a single root helper, not a fixed sudo password like PikaOS's `pika-sudo.sh`.
- **Moving in:** moving in from Android is part of setup.
- **The `fedora` account** is removed by default.

## Fedora side: S6 Setup and S6 Companion (0.4.0)

### First start (S6 Setup, before any desktop)

- **How it starts:**
  - TWRP (step 5) adds a temporary account, `s6setup`, and points SDDM's automatic login at it, through `/etc/sddm.conf.d/zz-s6migrate.conf`, and `/etc/sddm.conf` if the image sets a user there.
  - That session opens S6 Setup full screen: Python and Qt Quick, both already in the image (`python3-pyside6`, Qt 6.11).
  - It has its own on-screen keyboard (`qt6-qtvirtualkeyboard`).
- **Seven steps:**
  1. Welcome: bring my stuff, or start fresh.
  2. Wi-Fi: the Android networks are added automatically.
  3. Your account: name, user name, password; log in automatically; remove the public `fedora` account.
  4. Your tablet: device name, time zone, language, Android app support, Google Play. Filled in from Android.
  5. Look and feel: layout, size, light or dark, tune-ups, media codecs.
  6. Moving in: progress for each task and each package part.
  7. All set.
- **Hand-over:** "Start using Fedora" switches automatic login to your account and restarts the login manager. The setup account and its permission rule are then removed.
- **Fallback:** if S6 Setup can't start at all, the tablet goes back to the `fedora` account with the old text assistant (`s6-firstrun`).
- **Root helper:** root work goes through `/usr/local/libexec/s6migrate/s6-helper` via pkexec.
  - Polkit rule `49-s6migrate.rules`: the setup account needs no password; admins (`wheel`) are asked once.
  - Every argument is checked.
  - During the first run, your account has temporary passwordless `sudo`, so the steps run without prompts. S6 Companion removes it when the first run finishes.

### After login (S6 Companion)

A welcome and tools app, always in the menu, with "Open when I log in" as an option.

- **First login:** finishes the move.
  - Wallpaper and settings from Android.
  - Your layout and size.
  - Android for apps (Waydroid image, with or without Google Play).
  - Your Android apps and their data, from every part of the package.
- **Pages** (0.4.1 adds **Tablet**: battery level, charging, health and temperature; storage; memory; processor temperature; versions; S Pen detection. The S Pen battery can't be read on Linux):
  - **Home:** status and tips.
  - **Look:** five layouts, Size Standard / Larger / Largest, light or dark.
  - **Android apps:** start, stop, auto-stop minutes, check and fix, update Android.
  - **Updates:** Fedora updates through Discover, Flatpak, the tablet system (below) and S6 Migrate itself.
  - **Tune-ups:** each one on or off.
  - **Fixes:** Wi-Fi, Bluetooth, rotation, sound, touch keyboard, Android apps.
  - **Your stuff:** bring files, apps or settings over again; open folders.
  - **About:** credits.

**Layouts** (`s6-look`, through Plasma's scripting interface; neutral names, no look-alikes of other systems):

| Layout | What it is |
|---|---|
| Touch | One tall floating bar (default) |
| Centered taskbar | App icons in the middle of the bottom bar |
| Traditional | Full-width bar, menu on the left, window names |
| Top bar and dock | Menu and clock on top, a dock below |
| Plasma default | KDE's standard desktop |

**Size** is relative to the tablet's original screen scale (+0, +25%, +50%). Larger and Largest also turn on Plasma's touch mode.

**Tune-ups** (`s6-helper tune NAME on|off`; files in `*.d` folders, so they're easy to undo):

| Tune-up | What it changes |
|---|---|
| Memory | zram-friendly sysctl settings |
| Logs | journald capped at 200 MB |
| Shutdown | 15-second stop timeout |
| Downloads | 10 parallel downloads in dnf5 |
| Background | abrt and the dnf makecache timer stopped |
| Protect | `excludepkgs=sddm,sddm-wayland-plasma,iio-sensor-proxy`, because t860-fedora customises the login screen and sensor service |
| Codecs | RPM Fusion and full ffmpeg |
| Indexing | File search indexing (Baloo) off by default; per user |

### Tablet system updates (`s6-update`)

- **Check:** compares `/etc/t860-release` and `uname -r` with the newest t860-fedora release (GitHub API), and shows its release notes.
- **Update:**
  1. Download the release, verified against its `manifest.json`.
  2. Unpack the system image, and take the new modules and tablet tools out with `debugfs` (no mounting).
  3. Take the new `Image`, `gts6.dtb` and loader entry from the installer's ESP image.
  4. **Before** installing anything, save the running kernel as LAST KNOWN GOOD with t860-fedora's own `tabs6-kernel snapshot`.
  5. Install.
- **Keep or roll back:** after a restart, S6 Companion asks "Everything works: keep it" (`tabs6-kernel snapshot`) or "Go back" (`tabs6-kernel rollback`). If the tablet doesn't start, hold Volume Down at power-on and pick LAST KNOWN GOOD.
- **S6 Migrate itself:** `s6-update self` refreshes S6 Migrate's own Fedora files from this repository (once it is public).

### Split packages

- **Packing:** when no single card or drive has room, the space check offers "Split it across your drives". The biggest items go to the drive with the most room. Each part is a folder with the same date name, plus `parts.txt`.
- **TWRP:** collects every part and stops before erasing anything if a part is missing. Card parts are copied into Fedora; USB parts are read on first start.
- **Old packages:** the Summary step can delete older packages once the new one has packed and checked out. Saved packages also have a Delete option.

### How it was checked

- The switch script (with all 36 Fedora files embedded) ran end to end against mock drives under mksh and a bare busybox toolset.
- The setup and companion screens were rendered offscreen (mock mode) in light, dark, landscape and portrait.
- The restore modes and helper actions were tested against throwaway folders.

Not yet run on the tablet: SDDM automatic login into the setup account, pkexec and polkit, Plasma layout scripts, `kscreen-doctor` scaling, and `s6-update system`.

**Effects and Dolphin (0.4.2).** `s6-look effects off|soft|glassy` uses KWin's own effects; no extra software is needed.
- **Off:** no blur or translucency, opaque panels, quicker animations.
- **Soft** (default): blur and contrast behind panels, menus and popups; panels see-through until a window is maximised; windows scale in.
- **Glassy:** stronger frosted blur, always see-through panels, translucent menus, dialogs and inactive windows.

Changing the layout also restyles Dolphin through `s6-look dolphin`:
- Touch: large icons, one tap opens.
- Taskbar layouts: details list.
- Top bar and dock: icon grid with previews, and genie-style minimise.

Fully frosted app backgrounds would need a third-party window style (Kvantum or similar), which isn't included.

**Better Blur DX and Darkly (0.4.3).** Both are optional, installed at the first login (`s6-helper look-extras`) from the Fedora COPR repositories `infinality/kwin-effects-better-blur-dx` and `deltacopy/darkly`.
- **Better Blur DX** (xarblu) replaces Plasma's blur: KWin effect `better_blur_dx`, settings in `[Effect-better-blur-dx]`.
- **Darkly** (Bali10050) replaces the Breeze app style and window borders, with settings in `darklyrc`.

Kept light on the GPU:
- Soft: moderate blur strength (7), no noise, the blur cache on, no blurred window borders, only panels and menus blurred, Darkly menus 90% opaque.
- Glassy: strength 10, plus forced blur for a short app list (Dolphin, Konsole, System Settings, Kate, Ark); Darkly's sidebar, toolbars and tabs see-through. Dolphin's file list stays solid.
- Off: Breeze and no blur.

Fallbacks:
- If the repositories have no build for the tablet, Plasma's own blur and Breeze are used.
- Better Blur DX only works with the KWin version it was built for. `s6-look heal` runs at every login: if the effect didn't load (for example right after a Fedora update), it turns Plasma's blur back on and switches back once Better Blur DX loads again. If Darkly is missing, it falls back to Breeze.

Not yet confirmed: whether either COPR builds for aarch64 (the COPR site wasn't reachable from the build machine).

**Layouts as complete looks (0.4.4).** Each layout now also sets window borders, applied to Darkly, or to Breeze when Darkly is missing:

| Layout | Window buttons | Button size | Title | Corner radius |
|---|---|---|---|---|
| Touch | Right (minimise, maximise, close) | Large | Centred | 12 |
| Centered taskbar | Right | Default | Left | 10 |
| Traditional | Menu on the left, buttons on the right | Default | Left | 4 |
| Top bar and dock | Left (close, minimise, maximise) | Default | Centred | 12 |
| Plasma default | KDE's default arrangement | Default | Left | 6 |

Layout changes also restyle Dolphin and keep the chosen effects on the new panels.

- **Global Themes:** `s6-look install-themes` (run at first login) installs the five layouts as Plasma Global Themes ("S6 Touch", "S6 Centered", "S6 Traditional", "S6 Top Bar and Dock", "S6 Plasma") in `~/.local/share/plasma/look-and-feel`.
  - Each has the layout script, app style, window borders and a preview picture rendered from the same drawing as the setup screen.
  - They can be picked in System Settings too. Light/dark and effects are left as the user chose them.
- **Previews:** they show the chosen effects (see-through bars, a frosted sidebar for Glassy) and the window-button side.

**Packing check fixed (0.4.5).** A real package (73 items, 15.5 GB) came back marked as having errors.

- **Cause:** the old check packed each item, then read the original files a *second* time and required the same entry count. Anything that changed in between failed the item, and one failed item marked the whole package as bad. Examples: an app syncing, Android making thumbnails, a download finishing.
- **Fix:** each item is read once. Entries are counted from names beforehand, and the archive must read back completely with at least that many entries, allowing a few files deleted while packing. Truncated or unreadable archives still fail. Packing is also faster, because big items are no longer read twice.
- **Repair:** failed items are recorded in `failed.txt`, and `scan.sh` reports their count.
  - The app shows "some items need packing again" with **Fix it**, which re-packs only those items, in the right part of a split package.
  - For packages made by older versions, the missing items are found by checking which planned items have no archive on the drive.
  - The upgrade checks offer the same fix.
