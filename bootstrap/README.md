# EC100 bootloader build and factory boundary

System 0.1.4-dev builds the complete boot chain:

1. Rockchip DDR 750 MHz v1.05 (the retained proprietary DRAM-training component)
2. Source SPL from pinned Rockchip U-Boot
3. Source OP-TEE implementing ARM32 PSCI for the three Cortex-A7 cores
4. Source U-Boot with redundant MMC env and bootcount support
5. Raw FIT A/B, then matching SquashFS rootfs

`nerves_defconfig` pins U-Boot `1c535d65b8509f388d09e49fb6961f49fda35a1d`
and OP-TEE `5858c37a66cbffccf7b047d0f9a52dee0ebbf06c`. The Buildroot release
pins rkbin `f43a462e7a1429a9d407ae52b4745033034a6cf9`.

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
contains rkbin USB plug code and is never persisted. Source SPL replaces rkbin's
SPL in the NEWIDB. These artifacts are factory-only: no normal `.fw` update task
writes them. The separate eMMC boot0/boot1 hardware partitions are not touched.

## Memory contract

- U-Boot proper loads at 0x00200000; OP-TEE returns there.
- OP-TEE loads at 0x18000000 with 32 MiB reserved; shared memory is
  0x10000000+0x80000. Both U-Boot and Linux DTS reserve these ranges.
- This BSP's SPL jumps directly to OP-TEE's FIT entry; the factory FIT uses
  `tee-raw.bin`, **not** `tee.bin` with its OPTE header.
- Kernel FIT read buffer is 0x08000000, distinct from kernel load 0x02080000.
- DDR, SPL, U-Boot, OP-TEE and Linux all use UART0 at **115200 8N1**.
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

Readback verification passed on the EC100. A successful boot to Linux/IEx has
**not** yet been demonstrated; see [source-boot-install.md](../docs/source-boot-install.md).
