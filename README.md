# nerves_system_ec100

Minimal A/B Nerves system for the **IOTRouter EC100** based on the **Rockchip RK3506J**.

This system replaces the vendor OS and partition layout with Nerves. It uses official
Rockchip binaries for early hardware initialization and secure firmware, then builds
Rockchip's U-Boot, Linux, and the Nerves application for the EC100.

## Status

This system is still in hardware bring-up. Earlier builds reached Linux and sometimes
Erlang, but suffered execution faults and lockups. CPU voltage/frequency control has
been restored from the original board configuration; it did not resolve the instability.

The current configuration switches to official Rockchip DDR/SPL/secure-firmware
binaries. Version 0.1.10-dev reaches interactive Elixir with all three CPUs and
persistent ext4 mounted. Dynamic execution probes passed 1,300 launches on one boot;
the user also reports success after reboot. Long-term stability, A/B rollback, and
hardware watchdog reset remain unqualified.

See [the component-set notes](docs/official-rk3506-component-set.md),
[hardware map](docs/ec100-hardware-map.md), and
[first-boot checklist](docs/first-boot-checklist.md).

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

`mix firmware` builds on your computer. It does not flash the board. There are
three main stages; Nerves reuses cached system builds when possible.

### 1. Prepare the Linux system

Nerves uses **Buildroot** to prepare the toolchain and build the base system.
`nerves_defconfig` selects the components and their settings.

| Component | Where it comes from |
| --- | --- |
| ARM cross-compilation toolchain | Downloaded at a pinned version |
| DDR initializer (makes RAM usable), SPL (early loader), secure firmware, USB loader | Official prebuilt binaries from pinned Rockchip `rkbin` |
| U-Boot | Compiled from pinned Rockchip BSP source with our EC100 configuration and A/B boot policy |
| Linux kernel | Compiled from pinned Rockchip kernel source |
| Device tree (board hardware description) | Compiled from `dts/rk3506-ec100.dts` |
| Base Linux userspace and Erlang/OTP | Built as part of the Nerves system |

We do **not** compile the selected DDR initializer, SPL, or secure firmware.
`patches/buildroot/` selects the rkbin version and adapts its integration.
`bootstrap/patches/uboot/` adapts the legacy U-Boot configuration/compiler handling,
and accepts Buildroot's secure-firmware input. Linux retains the vendor device
tree's fixed secure-memory reservation.
See [SOURCES.md](SOURCES.md) for source pins.

### 2. Package the boot images

`post-createfs.sh` calls `bootstrap/post-image.sh`, then packages the kernel and
compiled device tree. A **FIT** is a container for boot images and their metadata.

| Output | Contents and purpose |
| --- | --- |
| `idbloader.img` | Official DDR initializer + SPL; starts the eMMC boot chain |
| `u-boot.itb` | Compiled U-Boot + official secure firmware + U-Boot's device tree |
| `ec100-maskrom-loader.bin` | USB flashing/recovery loader; run in RAM, not installed as the normal boot image |
| `ec100.itb` | Linux kernel + EC100 device tree; installed in a raw FIT slot |

Packaging verifies the selected rkbin inputs and changes the DDR initializer's
UART metadata to **115200 baud**, without changing its memory-training settings.
The low-level boot artifacts have a generated `bootloader.sha256` checksum file.

### 3. Add the application and create firmware

Nerves compiles your Elixir application and assembles its release with the system
files into **`rootfs.squashfs`**, the read-only root filesystem. It then packages
that filesystem, the kernel FIT, and the instructions in `fwup.conf` into a **`.fw`
firmware archive.

The `.fw` supports initial filesystem installation and A/B updates. The low-level
boot artifacts are separate: the factory flashing task installs them, while normal
OTA updates leave them untouched. A/B uses the same firmware images; the update
instructions choose which slot receives them.

## First installation

For MASKROM USB installation, run [`mix ec100.flash`](docs/factory-flashing.md) from
your Nerves application. It builds firmware as needed, detects the board, asks before
replacing its layout, backs up eMMC by default, installs the boot chain and initial
firmware, and verifies the writes. Factory installation replaces the existing layout
and data; normal OTA updates write only the inactive firmware slot and preserve data.
See [the bootloader details](bootstrap/README.md) for exact boot-image offsets.

## What runs when the board powers on

```text
Rockchip BootROM (already inside the chip)
  → DDR initializer: makes RAM usable
  → SPL: loads the U-Boot/secure-firmware FIT
  → Secure firmware: provides low-level services and starts U-Boot
  → U-Boot: selects A or B and loads that slot's kernel FIT
  → Linux: uses the device tree and mounts the matching root filesystem
  → erlinit: starts Erlang/OTP and the Nerves application
```

The shared ext4 data partition is separate from both read-only root filesystems.
Nerves runtime handles its first-use initialization; normal updates preserve it.

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
