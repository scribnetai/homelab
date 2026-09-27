# Changelog

## 2026-09-27 — Security fix: Kuma no longer published publicly
- `vps/docker-compose.yml`: Kuma binds to `127.0.0.1:3001` only. Docker programs
  iptables directly and bypasses ufw, so the previously published port was reachable
  from the public internet despite the firewall.
- Kuma is exposed on the tailnet via `tailscale serve` (automatic HTTPS on the
  MagicDNS name) instead.
- `README.md`: `tailscale serve` step added to the quickstart, plus Security notes
  (Hetzner firewall as defense in depth).

## 2026-09-27 — Initial commit
- `vps/cloud-init.yaml`: portable first-boot bootstrap (Ubuntu 24.04, Docker from the
  official apt repo, Tailscale, ufw default-deny with SSH + tailnet allowed,
  unattended-upgrades)
- `vps/docker-compose.yml`: Uptime Kuma pinned to `louislam/uptime-kuma:1`, state in
  the named volume `kuma-data`
- `vps/backup.sh` / `vps/restore.sh`: tarball backup/restore for the Kuma data volume
- `README.md`: Hetzner CX22 (Ashburn) quickstart, backup/restore, provider-move procedure
