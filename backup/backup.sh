#!/bin/sh
# Бэкап web → Яндекс Диск (docs/backup.md). Каждую ночь запускается systemd-таймером
# (backup/install.sh); руками — backup/backup.sh. Любые аргументы передаются restic:
#   backup/backup.sh snapshots      список снимков
# Источники смонтированы только на чтение; restore — в /restore (на хосте /root/restore).
set -eu
cd "$(dirname "$0")"
here=$(pwd)
set -a; . ./.env; set +a    # RESTIC_PASSWORD

docker build -q -t server-setup-backup . >/dev/null

restic() {
    docker run --rm -i --hostname web \
        -e RESTIC_PASSWORD -e RESTIC_REPOSITORY=rclone:yadisk:backup/servers/web \
        -e RCLONE_CONFIG=/rclone/rclone.conf -v "$here/rclone:/rclone" \
        -v restic-cache:/root/.cache/restic \
        -v /root/server-setup:/root/server-setup:ro \
        -v /root/projects:/root/projects:ro \
        -v /var/lib/docker/volumes:/var/lib/docker/volumes:ro \
        -v /root/restore:/restore \
        server-setup-backup "$@"
}

if [ $# -gt 0 ]; then
    restic "$@"
    exit
fi

staging=$here/staging
rm -rf "$staging"
mkdir -m700 "$staging"

# Базы — дамп изнутри контейнера, тем же pg_dump, что и версия сервера
docker exec obsidiantime-db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' >"$staging/obsidiantime.sql"
docker exec doubleb-db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' >"$staging/doubleb.sql"

# sqlite — через backup API: живой файл может оказаться посреди записи
sqlite_copy() {
    python3 -c 'import sqlite3, sys
d = sqlite3.connect(sys.argv[2]); sqlite3.connect(sys.argv[1]).backup(d); d.close()' "$1" "$2"
}
sqlite_copy "$here/../nginx/data/database.sqlite" "$staging/npm.sqlite"
sqlite_copy /var/lib/docker/volumes/loki_grafana-storage/_data/grafana.db "$staging/grafana.db"

# .env сайтов: код в git, а секреты только здесь
find /root/projects -maxdepth 3 -name .env -type f >"$staging/site-env-files.txt"

restic cat config >/dev/null 2>&1 || restic init
restic backup --host web --tag nightly \
    --exclude /root/server-setup/nginx/data/logs \
    --exclude /root/server-setup/monitoring/logs \
    --exclude /root/server-setup/backup/rclone \
    --files-from /root/server-setup/backup/staging/site-env-files.txt \
    /root/server-setup \
    /var/lib/docker/volumes/obsidiantime_minio_data/_data \
    /var/lib/docker/volumes/obsidiantime_media_volume/_data \
    /var/lib/docker/volumes/loki_grafana-storage/_data
restic forget --host web --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
if [ "$(date +%u)" = 7 ]; then restic check; fi

# Метрика для алерта BackupStale (node-exporter textfile collector)
metrics=$here/../monitoring/node-exporter-textfile
mkdir -p "$metrics"
echo "backup_last_success_timestamp_seconds $(date +%s)" >"$metrics/backup.prom.tmp"
mv "$metrics/backup.prom.tmp" "$metrics/backup.prom"
echo "бэкап готов"
