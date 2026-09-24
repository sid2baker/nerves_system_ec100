# Source references used for this scaffold

- Nerves A/B raw-FIT/update pattern: `nerves-project/nerves_system_trellis`
- Nerves Cortex-A7 toolchain/package structure: `nerves-project/nerves_system_rpi2`
- RK3506-enabled Linux tree pin: `armbian/linux-rockchip@428ab2713a61e9bc438eb1e065469797f97953b4`
- RK3506 SoC DTS ancestry and peripheral naming: `rockchip-linux/kernel`
- Source-built RK3506 U-Boot/SPL: `rockchip-linux/u-boot@1c535d65b8509f388d09e49fb6961f49fda35a1d` (2017.09-derived BSP; isolated patches under `bootstrap/patches`)
- Official low-level firmware and packaging tools: `rockchip-linux/rkbin@3e288fe814e059dd06833495f845cab04ac20a5c`: DDR 750MHz v1.08, SPL v1.12, standard TEE v2.50, USB plug v1.04. Buildroot source/archive/license hashes are pinned in `patches/buildroot`; binary hashes are in `bootstrap/rkbin.sha256`. DDR UART metadata is customized to 115200; USB plug code is RAM-only. No captured vendor firmware is used as a build input.
- Modern upstream U-Boot has RK3506 SoC support but the inspected tree lacked an RK3506 board defconfig/DTS; migration remains future work.
- Hardware register/boot behavior: Rockchip RK3506 TRM Revision 1.2 (user-provided PDF)

No IOTRouter userspace, Android/Rockchip `parameter.txt` partition layout, recovery partition,
OEM partition, or vendor management daemon is included.
