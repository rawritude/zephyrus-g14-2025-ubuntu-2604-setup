#!/usr/bin/env bash
# Sets up one-shot system tweaks when GNOME power profile changes.
# - Triggers on power-profile transitions; does not enforce afterward.
# - power-saver: BT off, brightness cap 50%, kbd backlight off, 60Hz
# - balanced/performance: BT on, kbd backlight medium, 120Hz, brightness untouched
set -euo pipefail

echo "==> Installing brightnessctl (sudo prompt)"
sudo apt install -y brightnessctl

echo "==> Creating directories"
mkdir -p "$HOME/bin" "$HOME/.config/systemd/user"

echo "==> Writing apply script"
cat > "$HOME/bin/power-profile-apply.sh" <<'APPLY_EOF'
#!/usr/bin/env bash
# One-shot tweaks on power-profile transition. Not enforced.
set -uo pipefail

profile="${1:-$(powerprofilesctl get)}"
logger -t power-profile "transition -> $profile"

case "$profile" in
    power-saver)
        rfkill block bluetooth >/dev/null 2>&1 || true

        cur=$(brightnessctl -d amdgpu_bl2 g 2>/dev/null || echo 0)
        max=$(brightnessctl -d amdgpu_bl2 m 2>/dev/null || echo 1)
        if [[ "$max" -gt 0 ]] && (( cur * 100 / max > 50 )); then
            brightnessctl -d amdgpu_bl2 set 50% >/dev/null
        fi

        brightnessctl -d 'asus::kbd_backlight' set 0 >/dev/null 2>&1 || true

        gdctl set --persistent --logical-monitor --primary \
            --monitor eDP-1 --mode 2880x1800@60.001 --scale 1.6666666269302368 \
            >/dev/null 2>&1 || true
        ;;
    balanced|performance)
        rfkill unblock bluetooth >/dev/null 2>&1 || true
        bluetoothctl power on >/dev/null 2>&1 || true

        brightnessctl -d 'asus::kbd_backlight' set 1 >/dev/null 2>&1 || true

        gdctl set --persistent --logical-monitor --primary \
            --monitor eDP-1 --mode 2880x1800@120.000 --scale 1.6666666269302368 \
            >/dev/null 2>&1 || true
        ;;
esac
APPLY_EOF
chmod +x "$HOME/bin/power-profile-apply.sh"

echo "==> Writing watcher script"
cat > "$HOME/bin/power-profile-watcher.sh" <<'WATCH_EOF'
#!/usr/bin/env bash
# Watches the GNOME power profile and calls apply on each change.
exec gdbus monitor --system \
    --dest org.freedesktop.UPower.PowerProfiles \
    --object-path /org/freedesktop/UPower/PowerProfiles 2>/dev/null \
    | while read -r line; do
        if [[ "$line" == *"ActiveProfile"* ]]; then
            sleep 0.3
            "$HOME/bin/power-profile-apply.sh"
        fi
    done
WATCH_EOF
chmod +x "$HOME/bin/power-profile-watcher.sh"

echo "==> Writing systemd user service"
cat > "$HOME/.config/systemd/user/power-profile-watcher.service" <<'UNIT_EOF'
[Unit]
Description=Apply per-power-profile system tweaks on changes
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/bin/power-profile-watcher.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT_EOF

echo "==> Enabling and starting service"
systemctl --user daemon-reload
systemctl --user enable --now power-profile-watcher.service

echo
echo "==> Status"
systemctl --user --no-pager status power-profile-watcher.service | head -12

cat <<MSG

Setup complete.

Manual test (without changing the profile):
  ~/bin/power-profile-apply.sh power-saver
  ~/bin/power-profile-apply.sh balanced

Real test:
  Click the system menu (top-right) and switch power profiles.
  You should see refresh-rate flicker, BT toggle, keyboard backlight
  change, and brightness capped only when entering power-saver from a
  higher level.

Logs:
  journalctl --user -u power-profile-watcher.service -f
  journalctl -t power-profile -f

Uninstall:
  systemctl --user disable --now power-profile-watcher.service
  rm ~/bin/power-profile-apply.sh ~/bin/power-profile-watcher.sh
  rm ~/.config/systemd/user/power-profile-watcher.service
  systemctl --user daemon-reload
MSG
