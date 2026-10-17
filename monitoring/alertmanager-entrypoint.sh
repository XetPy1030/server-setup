#!/bin/sh
# Alertmanager не подставляет переменные окружения в конфиг. Заменяем ${ИМЯ} значениями
# из окружения контейнера (monitoring/.env) и запускаем с готовым файлом.
set -eu
awk '{
    while (match($0, /\$\{[A-Z_]+\}/)) {
        name = substr($0, RSTART + 2, RLENGTH - 3)
        if (!(name in ENVIRON)) { print "не задана переменная " name > "/dev/stderr"; exit 1 }
        $0 = substr($0, 1, RSTART - 1) ENVIRON[name] substr($0, RSTART + RLENGTH)
    }
    print
}' /etc/alertmanager/alertmanager.tmpl.yml >/tmp/alertmanager.yml
exec /bin/alertmanager --config.file=/tmp/alertmanager.yml --storage.path=/alertmanager \
    --cluster.listen-address= "$@"
