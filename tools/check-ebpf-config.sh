#!/usr/bin/env bash
# Compares the running kernel's config against ebpf.config, reporting any
# entries that are missing or set differently. Run this before deciding
# whether a kernel rebuild is actually needed.
set -euo pipefail
cd "$(dirname "$0")/.."

FRAGMENT="ebpf.config"
LIVE_CONFIG="$(mktemp)"
trap 'rm -f "$LIVE_CONFIG"' EXIT

if [[ -r /proc/config.gz ]]; then
	zcat /proc/config.gz > "$LIVE_CONFIG"
elif [[ -r "/boot/config-$(uname -r)" ]]; then
	cp "/boot/config-$(uname -r)" "$LIVE_CONFIG"
else
	echo "error: no kernel config found (/proc/config.gz or /boot/config-$(uname -r))" >&2
	exit 1
fi

echo "Checking against running kernel $(uname -r) ..."
echo

NEEDS_REBUILD=0
NEEDS_MODPROBE=0
while IFS= read -r line; do
	[[ "$line" =~ ^#.*is\ not\ set$ ]] && continue
	[[ -z "$line" || "$line" == \#* ]] && continue

	NAME="${line%%=*}"
	WANT="${line#*=}"
	ACTUAL="$(grep -E "^${NAME}=" "$LIVE_CONFIG" || true)"
	ACTUAL_VAL="${ACTUAL#*=}"

	if [[ -z "$ACTUAL" ]]; then
		if grep -qE "^# ${NAME} is not set$" "$LIVE_CONFIG"; then
			echo "MISSING  $NAME (currently disabled, want =$WANT)"
		else
			echo "MISSING  $NAME (not present in live config)"
		fi
		NEEDS_REBUILD=1
	elif [[ "$ACTUAL_VAL" != "$WANT" ]]; then
		if [[ "$WANT" == "y" && "$ACTUAL_VAL" == "m" ]]; then
			echo "MODULE   $NAME (built as module, not built-in — try: modprobe ${NAME#CONFIG_}, no rebuild needed)"
			NEEDS_MODPROBE=1
		else
			echo "DIFFERS  $NAME (live: $ACTUAL_VAL, want: $WANT)"
			NEEDS_REBUILD=1
		fi
	fi
done < "$FRAGMENT"

echo
if [[ "$NEEDS_REBUILD" -eq 0 && "$NEEDS_MODPROBE" -eq 0 ]]; then
	echo "All entries in $FRAGMENT already match the running kernel. No rebuild needed."
elif [[ "$NEEDS_REBUILD" -eq 0 ]]; then
	echo "Everything is present — some features are modules, load them with modprobe if needed. No rebuild needed."
else
	echo "Some entries are missing or differ — a kernel rebuild (or reconfig) may be needed for those."
fi
