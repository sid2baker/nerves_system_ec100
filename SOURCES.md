# Source references used for this scaffold

- Nerves A/B raw-FIT/update pattern: `nerves-project/nerves_system_trellis`
- Nerves Cortex-A7 toolchain/package structure: `nerves-project/nerves_system_rpi2`
- RK3506-enabled Linux tree pin: `armbian/linux-rockchip@428ab2713a61e9bc438eb1e065469797f97953b4`
- RK3506 SoC DTS ancestry and peripheral naming: `rockchip-linux/kernel`
- Source-built RK3506 U-Boot/SPL: `rockchip-linux/u-boot@1c535d65b8509f388d09e49fb6961f49fda35a1d` (2017.09-derived BSP; isolated patches under `bootstrap/patches`)
- Source-built ARM32 secure monitor/PSCI: `OP-TEE/optee_os@5858c37a66cbffccf7b047d0f9a52dee0ebbf06c`, platform rk3506
- DDR init and temporary USB transport: `rockchip-linux/rkbin@f43a462e7a1429a9d407ae52b4745033034a6cf9`, DDR 750MHz v1.05 / USB plug v1.02. Proprietary DDR is persisted with source SPL; USB plug is RAM-only.
- Modern upstream U-Boot has RK3506 SoC support but the inspected tree lacked an RK3506 board defconfig/DTS; migration remains future work.
- Hardware register/boot behavior: Rockchip RK3506 TRM Revision 1.2 (user-provided PDF)

No IOTRouter userspace, Android/Rockchip `parameter.txt` partition layout, recovery partition,
OEM partition, or vendor management daemon is included.
