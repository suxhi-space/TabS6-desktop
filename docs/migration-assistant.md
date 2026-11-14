# Migration Assistant: move from Android to Linux without manual backups

**Goal:** a program that works like a desktop OS upgrade. You pick which files, apps and app
data to keep, it installs Linux, moves your selection over, and removes the old OS, without
you managing backups yourself.

**Status: design.** Nothing here is built yet.

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
| Is there a plaintext directory where the image stays readable to Linux? | Recon lists `/data` top-level; test with a small file first |
| Is it safe for mainline Linux to mount Samsung's `userdata` (f2fs or ext4) read-write? A mistake here could damage Android's data | Read-only mount tests first; Android stays the fallback |
| Can Aloha UEFI boot the stock Android kernel as a second entry? | UEFI experiment; otherwise switch by swapping boot images from TWRP |
| Fedora needs ~20-30 GB inside the image | Recon prints free space on `/data` |
| Final step: Linux inside an image file on an f2fs partition is slower than a real ext4 partition. Converting in place needs a careful copy-out, reformat, copy-back | Accept the image-file layout, or do the conversion as a separate guided step |

## What can move, in either design

| Moves with data | Moves, log in again | Will not move |
|---|---|---|
| Photos, videos, music, documents, downloads; most games and offline apps (into Waydroid); Wi-Fi networks (converted to NetworkManager) | Cloud-synced apps, browsers (use their sync) | 2FA authenticator secrets, banking apps, apps needing Play Integrity, Samsung-only apps (export Samsung Notes first) |

The assistant warns about each app in the third column before anything is erased.

## Recommendation

1. **Build Design A first.** It delivers most of what you described (pick what to keep,
   automatic move, automatic app restore) with the risk profile we already understand.
2. **Investigate Design B in parallel** once your recon results are in. The encryption line
   decides it. If B is viable, Design A's selection and restore code is reused unchanged:
   only the "where does the data wait" part changes.

Either way, the first input needed is `tools/recon/s6-recon.sh` output from your tablet.
