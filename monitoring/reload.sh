#!/bin/sh
# Вызывается из up.sh после docker compose up. Конфиги примонтированы файлами, и их
# правка сама по себе контейнеры не перезапускает — перечитываем явно.
# Loki, Promtail и Grafana сюда не входят: после правки их конфигов — на сервере
# docker compose restart <сервис>.
set -eu
cd "$(dirname "$0")"
docker compose exec -T prometheus promtool check config /etc/prometheus/prometheus.yml >/dev/null
docker compose kill -s HUP prometheus blackbox-exporter 2>/dev/null
# Конфиг Alertmanager собирается из шаблона только при старте контейнера
docker compose restart alertmanager 2>/dev/null
docker compose up -d --wait --wait-timeout 60 alertmanager 2>/dev/null
echo "Prometheus, blackbox и Alertmanager перечитали конфиги"
