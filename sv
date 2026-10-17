#!/bin/sh
# Управление серверами с Mac. <хост> — алиас из ~/.ssh/config и файл в hosts/.
#   ./sv <хост>                    зайти по ssh
#   ./sv <хост> deploy [сервис…]   git push, на сервере git pull + up.sh (по умолчанию все из hosts/<хост>)
#   ./sv <хост> ps                 запущенные контейнеры
#   ./sv <хост> logs <контейнер>   хвост логов
set -eu
cd "$(dirname "$0")"

usage() {
    echo "usage: ./sv <хост> [ssh | deploy [сервис…] | ps | logs <контейнер>]" >&2
    echo "хосты: $(ls hosts | tr '\n' ' ')" >&2
    exit 1
}

[ $# -ge 1 ] || usage
host=$1; shift
[ -f "hosts/$host" ] || usage

case "${1:-ssh}" in
    ssh)
        exec ssh "$host" ;;
    deploy)
        shift
        if [ -n "$(git status --porcelain)" ]; then
            echo "Есть незакоммиченные изменения — сначала commit" >&2
            exit 1
        fi
        services=${*:-$(sed 's/#.*//' "hosts/$host")}
        git push
        ssh "$host" "cd server-setup && git pull --ff-only && ./up.sh" $services ;;
    ps)
        ssh "$host" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" ;;
    logs)
        ssh -t "$host" docker logs -f --tail 100 "${2:?укажи контейнер}" ;;
    *)
        usage ;;
esac
