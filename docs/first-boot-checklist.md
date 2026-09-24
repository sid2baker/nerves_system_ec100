# EC100 first-boot checklist

Goal: BootROM → DDR/init → compatible U-Boot → FIT A → Linux → erlinit → BEAM →
IEx on UART0. Wi-Fi, LTE, RS485, M0 and FlexBUS are not prerequisites.

This is a qualification test plan. Linux/rootfs/shell bring-up is now verified;
see [current hardware results and remaining blockers](userspace-bringup.md).
Reliable Erlang startup and A/B rollback are not yet verified. The system build
is not an application release; build application firmware before expecting IEx.

## 0. Preserve recovery and resolve blockers

- [ ] Read [the hardware map](ec100-hardware-map.md). Keep `iotrouter/` unchanged.
- [ ] Back up the entire board eMMC, its boot hardware partitions and current
  bootloader/environment; verify hashes off-board. Preserve a known-good restore path.
- [ ] Verify MASKROM entry and recovery tooling on this board before repartitioning.
- [ ] Connect the verified debug UART with electrically appropriate serial hardware;
  Linux UART0 is **115200 8N1**, no hardware flow control. Do not infer header pinout
  or voltage from the DTS. Capture the entire power-on log (early loader baud may differ).
- [ ] Resolve the external supervisor: GPIO0_B1 is observed toggling approximately
  every 10 seconds, but this is NOT its timeout specification. Identify/measure
  timeout, feed waveform, reset coverage and bootloader-to-Linux handoff. No standard
  hardware watchdog is enabled yet. A long first boot may reset unexpectedly; do not
  call this image unattended-safe or deploy it to a remote device.
- [ ] Verify a compatible RK3506 bootloader. **Do not provision Nerves on the stock
  loader assuming its environment matches.** Captures indicate stock nonredundant
  32 KiB env at 0x003f8000, not the Nerves redundant 128 KiB envs at 0x00c00000 and
  0x00c20000. The source-built Rockchip BSP U-Boot now reaches Linux; rollback qualification
  is still pending.
- [ ] Verify DDR size, PSCI/secure-firmware handoff and reserved RAM ownership.
  Preserve the captured trust, ramoops and FDT reservations until this is understood.
- [ ] In the compatible U-Boot, verify physical eMMC selection independently of Linux:
  the current scripts use `mmc dev 0`. Linux alias mmc0 does not set U-Boot numbering.
- [ ] Verify FIT `bootm` support, load/decompression/FDT relocation ranges, redundant
  env CRC/selection/write compatibility, bootcount persistence and `altbootcmd` behavior
  against `bootstrap/README.md` and `bootstrap/uboot.env`. Confirm rollback actually runs
  after `bootcount > bootlimit`; do not assume config symbols alone prove this.

## 1. Host build and artifact checks

```sh
# mise.toml selects OTP 29; the inherited shell may use OTP 28.
mise exec -- mix compile
```

- [ ] Confirm generated Buildroot remains `BR2_arm=y`, `BR2_cortex_a7=y`,
  `BR2_TOOLCHAIN_EXTERNAL=y`, compiler prefix `armv7-nerves-linux-gnueabihf`.
- [ ] Inspect the built DTB, not only source. Check console 115200, eMMC supplies,
  both PHY addresses/reset GPIOs, USB roles, disabled watchdogs, no display reservations.
- [ ] Confirm CPU_FREQ, FIQ_DEBUGGER, DRM and SOFT_WATCHDOG disabled; GPIO/fixed
  regulators, Motorcomm PHY and INNO USB2 PHY built in.
- [ ] Inspect `dumpimage -l images/ec100.itb`: kernel and matching board DTB, both ARM.
  Verify extracted FIT DTB equals the standalone DTB. FIT must fit 32 MiB, rootfs 256 MiB.
- [ ] Build the minimal application (`MIX_TARGET=ec100 mix firmware` in its project),
  confirm it provides serial IEx and does not auto-validate merely on application start.
  Do not add vendor daemons or automatic unknown-GPIO feeding.

## 2. Factory layout (destructive, bench only)

See [the native Mix factory installer](factory-flashing.md) for offline preparation
and verified MASKROM writes. Use system 0.1.2-dev or later: its corrected zero-based
fwup MBR entries produce the p1/p2/p3 naming expected below.

Only after backup, recovery and bootloader checks:

- [ ] Confirm target disk identity/capacity and that all target filesystems are unmounted.
  Vendor eMMC was mmcblk1; Nerves should expose mmcblk0 because SPI MMC is disabled.
- [ ] Use the application's `complete` task only for initial provisioning. It writes
  the MBR, initializes envs/A and clears the starts of B/data. It is NOT an OTA task.
  The low-level loader must already be installed and compatible.
- [ ] Compare installed sectors with the authoritative `fwup.conf`:

| Region | Start sector (512 bytes) | Sector count |
| --- | ---: | ---: |
| Env A | 24576 | 256 |
| Env B | 24832 | 256 |
| FIT A | 32768 | 65536 |
| FIT B | 98304 | 65536 |
| Rootfs A / p1 | 163840 | 524288 |
| Rootfs B / p2 | 688128 | 524288 |
| Data / p3 | 1212416 | initially 1048576, expands to end |

- [ ] Confirm no vendor parameter/recovery/OEM/AMP partitions are required.
- [ ] Confirm factory state `nerves_fw_active=a`, `upgrade_available=0`, `bootcount=0`,
  `bootlimit=3`. Factory A starts validated; establish a good A before trial updates.
- [ ] If testing an already provisioned Nerves environment, inspect its `boot_slot`:
  ordinary OTA deliberately does not replace boot policy, so a stored 1500000-baud
  command will override the new DTS. Review a console-only migration on the compatible
  loader; do not rerun `complete` on a device with data to preserve.

## 3. First Linux / Nerves boot

- [ ] Save uninterrupted serial logs and firmware/kernel/DTB hashes with board identity.
- [ ] U-Boot selects FIT A and passes `root=/dev/mmcblk0p1`, `console=ttyS0,115200`.
  No vendor Android arguments or ttyFIQ0 should appear.
- [ ] Linux brings up three Cortex-A7 CPUs and expected 512 MiB RAM minus reservations.
  CPU DVFS remains off for this milestone (do not assume the inherited OPP table is safe).
- [ ] UART0 standard 8250 console remains readable through erlinit and BEAM.
- [ ] eMMC probes at ff480000, 4-bit, with GPIO voltage regulator and no repeated
  tuning/timeout/I/O errors. Confirm mmcblk0 identity and rootfs A mounted SquashFS read-only.
- [ ] erlinit starts the application; reach `iex>` over serial and record OTP/system version.
- [ ] Stop and preserve exact logs at the first failure. Change only the observed problem.

Useful non-destructive observations from IEx (BusyBox applets vary):

```elixir
System.cmd("dmesg", [])
File.read!("/proc/cmdline")
File.read!("/proc/mounts")
File.read!("/proc/partitions")
File.read!("/sys/devices/system/cpu/online")
File.ls!("/sys/class/net")
```

## 4. Basic hardware after IEx

- [ ] Verify p3 is ext4 mounted at `/root`, `/data` resolves there, and expansion uses
  the remaining eMMC. Write/sync a marker; confirm it survives reboot and power cycling.
- [ ] Attach each Ethernet connector separately. Record physical label ↔ eth0/eth1;
  check the correct MDIO addr 0 PHY binds as YT8522, link 100/full, DHCP/static networking
  and sustained transfer. No switch or connector mapping is assumed. Provision unique,
  stable MAC addresses; do not reuse the captured board's addresses.
- [ ] Verify both USB ports and OTG0 VBUS direction with suitable peripherals; avoid
  connecting competing VBUS sources. Do not assume connector roles from controller index.
- [ ] After measured watchdog DTS/driver integration, inspect
  `/sys/class/watchdog/watchdog0/identity` and its device path. Confirm it is the real
  reset mechanism, not softdog. Exercise Heart feeding, then deliberately stop feeding
  on the recoverable bench board and record reset latency/cause. Recheck cold boot and
  bootloader handoff. Never claim this test passed from device-node existence alone.
- [ ] Repeat software reboot, cold power-on and abrupt power-loss recovery. Check persistent
  filesystem recovery and serial log continuity. Do not validate a sick trial image.

## 5. A/B and deliberate rollback (after basic hardware works)

- [ ] Begin on known-good, validated A. Snapshot/hash FIT A, rootfs A and boot infrastructure;
  preserve data markers. Environment sectors are expected to change and must be excluded
  from loader-byte comparisons.
- [ ] Apply a distinguishable application update using normal `upgrade` selection. Confirm
  only FIT B/rootfs B and environment metadata changed; A, loader, MBR and data remain intact.
  Metadata must select B with `upgrade_available=1`, `bootcount=0` before reboot.
- [ ] Boot B with rootfs p2; observe persistent bootcount advancing for the pending firmware.
  Reject a second update while pending (existing task requirements enforce this).
- [ ] Only after application-specific health checks (storage, required networking/services,
  watchdog ownership and stable operation), call `Nerves.Runtime.validate_firmware/0`.
  Confirm `upgrade_available=0`, `bootcount=0`; reboot stays on B.
- [ ] Repeat B→A to verify the other direction and unchanged data/loader.
- [ ] Trial a version that intentionally does not validate. Reboot enough times to exceed
  bootlimit 3. Verify automatic return to the previous FIT AND matching rootfs; env clears
  pending/count and persistent markers survive. Record every bootcount/slot transition.
- [ ] On the recoverable bench setup, test power interruption during inactive-slot writes
  and environment commit. Verify either old validated firmware or intact new trial boots;
  no mixed kernel/DTB/rootfs, corrupt loader or erased data. Repeat before deployment.

## Build validation from this pass

`mise exec -- mix compile` succeeded for system `0.1.1-dev` after a source-level DTS
syntax fix: `/memreserve/` must precede the included SoC root nodes. The first failed
build log is `/tmp/ec100-reconcile-build.log`; successful rebuild log is
`/tmp/ec100-reconcile-build-2.log` (local transient logs, not hardware evidence).
A final `mise exec -- mix compile` after README changes also passed
(`/tmp/ec100-reconcile-final.log`). The generated kernel configuration and ARM FIT
were inspected, and the FIT's extracted DTB matched the standalone DTB byte-for-byte.
Built-DTB assertions checked the console/storage aliases, memory, watchdog disablement,
PHY addresses, and live MMC/USB/GMAC properties. The only fwup change is console baud;
all slot offsets and update operations are unchanged. Standalone dtc decompilation
still reports 21 warnings in inherited SoC clock/graph/duplicate-address nodes; these
were not hidden by modifying generated sources. No physical EC100 boot, provisioning,
watchdog reset or A/B test has been performed in this pass.
