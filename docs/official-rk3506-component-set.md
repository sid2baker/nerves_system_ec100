# Official RK3506J boot-component candidate

## Selection

Use official `rockchip-linux/rkbin` commit
`3e288fe814e059dd06833495f845cab04ac20a5c` (master resolved during this audit),
not floating master. Its own standard `RKBOOT/RK3506MINIALL.ini` and
`RKTRUST/RK3506TOS.ini` select:

| Role | File | SHA256 |
| --- | --- | --- |
| DDR | rk3506_ddr_750MHz_v1.08.bin | 4aff156670ec4558efcac280541bd541df6684812369594c605b4bfb4854e8e9 |
| SPL | rk3506_spl_v1.12.bin | d1d14e45cec200366d184be1be20cd58e820e5c6799f25b2e2b3994cff145514 |
| RAM USB transport | rk3506_usbplug_v1.04.bin | 977ef38105ff67adb1dc19a2808f83593547f52d71574de0b6d3220a5c207c6e |
| Secure firmware | rk3506_tee_v2.50.bin | 25ecab701828b2c0381b026b3e3ab7b00a76114b92415208a1e8d3c8fbdb7065 |

Downloaded and hashed these four files under `/tmp/ec100-official-rkbin/`.
This is a candidate selected by upstream configurations, not hardware validation
or a claim of a certified Nerves/Linux compatibility matrix.

Do not mix in `tee_ta_v2.52` merely because its version number is higher: the
TA-enabled variant has a separate RK3506TOS_TA.ini. Likewise RT DDR has a
separate loader configuration. Start with the standard upstream configuration.

## RK3506J evidence

Upstream `doc/release/RK3506_EN.md` explicitly records:

- DDR v1.03: added RK3506J support and optimized RK3506B/J drive strengths.
- TEE v1.24: added RK3506J support.
- DDR v1.08: merged RK3506/RK3506B binaries with automatic detection.

These establish RK3506J support in this release lineage; no separate J-named
DDR/TEE file is required by the inspected upstream configurations. Board-specific
memory wiring and actual boot behavior still require EC100 testing.

## U-Boot

Official rockchip-linux/u-boot next-dev currently resolves to
`1c535d65b8509f388d09e49fb6961f49fda35a1d`, which is already our U-Boot source pin.
Thus there is no reason to replace it with an unrelated U-Boot version just to
call the stack official. Keep a vendor-BSP build with the EC100 UART/eMMC setup
and minimal Nerves A/B environment/boot-policy modifications. rkbin does not
supply a ready-made EC100/Nerves U-Boot binary.

This avoids using the captured manufacturer's U-Boot binary as a build input.
The captured DTS remains useful evidence of EC100 board wiring, not a required
binary dependency.

## Memory and packaging contract: partly established

- Upstream loader INI: chip RK350F, NEWIDB=true, CREATE_IDB=true, RC4 off.
- FlashData is DDR v1.08, FlashBoot is SPL v1.12. LOADER2_PARAM declares
  LOAD_ADDR=0x03f00000 and FLAG=0; do not reinterpret this as the Linux load address.
- Upstream TOS INI: TOSTA=tee_v2.50 and ADDR=0x1000.
- The previous source-built OP-TEE loaded at 0x18000000, with a 32 MiB reservation and a
  separate 0x10000000 shared-memory reservation. These cannot simply be assumed
  correct for the official firmware.

Linux inherits the vendor `rk3502.dtsi` reservation `trust@0`, with
`reg = <0x0 0x62000>` (392 KiB). The captured factory device tree and our built
0.1.9 DTB both contain this same reservation. Linux's early reserved-memory
scan excludes it from allocation. The old custom source-TEE/SHM reservations
are removed.

The separate U-Boot `param_parse_optee_mem()` path reads ATAG_TOS_MEM or legacy
parameters. It is optional: vendor `bidram_core_reserve()` explicitly returns
success for size zero. Our initial assertion that this path must return a
nonempty region was incorrect; the hardware failure and correction are below.

## Implementation sequence

1. Update the rkbin package pin as a whole to the above revision, with its source
   hash/license metadata. Remove the separate v1.06 override once superseded.
2. Use its official DDR/SPL/USB loader configuration and tools, preserving the
   verified 115200 UART customization and checking decoded DDR parameters.
3. Package the vendor-BSP U-Boot with official TEE using the upstream TOS contract.
   Remove source OP-TEE build input and custom source-SPL packaging from this path.
4. Resolve secure/shared memory and DT fixups explicitly; retain kernel and
   userspace otherwise unchanged for the comparison.
5. Verify generated images, fit hashes/load addresses and sizes, redundant
   environment locations, and raw A/B boot scripts. Preserve MBR/layout unless
   an observed official-component requirement prevents it.
6. Factory-flash only after backup and recovery readiness; normal OTA cannot
   replace the low-level chain. Test cold boot, UART, exec probes, and only then
   qualify A/B trial boot, confirmation and rollback.

## 0.1.9-dev implementation status

The build configuration now selects this set. Buildroot patches update rkbin and
suppress the mainline-only u-boot-rockchip.bin install for this legacy BSP.
Source OP-TEE is disabled; source SPL is not installed or packaged. The separate
v1.06 override is removed. Updated DDR tool syntax is `--ver_edit`.

Host validation: rebuilt U-Boot with the secure-memory handoff check, ran the
complete post-image script with official SPL/DDR/TEE/USB binaries, and verified
the packaged TEE is byte-identical to the pinned input at FIT load 0x1000.
Decoded DDR output reports DDR3 750 MHz and UART 115200. Both Buildroot patches
pass dry-run against the pinned Buildroot tree. Updated Linux DTB compiles and
contains only the inherited trust/ramoops reservations, not the old custom TEE
nodes. Temporary validation tree: `/tmp/ec100-official-build.1CduCX`.

## 0.1.9 hardware failure and 0.1.10 correction

The user's hardware log shows DDR v1.08, official SPL v1.12 and TEE v2.50
starting. SPL falls back from GPT discovery to the raw FIT at sector 0x4000,
verifies all three hashes, then enters TEE and U-Boot. TEE reports:

```text
OP-TEE memory size: TEEOS 0x5e000 TA 0x1000 SHM 0x1000
```

U-Boot then stops at our added check:

```text
DRAM:  EC100: missing OP-TEE memory handoff; refusing boot
Bidram Error: Failed to reserve bidram for board
```

These sizes are consistent with the small vendor reservation, but are not by
themselves a complete address map. The fixed Linux reservation is established
by the vendor DTS and confirmed in the built DTB, not inferred from this log.
U-Boot's normal image addresses are above it: U-Boot 0x00200000, kernel FIT
buffer 0x00108000 (manual diagnostic buffer 0x08000000), kernel load
0x02080000, Linux FDT load 0x06000000. The BSP places ATAGS at 0x62000.

Version 0.1.10 removes patch 0003, restoring vendor handling of absent dynamic
TEE-memory parameters. It retains the existing fixed Linux reservation and
changes no firmware binaries, load addresses, partition layout, or boot policy.
The misleading dynamic-handoff comments/documentation are corrected.

Validation: rebuilt U-Boot after reversing only patch 0003, confirmed the fatal
check string is absent, and successfully ran factory boot-artifact packaging.
Validation outputs: `/tmp/ec100-reservation-fix.3ezYxE`.

### 0.1.10 hardware results

The user supplied a successful boot log: official DDR/SPL/TEE start, U-Boot
shows `trust@0: addr=0 size=62000`, Linux starts all three CPUs with PSCI 1.0
and SMCCC 1.1, SquashFS root mounts, and existing ext4 data mounts after journal
recovery. Erlang/OTP 29 and interactive Elixir 1.20.4 start. The earlier SIP
version/DRAM-refresh error messages are absent in this log; this does not verify
all firmware services.

IEx evaluation succeeded. Three 100-launch dynamic exec probes plus ten more
100-launch batches all passed: 1,300/1,300 on that boot, exit status zero. After
being asked to reboot and repeat the test, the user reported "it works"; no
second detailed transcript/count was supplied. The prior execution failure has
not reproduced in these tests, but long-term stability and root cause remain
unproven. A/B rollback and watchdog reset are still unqualified.

Remaining startup diagnostics include an unavailable NervesMOTD module in
`/etc/iex.exs`, vendor GPT/boot-partition discovery fallbacks, optional peripheral
configuration warnings, and an RGA driver binding failure. Preserve this working
baseline and address demonstrated issues individually.

## Upstream references

All paths use the pinned rkbin commit above:

- https://github.com/rockchip-linux/rkbin/blob/3e288fe814e059dd06833495f845cab04ac20a5c/RKBOOT/RK3506MINIALL.ini
- https://github.com/rockchip-linux/rkbin/blob/3e288fe814e059dd06833495f845cab04ac20a5c/RKTRUST/RK3506TOS.ini
- https://github.com/rockchip-linux/rkbin/blob/3e288fe814e059dd06833495f845cab04ac20a5c/doc/release/RK3506_EN.md
