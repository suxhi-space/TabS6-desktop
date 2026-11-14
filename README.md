# TabS6-mac

Research project: Apple's OS running natively (bare metal, no Android underneath) on a
**Samsung Galaxy Tab S6 Wi-Fi (SM-T860)**.

**Status: Phase 0 (recon) done. Nothing has been flashed.** The repository contains
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
| [docs/hardware.md](docs/hardware.md) | Every chip, address, GPIO and memory region, with sources |
| [docs/prior-art.md](docs/prior-art.md) | Every relevant port, what actually works vs what is claimed, SoC-vs-device code map, gap list |
| [docs/boot-path.md](docs/boot-path.md) | Boot path decision (UEFI chainload) with evidence and device-specific traps |
| [docs/macos-feasibility.md](docs/macos-feasibility.md) | Why macOS is blocked by silicon and what is realistic instead |
| [docs/linux-install-plan.md](docs/linux-install-plan.md) | **Recommended practical path:** Fedora + KDE on the tablet, keeping files and bringing Android apps via Waydroid |
| [docs/phase1-test-plan.md](docs/phase1-test-plan.md) | Step-by-step Phase 1 plan with expected outcomes, rollback procedures and abort criteria |

## Your next step

With the tablet booted into Android (your rooted GSI is fine), USB debugging on and
Magisk granting root to the shell:

```bash
tools/recon/s6-recon.sh      # read-only survey; writes recon-out/<time>/summary.txt
tools/recon/s6-backup.sh     # read-only, SHA-256-verified partition backup to s6-backup/
```

Both scripts only read from the tablet. Their output contains your serial number and
device identity, so keep it private (`.gitignore` already excludes it). Then share
`summary.txt` (redact the serial) so Phase 1 can be planned for your unit's exact state.
The most important line is the **`misc command field`**: if it says `boot-recovery`, read
Step 0b of the test plan before doing anything else.

## Ground rules

- The owner runs every flashing step on the device. Nothing in this repo flashes anything.
- Never flash bootloaders, modem, EFS, persist, PIT, or repartition.
- No Apple binaries (IPSW, kernelcache), Samsung/Qualcomm firmware, or device dumps in git.
  Apple's licence limits its OS to Apple hardware; supply your own IPSW and keep it local.

## Key references

- [Bentlybro/gts6l-mainline-linux](https://github.com/Bentlybro/gts6l-mainline-linux): mainline Linux on this exact tablet (boot method, hardware map)
- [Project-Aloha/mu_aloha_platforms](https://github.com/Project-Aloha/mu_aloha_platforms): SM8150 UEFI with a `samsung-gts6lwifi` target
- [mytiantian001/iPadOS-nabu](https://github.com/mytiantian001/iPadOS-nabu): iPadOS bring-up on the same SoC
- [rui12366B/UniXNU-gts7xlwifi](https://github.com/rui12366B/UniXNU-gts7xlwifi): iPadOS 17 on the Galaxy Tab S7+
- [UniXNU/UniXNU](https://github.com/UniXNU/UniXNU): the shared XNU-on-ARM64 porting framework
