#!/bin/bash
set -euo pipefail

CONFIG_DIR="/tmp/federation-output"
RADIUS_DIR="/etc/freeradius/3.0"
WG_INTERFACE="fadianroam-mgmt"

if [ -z "${FEDERATION_SECRET:-}" ]; then
    echo "ERROR: FEDERATION_SECRET not set"
    exit 1
fi

envsubst < "$CONFIG_DIR/proxy.conf" > "$RADIUS_DIR/proxy.conf"
envsubst < "$CONFIG_DIR/clients.conf" > "$RADIUS_DIR/clients.conf"
chown freerad:freerad "$RADIUS_DIR/proxy.conf" "$RADIUS_DIR/clients.conf"

freeradius -Cx -lstdout || { echo "RADIUS config check failed"; exit 1; }
systemctl restart freeradius
echo "FreeRADIUS reloaded"

if [ -s "$CONFIG_DIR/wg-peers.conf" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^PublicKey\ =\ (.+)$ ]]; then
            pubkey="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^AllowedIPs\ =\ (.+)$ ]]; then
            allowed="${BASH_REMATCH[1]}"
            if ! wg show "$WG_INTERFACE" peers | grep -q "$pubkey"; then
                wg set "$WG_INTERFACE" peer "$pubkey" allowed-ips "$allowed"
                echo "Added WG peer: $pubkey ($allowed)"
            else
                echo "WG peer exists: $pubkey"
            fi
            pubkey=""
        fi
    done < "$CONFIG_DIR/wg-peers.conf"
fi

echo "Deploy complete"
