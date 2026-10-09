# Local kernel patches

These patches address faults seen on the EC100 with the pinned Rockchip vendor
kernel. They are not all confirmed mainline Linux bugs.

## 0001 — Avoid an SD-card reboot crash

[Patch](0001-mmc-handle-null-vqmmc-supply.patch): the SD shutdown path tries to use
a voltage regulator that the SPI SD driver does not provide. Check for the missing
regulator instead of dereferencing it and crashing during reboot.

Upstream: [issue #563](https://github.com/armbian/linux-rockchip/issues/563), fixed
by [merged PR #564](https://github.com/armbian/linux-rockchip/pull/564). The local
patch is still needed for our pinned kernel revision.

## 0002 — Keep the Type-C port in device mode

[Patch](0002-phy-initialize-fixed-peripheral-mode.patch): the PHY can select host
mode from the ID signal even when configured as a fixed peripheral. Initialize
it as a device and prevent ID-driven host-role changes. This does not fake VBUS
presence.

Upstream: [draft PR #578](https://github.com/armbian/linux-rockchip/pull/578).
The PR contains a smaller ID-based role fix; this local patch also includes
explicit device-mode initialization and VBUS-detector error propagation.

## 0003 — Reinitialize USB after reconnect

[Patch](0003-usb-dwc2-reset-fixed-peripheral.patch): after reconnect, DWC2 can leave
EP0 (the USB control endpoint) inactive because its session-valid signal stays
low and reset handling skips reinitialization. Allow a received bus reset to
reinitialize a previously connected fixed peripheral; leave OTG behavior alone.

Reconnect tests passed with this patch, but boot-connected stalls remain a
separate observation, not necessarily a separate root cause. The proper upstream
fix may still involve PHY/session signaling.

Upstream: [draft PR #579](https://github.com/armbian/linux-rockchip/pull/579).

## 0004 — Ask the host to wait for a receive buffer (experimental)

[Patch](0004-usb-dwc2-nak-bulk-out-until-request.patch): start bulk OUT endpoints
in NAK ("not ready; retry") until a receive request is armed. This is a small
defensive candidate for the stall associated with early host traffic.

**Not a proven fix:** the candidate passed USB SSH/ping, but that boot received
bulk traffic late and did not exercise the failing early-traffic sequence.

Upstream: [draft PR #580](https://github.com/armbian/linux-rockchip/pull/580).
