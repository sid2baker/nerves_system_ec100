# 0.1.7-dev: restore original EC100 CPU power configuration

## Change

Restore board settings from `iotrouter/live-device-tree.dts`, not captured
runtime duty-cycle values:

- PWM0 channel 0 on `rm_io21_pwm0_ch0` (GPIO0_C5), inverse polarity, 5000 ns period.
- `vdd_arm` supplied by `vcc_sys`, 710000–1207000 uV range, 1011000 uV initial
  request, boot/always-on, 250 us upward settling time.
- CPU0 supply reference; all three CPUs retain their shared OPP table reference.
- Original four-point 600/800/1008/1200 MHz OPP table and PVTM properties.
  Replace the inherited table completely: the newer BSP adds different voltage
  bins, hardware filtering, and additional OPPs which are not in the capture.
- Enable the original TSADC needed by the PVTM thermal-zone lookup.
- Enable Rockchip cpufreq and explicitly retain required PWM/regulator/thermal
  driver support in the kernel fragment.

The default governor is explicitly `performance` to retain a 1200 MHz initial
comparison, subject to thermal limits. This is an experiment policy, **not a
claim that the original governor has been identified**. Powersave and userspace
are available for a subsequent lower-frequency test. No hard-coded runtime PWM
percentage or raw register writes are added.

Bootloader, DDR initialization, OP-TEE, userspace and partition layout are not
changed. This restores Linux board configuration; it does not make our newer
kernel's driver implementation identical to the vendor kernel. It also does not
correct an unverified pre-Linux supply state.

## Source validation

- Compiled the updated DTS against the pinned 0.1.6-dev kernel sources with their
  built dtc and external ARM toolchain. Output: `/tmp/ec100-cpu-power.dtb`.
- Compiled the original captured live DTS and compared every OPP property and
  child, and all non-phandle regulator properties: identical.
- Resolved and compared supply, CPU supply, PWM, pinctrl, NVMEM and PVTM phandle
  targets rather than comparing numeric handles: matching targets.
- Merged the kernel fragment with the existing built config and ran
  `olddefconfig`. CPU_FREQ, CPUFREQ_DT, ARM_ROCKCHIP_CPUFREQ, performance default,
  PWM_ROCKCHIP, REGULATOR_PWM, ROCKCHIP_OPP, ROCKCHIP_SYSTEM_MONITOR and
  ROCKCHIP_THERMAL all remain enabled.
- Isolated kernel compilation uses `/tmp/ec100-cpu-power-build` so the known-good
  artifact tree is not overwritten. Log: `/tmp/ec100-cpu-power-kernel-build.log`.

Source/config validation is not a hardware stability result. The isolated kernel
build is not a packaged Nerves firmware; firmware packaging and flashing remain
separate steps. Only about 11 GB disk space was free at implementation time, so
no new full Nerves artifact tree was started or old artifacts deleted.

## First board test after packaging

Use the diagnostic shell boot from the first-boot instructions, all three CPUs,
and **without `clk_ignore_unused` or `maxcpus=1`**. Do not save temporary bootargs.
Do not start stress tests until the logs show successful regulator, thermal,
PVTM and cpufreq initialization, with no dummy CPU supply or deferred probe.

Mount proc/sysfs/debugfs and capture:

```sh
cat /proc/cmdline
grep '^processor' /proc/cpuinfo
dmesg | grep -iE 'pvtm|pvtpll|cpufreq|regulator|thermal|defer'
cat /sys/kernel/debug/pwm
cat /sys/kernel/debug/regulator/regulator_summary
grep -E 'armclk|pwm0' /sys/kernel/debug/clk/clk_summary
ls /sys/devices/system/cpu/cpufreq
```

Inspect the discovered policy's available frequencies, governor, current rate,
and min/max limits. Expect only the original four frequencies, subject to BSP
runtime filtering. PWM must be owned by vdd_arm and its functional clock must
remain enabled without the unused-clock workaround. Do not require exactly
1650 ns duty: calibration, temperature and requested OPP can change the result.

If initialization is valid, run the existing static probe, then dynamic probe,
stopping at the first fault/hang. Record the complete UART output. Only afterward
make a separate supported 600 MHz operating-point comparison. Do not declare
success based on a short pass or restore arbitrary voltage/PWM values manually.
