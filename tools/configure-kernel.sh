#!/usr/bin/env bash
# Prepares .config in a cloned kernel source tree for building, starting
# from the running kernel's shipped config and layering ebpf.config on top:
#   1. Copy /boot/config-$(uname -r) into the kernel source as .config
#   2. Merge in ebpf.config via merge_config.sh -m (no auto-make/report)
#   3. Disable module signing (unsigned modules are fine for a dev VM)
#   4. Resolve new/dependent options with make olddefconfig
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EBPF_CONFIG="$SCRIPT_DIR/../ebpf.config"

usage() {
	cat <<EOF
Usage: $0 [kernel-src-dir]

  kernel-src-dir  Path to the cloned kernel source tree
                  (default: ./ubuntu-<codename>, matching clone-ubuntu-kernel.sh)

Example:
  $0
  $0 ~/src/ubuntu-noble
EOF
	exit 1
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

KERNEL_DIR="${1:-./ubuntu-$(lsb_release -cs)}"

[[ -d "$KERNEL_DIR" ]] || { echo "error: kernel source dir not found: $KERNEL_DIR" >&2; exit 1; }
[[ -x "$KERNEL_DIR/scripts/kconfig/merge_config.sh" ]] || { echo "error: $KERNEL_DIR doesn't look like a kernel source tree (missing scripts/kconfig/merge_config.sh)" >&2; exit 1; }
[[ -r "$EBPF_CONFIG" ]] || { echo "error: ebpf.config not found at $EBPF_CONFIG" >&2; exit 1; }
[[ -r "/boot/config-$(uname -r)" ]] || { echo "error: /boot/config-$(uname -r) not found" >&2; exit 1; }

echo "[1/3] Copying /boot/config-$(uname -r) into $KERNEL_DIR/.config ..."
cp "/boot/config-$(uname -r)" "$KERNEL_DIR/.config"

echo "[2/4] Merging $EBPF_CONFIG ..."
( cd "$KERNEL_DIR" && ./scripts/kconfig/merge_config.sh -m .config "$EBPF_CONFIG" )

echo "[3/4] Disabling module signing (unsigned modules are fine for a dev VM) ..."
( cd "$KERNEL_DIR" && ./scripts/config --disable MODULE_SIG )

echo "[4/4] Resolving dependent options with make olddefconfig ..."
( cd "$KERNEL_DIR" && make olddefconfig )

echo
echo "Done. .config is ready in $KERNEL_DIR."
