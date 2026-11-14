# Boot path for XNU on a Samsung SM-T860

**Decision: chain through Project Aloha's SM8150 UEFI, which already boots on this exact
tablet, and load XNU from UEFI. Do not build a fastboot-style shim.**

This answers brief task 7.3 ("shim via boot image vs UEFI chainload, with evidence").

## Options considered

| | A. Direct shim in the boot image (ios-pipa / nabu style) | B. UEFI chainload (Aloha, then a Darwin loader) |
|---|---|---|
| How it starts | Shim + XNU payload replace the kernel in a Samsung boot container | Aloha's FD is injected after the **stock** Samsung kernel; a small shellcode copies it to `0x9FC00000` and jumps |
| Proven on SM-T860? | **No.** Every reference uses `fastboot boot`, which Samsung ABL does not have | **Yes.** Reaches the UEFI screen and boots mainline Linux daily ([BOOT_METHOD.md](https://github.com/Bentlybro/gts6l-mainline-linux/blob/41fa9b85bfb55f9ee671a1dcb8161a5d90a2d542/docs/BOOT_METHOD.md)) |
| Iteration loop | Every kernel test = repack boot image (keeping the Samsung AVB trailer) + Odin flash | Flash boot **once**; then iterate by replacing files on the ESP, through UEFI's own **fastboot** (hold Volume-Down) or from TWRP |
| Size limits | XNU + ADT must fit in the 64 MiB boot partition next to the stock kernel | Payload on a FAT ESP (the `cache` partition, ~95 MB filesystem on the reference unit) |
| Display at handoff | Shim must find and keep the ABL framebuffer | UEFI GOP framebuffer at `0x9c400000`, 2560x1600 (already handed to Linux as simpledrm) |
| Matches UniXNU | No | **Yes.** UniXNU is UEFI-based: DarwinBoot runs inside a Mu-based firmware. The Tab S7+ port boots exactly this way on a Samsung |
| Brick risk per test | Each flash can strand the device if the image is bad (recover via Download Mode) | Only the first flash touches `boot`; later tests touch only the ESP |

## Why B

1. **It already works on this hardware.** The hard part, getting past Samsung ABL, is
   solved and documented with byte-level analysis. Route A would redo that work alone.
2. **Fast, low-risk iteration.** After one boot flash, every XNU experiment is a file copy
   to the ESP. A bad kernel just fails inside UEFI's loader; Volume-Down fastboot still works.
3. **It is how the most successful Samsung port works.** UniXNU-gts7xlwifi boots iPadOS
   from an edk2 UEFI behind an Android selector on a Samsung SM8250.

## Two ways to get from Aloha UEFI to XNU

| | B1. Standalone EFI loader on the ESP | B2. Rebuild Aloha with UniXNU modules |
|---|---|---|
| What | Put a Darwin loader at `\EFI\BOOT\BOOTAA64.EFI` (where systemd-boot sits for Linux). Candidates: ios-pipa `loader/xnuloader.efi` (standalone C, builds the ADT and exits boot services) or a UniXNU DarwinBoot built as an app | Add `UniXNU.inf`, `UniXNUDxe`, `DarwinBoot`, `UniXNURamDiskDxe`, DiskIo and FAT to the Aloha `samsung-gts6lwifi` DSC/FDF, as [UniXNU's UEFI guide](https://github.com/UniXNU/UniXNU/blob/main/docs/porting/uefi-firmware.md) requires |
| Firmware change | None. Uses the proven FD byte for byte | New FD; must stay 3 MiB at `0x9FC00000` |
| Best for | **First sign of life**: XNU drawing on the framebuffer | Long-term: full UniXNU tooling, menu, payload packaging, OS profiles |

Recommended order: **B1 first, then B2** once XNU is known to start.

## The boot chain, step by step

```text
XBL (Qualcomm, signed, never touched)
 └─ ABL (Samsung, 32-bit, never touched)
     └─ boot partition: stock Samsung boot image, SEANDROIDENFORCE + AVB trailer intact
         └─ kernel slot: [stock kernel][shellcode entry][Aloha SM8150 FD]
             └─ shellcode copies FD to 0x9FC00000, jumps
                 └─ Aloha UEFI (Project Mu) ─ GOP framebuffer 0x9c400000
                     ├─ hold Volume-Down → UEFI fastboot (flash the ESP)
                     └─ BDS: \EFI\BOOT\BOOTAA64.EFI on the FAT ESP (cache partition)
                         └─ Darwin loader (B1) / DarwinBoot (B2)
                             └─ XNU + Apple Device Tree + boot-args
```

The image is built with `magiskboot unpack/repack` (which keeps Samsung's trailer) and
Aloha's DualBootKernelPatcher, then flashed with a verification-disabled `vbmeta`
(flags = 3) in the same Odin session. The full recipe and its offline verification
checklist are in the mainline project's BOOT_METHOD.md. **This repository deliberately
does not contain the flashing steps as a script**: they belong in the Phase 1 test plan,
run by you, one step at a time.

## Known traps on this exact device

| Trap | Effect | Source |
|---|---|---|
| `misc` BCB left at `boot-recovery` (Magisk-in-recovery setup) | ABL boots `recovery` every time and **never executes `boot`**. Every boot experiment silently "falls back to stock" | mainline DEVLOG |
| `misc` is not Odin-flashable | The BCB can only be changed from a rooted, running Android or TWRP | mainline DEVLOG |
| Repacking without the Samsung AVB trailer | ABL rejects the image and boots stock/recovery | AVB_ANALYSIS.md |
| Full stock restore | Samsung VaultKeeper re-arms; OEM unlock must be re-confirmed online before custom flashing works again | mainline DEVLOG |
| Recovery-partition chainloading | Never reached UEFI; route closed | BOOT_METHOD.md |
| The unconditional-UEFI shellcode | Android does not boot while it is installed. Volume-key dual-boot needs the keys read from PMIC registers (PON RESIN, pm8150l GPIO 12), not TLMM GPIOs, so Aloha's stock key-selector shellcodes will not work unmodified | inference from hardware map |
| `cache` used as the ESP | The FAT filesystem was made with 512-byte sectors while UFS reports 4096; Linux needs a loop device to mount it. If you go back to Android, check that Android does not choke on or reformat a FAT `cache` | mainline PORT.md |
| PSCI `SYSTEM_RESET` / `SYSTEM_OFF` hang | A loader or kernel that resets through PSCI hangs; force-reboot with Power + Volume-Down (long press) | mainline POWER.md |

## Your situation: Android 16 GSI with Magisk

Your tablet runs an Android 16 GSI on Samsung's Android 12 vendor and kernel, rooted with
Magisk. On the SM-T860, the stock boot image has no ramdisk, so Magisk is usually installed
into **recovery**, and the BCB then points at recovery. If so, a UEFI boot image flashed to
`boot` will never run until the BCB is cleared, and clearing it without a bootable `boot`
strands the tablet. `tools/recon/s6-recon.sh` checks both (BCB command, boot ramdisk size)
without changing anything. Run it before planning any flash.
