# FadianRoam Federation Config

Federation member registry, relay configuration, and auto-deployment for [FadianRoam](https://fadianroam.yunzheng.space).

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [AGE](https://github.com/FiloSottile/age). Config changes auto-deploy to all federation proxies via GitHub Actions.

## Structure

```
members/          # One YAML per Site (SOPS-encrypted shared_secret)
federations/      # One YAML per Federation Relay proxy
scripts/          # Config generation and deployment
.sops.yaml        # SOPS encryption rules
```

## Joining as a Site

1. Open an **Issue** → "Join as FadianRoam Site"
2. Fill in your realm, WireGuard public key, location, etc.
3. Governance Committee reviews and approves
4. Admin generates your `shared_secret`, creates your member YAML, encrypts and pushes
5. CI/CD auto-deploys to all federation proxies
6. You receive your shared secret and MGMT VPN config securely

## Hosting a Federation Proxy

1. Open an **Issue** → "Deploy New Federation Proxy"
2. Prepare your server: install FreeRADIUS, WireGuard, SOPS, AGE
3. Add the CI/CD SSH public key to your deploy user:
   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBt/emqI0l/a2bfWwDiEoHiAZJaHeAoKnLjf/Z5gm7Ew fadianroam-federation-deploy
   ```
4. Generate AGE key: `mkdir -p /etc/sops && age-keygen -o /etc/sops/age-key.txt`
5. Submit the Issue with your server SSH host/port, AGE public key, and country
6. Admin adds your federation YAML, updates `.sops.yaml` with your AGE key, and adds your host to the CI/CD workflow

## For Admins

### Adding a member

```bash
# Generate shared secret
SECRET=$(openssl rand -hex 24)

# Create member file
cat > members/<realm>.yml << EOF
member:
  name: "..."
  realm: "<realm>"
  contact: "..."
  joined: "$(date +%Y-%m-%d)"
network:
  type: "bgp"
  mgmt_ip: "172.172.10.XX"
  wg_pubkey: "..."
  asn: XXXXX
radius:
  port: 1812
  shared_secret: "$SECRET"
  eap_methods:
    - "EAP-TTLS/PAP"
location:
  city: "..."
  country: "XX"
EOF

# Encrypt and push
sops encrypt -i members/<realm>.yml
git add members/<realm>.yml && git commit -m "update" && git push
```

### Adding a federation proxy

1. Add YAML to `federations/<name>.yml`
2. Add AGE public key to `.sops.yaml` (comma-separated with existing keys)
3. Re-encrypt all members: `for f in members/*.yml; do sops rotate -i "$f"; done`
4. Add host to `matrix.include` in `.github/workflows/deploy.yml`
5. Commit and push
