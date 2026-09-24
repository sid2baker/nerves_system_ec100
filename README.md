# nerves_system_ec100

Minimal A/B Nerves system for the **IOTRouter EC100** based on the **Rockchip RK3506J**.

This repository deliberately replaces the vendor OS and vendor partition scheme. It keeps
only a small RK3506 early-boot boundary: DDR must be initialized before U-Boot can run.
Everything from U-Boot onward is designed around Nerves.

## Status

This is a bring-up system scaffold. The A/B layout, Nerves packaging, immutable rootfs,
FIT generation, redundant U-Boot environment and rollback metadata are implemented.
A complete source-built factory image has been flashed and readback-verified on an
EC100. The first reset has **not yet reached Linux/IEx**; the device reports MASKROM.
See [the installation record](docs/source-boot-install.md).

The minimal DTS is now reconciled against the captured live EC100 DT and runtime:
UART0 at 115200 baud, 512 MiB RAM, 4-bit HS200 eMMC with GPIO-controlled I/O voltage,
two independent RMII/MDIO PHYs, and USB supplies/roles. CPU DVFS is deferred until the
live voltage/OPP policy is reconciled; no display/GPU stack is enabled.

See [the hardware map](docs/ec100-hardware-map.md) for evidence and deferred devices,
and [the first-boot checklist](docs/first-boot-checklist.md) before flashing.
**Successful source-boot-chain startup and watchdog reset behavior remain bring-up blockers.**

## Storage layout

All offsets are based on 512-byte eMMC sectors.

```text
0 MiB     +-----------------------------------+
          | RK3506 bootloader / DDR init      |
          | U-Boot / reserved                 |
12 MiB    | U-Boot env A (128 KiB)            |
12.125MiB | U-Boot env B (128 KiB)            |
16 MiB    +-----------------------------------+
          | FIT A (raw, 32 MiB)               |
48 MiB    +-----------------------------------+
          | FIT B (raw, 32 MiB)               |
80 MiB    +-----------------------------------+
 p1       | RootFS A, SquashFS (256 MiB)      |
336 MiB   +-----------------------------------+
 p2       | RootFS B, SquashFS (256 MiB)      |
592 MiB   +-----------------------------------+
 p3       | Persistent ext4 (grow to end)     |
          | mounted at /root; /data -> /root  |
 end      +-----------------------------------+
```

The raw FIT slots are intentionally not MBR partitions. Linux only sees:

```text
/dev/mmcblk0p1  rootfs A
/dev/mmcblk0p2  rootfs B
/dev/mmcblk0p3  persistent application data
```

## Update model

When A is running, `fwup` writes B. When B is running, it writes A. The running slot is
never modified.

A new slot is marked as a trial with:

```text
upgrade_available=1
bootcount=0
```

The U-Boot environment in `bootstrap/uboot.env` rolls back after three failed boots. A
healthy application validates itself with `Nerves.Runtime.validate_firmware/0`.

## Build

Use this repository as a path dependency from a Nerves application while bringing it up:

```elixir
# mix.exs in your application
{:nerves_system_ec100, path: "../nerves_system_ec100", runtime: false}
```

Then:

```sh
export MIX_TARGET=ec100
mix deps.get
mix firmware
```

The system build produces:

- `zImage`
- `rk3506-ec100.dtb`
- `ec100.itb` (FIT containing kernel + DTB)
- read-only `rootfs.squashfs`
- Nerves `.fw` with A/B upgrade tasks
- `/usr/share/fwup/ops.fw` for validate/revert/factory-reset

The selected RK3506-enabled Linux tree is pinned in `nerves_defconfig`. The Nerves
userspace and disk layout are independent of that tree and can be moved to upstream Linux
when the EC100 device tree is ready there.

## First installation

The system builds factory DDR/SPL/OP-TEE/U-Boot artifacts. See `bootstrap/README.md`.
The U-Boot source is currently the pinned Rockchip BSP, not modern mainline.

After that, initialize the Nerves-managed area with the firmware's `complete` task.
For MASKROM USB installation, run [`mix ec100.flash`](docs/factory-flashing.md) from
`ec100_app`. It builds the firmware, detects the board, asks before replacing its
layout, backs up eMMC, installs the complete boot chain and verifies every write.
No paths or partition options are needed. Normal OTA updates use the standard
`upgrade` task selection.

## Watchdog

Captured runtime shows GPIO0_B1 (`WDG_PI`) toggling, but does not establish the
external supervisor's timeout or protocol. The live DT has no watchdog device node;
its `/dev/watchdog0` is virtual, not proof of hardware reset coverage. Internal WDTs
remain disabled rather than assuming they service the board supervisor.

Hardware watchdog/Heart integration is **not yet ready**. Measure the external
watchdog first, then represent it with a standard Linux watchdog driver and verify
`/dev/watchdog0` identity and missed-heartbeat reset. Do not use softdog as a substitute.

## Files worth editing first

- `dts/rk3506-ec100.dts` — EC100 PCB wiring
- `linux/ec100.fragment` — kernel features
- `bootstrap/uboot.env` — A/B boot/rollback policy
- `fwup.conf` — flash layout and upgrade transactions
- `fwup-ops.conf` — validation/revert/factory reset
