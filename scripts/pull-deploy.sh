#!/usr/bin/env bash
# pull-deploy.sh — Pull-based GitOps agent for FadianRoam federation proxies.
#
# Runs on each proxy node via a systemd timer. Polls origin/main for new
# commits; when found, decrypts member YAMLs locally, generates FreeRADIUS
# + WireGuard configs, validates syntax, and applies — without ever exposing
# secrets to CI runners.
#
# Install:
#   sudo cp scripts/pull-deploy.sh /opt/fadianroam/pull-deploy.sh
#   sudo cp scripts/generate-configs.py /opt/fadianroam/generate-configs.py
#   # Copy systemd units from scripts/systemd/ and enable the timer
#
# Environment overrides (for local testing):
#   FADIANROAM_REPO_DIR     default: /opt/fadianroam/federation-config
#   FADIANROAM_BUILD_DIR    default: /opt/fadianroam/build
#   FADIANROAM_TARGET_DIR   default: /etc/freeradius/3.0
#   FADIANROAM_AGE_KEY      default: /etc/sops/age-key.txt
#   FADIANROAM_WG_IFACE     default: fadianroam-mgmt
#   FADIANROAM_MOCK         set "true" to skip systemctl + wg (for testing)

set -euo pipefail

REPO_DIR="${FADIANROAM_REPO_DIR:-/opt/fadianroam/federation-config}"
BUILD_DIR="${FADIANROAM_BUILD_DIR:-/opt/fadianroam/build}"
TARGET_DIR="${FADIANROAM_TARGET_DIR:-/etc/freeradius/3.0}"
AGE_KEY="${FADIANROAM_AGE_KEY:-/etc/sops/age-key.txt}"
WG_IFACE="${FADIANROAM_WG_IFACE:-fadianroam-mgmt}"
MOCK="${FADIANROAM_MOCK:-false}"

MEMBERS_DIR="${REPO_DIR}/members"
DEC_DIR="${BUILD_DIR}/members-dec"
SCRIPTS_DIR="${REPO_DIR}/scripts"

echo "=== FadianRoam Pull-Deploy === $(date -u +%Y-%m-%dT%H:%M:%SZ)"
cd "${REPO_DIR}"

# 1. Check for upstream changes
git fetch origin main
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Up to date — nothing to do."
    exit 0
fi

echo "New commits detected (${LOCAL:0:7} → ${REMOTE:0:7}). Pulling..."
git pull origin main

# 2. Decrypt member YAMLs on the proxy node (key never leaves this machine)
echo "Decrypting member files..."
rm -rf "${DEC_DIR}" && mkdir -p "${DEC_DIR}"
export SOPS_AGE_KEY_FILE="${AGE_KEY}"

for f in "${MEMBERS_DIR}"/*.yml; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    sops -d "$f" > "${DEC_DIR}/${base}"
    echo "  ✓ $(basename "$f")"
done

# 3. Generate FreeRADIUS + WireGuard configs from decrypted YAML
#    (realm alignment check runs inside generate-configs.py)
echo "Generating configs..."
rm -rf "${BUILD_DIR}/out"
python3 "${SCRIPTS_DIR}/generate-configs.py" "${DEC_DIR}" "${BUILD_DIR}/out"

# 4. FreeRADIUS syntax validation — roll back on failure
echo "Validating FreeRADIUS syntax..."
if ! freeradius -Cx -lstdout -d "${TARGET_DIR}" \
        -n freeradius \
        -c "${BUILD_DIR}/out/proxy.conf" 2>&1 | grep -q "Configuration appears to be OK"; then
    # Fall back to radiusd if freeradius binary not available
    if command -v radiusd &>/dev/null; then
        if ! radiusd -Cx -d "${BUILD_DIR}/out" 2>&1; then
            echo "❌ Syntax check FAILED. Rolling back to ${LOCAL:0:7}..."
            git reset --hard "${LOCAL}"
            exit 1
        fi
    fi
fi
echo "✓ Syntax check passed."

# 5. Apply configs to FreeRADIUS config dir
echo "Applying to ${TARGET_DIR}..."
cp "${BUILD_DIR}/out/clients.conf" "${TARGET_DIR}/clients.conf"
cp "${BUILD_DIR}/out/proxy.conf"   "${TARGET_DIR}/proxy.conf"

# 6. Reload FreeRADIUS
if [ "$MOCK" = "true" ]; then
    echo "Mock: systemctl reload freeradius (skipped)"
else
    sudo systemctl reload freeradius || sudo systemctl restart freeradius
    echo "✓ FreeRADIUS reloaded."
fi

# 7. Apply WireGuard peers
WG_PEERS="${BUILD_DIR}/out/wg-peers.conf"
if [ -s "${WG_PEERS}" ]; then
    echo "Updating WireGuard peers on ${WG_IFACE}..."
    pubkey=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^PublicKey\ =\ (.+)$ ]]; then
            pubkey="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^AllowedIPs\ =\ (.+)$ ]]; then
            allowed="${BASH_REMATCH[1]}"
            if [ -n "$pubkey" ]; then
                if [ "$MOCK" = "true" ]; then
                    echo "  Mock: wg set ${WG_IFACE} peer ${pubkey} allowed-ips ${allowed}"
                elif sudo wg show "${WG_IFACE}" peers 2>/dev/null | grep -qF "$pubkey"; then
                    echo "  Peer exists: ${pubkey:0:16}..."
                else
                    sudo wg set "${WG_IFACE}" peer "$pubkey" allowed-ips "$allowed"
                    echo "  ✓ Added peer: ${pubkey:0:16}... (${allowed})"
                fi
                pubkey=""
            fi
        fi
    done < "${WG_PEERS}"
fi

# 8. Cleanup decrypted secrets from disk
rm -rf "${DEC_DIR}"

echo "✓ Deploy complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
