#!/usr/bin/env bash
# Forwards a host port to a libvirt guest VM via iptables DNAT, and opens the
# matching hole in the libvirt firewall chain so the traffic isn't dropped.
# Also redirects locally-originated traffic (e.g. "ssh -p PORT ubuntu@localhost"),
# since packets generated on the host itself skip PREROUTING.
# Requires root (modifies iptables rules and sysctls).
set -euo pipefail

usage() {
	cat <<EOF
Usage: $0 <forward|unforward> --host-port PORT --vm-ip IP --vm-port PORT [--proto tcp|udp]

Example:
  sudo $0 forward   --host-port 8080 --vm-ip 192.168.122.50 --vm-port 80
  sudo $0 unforward --host-port 8080 --vm-ip 192.168.122.50 --vm-port 80
  sudo $0 forward   --host-port 2222 --vm-ip 192.168.122.136 --vm-port 22
EOF
	exit 1
}

[[ $# -ge 1 ]] || usage
ACTION="$1"
shift

PROTO="tcp"
HOST_PORT=""
VM_IP=""
VM_PORT=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--host-port) HOST_PORT="$2"; shift 2 ;;
		--vm-ip) VM_IP="$2"; shift 2 ;;
		--vm-port) VM_PORT="$2"; shift 2 ;;
		--proto) PROTO="$2"; shift 2 ;;
		*) echo "error: unknown argument: $1" >&2; usage ;;
	esac
done

[[ -n "$HOST_PORT" && -n "$VM_IP" && -n "$VM_PORT" ]] || usage

case "$ACTION" in
	forward)
		echo "[1/4] Forwarding host :$HOST_PORT -> $VM_IP:$VM_PORT ($PROTO) ..."
		iptables -t nat -I PREROUTING -p "$PROTO" --dport "$HOST_PORT" \
			-j DNAT --to-destination "$VM_IP:$VM_PORT"

		echo "[2/4] Allowing forwarded traffic through LIBVIRT_FWI ..."
		iptables -I LIBVIRT_FWI -p "$PROTO" -d "$VM_IP" --dport "$VM_PORT" \
			-m state --state NEW,ESTABLISHED -j ACCEPT

		echo "[3/4] Enabling ip_forward and route_localnet for local-origin traffic ..."
		sysctl -w net.ipv4.ip_forward=1 >/dev/null
		sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null

		echo "[4/4] Redirecting locally-originated traffic (e.g. ssh to localhost) ..."
		iptables -t nat -I OUTPUT -p "$PROTO" -o lo --dport "$HOST_PORT" \
			-j DNAT --to-destination "$VM_IP:$VM_PORT"
		iptables -t nat -I POSTROUTING -p "$PROTO" -s 127.0.0.1 -d "$VM_IP" --dport "$VM_PORT" \
			-j MASQUERADE

		echo "Done. Undo with: sudo $0 unforward --host-port $HOST_PORT --vm-ip $VM_IP --vm-port $VM_PORT --proto $PROTO"
		;;
	unforward)
		echo "[1/4] Removing POSTROUTING masquerade rule ..."
		iptables -t nat -D POSTROUTING -p "$PROTO" -s 127.0.0.1 -d "$VM_IP" --dport "$VM_PORT" \
			-j MASQUERADE

		echo "[2/4] Removing OUTPUT DNAT rule ..."
		iptables -t nat -D OUTPUT -p "$PROTO" -o lo --dport "$HOST_PORT" \
			-j DNAT --to-destination "$VM_IP:$VM_PORT"

		echo "[3/4] Removing LIBVIRT_FWI accept rule ..."
		iptables -D LIBVIRT_FWI -p "$PROTO" -d "$VM_IP" --dport "$VM_PORT" \
			-m state --state NEW,ESTABLISHED -j ACCEPT

		echo "[4/4] Removing PREROUTING DNAT rule ..."
		iptables -t nat -D PREROUTING -p "$PROTO" --dport "$HOST_PORT" \
			-j DNAT --to-destination "$VM_IP:$VM_PORT"

		echo "Done."
		;;
	*)
		usage
		;;
esac
