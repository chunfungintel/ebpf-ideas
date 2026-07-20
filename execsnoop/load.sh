#!/usr/bin/env bash
# Loads and attaches execsnoop.bpf.o using bpftool, pinning it to the BPF
# filesystem so it stays attached after this script exits.
# Requires root (loading BPF programs is a privileged operation).
set -euo pipefail
cd "$(dirname "$0")"

PIN_DIR="/sys/fs/bpf/execsnoop"
OBJ="execsnoop.bpf.o"

if [[ ! -f "$OBJ" ]]; then
	echo "error: $OBJ not found, run ./build.sh first" >&2
	exit 1
fi

if [[ -e "$PIN_DIR" ]]; then
	echo "error: $PIN_DIR already exists, run ./unload.sh first" >&2
	exit 1
fi

echo "[1/2] Loading and attaching $OBJ (pinned at $PIN_DIR) ..."
bpftool prog loadall "$OBJ" "$PIN_DIR" autoattach

echo "[2/2] Attached programs:"
bpftool prog show pinned "$PIN_DIR/handle_exec"

echo
echo "Now watch events with:"
echo "  sudo cat /sys/kernel/debug/tracing/trace_pipe"
echo "or:"
echo "  sudo bpftool prog tracelog"
echo
echo "When done, detach with: sudo ./unload.sh"
