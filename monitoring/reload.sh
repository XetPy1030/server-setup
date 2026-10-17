#!/bin/sh
# Вызывается из up.sh после docker compose up. Конфиги примонтированы файлами, и их
# правка сама по себе контейнеры не перезапускает. SIGHUP тоже не годится: git pull
# заменяет файл новым, а работающий контейнер видит старый — поэтому перезапуск,
# при старте Docker монтирует файл заново.
# Loki, Promtail и Grafana сюда не входят: после правки их конфигов — на сервере
# docker compose restart <сервис>.
set -eu
cd "$(dirname "$0")"
services="prometheus blackbox-exporter alertmanager"
# Проверка в свежем контейнере — с текущими файлами, а не с теми, что видит запущенный
docker compose run --rm --no-deps -T --entrypoint promtool prometheus \
    check config /etc/prometheus/prometheus.yml >/dev/null
docker compose restart $services 2>/dev/null
docker compose up -d --wait --wait-timeout 120 $services 2>/dev/null
echo "Prometheus, blackbox и Alertmanager перезапущены с текущими конфигами"
