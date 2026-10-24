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
# Counts distinguish installable-now from Ubuntu PHASED updates (apt
# defers those on a rollout schedule; Beszel counts them, a plain
# dist-upgrade simulation does not install them - both numbers are
# reported so the checker and the badge reconcile).
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
phased_list()   { apt-get -s dist-upgrade 2>/dev/null | awk '
                    /^The following .* deferred due to phasing:/ {f=1; next}
                    f && /^  / {for (i=1;i<=NF;i++) print $i; next}
                    f {exit}'; }
phased_count()  { phased_list | wc -l; }
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
PHASED="$(phased_count)"
if [ "$PHASED" -gt 0 ]; then
  echo "deferred by Ubuntu phasing: $PHASED (listed by Beszel; lands on Ubuntu's rollout schedule)"
  phased_list | sed 's/^/  /'
fi
reboot_state

if [ "${1:-}" = "--apply" ]; then
  if [ "$PENDING" -eq 0 ]; then
    echo "nothing to apply."
  else
    echo "-- applying: apt-get dist-upgrade (interactive) --"
    $SUDO apt-get dist-upgrade || { echo "ERROR: upgrade failed or was aborted."; exit 1; }
    echo "-- re-check --"
    echo "pending updates: $(count_pending)"
    PHASED_LEFT="$(phased_count)"
    [ "$PHASED_LEFT" -gt 0 ] && echo "note: $PHASED_LEFT update(s) remain deferred by Ubuntu phasing - expected; Beszel will keep counting them until the rollout reaches this host."
    reboot_state
  fi
fi
bump_badge
exit 0
