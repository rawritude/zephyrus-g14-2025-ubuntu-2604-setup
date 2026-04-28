# ASUS ROG Zephyrus G14 (2025, GA403WM) on Ubuntu 26.04 LTS — Setup Guide

A working setup for the 2025 G14 (Ryzen AI 9 HX 370 + RTX 5060 Mobile) on **Ubuntu 26.04 LTS "Resolute Raccoon"**, GNOME on Wayland, kernel 7.0. No third-party PPAs, no fighting installers, native kernel interfaces wherever possible.

This is a snapshot of what I actually did, not a wishlist. Each section explains the **decision** (why this path vs. the alternative) so you can swap in your own preference where it matters.

All scripts referenced live in `scripts/`. Read them before running — they touch udev, sudoers-adjacent things, and systemd user services.

---

## 0. Before you install: do these in Windows first

The G14 ships with Windows 11. Three Windows-side things will bite you if you skip them — do these **before** booting the Ubuntu installer USB.

### 0a. Suspend or disable BitLocker

Modern Windows 11 silently enables Device Encryption (BitLocker variant) tied to your TPM + boot config. If you change boot settings (Secure Boot, boot order) or partition the drive without first turning it off, **Windows will demand the recovery key on next boot** — which you may not have if you signed in with a local account.

- Settings → Privacy & Security → **Device encryption** → toggle **Off**, **OR**
- Control Panel → System and Security → **BitLocker Drive Encryption** → **Turn off BitLocker**

Wait for decryption to finish (status visible in the same panel — can take an hour-plus on a 1TB SSD). Don't reboot mid-decryption.

If you plan to keep Windows around dual-boot, you can re-enable it after Ubuntu is set up. If you're going Linux-only, just leave it off — you're about to wipe the partition anyway.

### 0b. Disable Fast Startup

Windows "Fast Startup" is hibernation-disguised-as-shutdown. It leaves the NTFS filesystem in a dirty state and the firmware in a hybrid state that confuses dual-boot setups and sometimes the Ubuntu installer's partition tools.

- Control Panel → Hardware and Sound → **Power Options** → **Choose what the power buttons do** → **Change settings that are currently unavailable** → uncheck **Turn on fast startup (recommended)** → Save changes.
- Then **Shift + click Restart** (or `shutdown /s /t 0` from cmd) to do a real cold shutdown before booting the installer.

### 0c. Disable Secure Boot in BIOS

You can re-enable Secure Boot **after** Ubuntu is installed — but it's much easier to start with it off and turn it back on once everything works.

1. Power off fully.
2. Hold **F2** while pressing power to enter BIOS (on some BIOS revisions: tap **F2** or **Delete** during the ASUS logo).
3. Press **F7** for Advanced Mode if you're in EZ Mode.
4. **Boot** tab → **Secure Boot** → **OS Type: Other OS** (or set Secure Boot to Disabled directly, depending on BIOS version).
5. **Save & Exit** (F10).

**Why turn it off first:** the installer is simpler, and the proprietary NVIDIA driver kernel modules aren't signed by a trusted key out of the box — with Secure Boot on, NVIDIA modules silently fail to load and you get llvmpipe / no dGPU until you fix it.

**Re-enabling Secure Boot afterwards (optional):**
- Ubuntu's `shim` is signed by Microsoft, so the bootloader itself works under Secure Boot.
- The unsigned NVIDIA modules need a Machine Owner Key (MOK) you enroll yourself: `sudo apt install -y mokutil` then follow the `mokutil --import` ceremony, reboot, complete enrollment in the blue MOK Manager screen.
- After successful re-enable, verify NVIDIA modules still load: `lsmod | grep nvidia`. If they don't, drop SB back to Disabled — it's not worth losing the dGPU over.

### 0d. (Optional) Decide your partition layout in advance

- **Linux-only:** the installer's "Erase disk and install Ubuntu" is fine.
- **Dual-boot:** shrink the C: partition from inside Windows first (Disk Management → right-click C: → Shrink Volume). Don't let the Ubuntu installer resize NTFS for you — it works but is one more thing that can go sideways. Leave 200GB+ free for Ubuntu.

### 0e. Decide on full-disk encryption now (one-shot decision)

The Ubuntu installer offers LUKS full-disk encryption during partitioning. **It's effectively a one-shot decision** — there's no clean "turn it on later" path; retrofitting LUKS to a live install means back up, wipe, reinstall, restore. If you might want FDE on a laptop you ever travel with, tick the box during install. Post-install you can still encrypt specific directories with `fscrypt` or `gocryptfs`, but that's not equivalent to FDE.

This guide doesn't cover the encryption decision in either direction — pick what fits your threat model.

### 0f. Make the installer USB

- Download Ubuntu 26.04 LTS desktop ISO from ubuntu.com.
- Flash with **Ventoy** (multi-ISO, easiest) or **Rufus** (single-ISO, dead simple). Ventoy lets you keep multiple ISOs on one stick for re-flashes.
- Boot menu key on the G14: **F2** for BIOS or **Esc** for the one-time boot menu (during ASUS logo).

You're good to install.

---

## 1. Hardware confirmed working (after install)

| Component | Status |
|---|---|
| AMD Ryzen AI 9 HX 370 (Strix Point, 12C/24T) | OOTB (`amd_pstate` active) |
| NVIDIA RTX 5060 Mobile (Blackwell, GB206) | OOTB with NVIDIA 595.58.03 |
| Radeon 890M iGPU | OOTB |
| MediaTek MT7925 WiFi 7 | OOTB — driver `mt7925e` binds, WiFi 7 (EHT-MCS) rates negotiate |
| Bluetooth | OOTB (verified via `bluetoothctl power on`) |
| Display 2880x1800 @ 120Hz (eDP-1) | OOTB |
| Keyboard backlight | OOTB via sysfs / `brightnessctl` |
| Battery charge limit sysfs | OOTB (`/sys/class/power_supply/BAT1/charge_control_end_threshold`) |
| Custom fan curves interface | OOTB (`asus_custom_fan_curve` attrs in `/sys/class/hwmon/`) — interface present; we didn't configure one |
| Webcam (USB2.0 FHD UVC) | Detected via `lsusb` — capture not tested |
| Audio | Not tested in this setup pass — but PipeWire is default and shows the speakers |
| VRR / FreeSync on internal panel | Not exposed (`vrr_capable` empty) — not a fault, common on AMD APU + OLED eDP |
| Fingerprint reader | Not present on this SKU |

---

## 2. The big decision: skip `asusctl`/`supergfxctl`, use the kernel directly

This is the most opinionated call in the guide. **You can go either way** — both work — but pick consciously.

### My choice: native kernel interfaces only

Kernel 7.0 already exposes almost everything the asus-linux tools wrap:

| Feature | Native interface |
|---|---|
| Performance profile (silent/balanced/performance) | `power-profiles-daemon` ↔ `/sys/.../platform_profile` |
| Battery charge limit | `/sys/class/power_supply/BAT1/charge_control_end_threshold` |
| Custom fan curves | `/sys/class/hwmon/hwmon*/` whose `name` is `asus` (`asus_custom_fan_curve` attrs) |
| GPU MUX / dGPU disable / TGP / dynamic boost | `/sys/class/firmware-attributes/asus-armoury/attributes/` |
| Keyboard backlight | `brightnessctl -d 'asus::kbd_backlight'` |

**Why I went this way (April 2026):**
- The asus-linux PPA hadn't shipped a `resolute` series yet (404/403 on the repo).
- Building from source meant stacking three bleeding-edge things at once: kernel 7.0 + NVIDIA 595 + asusctl-from-git. Too many unknowns at once.
- I don't need live RGB animations or one-shot MUX toggling enough to justify it.

**What I lose:** live per-key RGB, the polished `asusctl` CLI, and `supergfxctl mode integrated/hybrid/dedicated` as a one-liner. MUX switching still works — it's just a sysfs write + reboot.

### Alternative path: install asus-linux

If you want asusctl/supergfxctl/ROG Control Center, the upstream instructions are at https://asus-linux.org/guides/. Once a `resolute` PPA lands you can do roughly:

```bash
# Check first — this didn't exist when I wrote this guide.
curl -fsI https://ppa.launchpadcontent.net/asus-linux/stable/ubuntu/dists/resolute/

# If that 200s, then:
sudo add-apt-repository ppa:asus-linux/stable
sudo apt update
sudo apt install asusctl supergfxctl
sudo systemctl enable --now supergfxd
```

Until then, the only realistic options are: (a) skip them (this guide), (b) use a different distro for asus-linux (Fedora/Bazzite have first-class support), or (c) build from source and accept the maintenance burden. I would not recommend (c) on a fresh install.

---

## 3. Drivers / firmware

Nothing to do here — Ubuntu 26.04 ships everything you need:

```bash
# Verify NVIDIA
nvidia-smi                       # should show RTX 5060 Laptop GPU, driver 595.x
lsmod | grep nvidia              # nvidia, nvidia_modeset, nvidia_drm, nvidia_uvm

# Verify WiFi
lspci -k | grep -A3 -i mediatek  # mt7925e driver bound

# Firmware updates
fwupdmgr refresh
fwupdmgr get-updates
```

**Heads up:** NVIDIA 595 is new enough that Flathub's NVIDIA runtime extension may lag. Apps installed via apt use system libs and Just Work; some Flatpak apps may fall back to llvmpipe (software) until Flathub catches up.

---

## 4. Battery: charger-aware charge limit

The 2025 G14 dropped USB-C passthrough charging that the 2024 GA403 had. The 240W **barrel charger** does battery bypass — when plugged in via barrel, the system runs from AC and the battery isn't being cycled. The **USB-C** ports do *not* bypass; the battery stays in the circuit and gets topped off constantly. This is a hardware design choice (not a Linux bug, not fixed by BIOS so far — Windows users have the same complaint).

That asymmetry means a flat charge cap is leaving runtime on the table. The installer below sets up a **charger-aware** policy:

| Charger plugged in | Charge limit |
|---|---|
| Barrel | 100% (battery bypass anyway, full charge is fine) |
| USB-C | 80% (battery in circuit, cap to limit cycle wear) |
| Nothing | 80% (cosmetic; only kicks in when next charger appears) |

```bash
bash scripts/install-battery-limit.sh           # 80 on USB-C, 100 on barrel  (recommended)
bash scripts/install-battery-limit.sh 70        # 70 on USB-C, 100 on barrel
bash scripts/install-battery-limit.sh 80 80     # static 80% — no boost on barrel
bash scripts/install-battery-limit.sh 100 100   # effectively disable the cap
```

How it works: a small policy script in `/usr/local/bin/battery-charge-policy` reads `/sys/class/power_supply/ACAD/online` and writes the appropriate value to `/sys/class/power_supply/BAT1/charge_control_end_threshold`. A udev rule (`/etc/udev/rules.d/90-battery.rules`) runs the script whenever a Mains or USB power supply enters/leaves the system. Logs land in `journalctl -t battery-charge-policy`.

The G14 GA403WM exposes its battery as `BAT1` — confirm with `ls /sys/class/power_supply/` before running. If yours is `BAT0`, edit the generated `/usr/local/bin/battery-charge-policy`.

To temporarily charge past the current limit for a flight without uninstalling:

```bash
echo 100 | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold
```

The next charger plug/unplug event will reset to the policy value. If your battery later "won't charge past 80%" on USB-C — it's this rule, not a fault.

### Expected battery life with this setup

For reference (numbers from a months-old GA403WM at 99% battery health, 80% cap = ~58 Wh usable from full):

| Workload | Draw | Runtime from full (80% cap) |
|---|---|---|
| Idle / light browsing, power-saver mode, 60Hz, ~50% brightness | ~7–8 W | **~7 hours** |
| Productivity (editor + browser + chat), balanced, 120Hz | ~10–15 W | ~4–5 hours |
| Heavy multitasking / iGPU 3D / video calls | ~20–25 W | ~2–2.5 hours |
| Gaming on dGPU (`prime-run`) | 35–50 W+ | <1.5 hours — barrel charger recommended |

The big multipliers are **refresh rate** (60Hz vs 120Hz can be 2–3W on its own), **brightness** (cheapest power dial there is on an OLED), and **whether the dGPU is awake**. The power-profile automation in section 6 nudges all three at once when you switch to power-saver; that's where most of the "I got 7+ hours" comes from.

If you see idle draw above ~12W with the lid open and nothing running, something is keeping the dGPU on or a process is busy-waiting. Check `nvidia-smi` (should show no running processes) and `top` / `htop`.

---

## 5. Brightness + keyboard backlight without sudo

`brightnessctl` needs `video` + `input` group membership to work without sudo.

```bash
sudo apt install -y brightnessctl
bash scripts/fix-brightness-perms.sh
# then LOG OUT and LOG BACK IN
```

After that:

```bash
brightnessctl --list                              # find your device names
brightnessctl -d amdgpu_bl2 set 50%               # display (name may differ)
brightnessctl -d 'asus::kbd_backlight' set 1      # keyboard (0..3)
```

The display backlight device on this G14 is usually `amdgpu_bl2`, but the suffix can be `_bl0`/`_bl1`/`_bl2` depending on enumeration order — `brightnessctl --list` will show what's actually present.

Note: this G14 has no ambient light sensor (no `ACPI0008`), so there's no auto-brightness to enable.

---

## 6. Power profile automation (optional but nice)

GNOME's power profile menu has three modes: power-saver / balanced / performance. By default it only changes the platform profile. I wanted profile changes to also one-shot a few things:

- **power-saver** → Bluetooth off, display brightness capped at 50% (only if higher), keyboard backlight off, refresh rate → 60Hz
- **balanced / performance** → Bluetooth on, keyboard backlight medium, refresh rate → 120Hz, brightness untouched

Crucially, these are **one-shot**, not enforced. If I switch to power-saver and then bump brightness back up, it stays up. The script only fires on profile transitions.

```bash
bash scripts/setup-power-automation.sh
```

This:
1. Installs `brightnessctl`
2. Drops two scripts into `~/bin/` (`power-profile-apply.sh`, `power-profile-watcher.sh`)
3. Installs and starts a **user** systemd service (`power-profile-watcher.service`) that monitors UPower DBus for profile changes

**Manual test (without changing profile):**
```bash
~/bin/power-profile-apply.sh power-saver
~/bin/power-profile-apply.sh balanced
```

**Logs:**
```bash
journalctl -t power-profile -f
journalctl --user -u power-profile-watcher.service -f
```

**Tweaking it:** the per-profile actions are inside `~/bin/power-profile-apply.sh` — edit it directly. The refresh-rate change uses `gdctl` (GNOME's display control). The mode strings (`2880x1800@60.001`, `2880x1800@120.000`, `--scale 1.6666666269302368`) are hardcoded for the GA403WM's stock OLED panel and should match for any same-SKU G14. If your panel differs, run `gdctl show` to see available modes and edit the script.

**Uninstall:**
```bash
systemctl --user disable --now power-profile-watcher.service
rm ~/bin/power-profile-apply.sh ~/bin/power-profile-watcher.sh
rm ~/.config/systemd/user/power-profile-watcher.service
systemctl --user daemon-reload
```

---

## 7. OLED panel protections

The GA403WM ships with a 3K OLED panel. Linux has **no equivalent of Windows' pixel-shift / panel-refresh routines** — the panel's own firmware does some compensation, but you don't get the OS-level extras Armoury Crate gives you on Windows. Mitigation is "reduce static UI + reduce time at high brightness."

Three knobs do most of the work:

### 7a. Lower idle brightness

Brightness is the single biggest factor in OLED wear — running at 50% roughly doubles panel life vs. 80%. Use **Fn+F7 / Fn+F8** or the Quick Settings slider; aim for ~50% indoors. The power-profile automation in section 6 caps brightness at 50% when you switch to power-saver, which helps if you forget.

### 7b. Faster screen blank

```bash
gsettings set org.gnome.desktop.session idle-delay 180   # 3 minutes
gsettings set org.gnome.desktop.screensaver lock-enabled true
```

Three minutes is the OLED-friendly default — typical thinking pauses are under 2 min so it rarely fires during real work. If you read long articles often, 5 min is fine; just lower brightness more.

### 7c. Hide the top bar + auto-hide the dock

The persistent top bar (clock, indicators) and dock are the two biggest static-UI burn-in risks. Hide them.

**Install Extension Manager** (the GUI for browsing and installing GNOME extensions — Ubuntu doesn't ship it by default):

```bash
sudo apt install -y gnome-shell-extension-manager
```

**Top bar — hide via *Just Perfection*:**

1. Open **Extension Manager** → **Browse** tab.
2. Search for **Just Perfection**, click Install.
3. Switch to **Installed** tab → gear icon next to Just Perfection → **Visibility** → toggle **Panel** off.
4. The top bar is now gone except in the Activities overview (Super key).

The toggle is labeled **Panel**, not "Top Bar" — that one threw me. There's also a separate per-element section (Activities button, App menu, etc.) if you'd rather keep the bar but strip it down.

**Alternative for slide-in-on-hover behavior:** install **Hide Top Bar** instead of (or alongside) Just Perfection — it behaves like a macOS menu bar, auto-showing when you hit the top edge.

**Dock — auto-hide instead of always-visible:**

Ubuntu 26.04 ships GNOME's Dash-to-Dock variant by default. Set it to auto-hide:

```bash
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
```

`dock-fixed false` is the auto-hide toggle; `intellihide` makes it stay visible until a window actually overlaps it (more pleasant than aggressive auto-hide).

### 7d. Show battery percentage in the top bar

Counter-intuitively this *helps* — you stop hovering over the same static battery icon trying to gauge level, and the percentage text rotates often enough that no single subpixel sees long static load:

```bash
gsettings set org.gnome.desktop.interface show-battery-percentage true
```

### 7e. Use Dark mode

Settings → Appearance → **Dark**. Dark backgrounds = many subpixels emitting nothing = less wear and less heat. The whole desktop running dark is the cheapest OLED win there is.

---

## 8. Gaming setup

Steam, Proton-GE, MangoHud, GameMode, dGPU offload, launch options.

### 8a. Steam from apt (not snap)

```bash
sudo apt install -y steam mangohud gamemode gamescope protontricks
```

The snap version of Steam is sandboxed and notoriously fights with NVIDIA on Wayland — apt is the path that works without ceremony. Steam library lives at `~/.local/share/Steam/`.

### 8b. The missing `prime-run` wrapper

Ubuntu 26.04's `nvidia-prime` package ships `prime-select`, `prime-offload`, `prime-switch`, `prime-supported`, but **not** `prime-run` — which is what every Linux gaming guide on the internet tells you to use. Install the wrapper manually:

```bash
bash scripts/install-prime-run.sh
```

That writes `/usr/local/bin/prime-run` containing:

```sh
#!/bin/sh
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia exec "$@"
```

Verify:
```bash
prime-run glxinfo | grep "OpenGL renderer"
# OpenGL renderer string: NVIDIA GeForce RTX 5060 Laptop GPU/PCIe/SSE2
```

Without `prime-run`, apps render on the Radeon 890M iGPU. With it, they render on the RTX 5060.

### 8c. Proton-GE via ProtonUp-Qt (Flatpak)

If you've never used Flatpak on this install, add the Flathub remote first:

```bash
sudo apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

Then:

```bash
flatpak install -y flathub net.davidotek.pupgui2
flatpak run net.davidotek.pupgui2
```

Inside ProtonUp-Qt → choose Steam → install latest `GE-Proton`. **Fully restart Steam** afterwards or the new Proton version won't appear in the per-game compatibility dropdown.

### 8d. Steam launch options — the cheat sheet

Per game: Properties → General → Launch Options. One line. Steam substitutes `%command%` with the actual game executable.

**Format:** `[ENV_VARS] [wrapper1] [wrapper2] [wrapper3] %command% [game args]`

Wrappers chain right-to-left. Env vars before wrappers. Game args after `%command%`.

| Game type | Launch options |
|---|---|
| AAA / demanding 3D | `gamemoderun mangohud prime-run %command%` |
| Medium 3D, Proton (Windows-only) | `mangohud prime-run %command%` |
| Medium 3D, native Linux | `mangohud %command%` (try iGPU first) |
| Light / 2D / indie | blank, or `mangohud %command%` |
| Troubleshooting | `PROTON_LOG=1 gamemoderun mangohud prime-run %command%` (writes `~/steam-<appid>.log`) |

**Wrappers:**
- `prime-run` — runs on dGPU (RTX 5060). Without it, runs on iGPU (Radeon 890M).
- `mangohud` — overlay (FPS/CPU/GPU/temps/RAM). Toggle: **Right Shift + F12**.
- `gamemoderun` — Feral GameMode: pins CPU governor to performance, raises I/O priority, inhibits screensaver.

**Useful env vars:**
- `MANGOHUD_CONFIG=fps,gpu_temp,cpu_temp,ram` — pick what shows in MangoHud
- `DXVK_HUD=fps,memory,gpuload` — DXVK's built-in overlay
- `PROTON_LOG=1` — verbose log to `~/steam-<appid>.log`
- `WINEDEBUG=-all` — silence Wine spam, occasionally a small perf win
- `PROTON_USE_WINED3D=1` — fall back to OpenGL (debug only, almost never needed)

**Game arguments go AFTER `%command%`:**
```
prime-run %command% -windowed -nosplash
```

**Don't:**
- wrap the whole thing in quotes
- omit `%command%`
- use shell operators (`&&`, `;`) — Steam parses one command line, not a shell

### 8e. `gamemoderun` on battery — pick your spot

GameMode pins the CPU governor to `performance`. That roughly **doubles idle CPU power draw** on this chip. Worth it for AAA / CPU-bound games where you're already burning watts. Wasted on a 2D indie capping at 240fps. I leave it off for light games on battery.

### 8f. Cloud saves: Linux native vs. Proton are separate buckets

This bit me with Vampire Survivors. **Linux native Steam apps and Windows-via-Proton use separate Steam Cloud save buckets per game.** Switching a game from Linux-native to Proton (Properties → Compatibility → "Force the use of a specific Steam Play compatibility tool") will pull the **Windows** cloud saves, not the Linux ones. Pick one, stick with it per game, or accept that you'll need to manually move saves once.

---

## 9. System tweaks worth doing

### 9a. Standard tooling

```bash
sudo apt install -y \
    build-essential git vim htop tmux gh unzip gnome-tweaks
```

GNOME Tweaks unlocks per-key keyboard remapping, font scaling, and window behavior toggles that aren't in Settings.

### 9b. Lower swappiness (16GB RAM + NVMe)

Default `vm.swappiness=60` is tuned for spinning disks and tight RAM. On 16GB + a Micron NVMe, drop it to 10: less SSD wear, more responsive under memory pressure.

```bash
sudo sysctl -w vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
```

Verify after reboot: `sysctl vm.swappiness` → `10`.

### 9c. Set WiFi regulatory domain explicitly

The MT7925 supports WiFi 7 / 6GHz, but 6GHz channels are gated by regulatory domain. The kernel's default user-set domain is `00` ("worldwide") and rules get inferred from AP beacons — fine on a normal WiFi 6 router, but some 6GHz APs require an explicit country code to associate.

Replace `CA` below with your two-letter country code (`US`, `GB`, `DE`, etc.):

```bash
sudo iw reg set CA
echo 'options cfg80211 ieee80211_regdom=CA' | sudo tee /etc/modprobe.d/cfg80211.conf
```

The first line takes effect immediately; the second line persists across reboots by setting it as a kernel-module parameter (loaded before WiFi comes up).

Verify: `iw reg get` → `country CA: ...`.

### 9d. Auto-security-updates

Ubuntu installs `unattended-upgrades` by default but only the security pocket is enabled. If you want to be sure it's running:

```bash
sudo dpkg-reconfigure -plow unattended-upgrades
```

Pick "Yes" to enable. Logs land in `/var/log/unattended-upgrades/`.

---

## 10. Gotchas worth knowing about

### sudo-rs is the default `sudo` on 26.04

Ubuntu 26.04 ships **sudo-rs** (Rust rewrite, version 0.2.13), not the original C sudo. For day-to-day use it's identical, but a few things differ:

- `Defaults timestamp_type=global` is **not implemented** — sudo-rs uses per-tty credential caching with no global override. So `sudo -v` in one terminal does **not** carry over to a second terminal session.
- Some `Defaults` options from the C sudo's man page are silently ignored.
- Validate any `/etc/sudoers.d/*` file with `sudo visudo -c` after writing — sudo-rs sometimes accepts-with-warning rather than failing closed.

If you script things that need passwordless sudo, write a narrow `NOPASSWD` entry for the specific binary in `/etc/sudoers.d/`, don't rely on credential cache sharing.

### Flathub NVIDIA runtime can lag the apt driver

If a Flatpak app (e.g., a game launcher) shows software rendering / `llvmpipe`, that's because the Flathub NVIDIA runtime extension hasn't matched 595.x yet. Apt-installed Steam/games are unaffected because they use system libs directly.

### MUX / dGPU disable without supergfxctl

Look at `/sys/class/firmware-attributes/asus-armoury/attributes/` — the relevant attributes are there (e.g., `gpu_mux_mode`, `dgpu_disable`). Read them first to see current values and acceptable enumerated options:

```bash
ls /sys/class/firmware-attributes/asus-armoury/attributes/
cat /sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/possible_values
cat /sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value
```

Writes generally need root and a reboot to take effect. Don't blindly `echo` values you haven't read out of `possible_values` first.

---

## 11. Run-order TL;DR

For someone copying this guide on a fresh 26.04 install, do it in this order:

```bash
# 1. Standard tooling
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y build-essential git vim htop tmux gh unzip gnome-tweaks \
                    brightnessctl flatpak

# 2. System tweaks (swappiness + WiFi reg domain — replace CA with your country code)
sudo sysctl -w vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo iw reg set CA
echo 'options cfg80211 ieee80211_regdom=CA' | sudo tee /etc/modprobe.d/cfg80211.conf

# 3. Brightness perms (then log out/in)
bash scripts/fix-brightness-perms.sh

# 4. Battery cap (charger-aware: 80% on USB-C, 100% on barrel)
bash scripts/install-battery-limit.sh

# 5. Power profile automation
bash scripts/setup-power-automation.sh

# 6. OLED protections
gsettings set org.gnome.desktop.session idle-delay 180
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
sudo apt install -y gnome-shell-extension-manager
# Then open Extension Manager, install "Just Perfection",
# Visibility tab → toggle "Panel" off (hides the top bar).
# And switch the desktop to Dark mode (Settings → Appearance).

# 7. Gaming
sudo apt install -y steam mangohud gamemode gamescope protontricks
bash scripts/install-prime-run.sh
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub net.davidotek.pupgui2
# Then run ProtonUp-Qt to grab GE-Proton, restart Steam.
```

That's it. Everything in this guide is reversible — the udev rule, the user-level systemd service, the sysfs writes — none of it touches anything Ubuntu's package manager won't happily overwrite on the next dist-upgrade.

---

## Files in this folder

```
README.md                              this guide
scripts/install-battery-limit.sh       Charger-aware battery charge policy via udev
scripts/install-prime-run.sh           dGPU offload wrapper
scripts/fix-brightness-perms.sh        brightnessctl group fix
scripts/setup-power-automation.sh      one-shot per-profile system tweaks
```

Happy to take corrections / additions in the comments. Especially curious if anyone has tried the asus-linux PPA on resolute since I wrote this.
