#!/bin/bash
set -euo pipefail

CONFIG_DIR="${1:-out}"
RADIUS_DIR="/etc/freeradius/3.0"
WG_INTERFACE="fadianroam-mgmt"

sudo cp "$CONFIG_DIR/clients.conf" "$RADIUS_DIR/clients.conf"
sudo cp "$CONFIG_DIR/proxy.conf" "$RADIUS_DIR/proxy.conf"
sudo chown freerad:freerad "$RADIUS_DIR/clients.conf" "$RADIUS_DIR/proxy.conf"

sudo freeradius -Cx -lstdout || { echo "Config check failed"; exit 1; }
sudo systemctl reload freeradius
echo "FreeRADIUS reloaded"

if [ -s "$CONFIG_DIR/wg-peers.conf" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^PublicKey\ =\ (.+)$ ]]; then
            pubkey="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^AllowedIPs\ =\ (.+)$ ]]; then
            allowed="${BASH_REMATCH[1]}"
            if ! sudo wg show "$WG_INTERFACE" peers | grep -q "$pubkey"; then
                sudo wg set "$WG_INTERFACE" peer "$pubkey" allowed-ips "$allowed"
                echo "Added WG peer: $pubkey ($allowed)"
            else
                echo "WG peer exists: $pubkey"
            fi
            pubkey=""
        fi
    done < "$CONFIG_DIR/wg-peers.conf"
fi

echo "Deploy complete at $(date)"
