# EC100 hardware evidence and minimal Nerves board map

## Scope and provenance

This map was written before changing the board DTS. Captured data under `iotrouter/`
is read-only. DT enablement alone does **not** prove a populated peripheral. No new
physical-board tests were performed in this pass. Confidence below distinguishes
runtime confirmation from DT description and inference.

Evidence priority: live DT/runtime > other EC100 captures > pinned RK3506 SoC sources
> old skeleton. The kernel is still the commit in `nerves_defconfig`, not a new BSP.

### Inventory

`find iotrouter -type f | sort` found 677 files; the full path inventory is in
[`ec100-evidence-files.txt`](ec100-evidence-files.txt). The requested depth-two
inventory was also inspected. Main groups:

| Location | Contents / use |
| --- | --- |
| `live-device-tree.dts`, `.dtb` | Authoritative booted hardware tree |
| `text/` (72 files) | Boot logs, GPIO/pinctrl, clocks/regulators, MMC, MDIO/network, serial, watchdog observations, buses, processes, mounts and partitions |
| Top-level text files | Additional DT identity, command line, kernel log and partition captures |
| `binary/` (11 files) | First/last eMMC regions, boot hardware partitions, p1–p5, live FDT, proc-device-tree archive |
| `analysis/` | Derived boot/FIT/U-Boot evidence, disassembly, differences, hashes and policies; conclusions must be distinguished from direct runtime facts |
| `analysis/extracted/`, `analysis/recovery-files/` | Extracted FIT components and recovery files; not dependencies of Nerves |
| `copied/` | Vendor daemon executable and service; inspected as evidence, not installed |
| `runtime-evidence-20260830T053014Z/` | Manifest/hashes, boot files, MMC boot regions, proc/kallsyms, firmware/modules and sys/module parameters |
| `SHA256SUMS`, `FILE_SIZES.txt` and nested manifests | Capture integrity/provenance |

### Independent DT verification

```sh
dtc -I dtb -O dts -o /tmp/ec100-live-from-dtb.dts iotrouter/live-device-tree.dtb
diff -u iotrouter/live-device-tree.dts /tmp/ec100-live-from-dtb.dts
# Normalize both through the same dtc; compare all nodes/properties/reservations.
dtc -I dts -O dtb -o /tmp/ec100-text.dtb iotrouter/live-device-tree.dts
dtc -s -I dtb -O dts -o /tmp/ec100-text-normal.dts /tmp/ec100-text.dtb
dtc -s -I dtb -O dts -o /tmp/ec100-binary-normal.dts iotrouter/live-device-tree.dtb
diff -u /tmp/ec100-text-normal.dts /tmp/ec100-binary-normal.dts
```

The initial diff has 645 lines (string-list formatting, etc.). The normalized diff
is **empty**: no semantic difference found. Existing vendor-tree dtc warnings are
not evidence that peripherals work.

SHA256:

- Live DTB: `54b1c73bb8993046b47296ba8869d37e8bdac930ea21dcb456028003cac0ac60`
- Live DTS: `a82cd9db81d9c248ee7551fec8f448cdf0d5577ea4b510ea780c3a1532e6280d`
- Either sorted normalized DTS: `7532ac61107ad5e060fbd3e5727d63a6b64bc4d3bb8a30ec0056afaea9207a16`

## Classification / reconciliation

REQUIRED = boot/basic hardware; USEFUL = later real peripheral; VENDOR-ONLY = not
needed for Nerves; UNUSED = disabled reference node; UNKNOWN = insufficient proof.
Nerves state describes this pass's minimal target; all enabled functions still need
physical Nerves testing. GPIO notation is bank + port + bit, not a Linux global ID.

| Function / class | Live DT node | Pins / GPIO | Driver | Nerves DTS state | Confidence / corroboration |
| --- | --- | --- | --- | --- | --- |
| Console REQUIRED; FIQ wrapper VENDOR-ONLY | `/chosen`, `/fiq-debugger`, `/serial@ff0a0000` | UART0 GPIO0_C7/C6, mux 1, pull-up | `8250_dw` instead of FIQ debugger | UART0 enabled; ttyS0, 115200n8 | High: FIQ `serial-id=0`, `baudrate=115200`; `text/dmesg.txt` ttyFIQ0. Normal UART0 disabled in vendor tree because FIQ owns it |
| Aliases REQUIRED | `/aliases` | serial0–5, gpio0–4, ethernet0/1; vendor gpio5 = PCA9555 | OF | Keep SoC aliases; explicitly add mmc0 for boot eMMC | High for existing aliases; mmc0 is Nerves naming policy, not vendor numbering |
| DRAM REQUIRED | `/memory` | base 0, 0x20000000 bytes | ARM memory | 512 MiB; omit zero-length vendor tuples | High: DT and runtime |
| CPU/SMP REQUIRED | `/cpus/cpu@f00`, `@f01`, `@f02`, `/psci` | Three Cortex-A7 cores, PSCI SMC | ARM PSCI / GIC-400 | Inherit SoC topology; disable DVFS for first boot | High: `text/dmesg.txt` three CPUs; no M0 represented as Linux CPU |
| Interrupts/clocks/resets REQUIRED | `/interrupt-controller@ff581000`, `/clock-controller@ff9a0000`, syscons | SoC wiring | GIC / RK3506 CRU | Inherit pinned SoC DTSI | High: live tree agrees on addresses; no board GPIO inference |
| Firmware reservations REQUIRED; crash log USEFUL | `/reserved-memory/trust@0`, `ramoops@83000`; FDT reserve map | 0..0x61fff; 0x83000+0x2d000; 0x63000+0xb000 | reserved-memory / ramoops | Preserve trust/ramoops from SoC, add live memreserve | High addresses; actual firmware ownership must be checked with final loader |
| Display reservations VENDOR-ONLY | `/reserved-memory/linux,cma`, `drm-logo@0` | vendor CMA 22 MiB; logo 0x1d900000+0xb8000 | CMA / DRM | Remove inherited zero-size placeholders; do not copy logo/CMA | High DT; not needed headless |
| Boot eMMC REQUIRED | `/mmc@ff480000` | GPIO3_A0 clk, A1 cmd, A2–A5 data; mux 1 | `dw_mmc-rockchip` | 4-bit, non-removable, no-sd/no-sdio, HS200, max 150 MHz; real supplies | High: `text/mmc.txt`, dmesg HS200 S0411D; 3,825,205,248 bytes |
| eMMC I/O supply REQUIRED | `/mmcio-gpio-regulator` | GPIO0_D0: 0=1.8 V, 1=3.3 V, initial 0; 100 ms startup | `gpio-regulator` | Enabled with exact live voltage states/pinctrl | High: live DT and gpio-24 consumer in `text/gpio.txt` |
| Main rails REQUIRED | `/vcc12v-dc`, `/vcc-sys`, `/vcc-3v3` | fixed 12 V → 5 V → 3.3 V | fixed regulator | Minimal eMMC supply chain included | High DT; no invented enable GPIO |
| CPU voltage USEFUL | `/vdd-arm`, `/pwm@ff930000` | PWM0 ch0, GPIO0_C5 remap mux 0x2d; 5000 ns inverted PWM, 710000–1207000 µV | PWM regulator | Deferred; CPU_FREQ disabled rather than changing clocks without its supply | DT-backed. Pinned SoC OPP table differs and includes >1.2 GHz; must reconcile before enabling DVFS |
| Other rails USEFUL | `/vcc3v3-stb`, `/vcc-1v8`, `/vcc-ddr` | sys→3.3 V standby→1.8 V; DDR from sys | fixed regulator | Deferred with consumers | DT only; not required by chosen first-boot devices |
| GMAC0 REQUIRED | `/ethernet@ff4c8000`, `mdio/phy@0` | RMII0 GPIO2_B0–B7/C0 mux 1; reset GPIO1_A3 active-low | stmmac / Motorcomm YT8522 | Enabled, PHY addr 0, external input clock, 20/20/20 ms reset delays | High: DT + `text/mdio.txt`; eth0 link 100/full in dmesg |
| GMAC1 REQUIRED | `/ethernet@ff4d0000`, `mdio/phy@0` | RMII1 GPIO3_A6/A7/B0–B6 mux 2; reset GPIO1_A2 active-low | stmmac / Motorcomm YT8522 | Enabled, separate MDIO PHY addr 0, same clock/reset policy | High: DT + `text/mdio.txt`; connector naming not proven |
| Switch UNKNOWN | No switch/DSA node or fixed-link | Unknown | None established | Not invented | Evidence shows two PHYs on separate buses, not a managed switch; does not prove physical connector routing |
| USB REQUIRED/basic | `/usb2-phy@ff2b0000`, `/usb@ff740000`, `/usb@ff780000` | OTG0 VBUS GPIO1_D0 active-high; host1 supply fixed 5 V | Rockchip INNO USB2 PHY / DWC2 | Enable PHY + both ports; OTG0=otg, OTG1=host and exact supply relations | High DT + both controllers register in dmesg; connector routing/load capacity needs testing |
| GPIO/pinctrl REQUIRED | `/pinctrl/gpio@ff940000`, `@ff870000`, `@ff1c0000`, `@ff1d0000`, `@ff1e0000` | banks 0–4 | Rockchip GPIO/pinctrl | Inherit; select only first-boot groups | High: runtime bank IDs in `text/gpio.txt`; never use global Linux GPIO numbers in DTS |
| External watchdog UNKNOWN (required before unattended operation) | `/pinctrl/wdt` only; **no watchdog device node** | GPIO0_B1 (bank 0 offset 9), bias-disable | Candidate standard `gpio_wdt` after measurement | No invented timeout/polarity/algorithm; pin unclaimed | High pin association: `WDG_PI` in GPIO dump; toggles ~10.1 s in transition capture. Reset circuit/timing still unknown |
| Internal watchdog UNKNOWN for board reset coverage | No live watchdog@ff260000/ff268000 nodes | SoC-internal | DesignWare watchdog | Leave both disabled, replacing skeleton's unsupported selection of wdt0 | SoC support known; no evidence it services external supervisor |
| Vendor watchdog device VENDOR-ONLY | No corresponding DT node | `/sys/devices/virtual/watchdog/watchdog0` | Likely softdog, not hardware proof | Do not enable softdog as Heart substitute | `text/watchdog.txt`; dmesg softdog initialized; identity attribute not captured |
| UART3 USEFUL; RS485 role UNKNOWN | `/serial@ff0d0000` | RX GPIO0_A3 mux 0x15, TX GPIO0_A2 mux 0x14 | 8250_dw | Deferred/disabled | ttyS3 confirmed. No RTS/DE GPIO, polarity or `linux,rs485-enabled-at-boot-time` property |
| UART4 USEFUL; RS485 role UNKNOWN | `/serial@ff0e0000` | RX GPIO0_A0 mux 0x19, TX GPIO0_B0 mux 0x18 | 8250_dw | Deferred/disabled | ttyS4 confirmed; transceiver/connector mapping not proven |
| UART1/2/5 UNUSED | `/serial@ff0b0000`, `ff0c0000`, `ff4e0000` | UART1 DT TX/RX GPIO0_C2/C3; UART5 GPIO3_B3/B4 and CTS B2 | 8250_dw | Disabled | Live status disabled; do not map front-panel labels by UART number |
| I2C0 USEFUL | `/i2c@ff040000` | GPIO0_A7 SCL mux 0x1e, A6 SDA mux 0x1f | rk3x-i2c | Deferred/disabled | Live enabled; peripheral presence needs runtime probe review |
| GPIO expander / RTC USEFUL | I2C0 `gpio@20`, `ds1307@68` | PCA9555 at 0x20 (vendor gpio5), DS1307 at 0x68 | pca953x / rtc-ds1307 | Deferred | DT-backed, not proof all external I/O uses expander |
| I2C1/2 UNUSED | `/i2c@ff050000`, `ff060000` | I2C2 has GPIO0_A4/A5 remap groups | rk3x-i2c | Disabled | Live disabled |
| HaLow Wi-Fi USEFUL | `/spi@ff120000/mm6108@0` | CS GPIO0_B2, CLK B3, MOSI B4, MISO B6; IRQ B5; reset GPIO4_B3 | morse/mm610x | Deferred SPI0 | DT 50 MHz; captured morse modules/firmware. Reset GPIO conflicts with vendor user LED: investigate before enabling |
| SPI SD USEFUL | `/spi@ff130000/mmc-slot@0` | CS GPIO1_B3, MOSI B2, CLK C2, MISO C3 | mmc_spi | Deferred | Runtime mmc0 is this host, not boot eMMC; slot configured 20 MHz, 3.3 V |
| SPI NOR UNKNOWN | `/spi@ff488000/flash@0` | No board pinctrl supplied in live node | Rockchip SFC / spi-nor | Disabled | Live node enabled does not prove populated boot flash |
| LTE USEFUL | `/pinctrl/modem-reset-pin`, `modem-power-pin`; `/leds/pcie_power` | reset GPIO1_D1; power GPIO1_C0 | eventual standard power/reset consumer | Deferred | Runtime WWAN_RST_PI on gpio57 and pcie_power on gpio48; timings, active polarity and modem routing unknown |
| LEDs/buttons USEFUL/UNKNOWN | `/pinctrl/run-led`, `led1`, `led2`, `user-reset`; `/leds`, `/gpio-keys`, `/adc-keys*` | run GPIO1_A7, LED1 A6, LED2 A4, reset key A5; vendor heartbeat GPIO0_A5; user LED GPIO4_B3; key GPIO4_B2 | gpio-leds / gpio-keys / adc-keys | Deferred | Runtime LED_0 gpio39 and KEY_PI gpio37 corroborate some roles; reference LED/Wi-Fi reset conflict prevents blind copying |
| DI/DO UNKNOWN | No explicitly named DI/DO consumer nodes | Unknown | TBD | Disabled/not invented | Need connector mapping and electrical measurements; PCA9555 presence is insufficient |
| CAN0/1 USEFUL | `/can@ff320000`, `ff330000` | CAN0 TX/RX GPIO0_C3/C4; CAN1 C1/C2 | Rockchip CAN FD | Deferred/disabled | Both live enabled, 300 MHz assigned clock; transceiver/connector mapping unverified |
| ADC/thermal/RNG USEFUL | `/adc@ff4e8000`, `/tsadc@ff650000`, `/rng@ff710000` | ADC vref=1.8 V | Rockchip drivers | Remain deferred in board DTS | Live enabled; no invented ADC product-I/O mapping |
| M0 / FlexBUS / DSMC UNKNOWN or UNUSED | Disabled `/dsmc-slave`; no active M0 interface in live DT | Unknown application protocol | TBD | Deferred with no firmware/boot dependency | Not prerequisites for Linux/Nerves bring-up |
| Display/audio VENDOR-ONLY for this headless target | display-subsystem, VOP/DSI/DPHY/panel/backlight/RGA, I2C0 lt8912b@48, acodec-sound/audio-codec/sai4 | Includes enabled demo nodes | Not needed | Not copied/enabled | Enabled in vendor DT does not establish needed EC100 hardware; DRM stays off |
| Disabled audio UNUSED | I2C0 es8388@11, SAI1/3, DSM | Reference groups | Not needed | Disabled | Live disabled |
| Vendor suspend/debug integration VENDOR-ONLY | rockchip-suspend, arm-debug, system-monitor | SoC-specific | Vendor framework | No added board sleep-IO configuration, daemon or FIQ node | Reuse SoC foundation without copying vendor board policy |

### Ethernet details

Each MAC uses its own MDIO bus: `stmmac-0:00` and `stmmac-1:00`, both bound to
`YT8522 100M Ethernet`. In live phandles, 0x7d resolves to GPIO1; reset offsets 3
and 2 are therefore GPIO1_A3 and A2, not GPIO0. `clock_in_out = "input"` and
`phy-mode = "rmii"` are present on both. No guessed PHY IRQ or clock-output setting
is added. Captured MAC addresses/serial number are **not** copied into a reusable
board DTS. Provision unique stable MACs through the eventual bootloader/application.

### Watchdog is an explicit bring-up blocker, not solved by a device filename

Read `text/watchdog.txt`, `text/gpio.txt`, `text/watchdog-gpio9-transitions.txt`,
`text/iotrouter-process.txt`, and `text/dmesg.txt`. The vendor daemon has four GPIO
line-handle descriptors; this and the pin label support GPIO feeding, but do not
prove which thread owns the watchdog or its timeout. The copied executable is a
statically linked ARM ELF without section headers; simple strings did not resolve
the protocol. The live tree has only a pin group, not a watchdog consumer.

Before adding `linux,wdt-gpio`, identify the supervisor, measure reset on missed
edges, minimum/maximum interval, enable/disable behavior, polarity and bootloader
handoff. Then use the standard GPIO watchdog driver with measured
`hw_algo`/`hw_margin_ms`, verify its `/sys/class/watchdog/.../identity` and ensure
Heart feeds that device. Do not substitute softdog or claim the internal WDT
covers an external timer. A board may reset during a long boot until this is solved.

### Boot/storage boundary

Vendor eMMC is `mmcblk1` because SPI MMC registered first (`text/mmc.txt`); Nerves
keeps SPI MMC disabled and explicitly aliases the physical eMMC to mmc0. Verify
actual enumeration before writing. Linux and U-Boot MMC numbering are separate.

The current Nerves raw FIT/rootfs/persistent layout remains authoritative. No
vendor `parameter.txt`, Android args, recovery/OEM/AMP partitions or userspace is
introduced. `analysis/uboot-environment-policy.txt` reports stock U-Boot uses a
non-redundant 32 KiB environment at 0x003f8000, **not** our redundant environments
at 12 MiB/12.125 MiB. `analysis/uboot-boot-fit-ab-policy.txt` also describes different
stock boot behavior. These captures are a warning against using our fwup environment
operations with stock U-Boot, not a reason to adopt a vendor/misc partition protocol.
A separately verified compatible bootloader is still required for production A/B.
