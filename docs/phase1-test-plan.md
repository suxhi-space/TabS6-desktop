# Phase 1 test plan: safe boot path and a debug channel

**Goal of Phase 1:** reach a state where an XNU kernel can be loaded on the tablet and show
*something* on screen, with a tested way back to Android at every step. Phase 1 does
**not** install iPadOS and does **not** touch `userdata`.

**Ground rules**
- You run every flashing step on the device yourself. Nothing in this repo flashes.
- One change per boot. Write down what you flashed, its SHA-256, and what you saw.
- If an outcome is not one of the listed ones, **stop** and report back. Do not try a
  variant blind.
- Battery above 60%, original USB cable, a computer with Odin (Windows) or Heimdall
  (Linux/macOS) that you have tested in Download Mode **before** you need it.

**Never flash or modify:** BL (XBL, ABL, TZ, hyp, etc.), CP (modem), EFS, sec_efs,
persist, PIT, or the partition table. Phase 1 touches only `boot`, `vbmeta` and `cache`.

---

## Step 0: Recon and backups (no risk)

| # | Action | Expected | If not |
|---|---|---|---|
| 0.1 | Run `tools/recon/s6-recon.sh` | `summary.txt` in `recon-out/` | Fix adb/root first |
| 0.2 | Check the model line | `SM-T860` | **Stop.** SM-T865/T866N are different boards; nothing here applies unmodified |
| 0.3 | Check `ro.boot.bootloader` | e.g. `T860XXS5DWH1`. Note the revision digit (`S5` here) | Note it; the restore firmware must match or be newer |
| 0.4 | Check the BCB line | Empty command | If `boot-recovery`: read **Step 0b** before anything else |
| 0.5 | Check CPU features and EL line | No `paca`; `started at EL1` | Report: this would change [`macos-feasibility.md`](macos-feasibility.md) |
| 0.6 | Run `tools/recon/s6-backup.sh` | `All copies verified.` | Re-run; never flash without verified copies of `boot`, `recovery`, `vbmeta`, `dtbo`, `misc`, `cache`, `efs`, `sec_efs`, `persist` |
| 0.7 | Copy the backup folder to a second place (USB drive or private cloud) | Two copies | — |
| 0.8 | Download full stock firmware (BL/AP/CP/CSC) for SM-T860 matching your bootloader revision or newer, from a reputable firmware site or Samsung's own tool (e.g. Frija/Bifrost) | Four `.tar.md5` files | Do not proceed without it: it is your last-resort restore |
| 0.9 | Note what is in `recovery` (TWRP or Magisk-patched stock) from the recon output and the recovery splash | Known | — |
| 0.10 | Back up your personal files from the tablet | Done | — |

### Step 0b: if the BCB says `boot-recovery`

This is the Magisk-in-recovery setup. ABL is booting `recovery` on every power-on and
ignores `boot`. Consequences:
- Any image you flash to `boot` will appear to "do nothing".
- Clearing the BCB makes ABL boot `boot` again. If `boot` cannot then start Android, the
  tablet will not reach a rooted Android to fix it, and `misc` cannot be flashed with Odin.

**Do not clear it yet.** Bring the recon output back here so the next step can be planned
for your exact state. The options (each needs care) are: (a) move root to a TWRP-based
setup first, so recovery stays a working rescue system; or (b) follow the mainline project's
path, a full stock restore (which resets the BCB), re-confirm OEM unlock online, then
continue from a clean state, losing the GSI install.

## Step 1: Prove the escape routes work (low risk, no writes)

| # | Action | Expected |
|---|---|---|
| 1.1 | Power off. Hold Volume-Up + Volume-Down, plug in USB. Choose Download (short press Volume-Up) | Blue "Downloading" screen |
| 1.2 | Odin: device shows as `COM` (or `heimdall detect` finds it). **Do not flash.** Force-reboot: hold Power + Volume-Down ~10 s | Tablet reboots normally into Android |
| 1.3 | Reboot to recovery: power off, then hold Power + Volume-Up | Your recovery (TWRP or stock) appears |
| 1.4 | Confirm OEM unlock status in Developer options is still on and greyed (already unlocked) | Unlocked |

Only continue when all four work. Download Mode lives in the bootloader, which this plan
never touches, so it remains available even if `boot` is broken.

## Step 2: Reproduce the known-good UEFI handoff (medium risk)

Follow the mainline project's
[BOOT_METHOD.md](https://github.com/Bentlybro/gts6l-mainline-linux/blob/41fa9b85bfb55f9ee671a1dcb8161a5d90a2d542/docs/BOOT_METHOD.md)
**exactly**, using **your own** `boot.img` from Step 0 as input (not someone else's).
Build on the computer. Before flashing, the offline check (`tools/avb_analyze.py` in that
repo) must show every item:

```text
size = 67,108,864   ANDROID! v1, page 4096   UNCOMPRESSED_IMG at 0x1000
_FVH present        SEANDROIDENFORCE present  AVB0 present   AVBf footer self-consistent
```

Flash `boot` + `vbmeta` (flags 3) together as one AP tar in Odin. Nothing else.

| Outcome | Meaning | Next |
|---|---|---|
| Different splash, then a UEFI screen; on the PC a new USB device appears | **Pass.** Past ABL, Aloha UEFI runs | 2.1 |
| Normal Android boots | ABL did not run the new `boot` (BCB? trailer?) | Stop, report. Check `getprop ro.boot.boot_recovery` and the BCB |
| Hangs on the Samsung logo | Image accepted but UEFI did not start | Rollback R1, report |
| Bootloop | Rejected image | Rollback R1, report |

2.1: At the UEFI screen, hold Volume-Down. Expect UEFI fastboot (`fastboot devices` lists
the tablet). That gives you a flash path that does not depend on Odin.

**Android does not boot while this image is in `boot`.** Going back is Rollback R1.

## Step 3: A FAT ESP on `cache` (low risk once Step 2 passes)

Create the ESP image on the computer (FAT32, 512-byte logical sectors, as the mainline
project does) containing a plain UEFI test app first, for example the UEFI Shell or a
"hello world" `BOOTAA64.EFI`. Flash it with UEFI fastboot (`fastboot flash cache esp.img`).

| Outcome | Meaning |
|---|---|
| UEFI runs the test app | **Pass.** The iteration loop works: change a file, reflash `cache`, reboot |
| UEFI shows no boot option | ESP not found: check the FAT format and the `\EFI\BOOT\BOOTAA64.EFI` path |

## Step 4: First XNU sign of life (no new risk to the device)

Only after the hardware findings are reviewed and a loader is chosen (see
[`boot-path.md`](boot-path.md), route B1). The deliverable is an XNU build plus loader that
paints coloured bars into the framebuffer at `0x9c400000` at each early boot stage (nabu
patch 0010 style), so progress is visible without any serial port. This needs its own
written plan before any code is run on the device.

Pass: the bars progress past `arm_vm_init`. Any failure here costs one reboot: hold
Power + Volume-Down, and UEFI comes back.

## Step 5: Debug channel decision

There is no UART and RAM is wiped on reboot. In order of effort:
1. **Framebuffer console** (XNU `kprintf` drawn on screen). Free once Step 4 works.
2. **Persistent log ring** in a partition XNU can write early (nabu writes the end of
   `userdata`; Tab S7+ writes a spare partition), read back from recovery.
3. **USB CDC-ACM** from XNU (Tab S7+ `QcomXnuUsbDebug` on the same DWC3 IP), a live log on the computer.

Phase 1 is done when 1 works and 2 or 3 is chosen.

---

## Rollback procedures

Keep these printed or on another device.

| ID | Situation | Procedure |
|---|---|---|
| **R1** | Back to Android from the UEFI image | Boot recovery (Power + Volume-Up). In TWRP: Install → Image → your **original `boot.img`** from the backup → Boot partition; same for `vbmeta.img`. Or in Download Mode with Odin: AP = a tar containing your original `boot.img` and `vbmeta.img` (packed as in Step 2) |
| **R2** | Recovery unreachable, Download Mode works | Odin: AP tar of original `boot.img` + `vbmeta.img` + `recovery.img` |
| **R3** | Nothing boots, Download Mode works | Full stock flash: BL + AP + CP + **HOME_CSC** (keeps data where possible) with the firmware from 0.8. Then: OEM unlock may need online re-confirmation (VaultKeeper), and root/GSI must be redone. Restore `efs`/`sec_efs`/`persist` only if they were damaged, from your own backup |
| **R4** | Tablet looks dead (black, no Download Mode) | Charge 30 min. Hold Power + Volume-Down 15 s, then immediately Volume-Up + Volume-Down with USB plugged in. Phase 1 never touches the bootloader, so a true hard brick should not be possible from these steps |
| **R5** | Stuck in a PSCI-reset hang | Hold Power + Volume-Down ~10 s (hardware reset) |

## Abort criteria

Stop and report instead of continuing if:
- any backup does not verify,
- the model is not SM-T860,
- Step 1 fails in any way,
- an outcome is not in the tables above,
- Odin reports a failure on a partition you did not intend to write.
