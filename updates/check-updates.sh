#!/usr/bin/env bash
# check-updates.sh - one apt host's update picture, fleet-workflow style.
#
# Default mode is READ-ONLY: it refreshes package metadata (apt-get update,
# metadata only - installs nothing) and reports what a dist-upgrade WOULD
# do, from apt's own simulation. With --apply it runs the upgrade
# interactively (you confirm; nothing is forced with -y) and re-checks.
# EVERY run ends by restarting beszel-agent if present, so the hub's
# updates badge refreshes immediately instead of on the agent's slow
# cycle - check or apply, the board is left truthful either way.
#
# Usage:
#   ./check-updates.sh           # check only (safe anywhere, anytime)
#   ./check-updates.sh --apply   # check, upgrade after confirmation, re-check
#
# Works as root or as a sudo user (Proxmox hosts run as root and have no
# sudo - handled below). See updates/README.md for the fleet workflow.
set -u

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    echo "ERROR: not root and no sudo available."; exit 1
  fi
fi
command -v apt-get >/dev/null 2>&1 || { echo "ERROR: not an apt host."; exit 1; }

count_pending() { apt-get -s dist-upgrade 2>/dev/null | grep -c '^Inst'; }
list_pending()  { apt-get -s dist-upgrade 2>/dev/null | grep '^Inst' | awk '{print "  " $2}'; }
bump_badge()    {
  if systemctl cat beszel-agent >/dev/null 2>&1; then
    $SUDO systemctl restart beszel-agent
    echo "beszel-agent restarted - the hub badge refreshes within a minute."
  fi
}
reboot_state()  {
  if [ -f /var/run/reboot-required ]; then
    echo "REBOOT REQUIRED$( [ -s /var/run/reboot-required.pkgs ] && echo " by: $(paste -sd' ' /var/run/reboot-required.pkgs)")"
  else
    echo "no reboot required"
  fi
}

echo "== $(hostname) - $(date '+%F %T %Z') =="
echo "-- refreshing package metadata (apt-get update) --"
$SUDO apt-get update -qq || { echo "ERROR: apt-get update failed."; exit 1; }

PENDING="$(count_pending)"
echo "pending updates: $PENDING"
[ "$PENDING" -gt 0 ] && list_pending
reboot_state

if [ "${1:-}" = "--apply" ]; then
  if [ "$PENDING" -eq 0 ]; then
    echo "nothing to apply."
    exit 0
  fi
  echo "-- applying: apt-get dist-upgrade (interactive) --"
  $SUDO apt-get dist-upgrade || { echo "ERROR: upgrade failed or was aborted."; exit 1; }
  echo "-- re-check --"
  echo "pending updates: $(count_pending)"
  reboot_state
fi
bump_badge
exit 0
