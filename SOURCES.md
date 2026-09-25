# Sources

| Component | Source | Revision |
| --- | --- | --- |
| Linux | [armbian/linux-rockchip](https://github.com/armbian/linux-rockchip) | `428ab2713a61e9bc438eb1e065469797f97953b4` |
| U-Boot | [rockchip-linux/u-boot](https://github.com/rockchip-linux/u-boot) | `1c535d65b8509f388d09e49fb6961f49fda35a1d` |
| DDR, SPL, TEE, USB loader and packaging tools | [rockchip-linux/rkbin](https://github.com/rockchip-linux/rkbin) | `3e288fe814e059dd06833495f845cab04ac20a5c` |

Selected rkbin components: DDR 750 MHz v1.08, SPL v1.12, standard TEE v2.50,
and USB plug v1.04. Archive and license hashes are in `patches/buildroot/`;
binary hashes are in `bootstrap/rkbin.sha256`.

Nerves Buildroot and ARMv7 toolchain dependencies are declared in `mix.exs` and
locked in `mix.lock`. Component configuration is in `nerves_defconfig`.

## References

- [nerves_system_trellis](https://github.com/nerves-project/nerves_system_trellis): A/B raw-FIT updates
- [nerves_system_rpi2](https://github.com/nerves-project/nerves_system_rpi2): Cortex-A7 toolchain and package structure
- [Rockchip kernel](https://github.com/rockchip-linux/kernel): RK3506 SoC device-tree definitions
- Rockchip RK3506 Technical Reference Manual, revision 1.2

Component licenses remain governed by their respective upstream projects.
