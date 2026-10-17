#!/bin/sh
# Настройки самой машины. Без аргументов ставит всё, иначе — только перечисленные части:
#   host/install.sh                    journald docker upgrades
#   host/install.sh journald upgrades  то же без перезапуска dockerd
#
#   journald  лимит журнала systemd: 500M, на дисках меньше 20 ГБ — 150M
#             (сам systemd берёт 10% диска — на 5-гиговом VPS это треть свободного места)
#   docker    ротация логов контейнеров и live-restore; перезапускает dockerd,
#             контейнеры при этом не останавливаются
#   upgrades  автообновления раз в сутки (unattended-upgrades), без перезагрузки и без Docker;
#             что ставится — см. 20auto-upgrades
set -eu
cd "$(dirname "$0")"

journald() {
    disk_gb=$(df -BG --output=size / | tail -1 | tr -dc 0-9)
    if [ "$disk_gb" -lt 20 ]; then max=150M; else max=500M; fi
    mkdir -p /etc/systemd/journald.conf.d
    printf '[Journal]\nSystemMaxUse=%s\n' "$max" >/etc/systemd/journald.conf.d/size.conf
    systemctl restart systemd-journald
    journalctl --vacuum-size="$max" >/dev/null
    echo "journald: SystemMaxUse=$max, сейчас $(journalctl --disk-usage | grep -o '[0-9.]*[KMG]')"
}

docker_daemon() {
    install -Dm644 docker-daemon.json /etc/docker/daemon.json
    # live-restore перечитывается по SIGHUP, поэтому сначала включаем его reload'ом,
    # и только потом перезапускаем dockerd — контейнеры при этом не останавливаются.
    systemctl reload docker
    if [ "$(docker info -f '{{.LiveRestoreEnabled}}')" != "true" ]; then
        echo "live-restore не включился, dockerd не перезапускаю" >&2
        exit 1
    fi
    systemctl restart docker
    echo "docker: ротация логов действует только для новых контейнеров —"
    echo "пересоздайте их через docker compose up -d --force-recreate --no-build"
}

upgrades() {
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q unattended-upgrades
    install -Dm644 20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
    echo "upgrades: включены, первый запуск — по таймеру apt-daily-upgrade"
}

for part in ${*:-journald docker upgrades}; do
    case $part in
        journald) journald ;;
        docker) docker_daemon ;;
        upgrades) upgrades ;;
        *) echo "неизвестная часть: $part (есть journald, docker, upgrades)" >&2; exit 1 ;;
    esac
done
