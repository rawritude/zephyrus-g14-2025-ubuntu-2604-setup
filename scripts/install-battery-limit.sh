#!/usr/bin/env bash
# Caps battery charge at 80% via udev. Lower cap = longer battery lifespan
# at the cost of runtime. Edit the value below if you want a different cap.
set -euo pipefail

LIMIT="${1:-80}"

sudo tee /etc/udev/rules.d/90-battery.rules >/dev/null <<EOF
ACTION=="add", SUBSYSTEM=="power_supply", KERNEL=="BAT1", ATTR{charge_control_end_threshold}="${LIMIT}"
EOF

echo "${LIMIT}" | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold >/dev/null

sudo udevadm control --reload-rules
sudo udevadm trigger

echo
echo "Battery charge limit set to ${LIMIT}%. Verify with:"
echo "  cat /sys/class/power_supply/BAT1/charge_control_end_threshold"
echo
echo "To temporarily charge to 100% (resets on reboot):"
echo "  echo 100 | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold"
