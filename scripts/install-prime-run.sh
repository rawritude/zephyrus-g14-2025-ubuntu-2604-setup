#!/usr/bin/env bash
# Ubuntu 26.04's nvidia-prime package only ships prime-select / prime-offload /
# prime-switch / prime-supported. It does NOT ship the `prime-run` wrapper that
# the rest of the Linux gaming world documents. This installs it.
set -euo pipefail

sudo tee /usr/local/bin/prime-run >/dev/null <<'EOF'
#!/bin/sh
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia exec "$@"
EOF
sudo chmod +x /usr/local/bin/prime-run

echo
echo "Installed /usr/local/bin/prime-run. Verify with:"
echo "  prime-run glxinfo | grep 'OpenGL renderer'"
echo "Expected: NVIDIA GeForce RTX 5060 Laptop GPU/PCIe/SSE2"
