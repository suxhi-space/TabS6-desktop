# S6 Migrate v2: rebuild from scratch

Written after reading the whole project history (every request and every failure since the first brief). v1 grew
fix by fix on a live tablet until nobody, including its author, could say exactly what it had changed. v2 starts
from a **fresh t860-fedora install** and changes as little as possible, in a way that can always be listed and undone.

## The rules v2 follows (each one comes from something that broke)

| Rule | Why (what happened in v1) |
|---|---|
| **1. Every system change is recorded.** S6 writes `/var/lib/s6migrate/changes.list` (file, what S6 did, where the original was saved). `s6-undo` reverts any of it, exactly. | Changes piled up (PAM, SELinux, sudoers, NetworkManager, PipeWire, systemd units, boot entries) and reverts missed some. |
| **2. Never touch login or security files.** No edits to PAM, authselect, SELinux, `/etc/shadow` beyond `useradd`/`chpasswd`. | The "login failed" fix ZIPs edited PAM/SELinux/authselect; that state is still on the tablet. |
| **3. Never rewrite KDE's own settings.** No Plasma layout scripts, no editing `appletsrc`/`plasmashellrc`/`kwinrc`/`kdeglobals`/`dolphinrc`, nothing re-applied at login. The desktop is Fedora's KDE. | Layout scripts, tray tidy-ups (stopping plasmashell), per-layout Global Themes, an icon theme copy, a Dolphin stylesheet and toolbar file, Darkly keys, KWin effect keys: re-applied every login, they fought KDE and each other (plasmashell crashes, square Dolphin path box, fading windows, taskbar gone). |
| **4. Nothing runs at login.** No autostart "heal". | The heal step kept undoing what the user changed in System Settings. |
| **5. No KWin scripts that move windows or the keyboard.** | `s6-kbd` froze the tablet (keyboard/app resize loop). |
| **6. No big downloads before the first desktop by default.** System updates are offered in S6 Companion, run before the login screen only when asked, never on a first boot, never under a running desktop. | First boots took hours (repair, 500-package updates); a forced power-off mid-update half-installed packages. |
| **7. Third-party look add-ons (Darkly, Better Blur) are not part of v2's base.** If offered later, as an opt-in that installs and removes cleanly. | COPR builds didn't match KWin; Better Blur had to be built by hand; Darkly's options produced the broken Dolphin box. |
| **8. Patch nobody else's code at run time.** No rewriting Maliit's QML on the fly. | S6 Keyboard depended on matching Maliit's files line by line; Fedora's Maliit differs, so it half-applied (esc/ctrl row, 中文 key). |
| **9. Test on the device before shipping visual work; send one ZIP at a time.** | Three ZIPs at once confused things; render-only tests missed real-device behaviour. |

## What v2 keeps (the fixes that are real)

| Fix | How, in v2 |
|---|---|
| Wi-Fi drops / "!" no internet (ath10k, 5 GHz) | NetworkManager drop-in: power saving off, 2.4 GHz preferred (switch in Companion). Recorded, undoable. |
| No sound (all 4 speakers) and microphone | PipeWire drop-in `nofail` for t860-fedora's mic node; ALSA routes from Samsung's own `mixer_paths_tavil.xml` (SEC_TDM_RX_0 four channels, amps FL/FR/RL/RR, QUIN_MI2S_TX two channels, IN1L/IN1R), saved with `alsactl`. |
| USB-C drives/hubs | t860-fedora's `usb-role host`, from a Companion button (polkit: no password, can only flip the port). HDMI over USB-C is not possible (no Type-C controller driver). |
| Power + Volume Down screenshot | t860-fedora's `tabs6-powerkeyd` already does it; S6 adds nothing (v1's `s6-keys` duplicated it). |
| Restart into TWRP / Download mode | Companion power menu (helper action). |
| In-app updates without TWRP | `s6-update self`, branch fallback, no downgrades. |
| Restoring from the Android backup | Files, wallpaper, Wi-Fi networks, Bluetooth pairings, Linux versions of apps: once, in S6 Setup, from the package on the microSD card. |
| Android apps (Waydroid) | One root session for the whole move (one password). Before anything else: check Waydroid can start on this kernel (binder); if it can't, say so instead of half-working. |

## What v2 drops

S6 Quick Settings / control centre, S6 clock, tray tidy-up, the five layouts and their Global Themes, `s6-look`
(styles, effects, icons, Dolphin), S6 Looks, the Plymouth/KSplash themes, the OSD, `s6-kbd`, `s6-keys`, S6 Keyboard
(Maliit patching), the before-login extras job (COPR Darkly/Better Blur). Each can come back later only as a
self-contained opt-in module that records its changes (rule 1) and touches no KDE settings file (rule 3).

## How to get to a clean system

1. Reinstall t860-fedora fresh (its latest release has PS_HOLD power-off and other fixes) with the S6 switch ZIP
   from the microSD card. The Android backup on the card is not touched.
2. First boot: **S6 Setup** (account, Wi-Fi, time zone from a list, restore from the backup or start fresh). Nothing
   else; no layouts, no themes, no updates.
3. Desktop: Fedora's KDE. **S6 Companion** offers the fixes above, updates, Android apps, and Undo.

## Order of work

1. `changes.list` + `s6-undo` (rule 1), used by everything after it.
2. v2 fixes package: Wi-Fi, sound, USB, power menu. Unit tests with fake `amixer`/`nmcli`.
3. S6 Setup v2 (trimmed: no layout/look pages).
4. S6 Companion v2 (fixes, updates, Android, Undo; no Look page).
5. Switch ZIP builds v2 only; update ZIP for existing installs offers "clean up v1" (reverts v1's leftovers from
   its own lists) for anyone who doesn't reinstall.
