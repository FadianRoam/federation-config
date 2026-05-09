# FadianRoam Federation Config

Federation member registry and relay configuration for FadianRoam.

## Structure

```
members/           # Member YAML files (one per realm)
relay.yml          # Relay server configuration
scripts/           # Config generation and deployment scripts
.github/workflows/ # Auto-deploy on merge
```

## Adding a Member

1. Fork this repo
2. Create `members/<your-realm>.yml` (see existing files for format)
3. Submit a Pull Request
4. After review and merge, config is auto-deployed to the Federation Relay

## Auto-Deploy

On every push to `main`, GitHub Actions:
1. Generates FreeRADIUS `proxy.conf` and `clients.conf` from member YAML files
2. Generates WireGuard peer entries
3. Deploys to the Federation Relay via SSH
4. Reloads FreeRADIUS and updates WireGuard peers
