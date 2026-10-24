#!/usr/bin/env bash
# backup-rotate.sh - GFS retention tiers for the VPS backup tarballs.
#
# Ported 2026-10-24 from the Enshrouded kit's backup-rotate.sh (the fleet
# standard) and adapted for backup.sh's output:
#   - A "backup" here is a SET: the kuma-data-<stamp>.tgz and
#     beszel-data-<stamp>.tgz that one backup.sh run produced (same stamp).
#   - Tiers (grandfather-father-son), copies of the newest set:
#       weekly   (Sunday's set,   keep 5)
#       monthly  (the 1st's set,  keep 12)
#       yearly   (Jan 1st's set,  keep 3)
#   - DELTA vs the Enshrouded original: the game image self-trims its
#     dailies (newest 14); backup.sh does not, so this script also prunes
#     the root set list to the newest 14 sets.
#
# Tiers live in backups/archive/ under the backups dir, so a bulk copy of
# recent tarballs never drags the whole archive along.
#
# Run daily AFTER backup.sh, via bash explicitly (never a bare path -
# files that travel via Windows can lose their exec bit). Crontab:
#   CRON_TZ=America/New_York
#   15 4 * * * /usr/bin/bash /home/techops/homelab/vps/backup.sh >> /home/techops/homelab/vps/backup-cron.log 2>&1
#   45 4 * * * /usr/bin/bash /home/techops/homelab/vps/backup-rotate.sh >> /home/techops/homelab/vps/backup-cron.log 2>&1
#
# Day logic can be overridden for testing: ROTATE_DOW (1=Mon..7=Sun),
# ROTATE_DOM (01..31), ROTATE_MOY (01..12). Every run logs to
# backups/archive/rotate.log.
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUPS="$BASE/backups"
ARCHIVE="$BACKUPS/archive"
LOG="$ARCHIVE/rotate.log"
DOW="${ROTATE_DOW:-$(date +%u)}"
DOM="${ROTATE_DOM:-$(date +%d)}"
MOY="${ROTATE_MOY:-$(date +%m)}"
KEEP_DAILY=14

mkdir -p "$ARCHIVE/weekly" "$ARCHIVE/monthly" "$ARCHIVE/yearly"

log() { echo "$(date +%F\ %T) $*" >> "$LOG"; }

# Unique set stamps in a directory, newest first (stamps sort lexically).
stamps_in() { # $1 = dir
  ls "$1" 2>/dev/null | sed -n 's/.*-\([0-9]\{8\}-[0-9]\{6\}\)\.tgz/\1/p' | sort -ru
}

NEWEST="$(stamps_in "$BACKUPS" | head -1)"
if [ -z "${NEWEST:-}" ]; then
  log "no backup sets found in backups/ - nothing to do"
  exit 0
fi

promote() { # $1 = tier name, $2 = keep count (in sets)
  local dest="$ARCHIVE/$1" keep="$2" stamp old
  for f in "$BACKUPS"/*-"$NEWEST".tgz; do
    [ -f "$f" ] || continue
    if [ ! -f "$dest/$(basename "$f")" ]; then
      cp -p "$f" "$dest/$(basename "$f")"
      log "promoted $(basename "$f") -> $1/"
    fi
  done
  stamps_in "$dest" | tail -n +$((keep + 1)) | while read -r old; do
    rm -f "$dest"/*-"$old".tgz
    log "pruned set $old from $1/"
  done
}

[ "$DOW" = "7" ] && promote weekly 5
[ "$DOM" = "01" ] && promote monthly 12
[ "$DOM" = "01" ] && [ "$MOY" = "01" ] && promote yearly 3

# Daily trim of the root (backup.sh has no self-trim): keep newest 14 sets.
stamps_in "$BACKUPS" | tail -n +$((KEEP_DAILY + 1)) | while read -r old; do
  rm -f "$BACKUPS"/*-"$old".tgz
  log "pruned daily set $old from backups/"
done

log "run complete (dow=$DOW dom=$DOM moy=$MOY, newest set=$NEWEST)"
exit 0
