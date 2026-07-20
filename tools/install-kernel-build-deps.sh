#!/usr/bin/env bash
# Installs the packages needed to build an Ubuntu kernel from source
# (make, menuconfig, BTF generation via pahole, module packaging, etc).
# Requires root (installs packages via apt).
set -euo pipefail

PACKAGES=(
	build-essential
	bc
	bison
	flex
	rsync
	kmod
	cpio
	fakeroot
	libssl-dev
	libelf-dev
	libncurses-dev
	libudev-dev
	libpci-dev
	libiberty-dev
	dwarves       # provides pahole, required for CONFIG_DEBUG_INFO_BTF
	git
	python3
	python3-dev
)

echo "[1/2] Updating package lists ..."
apt update

echo "[2/2] Installing kernel build dependencies ..."
apt install -y "${PACKAGES[@]}"

echo
echo "Done. Sanity-check pahole (needed for BTF) with: pahole --version"
