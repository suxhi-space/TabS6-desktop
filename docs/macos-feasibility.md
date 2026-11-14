# Is macOS possible on the Tab S6?

**Short answer: not natively, with current macOS, on this CPU.** The blocker is a missing
CPU feature, not missing drivers. iPadOS 17 (possibly 18) is the realistic ceiling, and
iPadOS already has the tablet UI.

## The three hard requirements, checked

| Requirement | Why | Tab S6 (Snapdragon 855, Kryo 485) | Snapintosh's X2 Elite |
|---|---|---|---|
| **Pointer authentication (PAC, ARMv8.3)** | Apple-silicon macOS (kernel, drivers and system userland) is **arm64e**, which uses PAC instructions throughout. iOS/iPadOS 27 are arm64e-only too | **Missing.** Kryo 485 is ARMv8.2 (A76/A55-derived). Non-HINT PAC instructions (`BLRAA`, `RETAA`, `LDRAA`, ...) are undefined and trap | Present |
| **Control of EL2** (for the Snapintosh approach) | Snapintosh is an EL2 monitor that emulates Apple's SPTM/TXM and fakes Apple devices under an unmodified kernelcache | **Not available.** Qualcomm's hypervisor owns EL2 (`Hypervisor` carve-out at `0x85700000`); Android/UEFI enter at EL1 | UEFI hands over at EL2 on Windows-on-ARM laptops |
| **16 KiB pages** | XNU uses 16K translation granules | Supported (A76/A55 designs). This is *not* a blocker; the earlier assumption in our chat was wrong | Not supported; Snapintosh shadows 16K tables onto 4K |

Sources:
- UniXNU's [arm64e doc](https://github.com/UniXNU/UniXNU/blob/main/docs/porting/arm64e.md):
  *"arm64e needs native PAC hardware… iOS and iPadOS 18 are the last releases that
  support arm64, and iOS and iPadOS 27 are arm64e only."* Its [macOS profile](https://github.com/UniXNU/UniXNU/blob/main/docs/porting/macos.md)
  is an arm64e profile and *"the device must pass the arm64e requirements."*
- Snapintosh [README](https://github.com/Snapintosh/Snapintosh): EL2 monitor, stock
  arm64e kernelcache, one laptop model, Mac host over USB-C on every boot.
- iPadOS-nabu notes on SM7150/SM8150: *"Kryo 470 = ARMv8.2, no PAC → must build plain arm64"*;
  ID_AA64MMFR0 shows 16K granule supported.

Confirm on your unit: `tools/recon/s6-recon.sh` prints the CPU `Features` line (no `paca`
means no PAC) and the `started at EL1` line.

## Could PAC be worked around?

In theory, by trapping and emulating every PAC instruction, or by rewriting every arm64e
binary to arm64. In practice:
- **Trap and emulate**: PAC instructions appear in nearly every function prologue and
  epilogue of macOS system code. HINT-space ones (`PACIASP`/`AUTIASP`) would run as no-ops,
  but the combined branch/load forms are undefined and would trap on every call. That
  would be orders of magnitude too slow, and without EL2 the trap goes to the kernel itself.
- **Binary rewriting**: every system binary, the shared cache, every kext and the
  kernelcache, for every macOS update, with code signing to defeat. Nobody has done this;
  it would be a research project far larger than the whole port.

Neither is a sensible goal.

## Could older macOS work?

macOS on Apple silicon has been arm64e from the first release (macOS 11). There is no
arm64-only Apple-silicon macOS to fall back to. Intel macOS is x86-64 and would need full
emulation.

## What is realistic

| Target | Feasibility on the S6 | Notes |
|---|---|---|
| iPadOS 16 / 17 (arm64) | **Yes, as a long research project** | Same path as nabu and the Tab S7+ port. UniXNU's arm64 profile is `ipados-17.7.11-21H461` |
| iPadOS 18 (arm64) | Possible | Last arm64 release; one experimental SM8150 port (Redmi K20 Pro) uses it |
| iPadOS / iOS 27 | No | arm64e only |
| macOS (any Apple-silicon version) | No (natively) | arm64e + no EL2 |
| macOS streamed from a real Mac | Yes, today | Remote desktop or Sidecar-style apps; not native, but zero risk |

## What iPadOS on the S6 would and would not give you

Even the best Samsung port (Tab S7+) runs without Apple ID sign-in, App Store downloads,
iCloud, Secure Enclave or code-signing enforcement, and with rotation still unstable. Apps
have to be side-loaded into a relaxed-security system. It is a remarkable hack and a
genuine engineering project. It is not a supported, updatable daily OS, and iPadOS 17
is already two major versions behind, so new apps increasingly refuse to install on it.

If the goal is mainly **a more desktop-like tablet you can use every day**, the mainline
Linux port already gives you KDE Plasma natively on this exact tablet, and Android 16
desktop windowing on your current GSI is a no-wipe option. Both are worth knowing about
alongside this project.
