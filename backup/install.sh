#!/bin/sh
# Ставит systemd-таймер ночного бэкапа. Один раз на сервере: backup/install.sh
set -eu
cd "$(dirname "$0")"
[ -f .env ] || { echo "нет backup/.env с RESTIC_PASSWORD — см. .env.example" >&2; exit 1; }
[ -f rclone/rclone.conf ] || { echo "нет backup/rclone/rclone.conf — см. docs/backup.md" >&2; exit 1; }
install -m644 backup.service backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now backup.timer
systemctl list-timers backup.timer --no-pager
