# Linux on the Tab S6: install plan that keeps your files and apps

**Recommendation:** Fedora 44 + KDE Plasma from
[starlight4you/t860-fedora](https://github.com/starlight4you/t860-fedora) (release
2026.10.29 "GPU18"), with **Waydroid** for your Android apps.

Why this one:
- It is the only distro proven on the SM-T860. It builds on the daily-driven
  [Bentlybro/gts6l-mainline-linux](https://github.com/Bentlybro/gts6l-mainline-linux) port.
- It adds the native display driver (~60 fps, hardware vsync, no white flash on wake).
- Its installer imports firmware from **your own** tablet, rebuilds the UEFI boot image
  from **your own** stock boot, backs up `boot`/`cache`/`vbmeta` first, and verifies
  every write by reading it back.
- Its kernel has binder enabled and the image ships `waydroid` 1.6.3, so Android apps can
  run natively next to Linux apps.

**The honest caveat:** the author marks the release pre-release. Drivers are verified on the
real tablet, and the installer passed offline and simulated tests, but nobody has yet run
the full installer from stock Android on a fresh tablet
([VALIDATION.md](https://github.com/starlight4you/t860-fedora/blob/main/docs/VALIDATION.md)).
You would be one of the first. Our own backups (Part A) make that acceptable: the worst
case is a full stock restore, which is covered.

**What you lose:** Android stops booting (its `userdata` becomes the Fedora root). Going
back means a full stock restore (Part E). Your files and many apps survive because you copy
them off first. S Pen, the headphone jack and USB 3 speed do not work yet under Linux. The
microSD slot is not enabled in either project's device tree.

---

## Part A: Save everything (Android still running, no risk)

| # | Step | How | Done when |
|---|---|---|---|
| A1 | **Export two-factor authenticator accounts** | Google Authenticator: Transfer accounts → Export. Others: their own export, or move codes to a password manager | **Do this first.** Authenticator secrets are usually locked to the device's hardware keystore and will **not** survive any backup tool |
| A2 | Back up chat apps their own way | WhatsApp: Settings → Chats → Chat backup (Google Drive). Signal: Settings → Chats → Chat backups (passphrase file). Telegram: cloud-based, nothing to do | Each app shows a fresh backup |
| A3 | Back up apps and app data | Install **[Neo Backup](https://github.com/NeoApplications/Neo-Backup)** (free, open source, needs root, which you have). Back up APK + data + external data + OBB for every app you care about, into a folder on internal storage | Neo Backup shows each app backed up |
| A4 | Copy internal storage to your computer | `adb pull /sdcard/ ./tabs6-files/` (includes the Neo Backup folder, photos, downloads, documents). Check the photo count matches the Gallery | Files on the computer, spot-checked |
| A5 | Partition backup | `tools/recon/s6-backup.sh` | `All copies verified.` |
| A6 | Device survey | `tools/recon/s6-recon.sh`. Note the **BCB** line and the **boot ramdisk_size** | `summary.txt` saved |
| A7 | Stock firmware | Download BL/AP/CP/CSC for SM-T860 matching your bootloader revision or newer | Four `.tar.md5` files saved |
| A8 | Second copy | Copy `tabs6-files/`, `s6-backup/` and the firmware to a USB drive or private cloud | Two copies exist |
| A9 | Note your Wi-Fi password and Google account recovery details | | Written down |

### What will and will not come back in Waydroid

| Comes back with data | Comes back, but log in again | Probably will not work |
|---|---|---|
| Most games (local saves), offline tools, note apps, readers, media players, many utilities | Apps that sync from the cloud (Google apps, Discord, Spotify, cloud-save games) | Apps that keep data encrypted with the **hardware keystore** (authenticators, banking, Signal's live database, some password managers); apps that require **Play Integrity** (banking, some streaming and payment apps); Samsung-only apps (Samsung Notes, Health, etc.: export Samsung Notes as PDF/text first) |

Waydroid's Android images run a few versions behind current Android (LineageOS-based; check
which version `waydroid init` downloads). Apps that require a newer Android will refuse to install.

---

## Part B: Prepare the installer (Android still running)

| # | Step | Expected | If not |
|---|---|---|---|
| B1 | On your computer: install Python 3.9+ and Android platform-tools | `adb version` works | — |
| B2 | `python3 flash.py --download` (from the t860-fedora release) | Downloads ~5 GB and verifies all hashes | Re-run; never continue with a failed hash |
| B3 | Check the recon result for `boot`: the installer only accepts a **stock** Samsung boot (`UNCOMPRESSED_IMG` + `SEANDROIDENFORCE`) | On an SM-T860 with Magisk in recovery, `boot` is still stock | If `boot` is Magisk-patched: flash the stock `boot.img` from your AP firmware with Odin first |

## Part C: Install (point of no return for Android data)

| # | Step | Expected | If not |
|---|---|---|---|
| C1 | Flash the **official TWRP for gts6lwifi** to recovery with Odin, as [twrp.me](https://twrp.me/samsung/samsunggalaxytabs6qcomwifi.html) describes. Boot straight into TWRP afterwards (hold Power + Volume-Up) so stock Android does not overwrite it. This replaces Magisk-in-recovery; you no longer need it | TWRP main screen | Rollback R2 in [`phase1-test-plan.md`](phase1-test-plan.md) |
| C2 | In TWRP, turn **MTP off**. Stay on the main screen (not ADB sideload) | `adb devices` lists the tablet as `recovery` | — |
| C3 | `python3 flash.py --check-only` | All checks pass: model SM-T860, partition sizes, firmware partitions intact | **Stop** and send the output |
| C4 | `python3 flash.py --erase-android`, type `SM-T860 ERASE` when asked | Backs up boot/cache/vbmeta, imports firmware, writes and read-verifies userdata, cache, boot, vbmeta, then reboots | If any step reports a failure: **keep TWRP open, do not reboot**, send the output |
| C5 | First boot | A different logo, then the UEFI screen, then Fedora's first-boot setup (it expands the filesystem; give it a few minutes) | See "If it boots straight back into TWRP" below |
| C6 | Log in as `fedora` / `fedora`, then run `passwd` immediately | KDE Plasma desktop | — |

**If it boots straight back into TWRP every time:** your `misc` BCB is still set to
`boot-recovery` from the old Magisk-in-recovery setup. Because `boot` now holds a working
system, clearing it is safe at this point. Send the recon `summary.txt` and the TWRP
screen before doing it, and I'll give you the exact command for your state.

## Part D: Bring your stuff back (in Fedora)

| # | Step | How |
|---|---|---|
| D1 | Wi-Fi | KDE network applet, top right |
| D2 | Copy your files back | Easiest: put `tabs6-files/` on a USB stick or SSD and plug it into the tablet with a USB-C adapter (USB host works, at USB 2 speed). Copy into `~/Pictures`, `~/Documents`, etc. KDE Connect or `scp` over Wi-Fi also work |
| D3 | Start Waydroid | `sudo waydroid init` (add `-s GAPPS` if you need the Play Store), then open **Waydroid** from the app menu. Play Store users: register the device at Google's uncertified-device page as the [Waydroid docs](https://docs.waydro.id/faq/google-play-certification) describe |
| D4 | Restore apps | Install Neo Backup inside Waydroid, point it at the copied backup folder, restore apps with data. Waydroid apps then appear in the KDE app menu like normal apps |
| D5 | Log back in to cloud apps, restore WhatsApp/Signal from their own backups, re-add 2FA accounts | |

Waydroid's GPU acceleration on this tablet's Adreno 640 setup is **not yet confirmed** by
either project. If apps render slowly or not at all, report back before changing
graphics settings.

## Making it feel like Nobara, safely

Nobara is Fedora plus extra repositories, its own kernel and Mesa, and gaming tweaks. On
this tablet, the kernel and Mesa are the parts that make the hardware work, so:

| Safe | Avoid |
|---|---|
| Flathub (`flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`) | Nobara's repositories, kernel or Mesa |
| RPM Fusion free + nonfree for codecs (they build aarch64 packages) | Any third-party kernel or Mesa builds |
| Native ARM games and emulators: RetroArch, PPSSPP, Dolphin, etc. | `dnf system-upgrade` to a new Fedora release before the project supports it |
| Normal `sudo dnf upgrade` | Expecting a Fedora `kernel` package update to change anything: the tablet boots only the kernel on its ESP (see the mainline PORT.md) |
| KDE themes, icons, widgets, a dock-style panel at the bottom | Changing display resolution or scaling via low-level tools |

x86 Steam games would need emulation (FEX-Emu) on a 2019 phone chip; expect only light games.

## Part E: Going back to Android

1. Download Mode (Volume-Up + Volume-Down, plug in USB), then Odin with **BL + AP + CP +
   CSC** (full CSC, since userdata must be rebuilt) from Part A7.
2. Re-confirm OEM unlock online if Samsung asks (VaultKeeper re-arms after a full restore).
3. Reinstall your GSI and Magisk as before, then restore apps from Neo Backup and files from
   your computer.

The installer also keeps your original `boot`/`cache`/`vbmeta` under
`/var/lib/tabs6/android-backup/` on the Fedora system, and you have your own copies from A5.
