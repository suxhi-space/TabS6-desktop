# Galaxy Tab S6 desktop project

Giving a **Samsung Galaxy Tab S6 Wi-Fi (SM-T860)** a more desktop-like OS, running natively
(no Android underneath). Two tracks:

- **Linux (recommended, practical):** Fedora + KDE Plasma, keeping your files and bringing
  Android apps along with Waydroid. See [docs/linux-install-plan.md](docs/linux-install-plan.md).
- **Apple OS (research):** what it would take to boot Apple's XNU kernel and iPadOS on this
  tablet, and why macOS is out of reach on its CPU.

**Status: Phase 0 (recon) done for both tracks. Nothing has been flashed.** The repository contains
findings and read-only tools. No boot or flash code yet, by design.

## Bottom line from Phase 0

| Question | Answer |
|---|---|
| Can it run **macOS**? | **No, not natively.** The Snapdragon 855 lacks pointer authentication (ARMv8.3 PAC), and all Apple-silicon macOS is built for it. Every native macOS port so far (Pixel 8a, Xiaomi Pad 6S Pro, Snapintosh) runs on a PAC-capable CPU. [Details](docs/macos-feasibility.md) |
| Can it run **iPadOS**? | **Plausibly iPadOS 17 (maybe 18)**, as a long research project. Same SoC as an existing iPadOS bring-up (Xiaomi Pad 5), same touch, pen and amp family as a working Samsung port (Galaxy Tab S7+) |
| How do we get past Samsung's bootloader? | **Already solved for this exact tablet.** Mainline Linux boots on the SM-T860 through Project Aloha UEFI. XNU should load from that UEFI. [Details](docs/boot-path.md) |
| What is the hardware? | Fully identified. [Hardware table](docs/hardware.md) |
| What will be hardest? | Getting the iPadOS UI to present (the Pad 5 port is stuck there), then Wi-Fi (the S6's WCN3990 differs from every existing XNU Wi-Fi driver), then battery and sleep |

## Documents

| File | Contents |
|---|---|
| [docs/my-unit.md](docs/my-unit.md) | Recon results from your tablet and what they mean |
| [docs/hardware.md](docs/hardware.md) | Every chip, address, GPIO and memory region, with sources |
| [docs/prior-art.md](docs/prior-art.md) | Every relevant port, what actually works vs what is claimed, SoC-vs-device code map, gap list |
| [docs/boot-path.md](docs/boot-path.md) | Boot path decision (UEFI chainload) with evidence and device-specific traps |
| [docs/macos-feasibility.md](docs/macos-feasibility.md) | Why macOS is blocked by silicon and what is realistic instead |
| [docs/linux-install-plan.md](docs/linux-install-plan.md) | **Recommended practical path:** Fedora + KDE on the tablet, keeping files and bringing Android apps via Waydroid |
| [docs/migration-assistant.md](docs/migration-assistant.md) | The Migration Assistant app (`s6-migrate`): v0.1 packs your apps, data and folders; install command inside |
| [docs/phase1-test-plan.md](docs/phase1-test-plan.md) | Step-by-step Phase 1 plan with expected outcomes, rollback procedures and abort criteria |

## Your next step: one command, on the tablet

You need Termux (you have it) and Magisk root (you have it). Nothing is installed or left
behind except `curl` inside Termux if it is missing.

**1. Make a short-lived GitHub token** (in the tablet's browser, signed in to GitHub):
Settings → Developer settings → Personal access tokens → **Fine-grained tokens** →
Generate new token:
- Expiration: **1 day**
- Repository access: **Only select repositories** → `TabS6-desktop`
- Permissions → Repository permissions → **Contents: Read and write**

Copy the token.

**2. Paste this one line into Termux** and press Enter (copy it from this page in the browser):

```bash
command -v curl >/dev/null || pkg install -y curl; read -rsp 'GitHub token: ' T; echo; curl -fsSL -H "Authorization: Bearer $T" -H 'Accept: application/vnd.github.raw' 'https://api.github.com/repos/suxhi-space/TabS6-desktop/contents/tools/recon/tabs6-onetap.sh?ref=claude/android-tablet-desktop-ui-755uqh' | GH_TOKEN="$T" bash; unset T
```

Paste the token when asked (it stays hidden), tap **Grant** in the Magisk prompt, answer the
Design B question (`y` writes one 1 MiB test file, `n` writes nothing), read the report, and
type `yes` to upload.

What it does: surveys the tablet as root (read-only), builds a **scrubbed report** (serial
number, MAC and e-mail addresses removed; no raw device tree, kernel log or partition data),
shows you all of it, and uploads only that report to the temporary branch `recon-upload` under
a generic author name. The token lives only in memory, and every temporary file is deleted when
it finishes, even on error.

**3. Afterwards:** tell Claude "recon uploaded", then delete the token on GitHub. Uninstall
Termux too if you want nothing left at all.

<details><summary>Alternative: run it from a computer over USB</summary>

With `adb` and `git` on the computer (Windows: Git Bash):

```bash
git clone https://github.com/suxhi-space/TabS6-desktop.git
cd TabS6-desktop && git checkout claude/android-tablet-desktop-ui-755uqh
./tools/recon/collect.sh
```
</details>

Before any flashing, also run the verified backup (stays on your computer, never uploaded):

```bash
./tools/recon/s6-backup.sh
```

## Ground rules

- The owner runs every flashing step on the device. Nothing in this repo flashes anything.
- Never flash bootloaders, modem, EFS, persist, PIT, or repartition.
- No Apple binaries (IPSW, kernelcache), Samsung/Qualcomm firmware, or device dumps in git.
  Apple's licence limits its OS to Apple hardware; supply your own IPSW and keep it local.

## Credits

S6 Migrate builds on other people's work, above all [Bentlybro/gts6l-mainline-linux](https://github.com/Bentlybro/gts6l-mainline-linux) and [starlight4you/t860-fedora](https://github.com/starlight4you/t860-fedora). See [CREDITS.md](CREDITS.md) for everyone.

## Key references

- [Bentlybro/gts6l-mainline-linux](https://github.com/Bentlybro/gts6l-mainline-linux): mainline Linux on this exact tablet (boot method, hardware map)
- [Project-Aloha/mu_aloha_platforms](https://github.com/Project-Aloha/mu_aloha_platforms): SM8150 UEFI with a `samsung-gts6lwifi` target
- [mytiantian001/iPadOS-nabu](https://github.com/mytiantian001/iPadOS-nabu): iPadOS bring-up on the same SoC
- [rui12366B/UniXNU-gts7xlwifi](https://github.com/rui12366B/UniXNU-gts7xlwifi): iPadOS 17 on the Galaxy Tab S7+
- [UniXNU/UniXNU](https://github.com/UniXNU/UniXNU): the shared XNU-on-ARM64 porting framework
