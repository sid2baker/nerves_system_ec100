# EC100 Linux / userspace bring-up

## Verified on the board

The source boot chain reaches Linux 6.1.172 (the pinned Rockchip-derived
`armbian/linux-rockchip` tree), detects three CPUs and HS200 eMMC, mounts rootfs A
as SquashFS, and starts `/bin/sh` as PID 1. This required the manual equivalent
of the FIT/environment fixes now in source:

- Absolute SPL FIT `data-position`, rather than the incompatible relative offsets.
- U-Boot variables preserved through fwup archive creation **and** application.
- Explicit FIT configuration in `bootm`, avoiding the vendor plain-bootm handler.
- FDT load address `0x06000000`, providing the required alignment.
- Temporarily disabling `/usb@ff740000` in the RAM DTB.

This is not yet a reliable Erlang boot or an A/B rollback qualification.

## 0.1.6-dev changes and limitations

### USB OTG workaround

The Linux DTS disables `usb20_otg0` (`ff740000`). The observed panic is in
`dma_map_page_attrs`, reached via gadget request mapping during
`dwc2_conn_id_status_change`. RAM-DTB disabling of this controller avoided that
panic. This is a **workaround**, not a driver fix; Linux gadget/OTG functionality
on that port is unavailable. The separate `ff780000` host remains enabled.
BootROM MASKROM recovery is independent of Linux's DTS.

### Early serial console

Remove the explicit earlycon baud from both the DTS and factory U-Boot policy.
The generic early 8250 driver otherwise uses its default UART input clock to
program a divisor, rather than this board's 24 MHz clock. With no baud argument,
it preserves the UART configuration left by U-Boot. The regular console still
explicitly uses `ttyS0,115200`.

Changing only the environment was insufficient: this BSP merges the DT chosen
bootargs, which reintroduced the old earlycon setting in `/proc/cmdline`.
The rebuilt DTB and boot environment must both be tested. Existing persistent
U-Boot policy is not replaced by normal OTA. Hardware confirmation of clean
early output is still pending.

### Persistent ext4: do not add another formatter

The initial `erlinit` mount failure on blank p3 is expected on a factory image.
`Nerves.Runtime.Init` formats and mounts the application partition after Erlang
starts. The fwup metadata already supplies:

- `nerves_fw_application_part0_devpath=/dev/rootdisk0p3`
- `nerves_fw_application_part0_fstype=ext4`
- `nerves_fw_application_part0_target=/root`

`erlinit` supplies rootdisk symlinks. The application includes `nerves_runtime`;
there is no custom init-module override. Factory integration tests check the
metadata in both generated environment copies. The crash prevents reaching
this initialization, so an extra boot-time formatter would not address the
cause. Verify formatting, mounting, and subsequent data retention once Erlang
runs. Do not run factory `complete` to repair an existing data partition.

## Intermittent userspace failure

Even `/bin/sh -c 'exit 0'` sometimes segfaults. This is independent of Erlang
and occurs with OTG disabled. Dynamic-loader `--list` resolves the dependencies
of both `/sbin/init` and `erlexec`; successful resolution does not prove execution
is correct.

- Three CPUs: four shell launches succeeded, then a fault at `0xa6fc1d7c`
  (instruction permission fault, code `0x8000000f`, CPU 2).
- Another three-CPU test completed 50 launches. It was initially mistaken for
  single-core; `/proc/cpuinfo` disproved that interpretation.
- Confirmed one CPU (`maxcpus=1`, only processor 0): five successful launches,
  then a branch to PC `0x0`, LR `0xa6fba5b4`, code `0x80000005`.

Thus this is **not SMP-only**. No evidence yet justifies changing the external
ARMv7 toolchain or adding cache-coherency register writes. OP-TEE already sets
ACTLR.SMP during its per-core initialization.

Further checks: the crash also occurs with ASLR disabled; ASLR was restored to
2 afterward. Board SHA256 hashes of BusyBox, libc, and the loader exactly match
the staged factory rootfs. Explicit loader invocation failed after 35 successful
starts. With `LD_DEBUG=files,reloc`, attempt 23 (PID 147) failed after its first
`file=libc.so.6` message, before generating the link map. Earlier successful
processes' serial messages were interleaved with its kernel trace; they are not
evidence that the failing process completed relocation.

The exact extracted binaries passed 100 starts under QEMU Cortex-A7 user-mode
emulation. This is a comparison, not proof that the toolchain is fault-free.

The application now includes a temporary, statically linked
`/usr/bin/ec100-exec-probe`, built using the same external ARM toolchain. Run
`--static` first, then without arguments to trace shell starts. It captures the
faulting child's actual mappings, registers, PC/LR bytes, and stack at the first
signal. See the application's `diagnostics/README.md`. Its static child startup
passed 100 QEMU runs; target ptrace/fault capture remains unverified. The probe
is not started automatically and performs no persistent storage writes.

Next: finish and inspect the 0.1.6-dev application firmware, boot the diagnostic
shell on hardware, and capture a failure with this probe. Keep hardware changes
separate from loader tests. Do not exit the PID-1 shell.
