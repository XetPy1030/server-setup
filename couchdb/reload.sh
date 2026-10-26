#!/bin/sh
# Вызывается из up.sh после docker compose up. livesync.ini примонтирован файлом:
# git pull заменяет его новым, а работающий контейнер видит старый, да и читает
# CouchDB его только при старте. Поэтому после правки — перезапуск.
# Без правки не трогаем: перезапуск на секунды рвёт синхронизацию на всех устройствах.
set -eu
cd "$(dirname "$0")"
stamp=.livesync.ini.applied
sum=$(sha256sum livesync.ini | cut -d' ' -f1)
[ "$(cat "$stamp" 2>/dev/null)" = "$sum" ] && exit 0
docker compose restart couchdb
docker compose up -d --wait --wait-timeout 120 couchdb 2>/dev/null
echo "$sum" >"$stamp"
echo "CouchDB перезапущен с текущим livesync.ini"
