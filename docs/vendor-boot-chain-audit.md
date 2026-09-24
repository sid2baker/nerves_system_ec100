# Captured vendor boot chain: compatibility audit

## Scope

Read-only inspection of the original EC100 images under `iotrouter/binary/`.
No flashing or partition changes. These are manufacturer-used components, not
proof of a currently supported Rockchip distribution or published support policy.

## Verified image contents

Original GPT partition 1 (`uboot`) starts at LBA 16384 and is 8192 sectors.
`mmcblk1p1.img` contains a FIT with:

| Image | Load address | SHA256 |
| --- | --- | --- |
| U-Boot | 0x00200000 | 298f2de94b0493378ad37c015a5b9af4d1a99a12275767045190932b6a5aabff |
| OP-TEE | 0x00001000 | 93603ca22cdf22e47ac130e4ac386cdf9474443ab076039807dfc2d5d30b7ecd |
| U-Boot DTB | supplied by FIT | 55ba14e6c41eeffcd3c7fcf5c5b27d69c13a08e1509e24d76fd71dd2d415b14f |

Extracted with dumpimage into `/tmp/ec100-vendor-audit/image0`, `image1`, `image2`;
all three payload SHA256 values match the FIT's recorded hashes. This checks
integrity, not signature authenticity.

U-Boot identifies as 2017.09, built Mar 20 2026. Secure firmware identifies as
OP-TEE 3.13.0-958-g46dcf51e88a, Rockchip firmware v2.10.

## Boot policy and environment

Embedded U-Boot defaults include:

```
bootcmd=boot_fit;boot_android ${devtype} ${devnum};
bootdelay=0
bootcount=0
boottest=0
boottestcount=if test $boottest = 1; then setexpr bootcount ${bootcount} + 1; saveenv; echo boottest=1 bootcount=${bootcount};fi;
```

The image contains FIT/bootm handling, MMC read/write command text, environment
import/export/save commands, script loading and the `ENV_BLK` backend name.
These indicate plausible building blocks for our boot policy, not a verified
end-to-end boot capability. `boottestcount` is a vendor test script, not proof
of persistent trial-boot rollback. Searching embedded text did not find
`bootlimit`, `altbootcmd` or `upgrade_available`; absence of strings alone does
not prove every associated feature is unavailable.

The inspected Rockchip BSP `env/env_blk.c` uses compile-time ENV_OFFSET/ENV_SIZE
and optionally ENV_OFFSET_REDUND. We do not have the exact configuration of this
captured binary. **Do not run saveenv on our current disk using that binary**
until its offsets, size, environment format and hardware partition are known.

The original partition at LBA 24576 is `misc`, size 8192 sectors. Our redundant
environments occupy part of that same region. Consequently vendor misc writes
are not safe to assume compatible with our layout. The default vendor boot
flow must not be used unchanged against the Nerves layout.

## Required changes / blockers

1. Vendor OP-TEE is loaded at 0x1000, whereas ours loads at 0x18000000. Our SPL's
   OP-TEE handoff and Linux secure/shared-memory reservations must be reconciled
   with the vendor image contract. Do not simply replace tee-raw.bin.
2. Establish the vendor loader/IDB format and SPL handoff contract before replacing
   the first-stage chain. Preserve the known-good factory recovery loader.
3. Prove or configure redundant persistent environment storage in a region that
   cannot collide with vendor misc handling or FIT/rootfs slots.
4. Install an explicit Nerves boot script that loads matching FIT/rootfs A or B,
   tracks trial attempts persistently and falls back. Validate power-loss and
   successful-boot confirmation on the real board.
5. Retain MBR/rootfs A/B/data layout provisionally. Same original/current U-Boot
   offset (8 MiB) is helpful but does not prove overall compatibility. GPT is
   not inherently required for the explicit raw-sector boot path; the captured
   default vendor flow does depend on named boot partitions.

## Recommendation

Use vendor DDR and secure firmware, and prefer a vendor SPL whose handoff matches
that secure firmware. Use the captured U-Boot binary only if its environment
storage and boot-policy features can be established safely. Otherwise build
U-Boot from the vendor BSP with minimal EC100/Nerves policy configuration.
Our existing U-Boot is already Rockchip BSP-derived; source building itself is
not equivalent to abandoning vendor support.

This is not merely swapping packaging filenames. At minimum it touches boot
packaging, secure-memory/handoff configuration and persistent boot policy; it
may also need factory environment/fwup changes. Exact line count is premature.
No usable vendor-chain Nerves firmware has been produced by this audit.
