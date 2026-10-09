# nerves_system_ec100

[Nerves](https://nerves-project.org/) system for the **IOTRouter EC100**, based on
the Rockchip RK3506J (ARM Cortex-A7).

- Source-built U-Boot and Linux with pinned Rockchip DDR, SPL, and secure firmware
- A/B firmware updates with application validation and boot-count rollback
- Shared ext4 application storage at `/data` (`/root`)
- Ethernet, eMMC, and a **115200 8N1** serial console (no flow control)

## Build

This system requires Nerves 2 (currently `2.0.0-pre.3`). For an existing application,
update its Nerves dependency, remove `:shoehorn`, and replace
`&Nerves.Release.init/1` with `&Nerves.init_release/1` in its release steps.

Add this system to your Nerves application's dependencies and target configuration:

```elixir
{:nerves_system_ec100,
 path: "../nerves_system_ec100",
 runtime: false,
 targets: [:ec100]}
```

Adjust the path for your checkout. From the application directory:

```sh
mix deps.get
MIX_TARGET=ec100 mix nerves.artifact.build nerves_system_ec100
MIX_TARGET=ec100 mix firmware
```

Nerves 2 does not automatically build custom systems. The artifact build requires
a working Docker or Podman installation; rerun it after changing this system.
Prebuilt artifacts are downloaded as needed by `mix firmware`, not `mix deps.get`.
For the first build after upgrading from Nerves 1, use a fresh system checkout:
the current prerelease copies old `.nerves/` and Buildroot caches into its container
workspace, which can exhaust disk space or leave broken host-path symlinks.

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
`ec100-backups/`, installs the GPT, boot images, and slot A, verifies writes, and
resets the board. It does not write the eMMC boot0/boot1 hardware partitions.

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
preserves the bootloader, partition table, and shared data. Provision the GPT layout
with factory installation; OTA does not repartition the eMMC. Configure the
application's upload success callback to reboot, or reboot after a successful upload.

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
| Protective MBR and primary GPT | 0 | 17 KiB |
| DDR/SPL loader | 32 KiB | Below 8 MiB |
| U-Boot/TEE FIT | 8 MiB | Up to 4 MiB |
| Environment A / B | 12 / 12.125 MiB | 128 KiB each |
| Kernel FIT A / B | 16 / 48 MiB | 32 MiB each |
| Rootfs A (`mmcblk0p1`) | 80 MiB | 256 MiB |
| Rootfs B (`mmcblk0p2`) | 336 MiB | 256 MiB |
| Data (`mmcblk0p3`) | 592 MiB | Remaining space before backup GPT |
| Backup GPT | Final 33 sectors | 16.5 KiB |

The eMMC uses GPT with three partitions named `rootfs-a`, `rootfs-b`, and `data`.
Root filesystems are read-only SquashFS. Nerves initializes the shared ext4 data
partition on first use and mounts it at `/root`; `/data` is an alias. Raw FIT slots
are outside the GPT partitions. The kernel supports both gzip and XZ SquashFS.

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
writes remain untested. Reboot with an inserted SD card works with the included
[MMC regulator fix](https://github.com/armbian/linux-rockchip/issues/563).
Both CAN interfaces register, but physical CAN traffic has not been tested.

## User controls

- Run LED: GPIO1_A7, `/sys/class/leds/ec100:run/brightness`. Values `0` and `1`
  control the output; the physical on/off polarity is not yet recorded.
- User button: GPIO1_A5, active-low, exposed by `gpio-keys` as `KEY_PROG1`
  (code 148). Press/release events have been verified. No reset action is bound.

## USB

USB0 (`ff740000.usb`) uses the Type-C connector as a fixed CDC ECM Ethernet
peripheral for laptop setup. It is not an OTG host port. Power the EC100 separately;
the Type-C host VBUS switch (GPIO1_D0) remains claimed and off. MASKROM flashing
and recovery remain independent of Linux USB support.

For an application using `vintage_net_direct`, include this entry in its
`:vintage_net` configuration:

```elixir
{"usb0", %{type: VintageNetDirect}}
```

VintageNetDirect derives a /30 subnet from the hostname and interface, and serves
DHCP to the laptop. On the test board, the addresses are `172.31.92.201` (EC100)
and `172.31.92.202` (laptop). The application must provide SSH and an authorized key.

Current status (Linux laptop, system `0.1.28-dev`):
- Booting unplugged, then connecting passed USB SSH/ping and three reconnect cycles.
- Booting with Type-C connected stalled USB traffic; unplug/replug did not recover
  it. One USB0 software disconnect/connect restored operation without a reboot.
- Usable for development with Ethernet as a fallback; boot-connected reliability
  remains unresolved. macOS and Windows are untested.

Local PHY/DWC2 patches keep USB0 in device mode and allow reconnect resets despite
missing session-valid sensing. The PHY stays awake; gadget state/carrier may
remain stale while unplugged.

USB1 (`ff780000.usb`) is enabled as an internal host with USB serial (`option`),
CDC ACM, and CDC ECM drivers. No modem is fitted, so device operation is untested;
modem power/reset and networking are not configured. Before adding a USB-network
modem, verify interface identity so it cannot inherit the setup port's
`VintageNetDirect`/DHCP-server configuration.

## Watchdog

The GPIO watchdog is configured on GPIO0_B1 with toggle feeding, `always-running`,
and `nowayout`. Heart opens `/dev/watchdog0` (expected identity: `GPIO Watchdog`)
with a 60-second timeout. The 10-second hardware feeding margin is provisional,
not a measured circuit timeout.

Hardware watchdog recovery is verified on the EC100. **Remove the watchdog-disable
jumper for normal operation**; leaving it fitted disables hardware watchdog resets.
With `nowayout`, closing the watchdog device does not disarm it.

## Remaining qualification

Automatic A/B rollback, power-loss recovery, CAN traffic, and long-term stability
still require hardware qualification.

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
