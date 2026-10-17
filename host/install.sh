#!/bin/sh
# Ставит host-конфиги: ротацию логов Docker, live-restore и лимит journald.
set -eu
cd "$(dirname "$0")"

install -Dm644 journald.conf /etc/systemd/journald.conf.d/size.conf
systemctl restart systemd-journald

install -Dm644 docker-daemon.json /etc/docker/daemon.json
# live-restore перечитывается по SIGHUP, поэтому сначала включаем его reload'ом,
# и только потом перезапускаем dockerd — контейнеры при этом не останавливаются.
systemctl reload docker
if [ "$(docker info -f '{{.LiveRestoreEnabled}}')" != "true" ]; then
    echo "live-restore не включился, dockerd не перезапускаю" >&2
    exit 1
fi
systemctl restart docker

echo "Готово. Ротация логов действует только для новых контейнеров:"
echo "пересоздайте их через docker compose up -d --force-recreate --no-build"
