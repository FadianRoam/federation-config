#!/usr/bin/env python3
"""Generate FreeRADIUS and WireGuard configs from member YAML files."""

import glob
import os
import sys
import yaml


def main():
    members_dir = sys.argv[1] if len(sys.argv) > 1 else "members"
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "out"
    os.makedirs(output_dir, exist_ok=True)

    members = []
    for path in sorted(glob.glob(os.path.join(members_dir, "*.yml"))):
        with open(path) as f:
            members.append(yaml.safe_load(f))

    # --- clients.conf ---
    lines = [
        "client localhost {",
        "    ipaddr = 127.0.0.1",
        "    secret = testing123",
        "    shortname = localhost",
        "}",
        "",
    ]
    for m in members:
        slug = m["member"]["realm"].replace(".", "-")
        lines += [
            f"client member_{slug} {{",
            f'    ipaddr = {m["network"]["mgmt_ip"]}',
            f'    secret = {m["radius"]["shared_secret"]}',
            f"    shortname = {slug}",
            "}",
            "",
        ]
    with open(os.path.join(output_dir, "clients.conf"), "w") as f:
        f.write("\n".join(lines))

    # --- proxy.conf ---
    lines = ["proxy server {", "    default_fallback = no", "}", ""]
    for m in members:
        slug = m["member"]["realm"].replace(".", "-")
        realm = m["member"]["realm"]
        ip = m["network"]["mgmt_ip"]
        secret = m["radius"]["shared_secret"]
        port = m["radius"].get("port", 1812)
        lines += [
            f"home_server hs_{slug} {{",
            "    type = auth+acct",
            f"    ipaddr = {ip}",
            f"    port = {port}",
            f"    secret = {secret}",
            "    response_window = 20",
            "    status_check = status-server",
            "    check_interval = 30",
            "    check_timeout = 4",
            "    num_answers_to_alive = 3",
            "}",
            "",
            f"home_server_pool pool_{slug} {{",
            "    type = fail-over",
            f"    home_server = hs_{slug}",
            "}",
            "",
            f"realm {realm} {{",
            f"    pool = pool_{slug}",
            "    nostrip",
            "}",
            "",
        ]
    lines += [
        "realm LOCAL {",
        "}",
        "",
        "realm NULL {",
        "    reject = yes",
        "}",
        "",
        "realm DEFAULT {",
        "    reject = yes",
        "}",
    ]
    with open(os.path.join(output_dir, "proxy.conf"), "w") as f:
        f.write("\n".join(lines))

    # --- WireGuard peers ---
    lines = []
    for m in members:
        name = m["member"]["name"]
        realm = m["member"]["realm"]
        ip = m["network"]["mgmt_ip"]
        pubkey = m["network"]["wg_pubkey"]
        lines += [
            f"# {name} ({realm})",
            "[Peer]",
            f"PublicKey = {pubkey}",
            f"AllowedIPs = {ip}/32",
            "",
        ]
    with open(os.path.join(output_dir, "wg-peers.conf"), "w") as f:
        f.write("\n".join(lines))

    print(f"Generated configs for {len(members)} member(s) in {output_dir}/")


if __name__ == "__main__":
    main()
