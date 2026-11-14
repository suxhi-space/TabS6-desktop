# The owner's Tab S6: recon results (2026-11-14)

From the scrubbed on-device report (`tabs6-onetap.sh`). No identifiers recorded here.

## Matches the reference Linux port exactly

| Item | This unit | Reference unit (gts6l-mainline-linux) |
|---|---|---|
| Model / codename | SM-T860 / `gts6lwifi` | same |
| Bootloader / firmware | **T860XXS5DWH1** | **T860XXS5DWH1** (same build) |
| `msm-id` / `board-id` | `0x169 0x20000` / `0x10008 0x2` | same |
| boot / cache / userdata / misc | sda20 / sda27 / sda30 / sda10 | same |
| userdata size | 110 GiB (128 GB model) | 128 GB model |
| RAM | 6 GB (MemTotal 5.3 GiB) | 6 GB |
| Touch | `fts_touch` @ 0x49 | STM FTS1BA90A @ 0x49 |
| Amps | 4x `cs35l41` @ 0x40-0x43 | same |
| Fuel gauge / charger / MUIC | `sm5705-fuelgauge` @ 0x71, `sm5705` | same |
| S Pen | `w90xx` @ 0x56 | Wacom W9021 @ 0x56 |
| Mic codec | `cs48l33` on SPI | same |
| Panel | `SDC_420000` (Samsung Display) | ANA38401 / AMSA05RB06 |
| Firmware files the Linux installer imports | all present: `a640_gmu`, `a640_zap.*`, `a630_sqe.fw`, adsp, cdsp, slpi, `crbtfw21`/`crnv21`, `wlanmdsp.mbn`, CS35L41 protection firmware | — |

Not in the Linux port (no driver): `stm32_pogo` (**Book Cover Keyboard** pogo connector),
`et7xx` (in-display fingerprint), `nq-nci` (NFC), `a96t3x6` grip sensors.

## Answers to the open questions

| Question | Result | Consequence |
|---|---|---|
| Pointer authentication (PAC)? | **No** (`paca`/`pacg` absent, cores 0x804/0x805) | macOS and iPadOS 26+ ruled out on this unit, as expected |
| Exception level | Not in the kernel log (rotated after ~44 h uptime) | Not needed for any current plan |
| `misc` BCB | **Empty** | The "boot-recovery" trap does not apply |
| Where is root (Magisk)? | `boot` has a **427 KB ramdisk**; stock SM-T860 boot has none | Magisk is almost certainly **in boot**, so installing TWRP to recovery does **not** remove root. The "copy app data before TWRP" ordering constraint goes away |
| Recovery contents | 17.8 MB ramdisk | TWRP or stock recovery; owner to confirm |
| vbmeta | `AVB0`, flags `3` | Verification already disabled |
| Data encryption | FBE (`filenames_mode aes-256-cts`, `fileencryption=ice` in fstab), **no metadata encryption**, f2fs | Design B is possible in principle; probe pending |
| Design B probe | `probe.bin` sha256 starts `d2eca428` | Check in TWRP (Cancel decrypt): must print the same hash |
| Free space on /data | **14 GB free of 110 GB (96 GB used)** | Design B needs ~30 GB free; Design A staging needs room for whatever is moved |
| microSD | **32 GB card present** (`mmcblk0p1`) | Usable as Design A staging from Android/TWRP. Not usable from Linux yet (no SD node in the Linux device tree) |
| Battery | 257 charge cycles | Fine |

## Needs a manual check

The report shows `verifiedbootstate=green`, `flash.locked=1`, `vbmeta.device_state=locked`,
`warranty_bit=0`. A Samsung running a GSI with Magisk **cannot** have a locked bootloader, so
these values are almost certainly spoofed (Play Integrity fixes, or the GSI hiding its state).
Confirm in **Download Mode**: the screen should say the OEM lock is **OFF** / unlocked. Note any
`KG STATE` / `RMM STATE` line too.
