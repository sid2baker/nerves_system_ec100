# nerves_system_ec100

[Nerves](https://nerves-project.org/) system for the **IOTRouter EC100**, based on
the Rockchip RK3506J (ARM Cortex-A7).

- Source-built U-Boot and Linux with pinned Rockchip DDR, SPL, and secure firmware
- A/B firmware updates with application validation and boot-count rollback
- Shared ext4 application storage at `/data` (`/root`)
- Ethernet, eMMC, and a **115200 8N1** serial console (no flow control)

## Build

Add this system to your Nerves application's dependencies and target configuration:

```elixir
{:nerves_system_ec100,
 path: "../nerves_system_ec100",
 runtime: false,
 targets: [:ec100],
 nerves: [compile: true]}
```

Adjust the path for your checkout. From the application directory:

```sh
export MIX_TARGET=ec100
mix deps.get
mix firmware
```

The build produces application firmware (`.fw`) and separate factory boot images.
It does not flash the board. Source pins are listed in [SOURCES.md](SOURCES.md);
boot-image details are in [bootstrap/README.md](bootstrap/README.md).

## Factory installation

**Factory flashing replaces the boot chain, partition layout, and application data.**
Use a stable power supply and keep a recovery backup. Installation is not
power-loss atomic.

Requirements: `rkdeveloptool`, `fwup`, Elixir/OTP, and enough space for a full eMMC
backup (about 3.8 GB) plus staging files. Connect exactly one EC100 in MASKROM mode.
From the application directory:

```sh
MIX_TARGET=ec100 mix ec100.flash
```

The task builds firmware, asks for confirmation, backs up the eMMC user area to
`ec100-backups/`, installs the boot images and slot A, verifies writes, and resets
the board. It does not write the eMMC boot0/boot1 hardware partitions.

USB commands use `sudo -n` by default; authenticate beforehand or use `--no-sudo`
with suitable USB permissions. Other options are `--no-reset`, `--yes`, and
`--no-backup`. Skipping the backup removes the ability to restore the previous
firmware and data from that run. Readback verification always runs.

## OTA updates

The application must provide SSH firmware upload support and an authorized key.
From the application directory:

```sh
MIX_TARGET=ec100 mix firmware
MIX_TARGET=ec100 mix firmware.gen.script
./upload.sh <board-address>
```

OTA writes the inactive kernel/rootfs slot and selects it for the next boot. It
preserves the bootloader and shared data. Configure the application's upload
success callback to reboot, or reboot after a successful upload.

Check the running trial in IEx:

```elixir
Nerves.Runtime.KV.get_all_active()
Nerves.Runtime.KV.get_all() |> Map.take(["nerves_fw_active", "upgrade_available", "bootcount"])
```

The standard Nerves application's StartupGuard validates automatically after
startup. For an application configured for manual validation, check its health
and then confirm it:

```elixir
Nerves.Runtime.validate_firmware()
```

Rebooting does not alternate slots. With `bootlimit=3`, an unvalidated trial gets
three boot attempts; the fourth rolls back. Validation keeps the selected slot
and clears the trial flag and counter. Keep data migrations rollback-compatible.

## Storage

| Region | Start | Size |
| --- | ---: | ---: |
| DDR/SPL loader | 32 KiB | Below 8 MiB |
| U-Boot/TEE FIT | 8 MiB | Up to 4 MiB |
| Environment A / B | 12 / 12.125 MiB | 128 KiB each |
| Kernel FIT A / B | 16 / 48 MiB | 32 MiB each |
| Rootfs A (`mmcblk0p1`) | 80 MiB | 256 MiB |
| Rootfs B (`mmcblk0p2`) | 336 MiB | 256 MiB |
| Data (`mmcblk0p3`) | 592 MiB | Remaining eMMC |

Root filesystems are read-only SquashFS. Nerves initializes the shared ext4 data
partition on first use and mounts it at `/root`; `/data` is an alias. Raw FIT slots
are outside the MBR partitions. The kernel supports both gzip and XZ SquashFS.

## SD, CAN, and serial ports

| Interface | Linux device | Board pins |
| --- | --- | --- |
| SPI SD slot | `mmcblk1` when a card is present | SPI1: GPIO1_B3 CS, B2 MOSI, C2 clock, C3 MISO |
| UART3 | `/dev/ttyS3` | GPIO0_A2 TX, A3 RX |
| UART4 | `/dev/ttyS4` | GPIO0_B0 TX, A0 RX |
| CAN0 | `can0` (verify controller mapping) | GPIO0_C3 TX, C4 RX |
| CAN1 | `can1` (verify controller mapping) | GPIO0_C1 TX, C2 RX |

The SD slot uses 3.3 V, a maximum 20 MHz SPI clock, and card-detect polling.
Explicit MMC aliases keep eMMC at `mmcblk0` and the SPI slot at `mmcblk1`.
Verify `/proc/partitions` and `/sys/class/block/mmcblk1/device/type` before mounting
an SD partition read-only. Never format a guessed device. Test booting both with
and without an inserted card before relying on this setup.

CAN controllers are enabled but not automatically brought up. Set the bitrate to
match the peer, verify connector mapping, and use correct bus termination. An
internal loopback test does not verify the transceivers or connector wiring.

UART3/4 use TX/RX without DE GPIO, RTS polarity, or boot-time RS485 mode settings.
A two-port Modbus RTU write/read test passed with both client/server orientations
at 9600 baud, 8N1, without software direction control. This supports using the
hardware's automatic direction handling at these settings; other speeds and bus
loads remain unqualified. Do not connect a TTL UART adapter directly to RS485 A/B
terminals. UART0 remains the boot console.

The SPI SD slot has passed card detection, read-only FAT mounting, directory
listing, and unmounting, with eMMC numbering preserved. SD file contents and
writes remain untested. Both CAN interfaces register, but physical CAN traffic
has not been tested.

## User controls

- Run LED: GPIO1_A7, `/sys/class/leds/ec100:run/brightness`. Values `0` and `1`
  control the output; the physical on/off polarity is not yet recorded.
- User button: GPIO1_A5, active-low, exposed by `gpio-keys` as `KEY_PROG1`
  (code 148). Press/release events have been verified. No reset action is bound.


## Hardware limits

- GPIO0_B1 feeds the external watchdog through the Linux GPIO watchdog driver.
  Heart uses `/dev/watchdog0`; expected identity is `GPIO Watchdog`. The configured
  10-second hardware margin is provisional, not a measured reset timeout.
- External watchdog reset behavior and J1 jumper semantics are unverified. Do not
  rely on watchdog recovery until the physical circuit has been tested.
- USB OTG0 is disabled. Automatic A/B rollback, power-loss recovery, and long-term
  stability still require hardware qualification.

## Configuration

- `dts/rk3506-ec100.dts` — board hardware
- `linux/ec100.fragment` — kernel features
- `bootstrap/uboot.env` — boot selection and rollback
- `fwup.conf` — storage layout and firmware updates
- `fwup-ops.conf` — validation, revert, and factory reset

## Tests

Run the factory-flashing tests without building the system:

```sh
elixir -r lib/mix/tasks/ec100.flash.ex -r test/test_helper.exs -r test/ec100_flash_test.exs -e 'Mix.start()'
```
