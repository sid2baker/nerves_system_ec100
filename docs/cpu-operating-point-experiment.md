# Next experiment: verify the EC100 CPU operating point

## Objective

Determine whether CPU clock/voltage configuration contributes to intermittent
userspace faults and hard lockups. This is a hypothesis test, not a confirmed fix.
Do not change DDR initialization, OP-TEE, userspace, or CPU count in the same
experiment. Keep `iotrouter/` read-only.

## Evidence and limits

- The original live DTS connects `cpu@f00` to a PWM `vdd-arm` regulator and a
  shared OPP table containing 600, 800, 1008, and 1200 MHz operating points.
- `iotrouter/text/clk-summary.txt` records the original `armclk` at 1200 MHz.
  **1200 MHz is not itself an overclock relative to this capture.**
- `iotrouter/text/regulator-summary.txt` reports original `vdd_arm` at 874 mV.
  This is a driver-reported value, not a physical rail measurement or a universal
  safe voltage for all frequencies, temperatures, or silicon samples.
- Original dmesg records PVTM calibration (`pvtm=1580`, voltage selection 0).
- Current U-Boot reports 1200 MHz PVTPLL. Our Linux board DTS omits the original
  CPU regulator setup, and `CONFIG_CPU_FREQ` is disabled. Disabling DVFS does not
  establish a conservative or verified clock/voltage pair.
- Earlier shell crashes occurred even on one CPU. In the latest firmware,
  single-core static/dynamic tests passed; a three-core dynamic test hung at
  attempt 59. A normal boot also reached BEAM and then a CPU 2 hard lockup.

The question is whether the current inherited supply/clock state is correct,
not whether every 1200 MHz configuration is inherently unsafe.

## 1. Preserve the baseline

1. Record system/app versions, firmware SHA256, kernel configuration, compiled
   DTB, bootloader manifest, and exact U-Boot arguments.
2. Preserve the current firmware and existing eMMC backup. Do not overwrite the
   recovery backup or rerun factory `complete` merely to change kernel/DTB.
3. Capture UART output at 115200 8N1 with exactly one serial reader.
4. Record cold versus warm boot, supply, attached peripherals, ambient
   conditions, CPU count, and time to failure. Keep these consistent.
5. Use the existing `init=/bin/sh` diagnostic boot rather than Erlang startup.
   Do not exit the PID-1 shell. Retain all three CPUs for the first comparison,
   since the latest hang was reproduced in that configuration.

## 2. Audit before enabling regulator control

Read these original captures together:

- `iotrouter/live-device-tree.dts`: `cpus`, `cpu0-opp-table`, `vdd-arm`, referenced
  PWM controller, PWM pinctrl, upstream supply, and referenced NVMEM cells.
- `iotrouter/text/clk-summary.txt`
- `iotrouter/text/regulator-summary.txt`
- `iotrouter/text/pinctrl.txt`
- `iotrouter/dmesg.txt`

Compare with:

- `dts/rk3506-ec100.dts` and the pinned kernel's `rk3506.dtsi`.
- `linux/ec100.fragment` and the actual generated kernel `.config`.
- `bootstrap/rk3506-ec100.dts` and the built U-Boot's clock, PWM and regulator
  initialization paths.
- The pinned kernel's PWM-regulator, Rockchip OPP/PVTM and CPU-frequency drivers.

Resolve numeric phandles to their nodes. Do not copy numeric phandles into our
source DTS: use the correct source labels. Verify:

- PWM controller/channel, pin mux, period, polarity and duty-to-voltage mapping.
- Supply chain, min/max/init voltage and settling time.
- CPU supply attachment and shared OPP attachment on all relevant CPU nodes.
- PVTM/PVTPLL properties, leakage/NVMEM dependencies and voltage-selection code.
- Whether U-Boot initializes or changes the same PWM output before Linux.
- Whether Linux could gate an unclaimed PWM clock or alter its pin state.

**Stop if any mapping or dependency is unresolved.** Do not substitute a fixed
regulator, guessed GPIO, arbitrary duty cycle, or raw register write.

## 3. Capture the current operating state

From the diagnostic shell, mount `/proc`, `/sys`, and debugfs if they are not
already mounted. For a fresh PID-1 shell, use one line at a time:

```sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs debugfs /sys/kernel/debug
cat /proc/cmdline
grep '^processor' /proc/cpuinfo
cat /sys/kernel/debug/clk/clk_summary
cat /sys/kernel/debug/regulator/regulator_summary
cat /sys/kernel/debug/pwm
```

An already-mounted error is not a request to unmount anything. If a debugfs
entry or filesystem is unavailable, record that limitation; do not infer a
voltage or clock value from an absent interface. Missing cpufreq policy files
are expected with CPU_FREQ disabled.

Save the output externally through the serial log, not to the read-only rootfs.
Software clock/regulator state can be incomplete when firmware owns the hardware.

### Physical voltage measurement

Only measure at a CPU-rail test point positively identified from board
schematics or verified hardware documentation. Use suitable equipment and a
verified ground reference. Do not guess a pad or probe fine-pitch live pins.
Record idle and test-load readings; a multimeter cannot exclude short voltage
transients. If no safe test point exists, mark voltage measurement unavailable.

## 4. Restore the verified CPU power-management path

This is a prerequisite platform change, **not** a frequency-only experiment:

1. Add the verified regulator, PWM/pinctrl, supply references and CPU OPP/PVTM
   configuration. Preserve unrelated board configuration.
2. Enable the required CPU-frequency/regulator/PWM drivers and dependencies.
   Follow the pinned BSP's implementation rather than choosing symbols by name
   alone. Do not invent voltages or omit calibration merely to make probe pass.
3. Bump the system version, compile and inspect the final DTB and kernel config.
4. Verify hashes show DDR, OP-TEE and userspace inputs have not changed. Record
   any unavoidable artifact changes rather than claiming an identical baseline.
5. Deploy through an appropriate verified update path that preserves existing
   data and recovery. Do not change the bootloader unless the audit establishes
   that a bootloader correction is required; treat that as a separate experiment.
6. Boot the diagnostic shell and verify regulator/OPP/CPU-frequency probe success.
   Stop on missing supply, dummy CPU regulator, failed calibration, or rejected
   OPP messages.

Serial SysRq may be enabled as an explicitly recorded diagnostics-only change.
Verify it works while healthy before relying on it during a lockup. Keep lockup
detection enabled; disabling the detector would hide evidence.

## 5. Select and verify a supported 600 MHz point

Discover the actual policy path; do not assume a particular policy number:

```sh
ls /sys/devices/system/cpu/cpufreq
```

For the policy covering the online CPUs, inspect `affected_cpus`,
`scaling_driver`, `scaling_available_governors`, `scaling_available_frequencies`,
`scaling_min_freq`, `scaling_max_freq`, and `scaling_cur_freq`.

Only if the driver exposes 600000 kHz and permits the transition:

1. Record the existing limits and governor.
2. Set the minimum to 600000 first, then the maximum to 600000. This avoids
   requesting a maximum below an existing higher minimum. Check every write.
3. Verify the policy limits and current rate, and compare the clock summary.
4. Capture regulator state and any physical voltage measurement again.

Use the CPU-frequency driver so voltage/frequency transitions remain coordinated.
Do not use `devmem`, an arbitrary U-Boot clock command, or a PWM sysfs override.
Do not force the transition if the driver rejects it. A normal OPP transition
can change voltage too: report it as an **operating-point comparison**, not an
isolated frequency experiment.

## 6. Stress and capture failures

Keep the same CPU count, DDR, OP-TEE, userspace, peripherals and boot mode.
First check both existing diagnostic modes:

```sh
/usr/bin/ec100-exec-probe --static
/usr/bin/ec100-exec-probe
```

Stop and preserve the complete first fault report if either fails. If both pass,
run an untraced 10,000-start sample. Enter the final `echo` separately after the
loop completes to avoid serial paste concatenation:

```sh
i=0
while [ "$i" -lt 10000 ]; do
  /bin/sh -c 'exit 0' || break
  i=$((i+1))
done
```

```sh
echo "successful starts: $i"
```

Record the test duration, achieved CPU rate, voltage observations and failure
count. Repeat across several cold boots. Repeat an equivalent sample at the
verified higher operating point only if its supply configuration is established
as safe; do not deliberately restore a suspected unsafe voltage.

If the system hangs, preserve serial output and use the previously validated
SysRq procedure for task/CPU stacks. Allow the lockup detector time to report.
If neither responds, record the last attempt and recovery method. A missing
report does not mean the test passed.

## 7. Interpret conservatively

- Stable at 600 MHz, failing at the verified higher OPP: operating-point or
  timing sensitivity is implicated, but undervoltage/DDR failure is not proven.
- Both stable after restoring regulator management: the configuration change
  is implicated; confirm across cold boots and larger samples before calling it
  fixed. Timing and mapping differences can mask an intermittent failure.
- Both fail: retain the evidence and investigate DDR v1.06 versus current v1.05
  next, before choosing arbitrary DDR timings. Compare secure firmware and exact
  vendor kernel behavior afterward.
- Traced passes but untraced fails: instrumentation may change scheduling or
  memory layout. Preserve both results.

Do not claim a cache/TLB bug, glibc bug, or hardware defect solely from where a
bad pointer is consumed. Change one attributable factor at each subsequent step.
