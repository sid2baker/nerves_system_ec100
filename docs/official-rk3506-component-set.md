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
- Our current OP-TEE is loaded at 0x18000000, with a 32 MiB reservation and a
  separate 0x10000000 shared-memory reservation. These cannot simply be assumed
  correct for the official firmware.

Integration uses the vendor runtime handoff rather than inventing a static
reservation from this load address. `param_parse_optee_mem()` reads ATAG_TOS_MEM
(or the vendor legacy parameter block); `board_bidram_reserve()` reserves it,
and `arch_fixup_fdt()` calls `bidram_fixup()` and publishes the resulting banks
to Linux. An EC100 patch rejects a missing secure-memory handoff and prints the
region. The existing vendor SoC `trust@0` reservation remains; the custom source
TEE/SHM reservations are removed. Exact runtime reservations and services must
still be verified on hardware.

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

No flashing or hardware qualification has occurred. First boot must show the
secure-memory handoff, sensible Linux RAM banks, working UART and SIP/PSCI,
and correct PWM/OPP state. Do not treat host packaging validation as stability
or A/B rollback validation.

## Upstream references

All paths use the pinned rkbin commit above:

- https://github.com/rockchip-linux/rkbin/blob/3e288fe814e059dd06833495f845cab04ac20a5c/RKBOOT/RK3506MINIALL.ini
- https://github.com/rockchip-linux/rkbin/blob/3e288fe814e059dd06833495f845cab04ac20a5c/RKTRUST/RK3506TOS.ini
- https://github.com/rockchip-linux/rkbin/blob/3e288fe814e059dd06833495f845cab04ac20a5c/doc/release/RK3506_EN.md
