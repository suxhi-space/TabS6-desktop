# Galaxy Tab S6 Wi-Fi (SM-T860, `gts6lwifi`): hardware table

This replaces section 2 of the original brief. Every `[unverified]` item there is now filled in.

**Sources.** Most rows come from the mainline Linux port for this exact model,
[Bentlybro/gts6l-mainline-linux](https://github.com/Bentlybro/gts6l-mainline-linux) at
`41fa9b8` (2026-09-07). Its authors took addresses from the tablet's own extracted
stock device tree and then drove each block with a working driver. The memory map comes from
[Project-Aloha/mu_aloha_platforms](https://github.com/Project-Aloha/mu_aloha_platforms) at
`cf5dcae4`, `Platforms/SurfaceDuo1Pkg/Device/samsung-gts6lwifi/`. "Proven" means a
working driver exists, not just a datasheet value.

**Still to do on your own unit.** Run `tools/recon/s6-recon.sh` and fill the last
column. Units can differ in RAM size, panel vendor and firmware revision.

## SoC and platform

| Item | Value | Status | Measured on my unit |
|---|---|---|---|
| Model / codename | SM-T860, `gts6lwifi`. SM-T865 (`gts6l`) and SM-T866N are different boards; the Linux and UEFI work targets SM-T860 only | proven | |
| SoC | Qualcomm **SM8150P v2** (Snapdragon 855), `msm-id 0x169/0x20000`, `board-id 0x10008/0x2` | proven (brief's guess was right) | |
| CPU | 8 cores in **3 clusters**: 4x Kryo 485 Silver (A55-derived, part `0x805`, 1.79 GHz), 3x Gold (A76-derived, `0x804`, 2.42 GHz), 1x Gold Prime (2.84 GHz) | proven | |
| ISA level | **ARMv8.2-A. No pointer authentication (PAC), no MTE.** 4 KiB and 16 KiB translation granules both supported by the A76/A55 core designs | inferred from core type; confirm with recon (`Features` has no `paca`) | |
| Exception level at kernel entry | **EL1.** EL2 is held by Qualcomm's hypervisor: the UEFI memory map reserves a `Hypervisor` region at `0x85700000` | strong inference; confirm with recon (`started at EL1`) | |
| GPU | **Adreno 640** (`qcom,adreno-640.1`) @ `0x2c00000`, GMU @ `0x2c6a000`. Zap shader is Samsung-signed and has to come from the device | proven (freedreno, glmark2 848) | |
| RAM | 6 GB variant: DRAM `0x80000000` + `0x180000000`. ~4.8 GiB usable under Linux. 8 GB variants exist (256 GB storage SKU) | proven for 6 GB | |
| Storage | UFS @ `0x1d84000` (PHY `0x1d87000`, ICE `0x1d90000`). 128 GB in the reference unit | proven | |
| PMICs | PM8150, PM8150L, PM8009 (RPMh regulators). **Battery is not on the Qualcomm PMIC** (see below) | proven | |
| GIC | GICv3: GICD `0x17a00000`, GICR `0x17a60000`, standard for SM8150 | proven on other SM8150 ports | |
| Timer | 19.2 MHz arch timer. Qualcomm PPI numbering: virtual timer is INTID 19, physical INTID 18 (not 27/30 as XNU assumes) | measured on SM7150/SM8150 XNU ports | |

## Board peripherals

| Item | Value | Status | Measured on my unit |
|---|---|---|---|
| Display panel | Samsung **ANA38401 / AMSA05RB06**, 10.5" AMOLED, **2560x1600**, **dual-DSI command mode**, no DSC. Reset GPIO 59, TCON-ready GPIO 140 | proven (panel node, native DPU in t860-fedora) | |
| Bootloader framebuffer | **`0x9c400000`**, 2560x1600, stride 10240, a8r8g8b8 (32 MiB reserved). Linux `simpledrm` drives it with no DSI/DPU programming, so a dumb framebuffer is a viable first display path | proven | |
| Brightness | No hardware backlight node: AMOLED brightness goes through DCS on the DSI link. Needs the native display pipe; software dimming works without it | proven | |
| Touch | **STM FTS1BA90A** (Samsung SEC-TS protocol), I2C addr `0x49` on **QUP2 SE17** (`0xc80000`), IRQ TLMM GPIO 87 (level low), AVDD `L17A` 3.0 V, VDD `L14A` 1.8 V. SE17 is **GSI-DMA-only** per boot firmware: GPI DMA `0xc00000` must be used | proven | |
| S Pen | **Wacom W9021**, I2C `0x56` on i2c14, IRQ GPIO 5, PDCT GPIO 53, FWE GPIO 11 | from stock DT, no driver yet | |
| Wi-Fi | Qualcomm **WCN3990** (802.11ac 2x2) over **SNOC** @ `0x18800000`, `ath10k_snoc`. The WLAN firmware runs on the **modem Q6 (mpss)** @ `0x4080000`. MSA memory must sit in HLOS-owned DDR (`0xc0000000`), not the `sm8150.dtsi` default `0x8bc00000`, or the SoC locks up silently. The stock DT's QCA6390/`wil6210` node is an unfitted part | proven | |
| Bluetooth | WCN3990 BT over **UART QUP2 SE3** (`serial@c8c000`), `hci_qca`. Firmware `crbtfw21`/`crnv21` from the device; BD address from `/efs/bluetooth/bt_addr` | proven | |
| Audio out | ADSP + APR, **Secondary TDM** to **four Cirrus CS35L41** amps, I2C `0x40`-`0x43`, shared reset TLMM GPIO 148 | proven | |
| Microphones | **Cirrus CS48L33** on SPI over Quinary MI2S | proven | |
| Haptics | Dialog **DA7280** @ I2C `0x4a`, IRQ GPIO 42 | from stock DT | |
| Battery / charger | Silicon Mitus **SM5705** charger + fuel gauge + MUIC on I2C (fuel gauge `0x71` on i2c11). Charger registers reset on cable movement | proven (driver written from scratch) | |
| Buttons | Power = PMIC PON KPDPWR, Volume-Down = PON RESIN, **Volume-Up = `pm8150l_gpios 12`** (active low) | proven | |
| USB | DWC3 @ `0xa600000`, dual-role, VBUS from SM5705 boost. High speed works; SuperSpeed unsolved | proven | |
| Sensors | LSM6DSO accelerometer and others behind the **SLPI** DSP (needs PAS boot + FastRPC) | proven (accelerometer) | |
| Power off / reset | **PSCI `SYSTEM_OFF` and `SYSTEM_RESET` hang** on this firmware. Use PMIC `PS_HOLD` @ `0xc264000`; disarm SMPL first | proven | |
| Debug UART | **None usable.** No serial console; persistent RAM (ramoops) does not survive reboot because the bootloader retrains DDR | proven | |

## Boot chain facts

| Item | Value |
|---|---|
| Chain | AArch64 XBL, then 32-bit ARM **ABL**, then the Android boot image |
| Fastboot | **None in Samsung ABL.** Download Mode (Odin/Heimdall) only. The Aloha UEFI provides its own fastboot (hold Volume-Down at the UEFI screen) |
| Boot image contract | Android boot image **v1**, kernel wrapped in Qualcomm `UNCOMPRESSED_IMG`, Samsung **`SEANDROIDENFORCE`** marker and an **AVB footer/vbmeta trailer**. Images without the trailer silently fall back to stock |
| Boot partition | 64 MiB (`sda20` on the reference unit) |
| `misc` partition | Holds the bootloader control block. **Not Odin-flashable** (not in the flashable PIT) |
| Download Mode | Power off, hold Volume-Up + Volume-Down, plug in USB |
| Device Unlock Mode | Same key combo; long-press Volume-Up at the warning screen |
| Recovery | Power off, hold Power + Volume-Up (with USB connected on some firmware) |
| UEFI load address | Aloha SM8150 FD at `0x9FC00000`, size 3 MiB (same as the Xiaomi Pad 5 / Mu-Silicium HanaPkg) |

## Memory map at UEFI (from Aloha `PlatformMemoryMapLib.c`)

Regions that matter for a Darwin loader. XNU maps its whole managed range cacheable, so
every Qualcomm carve-out must stay outside it (nabu's lesson: "never map carve-outs cacheable").

| Range | Size | Owner |
|---|---|---|
| `0x80000000` | 42 MiB | Kernel load area |
| `0x85700000` | 6 MiB | **Hypervisor (QHEE)** |
| `0x86000000` | 2 MiB | SMEM |
| `0x86200000` / `0x87a00000` | 24 MiB / 72 MiB | QTEE / TZ apps |
| `0x8c1e4000` | ~250 MiB | PIL region (modem, ADSP, SLPI, CDSP, WLAN firmware) |
| `0x9b000000` | 20 MiB | SLPI ELF span (per mainline DT) |
| `0x9c400000` | 32 MiB | **Display (framebuffer)** |
| `0x9fc00000` | 3 MiB | UEFI FD |
| `0xc0000000` up | ~2 GiB | Free DDR (UEFI DXE heap) |
| `0x140000000` up | ~1 GiB | Free DDR (6 GB variant, minus 2 MiB pstore at `0x17fe00000`) |

## What this means for an Apple OS port

- **Same SoC as the Xiaomi Pad 5 (`nabu`)**, which has an iPadOS bring-up
  ([mytiantian001/iPadOS-nabu](https://github.com/mytiantian001/iPadOS-nabu)). SoC-level
  addresses (GIC, UFS, PS_HOLD, IMEM, USB) are identical, and so is the 1600x2560 panel resolution.
- **Same touch chip family (STM FTS1BA90A), four CS35L41 amps and a Wacom pen as the Galaxy Tab S7+**,
  which has the most complete iPadOS port of any Samsung tablet
  ([rui12366B/UniXNU-gts7xlwifi](https://github.com/rui12366B/UniXNU-gts7xlwifi)).
- **Wi-Fi is the odd one out.** WCN3990/ath10k over SNOC with modem-hosted firmware. Every
  XNU Wi-Fi port so far uses QCA6390/ath11k over PCIe. Expect Wi-Fi to be new work.
- **Battery (SM5705)** is Samsung-specific and needs a new driver on any OS.
