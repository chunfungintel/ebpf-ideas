#!/usr/bin/env bash
# Compiles execsnoop.bpf.c into a loadable BPF object.
# Regenerates vmlinux.h from the running kernel's BTF, since the CO-RE
# types used in execsnoop.bpf.c must match this machine's kernel.
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/2] Generating vmlinux.h from /sys/kernel/btf/vmlinux ..."
bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

echo "[2/2] Compiling execsnoop.bpf.c -> execsnoop.bpf.o ..."
clang -O2 -g -target bpf -D__TARGET_ARCH_x86 -c execsnoop.bpf.c -o execsnoop.bpf.o

echo "Done: execsnoop.bpf.o"
