# Credits

S6 Migrate is a migration assistant and companion for other people's work. It packs your Android
apps, data, files and settings, drives an existing Fedora port for the Galaxy Tab S6 from the tablet
itself, and puts everything back. The hard parts of running Linux on this tablet were done by the
projects below. Thank you.

## Linux on the Galaxy Tab S6 (what S6 Migrate installs)

| Project | What it is | How S6 Migrate uses it |
|---|---|---|
| [Bentlybro/gts6l-mainline-linux](https://github.com/Bentlybro/gts6l-mainline-linux) by **Bentlybro** ([write-up](https://bentlybro.com/posts/mainline-linux-on-the-galaxy-tab-s6-a-32-byte-field-and-one-line-of-device-tree)) | The mainline Linux port for the SM-T860: getting past Samsung's bootloader, the kernel and device tree, touch, battery, Wi-Fi, audio, sensors, and the documentation of every pitfall | Foundation of the whole Linux path; its findings (the `misc` boot control block, the Wi-Fi memory fix, the boot method) shaped the switch's safety checks |
| [starlight4you/t860-fedora](https://github.com/starlight4you/t860-fedora) by **starlight4you** | Fedora 44 KDE for the SM-T860, built on Bentlybro's port, with the native display driver and a recovery installer | The system S6 Migrate downloads (pinned release and checksums) and installs by running its installer from TWRP |
| [Project Aloha](https://github.com/Project-Aloha) (`mu_aloha_platforms`, `DualBootKernelPatcher`) | SM8150 UEFI firmware with a `samsung-gts6lwifi` target, and the tool that injects it into the stock boot image | The boot hand-off inside the t860-fedora installer |
| [Magisk](https://github.com/topjohnwu/Magisk) by topjohnwu | Root for Android, and `magiskboot` | Root lets S6 Migrate read app data and settings; `magiskboot` repacks the boot image in the installer |
| [TWRP](https://twrp.me) | Custom recovery | Runs the switch |
| [Fedora Project](https://fedoraproject.org), [KDE Plasma](https://kde.org), [Mesa](https://mesa3d.org) (freedreno, Turnip), [linux-msm](https://github.com/linux-msm) and the mainline Linux contributors | The operating system, desktop, graphics drivers and Qualcomm support | Everything you use after the move |

## Updates and tune-ups

| Project | Use |
|---|---|
| t860-fedora's `tabs6-kernel` (starlight4you) | LAST KNOWN GOOD kernel snapshot and rollback, used by `s6-update` before and after a tablet system update |
| [RPM Fusion](https://rpmfusion.org) | Optional media codecs (full ffmpeg, GStreamer plugins) |
| [KDE Plasma](https://kde.org) scripting, kscreen-doctor, Discover | Layouts, screen size, and Fedora updates in S6 Companion |
| [PikaOS](https://pika-os.com), [Nobara](https://nobaraproject.org), [Zorin OS](https://zorin.com) | Inspiration for the welcome app, tune-ups and layout picker (no code or artwork used) |

## Android apps on Fedora

| Project | Use |
|---|---|
| [Waydroid](https://github.com/waydroid/waydroid) and [LineageOS](https://lineageos.org) | Run your Android apps on Fedora |
| [bindfs](https://bindfs.org) | Share Linux folders with Android apps |

## Linux versions suggested for your apps

[Pear Desktop](https://github.com/pear-devs/pear-desktop) (YouTube Music), [FreeTube](https://freetubeapp.io),
[Telegram Desktop](https://desktop.telegram.org), [Vesktop](https://github.com/Vencord/Vesktop),
[Thunderbird](https://www.thunderbird.net), [Firefox](https://www.mozilla.org/firefox/),
[LibreOffice](https://www.libreoffice.org), [Marknote](https://apps.kde.org/marknote/), [Obsidian](https://obsidian.md),
[VLC](https://www.videolan.org), [Haruna](https://apps.kde.org/haruna/), [Krita](https://krita.org), [GIMP](https://www.gimp.org),
[Kamoso](https://apps.kde.org/kamoso/), [KDE Connect](https://kdeconnect.kde.org), and KDE's Gwenview, Dolphin, Okular and KCalc.
The list is in [`tools/migrate/lib/alternatives.tsv`](tools/migrate/lib/alternatives.tsv); suggestions welcome.

## App look

The app uses the [Red Hat Display and Red Hat Text](https://github.com/RedHatOfficial/RedHatFont) fonts by Red Hat,
under the SIL Open Font License 1.1 (bundled as `android/app/src/main/fontassets/fonts/OFL.txt`), and Fedora's blue.
It uses no Fedora, Microsoft or Apple logos.

## Research references (Apple OS track)

[UniXNU](https://github.com/UniXNU/UniXNU), [iPadOS-nabu](https://github.com/mytiantian001/iPadOS-nabu),
[UniXNU-gts7xlwifi](https://github.com/rui12366B/UniXNU-gts7xlwifi), [ios-pipa](https://github.com/nishant713/ios-pipa),
[ios-apollo](https://github.com/aTechGeekDev/ios-apollo), [Snapintosh](https://github.com/Snapintosh/Snapintosh),
[macOS-ForSheng](https://github.com/CrossDarwin/macOS-ForSheng), [macos-pixel8a](https://github.com/Rubanoxd/macos-pixel8a),
[Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) and [Mac.apk](https://github.com/kksimp/Mac.apk) informed
`docs/macos-feasibility.md` and `docs/prior-art.md`. S6 Migrate does not include their code.

## Licences

S6 Migrate does not copy code from these projects: it downloads the t860-fedora release as published
and runs its installer, and calls the other tools as separate programs. Each project keeps its own
licence (t860-fedora and gts6l-mainline-linux: GPL-2.0; see each repository).
