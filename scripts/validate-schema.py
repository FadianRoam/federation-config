#!/usr/bin/env python3
"""
validate-schema.py — CI-safe schema validator for FadianRoam member files.

Modes:
  --check-encrypted <dir>       Verify all *.yml files are SOPS-encrypted.
                                Safe to run in CI — no decryption key needed.
  --check-schema <dir>          Validate required fields and realm/filename
                                alignment. Requires pre-decrypted files.
  --check-sops-coverage <dir>   Verify every member file matches a creation
                                rule in .sops.yaml. Safe to run in CI.
"""

import glob
import os
import re
import sys
import yaml

REQUIRED = {
    "member":   ["name", "realm", "contact", "joined"],
    "network":  ["mgmt_ip", "wg_pubkey", "asn"],
    "radius":   ["port", "shared_secret", "eap_methods"],
    "location": ["city", "country"],
}

VALID_EAP = {
    "EAP-TLS", "EAP-TTLS/PAP", "EAP-TTLS/MSCHAPv2",
    "PEAP/MSCHAPv2", "EAP-PWD",
}


def check_encrypted(directory: str) -> bool:
    paths = sorted(glob.glob(os.path.join(directory, "*.yml")))
    if not paths:
        print(f"⚠️  No *.yml files found in {directory}")
        return True
    ok = True
    for path in paths:
        with open(path) as f:
            content = f.read()
        if "sops:" not in content:
            print(f"❌ {path} — not SOPS-encrypted!")
            ok = False
        elif "ENC[" not in content:
            # File has sops block but no encrypted values — likely plaintext secret
            print(f"❌ {path} — sops block present but no ENC[] values found (plaintext secret?)")
            ok = False
        else:
            print(f"✓  {path}")
    return ok


def check_schema(directory: str) -> bool:
    paths = sorted(glob.glob(os.path.join(directory, "*.yml")))
    if not paths:
        print(f"⚠️  No *.yml files found in {directory}")
        return True
    ok = True
    for path in paths:
        with open(path) as f:
            try:
                data = yaml.safe_load(f)
            except yaml.YAMLError as e:
                print(f"❌ {path} — YAML parse error: {e}")
                ok = False
                continue

        file_ok = True

        # Required sections + keys
        for section, keys in REQUIRED.items():
            if section not in data:
                print(f"❌ {path} — missing section '{section}'")
                file_ok = False
                continue
            for key in keys:
                if key not in data[section]:
                    print(f"❌ {path} — missing '{section}.{key}'")
                    file_ok = False

        # Realm vs filename
        if "member" in data and "realm" in data["member"]:
            realm = data["member"]["realm"]
            expected = re.sub(r'\.sops\.yml$|\.yml$', '', os.path.basename(path))
            if realm != expected and not realm.endswith("." + expected):
                print(f"❌ {path} — realm '{realm}' does not match filename '{expected}'")
                file_ok = False

        # EAP method whitelist (warning only)
        if "radius" in data and "eap_methods" in data["radius"]:
            for method in data["radius"]["eap_methods"]:
                if method not in VALID_EAP:
                    print(f"⚠️  {path} — unknown EAP method '{method}'")

        if file_ok:
            print(f"✓  {path}")
        else:
            ok = False

    return ok


def check_sops_coverage(directory: str) -> bool:
    sops_path = os.path.join(os.path.dirname(directory.rstrip("/")), ".sops.yaml")
    if not os.path.exists(sops_path):
        sops_path = ".sops.yaml"
    if not os.path.exists(sops_path):
        print(f"❌ .sops.yaml not found")
        return False
    with open(sops_path) as f:
        sops_cfg = yaml.safe_load(f)
    rules = sops_cfg.get("creation_rules", [])
    patterns = [r.get("path_regex", "") for r in rules if r.get("path_regex")]
    if not patterns:
        print(f"❌ .sops.yaml has no creation_rules with path_regex")
        return False
    paths = sorted(glob.glob(os.path.join(directory, "*.yml")))
    if not paths:
        print(f"⚠️  No *.yml files found in {directory}")
        return True
    ok = True
    for path in paths:
        matched = any(re.search(p, path) for p in patterns)
        if not matched:
            print(f"❌ {path} — no .sops.yaml creation rule matches this path")
            ok = False
        else:
            print(f"✓  {path}")
    return ok


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    mode, directory = sys.argv[1], sys.argv[2]
    if mode == "--check-encrypted":
        sys.exit(0 if check_encrypted(directory) else 1)
    elif mode == "--check-schema":
        sys.exit(0 if check_schema(directory) else 1)
    elif mode == "--check-sops-coverage":
        sys.exit(0 if check_sops_coverage(directory) else 1)
    else:
        print(f"Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
