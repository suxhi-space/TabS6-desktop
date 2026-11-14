# Prior art: what exists, what actually works, and what transfers to the Tab S6

Researched 2026-11-14. All repositories were cloned and read; commit hashes are given so
claims can be re-checked. "Claimed" means the project's own README says so. "Verified"
means the code or the project's engineering notes back it up.

## The short version

1. The brief's "template to follow", **ios-pipa**, overstates its state. Its README
   claims touch at 90% and GPU at 85%. Its own handover notes from 2026-11-08 say the
   touchscreen **does not respond**. The repository is one WIP commit, and the XNU patch
   series it describes (0060-0160) is not in it: kernels are built in a separate,
   non-public repository. Treat it as reference code, not a template.
2. Two much better references exist that the brief did not know about:
   - **iPadOS-nabu**: an iPadOS port on the Xiaomi Pad 5, the **same SoC (SM8150)** and
     same panel resolution as the Tab S6.
   - **UniXNU-gts7xlwifi**: iPadOS 17 on the **Galaxy Tab S7+**, a Samsung tablet one
     generation newer, with GPU, touch, S Pen, Wi-Fi, Bluetooth, audio and battery working.
3. **The Tab S6 boot problem is already solved for Linux.** Mainline Linux (Fedora + KDE)
   runs natively on the SM-T860 through Project Aloha UEFI. That gives a proven,
   documented way past Samsung's bootloader and a complete hardware map.
4. **macOS is blocked by the CPU**, not by effort. See [`macos-feasibility.md`](macos-feasibility.md).

## Project survey

| Project | Device / SoC | OS | State (verified) | Relevance to S6 |
|---|---|---|---|---|
| [gts6l-mainline-linux](https://github.com/Bentlybro/gts6l-mainline-linux) `41fa9b8` | **Tab S6 Wi-Fi, SM8150** | Fedora 44 + KDE, mainline 6.12 | Daily-drivable: UFS, display (simpledrm), touch, Adreno 640, Wi-Fi, BT, speakers, mics, battery, suspend, sensors. Not done: native DSI, S Pen, USB 3 | **Highest.** Boot path, hardware map, every SoC gotcha |
| [t860-fedora](https://github.com/starlight4you/t860-fedora) `8b97198` | Tab S6 Wi-Fi | Fedora 44, Linux 6.18 | Adds native DPU/dual-DSI display at ~60 fps. Installer marked pre-release and not yet fully validated end-to-end | High: native display pipe reference |
| [mu_aloha_platforms](https://github.com/Project-Aloha/mu_aloha_platforms) `cf5dcae4` | SM8150 devices incl. **`samsung-gts6lwifi`** | UEFI (Project Mu) | The UEFI the Linux port boots through | **Boot path** |
| [iPadOS-nabu](https://github.com/mytiantian001/iPadOS-nabu) `057b7f5` | Xiaomi Pad 5, **SM8150-AC** | iPadOS 16.6.1 (iPad7,3 userland) | XNU boots, UFS root r/w, launchd + SpringBoard + backboardd start, PMIC keys. **UI not visible yet** (backboardd turns display off after one frame), 1 core stable, no GPU, touch not finished | **Highest for XNU**: same SoC, same addresses |
| [UniXNU-gts7xlwifi](https://github.com/rui12366B/UniXNU-gts7xlwifi) `88b34f9` | **Galaxy Tab S7+ Wi-Fi**, SM8250 | iPadOS 17.7.11 | 8 cores, UFS root + Data, GOP framebuffer + DPU scanout, Adreno 650 + AdrenoMetal (Turnip), STM FTS touch, S Pen as Apple Pencil, Wi-Fi (QCA6390/ath11k), BT, speakers + mic, battery, haptics, shutdown. Rotation can reset the SoC | **Highest for Samsung-specific drivers** |
| [UniXNU](https://github.com/UniXNU/UniXNU) `0c1bac3` | Framework + 374 device records | iOS 16 / iPadOS 17-18 (arm64), iPadOS/macOS 27 (arm64e) | Shared build system, DarwinBoot UEFI loader, OS profiles, components. 24 SM8150 device records (many forks of the same few phones); best documented SM8150 result is "iOS 16.7.16 userland reached; GPU pending" (OnePlus 7 Pro) | **Framework to build on** |
| [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) `fb4efb3` | Many; `HanaPkg` = SM8150 (Pad 5, Mi 9, Poco X3 Pro, LG G8X) | UEFI | Pad 5: display, UFS, USB device mode, Windows and Linux boot. Boots several Samsung Snapdragon phones by the same boot.img route. **No Tab S6 target** | UniXNU's expected UEFI base; HanaPkg as fallback |
| [ios-pipa](https://github.com/nishant713/ios-pipa) `830ec1c` | Xiaomi Pad 6, SM8250 | iOS 16 (iPhone10,3) per handover | SpringBoard rendered via fastboot-boot shim, power key, UFS. Touch **not working** as of its 2026-11-08 notes | Medium: shim, mkadt, NT36523 work (not our touch chip) |
| [ios-apollo](https://github.com/aTechGeekDev/ios-apollo) `1f75f38` | Mi 10T, SM8250 | iOS 16 | Origin of pipa's Adreno 650 / ath11k work | Low-medium |
| [Snapintosh](https://github.com/Snapintosh/Snapintosh) `940eeb9` | ASUS Zenbook A16, Snapdragon X2 Elite | macOS 27 | Desktop with GPU; needs a Mac over USB-C every boot. EL2 monitor + PAC-capable CPU | **Not transferable** (see macOS doc) |
| HackiOS, ios-sweet | Phones (SM7150 etc.) | iOS 16.x | Early | Low |

## Where the S6 differs from each reference

| Area | Tab S6 | nabu (same SoC) | Tab S7+ (Samsung) |
|---|---|---|---|
| Boot | Samsung ABL, no fastboot, AVB trailer required | Xiaomi ABL, `fastboot boot` | Samsung ABL, Renegade edk2 UEFI behind an Android selector |
| Framebuffer | `0x9c400000`, 2560x1600 landscape, dual-DSI cmd mode | `0x9c000000`, 1600x2560 portrait | GOP + DPU direct scanout, dual-DSI |
| Touch | STM FTS1BA90A, I2C QUP2 SE17, GSI-DMA only | Novatek NT36523, SPI | **STM FTS1BA90A**, bit-banged GPIO I2C |
| Pen | Wacom W9021 I2C | none | **Wacom** I2C (T970Pen) |
| Wi-Fi | **WCN3990, ath10k_snoc, modem-hosted fw** | not implemented | QCA6390, ath11k, PCIe |
| BT | WCN3990 UART | none | QCA6390 UART |
| Audio | ADSP, Secondary TDM, **4x CS35L41** | none | ADSP, Primary TDM, **4x CS35L41** |
| Battery | **SM5705** I2C | not implemented | MAX77705 |
| GPU | Adreno 640 (A6xx) | none | Adreno 650 (A6xx) |
| CPU clusters | 4+3+1 | 4+3+1 | 4+3+1 |
| Power off | PSCI hangs; PS_HOLD | PSCI SYSTEM_RESET works | PSCI failsafe patch |

## Code map: SoC-specific vs device-specific

How much of each reference could be reused on the S6, by subsystem.

| Subsystem | Reuse source | SoC-specific (reusable as-is or nearly) | Device-specific (S6 work) |
|---|---|---|---|
| UEFI | Aloha `samsung-gts6lwifi` | everything; already targets this board | add UniXNU's DXE modules (DarwinBoot, UniXNUDxe, RamDisk) to the DSC/FDF, or chain an EFI app |
| Boot shim (non-UEFI route) | nabu `shim/` | GIC, PSCI-over-SMC, MMU (16K, never cache carve-outs), UFS base `0x1d84000`, IMEM | framebuffer address and orientation, memory map, Samsung boot container packaging |
| XNU platform | nabu `xnu/patches` 0001-0023 (non-PAC build, GICv3 group-1 IRQ timer, PSCI via SMC, device-tree platform expert) | **all of it**: same core types, same GIC quirks, same timer PPIs | none expected |
| SMP / scheduler | Tab S7+ `t970-three-clusters.patch`, IPIs via SPI | 4+3+1 topology matches | IPI SPI base must be measured |
| Shutdown | Tab S7+ shutdown failsafe | — | PS_HOLD path (PSCI hangs on S6) |
| Storage | nabu UFS driver / UniXNU `ShengUfs` | UFS host @ `0x1d84000` identical to nabu | Samsung TZ "lying halt bit" clock quirk (mainline `BRANCH_HALT_SKIP`); prefer inheriting UEFI's UFS state |
| Display | UniXNU `GopFramebuffer`, Tab S7+ DPU scanout | MDSS/DPU generation close to SM8250 | ANA38401 dual-DSI cmd panel, landscape 2560x1600; DCS brightness |
| Touch | Tab S7+ `T970FtsTouch.cpp` | protocol (STM FTS / SEC-TS) | bus: QUP2 SE17 needs GPI DMA, or bit-bang GPIO I2C as T970 does (pins to be read from the stock DT); rails L14A/L17A |
| S Pen | Tab S7+ `T970Pen.cpp` | Wacom I2C protocol | i2c14 @ `0x56`, GPIOs 5/53/11 |
| Buttons | nabu PMIC PON keys | PON block | Volume-Up on `pm8150l_gpios 12` |
| GPU | Tab S7+ `Adreno650` + AdrenoMetal, UniXNU `Adreno6xx` (SM-T733) | A6xx family, Turnip supports A640 | A640 GMU/firmware, Samsung-signed zap shader from the device |
| Wi-Fi | pipa/T970 LinuxKPI + ath11k | — | **new**: ath10k_snoc on LinuxKPI, mpss (modem) PAS boot for WLAN fw, QMI, MSA at `0xc0000000` |
| Bluetooth | T970 BlueTool replacement, pipa bt-inject | Qualcomm UART HCI approach | WCN3990 firmware (`crbtfw21`), QUP2 SE3 UART, BD address from efs |
| Audio | Tab S7+ `T970Audio.cpp` + HAL | ADSP/APR/AFE stack, CS35L41 driver | Secondary TDM, SM8150 ADSP firmware, amp I2C bus and reset GPIO 148 |
| Battery | — | — | **new**: SM5705 fuel gauge + charger |
| Haptics | Tab S7+ (PMIC LDO motor) | — | **new**: DA7280 I2C haptics driver |
| Sensors | Tab S7+ SLPI boot | SLPI PAS | LSM6DSO behind SLPI + FastRPC |
| USB debug | Tab S7+ `QcomXnuUsbDebug`, `QcomDwc3` | DWC3 @ `0xa600000` (same IP family as SM8250) | PHY init details; SM5705 MUIC routing |

## Gap list for the Tab S6

Ordered by when it blocks progress.

1. **Boot handoff into a Darwin loader.** Aloha UEFI reaches a UEFI screen on this tablet
   (proven). Missing: a UniXNU-integrated build of that UEFI, or a standalone EFI loader on
   the ESP. See [`boot-path.md`](boot-path.md).
2. **A board ADT and memory plan.** One contiguous XNU range that avoids all carve-outs.
   Candidate: start in the free DDR above `0xc0000000`, using the nabu and Tab S7+ approaches.
3. **Debug channel.** No UART; ramoops is wiped on reboot. Use a framebuffer console,
   then a persistent log ring in a spare partition (nabu, Tab S7+), then USB CDC-ACM.
4. **iPadOS UI actually presenting.** nabu is stuck exactly here on the same SoC.
   Tab S7+ solved it with UniXNU's GOP display path and specific boot-args.
5. **Touch.** FTS1BA90A logic exists (Tab S7+); the S6 bus needs GPI DMA or GPIO bit-bang.
6. **GPU.** A640 support in the A6xx drivers.
7. **Wi-Fi.** Largest new driver effort (ath10k_snoc + modem firmware boot).
8. **Battery, haptics, sensors, sleep.** Board-specific, lower priority.

## Licensing notes

- The Linux references (mainline port, t860-fedora) are **GPL-2.0**. XNU port code is
  APSL/BSD/MIT. Use the GPL sources for **facts** (register addresses, sequences, quirks),
  not copied code, or keep any derived driver separately licensed.
- Apple binaries (IPSW, kernelcache, trust caches) and Samsung/Qualcomm firmware must come
  from your own copies and must not be committed. `.gitignore` covers the common file types.
