#!/bin/sh
# Раз в минуту пишет состояние контейнеров для node-exporter (textfile collector):
#   docker_container_up{name,restart_policy}  1 — running, 0 — нет
#   docker_container_healthy{name}            1/0, только у контейнеров с healthcheck
#   docker_container_restarts_total{name}     сколько раз Docker перезапускал контейнер
# Алерты — monitoring/prometheus-rules/alerts.yaml, группа containers.
set -u
out=/textfile/containers.prom

while :; do
    docker ps -aq | xargs -r docker inspect -f \
        '{{.Name}} {{.State.Status}} {{.HostConfig.RestartPolicy.Name}} {{.RestartCount}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' |
    while read -r name status policy restarts health; do
        name=${name#/}
        up=0; [ "$status" = running ] && up=1
        echo "docker_container_up{name=\"$name\",restart_policy=\"$policy\"} $up"
        echo "docker_container_restarts_total{name=\"$name\"} $restarts"
        case $health in
            healthy) echo "docker_container_healthy{name=\"$name\"} 1" ;;
            unhealthy) echo "docker_container_healthy{name=\"$name\"} 0" ;;
        esac
    done | sort >"$out.tmp"
    # Docker не ответил — оставляем прошлый файл, а не пустой
    if grep -q docker_container_up "$out.tmp"; then mv "$out.tmp" "$out"; fi
    sleep 60
done
