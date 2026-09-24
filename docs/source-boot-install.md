# Source boot-chain factory install: observed result

System version: **0.1.3-dev**. Application: `../../ec100_app`, using this system,
XZ rootfs, application version 0.1.0. Builds succeeded, five factory-task tests passed.

## What was installed

- RK3506 DDR v1.05 + source SPL NEWIDB at LBA64
- Source U-Boot / OP-TEE FIT at LBA16384 (8 MiB)
- Redundant 128 KiB env at LBA24576 / 24832
- Application FIT A and rootfs A; starts of B/data invalidated per `complete`
- MBR p1/p2/p3 at existing offsets; old GPT primary area/backup metadata cleared

The full low boot area was replaced to remove stale loader copies. No vendor
bootloader binary was copied into the persistent boot chain. U-Boot is still
Rockchip's 2017.09-derived source BSP, not mainline. OP-TEE is source-built and
packaged as raw executable bytes (this SPL does not parse an OPTE binary header).

## Backup and verification

Full pre-write eMMC user-area backup (3,825,205,248 bytes):

`../../ec100_app/ec100-backups/source-bootchain-0.1.3-install/emmc-before.img`

SHA256: `d040bb36b36c95382a246be4dd09bde6db82c9644321bdbca039c39cad9a5c49`

That directory contains `manifest.txt`, all staged regions and matching readback
files. Every region's byte length and SHA256 matched. Separate eMMC boot0/boot1
hardware partitions were not modified. This is not a secure erase of old data.

Command used from the application project:

```sh
MIX_TARGET=ec100 mise exec -- mix ec100.flash \
  --firmware _build/ec100_dev/nerves/images/ec100_app.fw \
  --sectors 7471104 --output ec100-backups/source-bootchain-0.1.3-install \
  --flash --sudo --yes --migrate-gpt \
  --loader ../dev/nerves_system_ec100/.nerves/artifacts/nerves_system_ec100-portable-0.1.3-dev/images/ec100-maskrom-loader.bin \
  --bootloader-dir ../dev/nerves_system_ec100/.nerves/artifacts/nerves_system_ec100-portable-0.1.3-dev/images
```

Flash log: `/tmp/ec100-source-flash.log`. After successful verification,
`sudo -n rkdeveloptool rd` reported `Reset Device OK.`

## Boot result: NOT yet successful

After reset, `rkdeveloptool ld` again reports `2207:350f`, LocationID 105,
**MASKROM**. No readable SPL/U-Boot/Linux banner was captured. Initial serial
capture at 115200 contains 66 garbled bytes (`/tmp/ec100-source-boot-serial.log`),
which is insufficient to distinguish different DDR baud, boot failure, or forced
MASKROM entry. It is not evidence of a successful Linux boot.

A separate user-owned `screen` session was also reading ttyUSB0 and changed its
terminal settings. The agent's competing reader has been stopped; only screen
remains. A screen hardcopy was blank. Do not run two serial readers simultaneously.

Next physical check: release any MASKROM strap/button and cold power-cycle with
one serial reader. If it still returns to MASKROM, investigate the NEWIDB/DDR/SPL
handoff with early-stage baud capture before changing Linux or A/B policy. Preserve
the backup. Recovery transport is still available. No watchdog, Ethernet, IEx or
rollback success is claimed.

## Source-level build fixes

- Legacy header-only redundant MMC env and BOOTCOUNT_ENV/BOOTCOUNT_LIMIT enabled;
  confirmed in generated `include/autoconf.mk`, not merely requested in a fragment.
- `altbootcmd=run bootcmd` ensures the rollback script runs after bootlimit.
- FIT buffer 0x08000000 avoids kernel load/decompression region overlap.
- OP-TEE reserves 0x18000000+32 MiB and shared memory 0x10000000+512 KiB in both DTs.
- Legacy compiler warnings left visible but no longer fatal; Buildroot TEE path
  respected; board OF_LIST corrected; rkbin packaging handled in source post-image.
- Read-only flash-info probe retries USB re-enumeration after downloading transport.

These changes are recorded in repository sources, not generated-only fixes.
