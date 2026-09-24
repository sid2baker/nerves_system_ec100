# Application integration and preflash inspection

The application at `../../ec100_app` now uses `../dev/nerves_system_ec100`
(system 0.1.2-dev). Its SquashFS compression was changed from LZ4 to XZ to match
this kernel. `MIX_TARGET=ec100 mise exec -- mix deps.get` and `mix firmware`
succeeded. Application output: `_build/ec100_dev/nerves/images/ec100_app.fw`.
Offline `mix ec100.flash` preparation also passed, output `/tmp/ec100-app-current-prepared`.

## Actual board observation

USB reports RK3506 2207:350f, LocationID 105, MASKROM. FT232 serial adapter is
`/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0KPLVO-if00-port0`.

A pre-existing RK3506 `MiniLoaderAll.bin` from the other system checkout's
0.3.8 images was downloaded to RAM using `sudo -n rkdeveloptool db`. SHA256:
`01c2925ec179492a42c3d2ccaa55edab07f154ca7ef8eada30be11953353393c`.
No loader was written to eMMC. Non-root access failed; sudo was necessary.
The first immediate `rfi` failed during USB re-enumeration; a subsequent probe
succeeded. The current Mix task does not yet retry this transient probe failure.

`rfi`: 7471104 sectors, 3648 MiB. Read-only inspection saved the first 16 MiB
and last sector to `/tmp/ec100-preflash-inspection/` (not a full disk backup).

- First 16 MiB SHA256: `41db7c271164784e4aaf0609692228f8f7f122dc810861c84ffdf7a8832a9a97`
- Last sector SHA256: `6e6a5ae0c0a02816d1bc6e3b76a42cf8b5e59016b374bde491c5c600dbfccac0`

The board currently has a protective GPT MBR and U-Boot identifies itself as
`U-Boot 2017.09 (Mar 20 2026 - 16:12:47 +0800)`. Stored environment strings show:

- `bootcmd=run nerves_init; run nerves_boot`
- vendor `boot_fit`, console `ttyFIQ0`, root by `PARTLABEL`
- `nerves_fw_validated` / `nerves_fw_booted` protocol
- persistent data `/dev/rootdisk0p7`, f2fs

This is **not** the current raw-FIT/redundant-env/bootcount/ext4 boot contract.
Flashing the prepared image while preserving this bootloader would destroy the
old partition layout without establishing a working new boot path. No eMMC writes
or reset were performed. The board was left with the temporary USB loader running.

Next prerequisite: build and verify a bootloader matching `bootstrap/`, then add
an explicit backed-up GPT-to-MBR factory migration and install that boot chain.
Do not bypass `--compatible-bootloader` or the GPT guard on this board.
