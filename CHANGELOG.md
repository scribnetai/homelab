# Changelog

## 2026-09-27 — Initial commit
- `vps/cloud-init.yaml`: portable first-boot bootstrap (Ubuntu 24.04, Docker from the
  official apt repo, Tailscale, ufw default-deny with SSH + tailnet allowed,
  unattended-upgrades)
- `vps/docker-compose.yml`: Uptime Kuma pinned to `louislam/uptime-kuma:1`, state in
  the named volume `kuma-data`
- `vps/backup.sh` / `vps/restore.sh`: tarball backup/restore for the Kuma data volume
- `README.md`: Hetzner CX22 (Ashburn) quickstart, backup/restore, provider-move procedure
