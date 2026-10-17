#!/bin/sh
# Запускается на сервере: поднимает перечисленные сервисы (папки с docker-compose.yml).
#   ./up.sh nginx portainer monitoring
# Ждёт, пока контейнеры станут healthy (без healthcheck — просто running).
# Не дождался за 3 минуты — выходит с ошибкой, следующие сервисы не трогает.
set -eu
cd "$(dirname "$0")"
[ $# -ge 1 ] || { echo "usage: ./up.sh <сервис>…" >&2; exit 1; }

for s in "$@"; do
    echo "== $s"
    if grep -q web-network "$s/docker-compose.yml"; then
        docker network inspect web-network >/dev/null 2>&1 || docker network create web-network
    fi
    (cd "$s" && docker compose up -d --remove-orphans --wait --wait-timeout 180)
    # Правка примонтированных конфигов контейнер не пересоздаёт — reload.sh велит их перечитать
    if [ -x "$s/reload.sh" ]; then "$s/reload.sh"; fi
done
