#!/bin/bash
set -euo pipefail
umask 077
PROJECT_DIR="$HOME"
BACKUP_DIR="$HOME/backups"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
ARCHIVE="$BACKUP_DIR/uptime-kuma-$TIMESTAMP.tar.gz"
mkdir -p "$BACKUP_DIR"
cd "$PROJECT_DIR"
trap 'sudo docker compose start' EXIT
sudo docker compose stop
sudo tar -czf "$ARCHIVE.tmp" -C "$PROJECT_DIR" data
sudo mv "$ARCHIVE.tmp" "$ARCHIVE"
sudo docker compose start
trap - EXIT
ls -1t "$BACKUP_DIR"/uptime-kuma-*.tar.gz |
    tail -n +8 |
    while IFS= read -r file; do
        sudo rm -- "$file"
    done
echo "Backup completed: $ARCHIVE"
