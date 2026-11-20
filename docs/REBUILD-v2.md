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

## Full list of planned changes (v2 base)

Everything below is recorded in `/var/lib/s6migrate/changes.list` as it happens; "Undo" reverts it.

### A. Programs S6 installs (its own files only, all under /usr/local)
| Path | What |
|---|---|
| `/usr/local/bin/s6-companion` | S6 Companion (welcome / tools app) |
| `/usr/local/bin/s6-update` | update S6 itself from GitHub; check t860-fedora releases |
| `/usr/local/bin/s6-restore` | restore from the Android backup (files, wallpaper, Wi-Fi, Bluetooth, apps) |
| `/usr/local/bin/s6-android` | start/stop Waydroid, list/launch/remove Android apps |
| `/usr/local/bin/s6-report` | a report for troubleshooting |
| `/usr/local/bin/s6-undo` | list and revert S6's system changes |
| `/usr/local/libexec/s6migrate/s6-helper` | the root side (run through pkexec; checks every argument) |
| `/usr/local/libexec/s6migrate/s6-sound` | speaker/mic routes, report |
| `/usr/local/libexec/s6migrate/s6-usb` | USB-C host/device |
| `/usr/local/share/s6migrate/app/` | Setup + Companion UI (Python + QML) |
| `/usr/local/share/applications/s6-companion.desktop` | menu entry |
| `/usr/local/share/icons/hicolor/scalable/apps/s6-companion.svg` | icon |

### B. System settings S6 changes (each recorded, original kept)
| Change | Why | When |
|---|---|---|
| new `/etc/NetworkManager/conf.d/60-s6migrate-wifi.conf` (power saving off) | Wi-Fi "!" / drops | install |
| saved Wi-Fi networks: band 2.4 GHz (`802-11-wireless.band bg`) | 5 GHz barely works on this radio data | install; switch in Companion |
| new `/etc/modprobe.d/s6migrate-wifi-country.conf` (your country) | correct channels | install |
| edit `/etc/pipewire/pipewire.conf.d/51-tabs6-mic.conf`: add `flags = [ nofail ]` | a failing mic node stopped all sound | install |
| ALSA mixer routes saved to `/var/lib/alsa/asound.state` (Fedora's alsa-restore loads them at boot) | speakers (4 amps) and mics silent | install; "Fix sound" |
| new `/etc/polkit-1/rules.d/49-s6migrate.rules` | password once for S6's helper; none for the USB-C button | install |
| user account created (`useradd`, `wheel`), password set (`chpasswd`); t860-fedora's default `fedora` account removed | one account, yours | Setup |
| time zone, language/region, device name (`timedatectl`, `localectl`, `hostnamectl`) | your choices | Setup |
| Wi-Fi networks from Android added to NetworkManager | connects at first start | Setup |
| Bluetooth pairings from Android into `/var/lib/bluetooth` (optional) | devices reconnect | Setup |
| Linux versions of your apps (Flathub / Fedora) | your choice per app | Setup |
| Waydroid: `waydroid init`, `waydroid-container` enabled, folder sharing unit `s6migrate-waydroid-share.service` | Android apps | only if chosen, after the kernel check passes |

### C. Temporary during first boot only (removed when Setup finishes, removal recorded)
| Change | Why |
|---|---|
| account `s6setup` + autologin `/etc/sddm.conf.d/zz-s6migrate.conf` | Setup runs before any account exists |
| `/etc/sudoers.d/50-s6migrate-firstrun` | Setup's steps without password prompts |
| autostart of S6 Setup in the `s6setup` account | opens Setup |

### D. Your home folder
| Change | Note |
|---|---|
| restored files in Pictures, Downloads, Documents, Music, Videos, `~/Android/<folder>` | from the backup |
| wallpaper set once with KDE's `plasma-apply-wallpaperimage` | KDE's own tool; nothing re-applied |
| `~/.config/s6migrate/` | S6's own state only |
| **no edits to any KDE settings file** | rule 3 |

### E. Never touched (v1 did; v2 won't)
PAM, authselect, SELinux, `/etc/sudoers` (beyond C), boot entries / kernel command line, Plymouth, SDDM theme,
`kwinrc`, `kdeglobals`, `plasma-org.kde.plasma.desktop-appletsrc`, `plasmashellrc`, `dolphinrc`, `darklyrc`,
`ksplashrc`, KWin scripts, Global Themes, icon themes, Maliit's files, dnf settings, sysctl/journald/systemd tune-ups,
COPR repositories.

### F. System updates
Not on first boot. In Companion: "Check for updates" uses Fedora's own offline updates (`dnf offline`), installed
during a restart by Fedora's standard mechanism, only when you press it. No S6 service.

### G. Add-ons afterwards, one at a time (each: own files, recorded, removable, tested on the tablet first)
1. Android app manager (your apps, launch, menu entries, uninstall)
2. Control centre (Googlebook-style; added to the panel once, on request; removable). It replaces KDE's own tray
   entries for Wi-Fi, sound, battery, brightness and Bluetooth: those are switched off in KDE's tray settings once,
   when the add-on is installed (recorded; removing the add-on switches them back), so nothing shows twice. App tray
   icons, the keyboard, clipboard and notifications stay in the tray (hidden ones behind ^, like Windows). The
   battery percentage is drawn inside the battery icon, like Android.
3. Clock + notifications
4. On-screen keyboard (Gboard-style, built as its own keyboard, not patches)
5. Layouts (placement only)
6. Look extras (Darkly, Better Blur): opt-in installs with clean removal
7. Text selection bar (KDE input permission)
8. Boot screen (logo + bar) / verbose switch
