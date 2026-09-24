# EC100 bootloader build and factory boundary

System 0.1.10-dev integrates the official Rockchip low-level component set:

1. Official DDR 750 MHz v1.08
2. Official SPL v1.12
3. Official secure firmware v2.50 (standard, not TA-enabled variant)
4. Rockchip-BSP U-Boot with redundant MMC env and Nerves bootcount support
5. Raw FIT A/B, then matching SquashFS rootfs

`nerves_defconfig` pins U-Boot `1c535d65b8509f388d09e49fb6961f49fda35a1d`.
`patches/buildroot` pins rkbin `3e288fe814e059dd06833495f845cab04ac20a5c`;
`rkbin.sha256` independently checks the four selected binary inputs. There is
no separate DDR override or source-built OP-TEE dependency.

The U-Boot tree is the **Rockchip 2017.09-derived BSP**, not modern mainline.
Mainline has RK3506 SoC support but the inspected tree has no complete RK3506
board defconfig/DTS. This source-built BSP is a transitional bring-up component;
replacing it with mainline remains desirable, not a completed milestone.

## Disk contract

| Component | Byte offset | Maximum span |
| --- | ---: | ---: |
| MBR | 0 | 512 bytes |
| NEWIDB: DDR + SPL | 0x00008000 (LBA64) | up to 8 MiB boundary |
| U-Boot/OP-TEE FIT | 0x00800000 (LBA16384) | 4 MiB |
| Redundant env A | 0x00c00000 | 128 KiB |
| Redundant env B | 0x00c20000 | 128 KiB |
| Kernel/DTB FIT A | 0x01000000 | 32 MiB |
| Kernel/DTB FIT B | 0x03000000 | 32 MiB |

`bootstrap/post-image.sh` creates `idbloader.img`, `u-boot.itb`, a temporary
`ec100-maskrom-loader.bin`, and `bootloader.sha256`. The temporary transport
uses official USB plug v1.04. USB plug code is never persisted; the NEWIDB
contains official DDR and SPL. The official INI's SPL selection is not overridden. These artifacts are factory-only: no normal `.fw` update task
writes them. The separate eMMC boot0/boot1 hardware partitions are not touched.

## Memory contract

- U-Boot proper loads at 0x00200000; OP-TEE returns there.
- Official TEE loads at 0x1000, as specified by RK3506TOS.ini; its binary is
  packaged intact. The old 0x18000000/0x10000000 source-TEE reservations are removed.
- Linux inherits the vendor SoC DTS's `trust@0` reservation: base 0, size
  0x62000 (392 KiB). The captured factory device tree has the same reservation.
  This is separate from U-Boot's optional dynamic TEE-memory tags. Vendor
  U-Boot allows an empty dynamic reservation; our 0.1.9-dev check incorrectly
  rejected it and has been removed. See the hardware findings in
  [the component-set notes](../docs/official-rk3506-component-set.md).
- Kernel FIT read buffer is 0x08000000, distinct from kernel load 0x02080000.
- UART target is **115200 8N1**. DDR is explicitly patched and U-Boot/Linux
  configured accordingly; verify the official SPL/TEE handoff on hardware.
  `ddrbin-param.txt` changes only DDR UART speed, not memory training or wiring.
  Packaging uses the pinned vendor DDR parameter tool, a fixed version label,
  and checks the decoded result before creating IDB and USB transport images.

## Legacy BSP fixes

`bootstrap/patches/uboot` keeps the necessary adaptation isolated:

- Header-only redundant-env and env-backed bootcount options (the modern Kconfig
  names alone are silently discarded by this BSP).
- Current-GCC warnings remain visible rather than fatal. This is not a claim that
  every legacy BSP warning has been fixed.
- FIT generator accepts Buildroot's TEE input path.
- Invalid/missing environment must not fall back to vendor Android boot policy.

`fwup.conf` creates the actual factory environment. U-Boot references use `$name`,
not escaped `${name}`: fwup would expand the latter when applying the archive,
leaving empty MMC/boot arguments. The staging test checks both environment copies
against `bootstrap/uboot.env`. `boot_slot` refuses to boot after a failed MMC read.

The environment includes `altbootcmd=run bootcmd`:
U-Boot selects altbootcmd after exceeding bootlimit. `bootcmd` then rolls back the
pending slot. Validate via `Nerves.Runtime.validate_firmware/0` only after real
application health checks. Rollback is implemented but not hardware-validated yet.

## Factory installation

Run `mix ec100.flash` from the application. It uses the built
`images/ec100-maskrom-loader.bin` as temporary RAM transport, so its DDR output
also uses 115200. Persistent boot components come from the same system build.
The original `bootstrap/MiniLoaderAll.bin` is retained only as a recovery reference;
it still uses 1500000 and is not selected by the task. See [factory-flashing.md](../docs/factory-flashing.md).
Full installation backs up
all eMMC user-area bytes, explicitly removes old GPT metadata, replaces the low
boot area (including stale loader copies/vendor env), writes current firmware,
and verifies every range before optional reset. It is not power-loss atomic.

Earlier source-chain factory readback verification passed, but userspace was
unstable. On hardware, 0.1.9-dev reached official TEE and U-Boot but stopped at
our incorrect dynamic-reservation check. Version 0.1.10-dev removes that check
and has reached IEx on hardware, with 1,300 dynamic launches passing on one boot
and a subsequent user-reported successful reboot test. Long-term stability and
A/B rollback remain unqualified.
