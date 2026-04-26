#!/usr/bin/env bash
# Adds the current user to video + input groups so brightnessctl works without sudo.
# Group membership only takes effect after logout/login.
set -euo pipefail

sudo usermod -aG video,input "$USER"

echo
echo "Done. Now LOG OUT and LOG BACK IN for the new groups to take effect."
echo "After login, verify with:"
echo "  groups | tr ' ' '\\n' | grep -E '^(video|input)\$'"
echo "  brightnessctl set 50%   # should succeed silently"
