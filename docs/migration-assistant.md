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
| Android side: download Fedora (checksummed) to the drive with `manifest.env` + `SHA256SUMS`, final package top-up, build the ZIP, queue it for TWRP (`/cache/recovery/openrecoveryscript`), reboot to recovery | app | Next |

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
