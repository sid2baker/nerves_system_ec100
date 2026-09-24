# Flash the EC100

From the application directory:

```sh
cd ../../ec100_app
mix ec100.flash
```

The application selects `MIX_TARGET=ec100` automatically for this task. Use
`mise exec -- mix ec100.flash` if your shell hasn't activated the project's OTP.
Connect exactly one EC100 in MASKROM mode first.

The task automatically:

1. Builds the application firmware and finds its system boot artifacts.
2. Detects the connected RK3506.
3. Runs `rkdeveloptool db` with the system's `images/ec100-maskrom-loader.bin`
   (RAM-only transport, with DDR UART configured for 115200).
4. Reads the real eMMC capacity and reports the current MBR/GPT layout.
5. Asks once before replacing the boot chain, partitions and application data.
6. Saves the entire eMMC user area plus its SHA256 under `ec100-backups/`.
7. Installs DDR/SPL, source U-Boot/OP-TEE, redundant environments, FIT A and rootfs A;
   replaces GPT with the current Nerves MBR; invalidates B and initializes data.
8. Reads back and verifies every written region, then resets the board.

No need to specify a firmware path, capacity, output directory, loader, partition
migration flag or bootloader directory. The backup location is printed before
confirmation. Cancelling leaves eMMC untouched (the temporary loader remains in RAM).

## Requirements

- `rkdeveloptool`, `fwup`, and the project's Elixir/OTP environment.
- By default USB commands use `sudo -n`; arrange USB permissions or authenticate
  sudo beforehand. If your user already has USB access, pass `--no-sudo`.
- Enough disk space for the full backup (about 3.8 GB on this EC100) and staged files.
- Trusted local firmware and boot artifacts. Hash checks establish integrity, not
  authenticity. This task builds locally; it isn't a general signed-firmware installer.

Only optional switches:

- `--no-backup`: skip the full eMMC backup. Confirmation and readback verification
  still run; this run cannot restore the previous firmware/data. Staged files and
  readbacks still go under `ec100-backups/`.
- `--yes`: skip the destructive-operation confirmation.
- `--no-reset`: leave the USB loader running after verified installation.
- `--no-sudo`: use direct USB permissions.

## Scope and safeguards

This is **destructive factory installation**, not OTA, secure erase or a guarantee
of a successful boot. Normal OTA still writes only inactive FIT/rootfs plus metadata.

The layout remains defined by `fwup.conf`: three MBR partitions, raw FIT A/B slots,
redundant env, persistent ext4. The task checks the generated partition layout and
payload bounds, checks boot artifact hashes, backs up before any persistent write unless explicitly disabled,
and stops without reset on any failed readback. It refuses zero/multiple/wrong USB
devices. USB re-enumeration after `db` is retried only for the read-only capacity probe.

Factory provisioning is not power-loss atomic. Boot0/boot1 hardware partitions are
not touched. Old data beyond initialized regions is not securely erased. Keep the
backup; don't unplug USB or connect another Rockchip device during installation.
`factory.img` in the backup directory is sparse staging data, not a complete boot
image—do not flash it with dd.

System 0.1.4-dev configures DDR, SPL, U-Boot, OP-TEE and Linux for **115200 8N1**.
The built transport is verified against `bootloader.sha256` before downloading;
it is never written to eMMC. The original `bootstrap/MiniLoaderAll.bin` remains
as a recovery reference only (its DDR output uses 1500000).
See [`bootstrap/README.md`](../bootstrap/README.md).

Changing the DDR console requires factory flashing; an ordinary OTA update does
not replace the IDB bootloader. The 0.1.4-dev system and application builds passed,
and the decoded DDR parameters differ only in UART speed and version label.
Hardware confirmation at 115200 is still pending.

Eight tests cover staging with real fwup, partition/resource bounds, boot placement,
device selection, backup-before-write, MBR-last order and aborting on failed readback.
This simplified command has not been used to reflash hardware yet. The prior complete
installation passed readback but has not reached Linux/IEx; see
[source-boot-install.md](source-boot-install.md).
