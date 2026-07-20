#!/usr/bin/env bash
# Prepares .config in a cloned kernel source tree for building, starting
# from the running kernel's shipped config and layering ebpf.config on top:
#   1. Back up any existing .config in the kernel source dir
#   2. Copy /boot/config-$(uname -r) into the kernel source as .config
#   3. Merge in ebpf.config via merge_config.sh -m (no auto-make/report)
#   4. Disable module signing (unsigned modules are fine for a dev VM)
#   5. Resolve new/dependent options with make olddefconfig, then verify
#      MODULE_SIG actually ended up disabled
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

if [[ -e "$KERNEL_DIR/.config" ]]; then
	BACKUP="$KERNEL_DIR/.config.bak.$$"
	echo "[1/5] Existing .config found, backing up to $BACKUP ..."
	cp "$KERNEL_DIR/.config" "$BACKUP"
else
	echo "[1/5] No existing .config in $KERNEL_DIR."
fi

echo "[2/5] Copying /boot/config-$(uname -r) into $KERNEL_DIR/.config ..."
cp "/boot/config-$(uname -r)" "$KERNEL_DIR/.config"

echo "[3/5] Merging $EBPF_CONFIG ..."
( cd "$KERNEL_DIR" && ./scripts/kconfig/merge_config.sh -m .config "$EBPF_CONFIG" )

echo "[4/5] Disabling module signing (unsigned modules are fine for a dev VM) ..."
# SECURITY_LOCKDOWN_LSM does "select MODULE_SIG if MODULES", so disabling
# MODULE_SIG alone gets silently reverted by olddefconfig below. Disable the
# selector too, and clear the Canonical key paths that would otherwise make the
# build demand a signing cert we don't have.
( cd "$KERNEL_DIR" && ./scripts/config \
	--disable SECURITY_LOCKDOWN_LSM \
	--disable SECURITY_LOCKDOWN_LSM_EARLY \
	--disable MODULE_SIG \
	--disable MODULE_SIG_ALL \
	--disable MODULE_SIG_FORCE \
	--set-str SYSTEM_TRUSTED_KEYS "" \
	--set-str SYSTEM_REVOCATION_KEYS "" )

echo "[5/5] Resolving dependent options with make olddefconfig ..."
( cd "$KERNEL_DIR" && make olddefconfig )

# Re-check after olddefconfig: a leftover "select MODULE_SIG" (e.g. lockdown
# LSM sneaking back in) would flip signing on again here, not at the config step.
if grep -q '^CONFIG_MODULE_SIG=y' "$KERNEL_DIR/.config"; then
	echo "error: CONFIG_MODULE_SIG is still enabled in $KERNEL_DIR/.config after olddefconfig" >&2
	echo "       something still selects it — check: grep -rn 'select MODULE_SIG' $KERNEL_DIR --include=Kconfig" >&2
	exit 1
fi
if grep -q '^CONFIG_SECURITY_LOCKDOWN_LSM=y' "$KERNEL_DIR/.config"; then
	echo "error: CONFIG_SECURITY_LOCKDOWN_LSM is still enabled — it will re-select MODULE_SIG" >&2
	exit 1
fi

echo
echo "Done. .config is ready in $KERNEL_DIR (module signing disabled)."
