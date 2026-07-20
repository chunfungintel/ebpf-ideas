#!/usr/bin/env bash
# Detaches and removes the pinned execsnoop BPF programs.
set -euo pipefail

PIN_DIR="/sys/fs/bpf/execsnoop"

if [[ ! -e "$PIN_DIR" ]]; then
	echo "nothing pinned at $PIN_DIR"
	exit 0
fi

echo "Removing pinned programs at $PIN_DIR ..."
rm -rf "$PIN_DIR"
echo "Done."
