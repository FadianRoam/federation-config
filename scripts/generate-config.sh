#!/bin/bash
set -euo pipefail

MEMBERS_DIR="$(dirname "$0")/../members"
OUTPUT_DIR="${1:-/tmp/federation-output}"

mkdir -p "$OUTPUT_DIR"

PROXY_CONF="$OUTPUT_DIR/proxy.conf"
CLIENTS_CONF="$OUTPUT_DIR/clients.conf"
WG_PEERS="$OUTPUT_DIR/wg-peers.conf"

cat > "$PROXY_CONF" << 'HEADER'
proxy server {
    default_fallback = no
}
HEADER

cat > "$CLIENTS_CONF" << 'HEADER'
client localhost {
    ipaddr = 127.0.0.1
    secret = testing123
    shortname = localhost
}
HEADER

> "$WG_PEERS"

for member_file in "$MEMBERS_DIR"/*.yml; do
    [ -f "$member_file" ] || continue

    realm=$(grep "  realm:" "$member_file" | awk '{print $2}' | tr -d '"')
    mgmt_ip=$(grep "  mgmt_ip:" "$member_file" | awk '{print $2}' | tr -d '"')
    wg_pubkey=$(grep "  wg_pubkey:" "$member_file" | awk '{print $2}' | tr -d '"')
    name=$(grep "  name:" "$member_file" | head -1 | sed 's/.*name: *//;s/"//g')
    shortname=$(echo "$realm" | tr '.' '-')

    if [ -z "$realm" ] || [ -z "$mgmt_ip" ]; then
        echo "Skipping $member_file: missing realm or mgmt_ip"
        continue
    fi

    cat >> "$PROXY_CONF" << EOF

home_server hs_${shortname} {
    type = auth+acct
    ipaddr = ${mgmt_ip}
    port = 1812
    secret = \${FEDERATION_SECRET}
    response_window = 20
    status_check = status-server
    check_interval = 30
    check_timeout = 4
    num_answers_to_alive = 3
}

home_server_pool pool_${shortname} {
    type = fail-over
    home_server = hs_${shortname}
}

realm ${realm} {
    pool = pool_${shortname}
    nostrip
}
EOF

    cat >> "$CLIENTS_CONF" << EOF

client member_${shortname} {
    ipaddr = ${mgmt_ip}
    secret = \${FEDERATION_SECRET}
    shortname = ${shortname}
}
EOF

    if [ -n "$wg_pubkey" ]; then
        cat >> "$WG_PEERS" << EOF
# ${name} (${realm})
[Peer]
PublicKey = ${wg_pubkey}
AllowedIPs = ${mgmt_ip}/32

EOF
    fi

    echo "Processed: ${realm} (${mgmt_ip})"
done

cat >> "$PROXY_CONF" << 'FOOTER'

realm LOCAL {
}

realm NULL {
    reject = yes
}

realm DEFAULT {
    reject = yes
}
FOOTER

echo ""
echo "Generated:"
echo "  $PROXY_CONF"
echo "  $CLIENTS_CONF"
echo "  $WG_PEERS"
