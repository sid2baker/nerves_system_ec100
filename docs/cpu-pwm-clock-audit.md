# CPU PWM/clock audit — 0.1.6-dev

## Scope

Read-only source audit prompted by the diagnostic-shell capture: armclk reported
1200 MHz, no CPU regulator registered, empty PWM debugfs output, and clk_pwm0
hardware enable N. The initial audit made no firmware, bootloader, voltage, or board changes.
Subsequent hardware results are recorded below; the 0.1.7-dev source restoration
is described in `cpu-power-restoration.md`.

Source references below are relative to the 0.1.6-dev artifact build directories
`build/linux-custom` (Linux) and `build/uboot-custom` (U-Boot).

## Original wiring

`iotrouter/live-device-tree.dts` resolves as follows:

- `vdd-arm` uses PWM phandle 0xa9: controller `pwm@ff930000`, channel 0,
  period 5000 ns, inverse polarity.
- Supply phandle 0xa7 is `vcc_sys` (5 V).
- Regulator range is 710000–1207000 microvolts, initial voltage 1011000
  microvolts, upward settling time 250 us, boot-on and always-on.
- PWM pinctrl phandle 0x63 is `rm-io21-pwm0-ch0`: GPIO bank 0, pin 21
  (GPIO0_C5), mux function 0x2d. Configuration phandle 0x72 means bias disabled,
  drive-strength 1. Linux source label: `rm_io21_pwm0_ch0` in
  `arch/arm/boot/dts/rk3506-pinctrl-rmio.dtsi`.
- `iotrouter/text/pwm.txt` reports requested/enabled CPU PWM, period 5000 ns,
  duty 1650 ns, inverse polarity. The original regulator summary reports 874 mV.
  These are software reports, not measured voltage or settings to copy blindly.
- Original clock summary reports clk_pwm0 enabled at 93750000 Hz. Its peripheral
  and oscillator clocks are not reported enabled; do not mistake their disabled
  state alone for loss of PWM output.

## Current U-Boot

`bootstrap/rk3506-ec100.dts` has no CPU regulator and does not enable its PWM
controller. The inherited `arch/arm/dts/rk3506.dtsi` leaves pwm@ff930000 disabled.

The built configuration has PWM and PWM-regulator drivers, but their existence
alone does not instantiate this missing device. Generic
`arch/arm/mach-rockchip/board.c` calls `regulators_enable_boot_on()`; there is no
CPU regulator node here for that path to configure. The RK3506-specific
`arch/arm/mach-rockchip/rk3506/rk3506.c` contains no CPU PWM setup. Its
`set_armclk_rate()` implementation is the generic weak no-op.

Thus the inspected source-owned board setup does not establish this CPU PWM
configuration. The state left by BootROM/proprietary DDR initialization remains
unknown. We have not read pre-Linux PWM registers or measured the output.

## Current Linux

- `dts/rk3506-ec100.dts` does not restore the CPU PWM regulator or enable PWM0.
- `rk3506.dtsi` includes `rk3502.dtsi`; the latter leaves `pwm0_4ch_0` disabled.
- Built config already has `CONFIG_PWM_ROCKCHIP=y` and `CONFIG_REGULATOR_PWM=y`;
  `CONFIG_CPU_FREQ` is disabled.
- `drivers/clk/rockchip/clk-rk3506.c:727–735` registers PWM0 clocks with flags 0,
  not `CLK_IGNORE_UNUSED`. `clk_pwm0` is a gated composite clock.
- `drivers/clk/clk.c:1411–1499` walks clocks at late init. A clock with no enable
  reference and no IGNORE_UNUSED flag is disabled if hardware reports it on.
  `clk_ignore_unused` skips that sweep and prints
  `clk: Not disabling unused clocks`.

This establishes a source path that can shut down a firmware-enabled CPU PWM
clock when no driver claims it. The current capture shows the resulting clock
is off, but does **not** prove it was on before Linux or that this sweep caused
its transition. Clock-off behavior of the physical regulator remains unmeasured.

### Correction to the inherited-clock description

`rk3502.dtsi` assigns 1200000000 Hz to `pvtpll_core`; the RK3506 clock driver
also selects the PVTPLL source during initialization. Linux therefore has an
explicit CPU clock setup even without cpufreq, not merely an untouched inherited
clock. `drivers/clk/rockchip/clk-pvtpll.c` returns cached `cur_rate` from
`rockchip_clock_pvtpll_recalc_rate()`. The summary's 1200 MHz is a driver-reported
rate, not an independent frequency measurement.

## Completed hardware test: preserve unused clocks

The user tested this option with all three CPUs online. Linux printed
`clk: Not disabling unused clocks`; clk_pwm0 and the other PWM clocks reported
hardware enable Y. Nevertheless, the static probe reached attempt 15 and then
panicked at 134.048288 seconds: `Watchdog detected hard LOCKUP on cpu 1`.
CPU0 ran `rockchip_panic_notify`; CPU1 and CPU2 repeatedly sampled
0xffff0004/0034/0064/0094. The full CRU dump contained nonzero values; its initial
zero-filled ranges were not evidence of an all-zero CRU. No dynamic test was run.

Conclusion: preserving unused clocks is not sufficient. It does not establish
PWM waveform or CPU voltage. Do not adopt this option as a permanent fix.

### Procedure retained for provenance

Before restoring the entire regulator/OPP path, compare one temporary boot with
`clk_ignore_unused`. This changes no on-disk firmware and makes no explicit
voltage/duty-cycle request. It preserves all otherwise-unused clocks, not just
PWM0; it is a diagnostic, not a production fix. It cannot enable a clock that
was already off before the sweep.

Interrupt U-Boot at `=>`. Enter each line separately; stop if the MMC read fails:

```text
mmc dev 0
mmc read 0x08000000 0x8000 0x10000
setenv bootargs console=ttyS0,115200
setenv bootargs "${bootargs} root=/dev/mmcblk0p1 rootwait ro"
setenv bootargs "${bootargs} init=/bin/sh clk_ignore_unused"
printenv bootargs
bootm 0x08000000#conf - 0x08000000#conf
```

Do not saveenv. Keep all three CPUs as in the failing comparison. In the shell:

```sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug
cat /proc/cmdline
grep '^processor' /proc/cpuinfo
dmesg | grep 'unused clocks'
grep pwm /sys/kernel/debug/clk/clk_summary
cat /sys/kernel/debug/pwm
```

An empty PWM debugfs listing is still expected: this option does not instantiate
PWM devices or a regulator. First collect these outputs before further stress.
If clk_pwm0 now reports hardware enable Y, compare the existing static and
dynamic probes with the previous baseline, capturing the full UART output:

```sh
/usr/bin/ec100-exec-probe --static
/usr/bin/ec100-exec-probe
```

Stop on the first fault/hang. Passing 100 iterations is preliminary, not proof
of stability; follow with repeated untraced tests and cold boots only after the
clock-state comparison has been assessed.

Interpretation:

- PWM clock Y only with the option: strong evidence the late sweep disabled it
  in the baseline. Still not a measurement of PWM waveform or rail voltage.
- Clock Y and stable tests: unused-clock shutdown is implicated; isolate PWM0
  with a targeted follow-up before declaring the cause proven.
- Clock N: it was not simply preserved by skipping the sweep; examine pre-Linux
  PWM state and earlier clock setup before adding voltage controls.
- Failures persist: this does not validate the missing regulator setup or rule
  out voltage issues, but prevents treating the sweep as a sufficient explanation.

Power cycling and normal autoboot restores the saved boot arguments. Do not
make this broad clock-preservation option permanent. No new build or version
bump is needed for this temporary command-line experiment.
