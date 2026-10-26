# Бэкапы web → Яндекс Диск

Работают с 2026-10-17 (этап 2 в [roadmap.md](roadmap.md)): каждую ночь в 04:00 по Москве, репозиторий restic — `backup/servers/web` на Яндекс Диске. Восстановление баз и файлов проверено на первом снимке.

## Что копируем

| Что | Где на сервере | Как |
|-----|----------------|-----|
| Postgres obsidiantime | контейнер `obsidiantime-db` | `pg_dump` → `staging/obsidiantime.sql` |
| Postgres doubleb-shop | контейнер `doubleb-db` | `pg_dump` → `staging/doubleb.sql` |
| NPM: база хостов | `nginx/data/database.sqlite` | sqlite backup API → `staging/npm.sqlite` |
| Grafana | том `loki_grafana-storage` | `grafana.db` — sqlite backup API → `staging/grafana.db`, остальное файлами |
| CouchDB: заметки Obsidian (зашифрованы на устройствах) | `couchdb/data`, `couchdb/etc` | файлами, в составе `server-setup/`: файлы CouchDB только дописываются, копия на ходу целая. Восстановление — [obsidian-sync.md](obsidian-sync.md) |
| Весь `server-setup/` | конфиги, сертификаты NPM, Portainer, `.env`, ключ tg-relay | файлами, без логов и без `backup/rclone` |
| Файлы MinIO и media obsidiantime | тома `obsidiantime_minio_data`, `obsidiantime_media_volume` | файлами |
| `.env` сайтов | `/root/projects/*/.env` (до 3 уровней) | файлами |

Не копируем: Loki и Prometheus (логи и метрики, ~1.5 ГБ, восстанавливать не нужно), образы (собираются из реп), код сайтов (он в git; незакоммиченное на сервере пропадёт).

Первый снимок — 90 МБ, на Диске после сжатия — 50 МБ; дальше restic отправляет только изменения.

## Как устроено

- [backup/backup.sh](../backup/backup.sh) делает дампы в `backup/staging/` и запускает restic в контейнере (образ из [backup/Dockerfile](../backup/Dockerfile): `restic/restic` + бинарник rclone). Источники смонтированы только на чтение, восстановление — в `/root/restore`.
- Шифрование, дедупликация, сжатие — средствами restic. Хранение: 7 ежедневных, 4 недельных, 6 месячных снимков. По воскресеньям — `restic check`.
- После успеха пишет время в `monitoring/node-exporter-textfile/backup.prom`. Алерт **BackupStale** — если успешного бэкапа нет 26 часов ([alerts.md](alerts.md)).
- Расписание — systemd-таймер `backup.timer`; пропущенный запуск выполняется после загрузки сервера. Ставится один раз: `backup/install.sh`.

Только на сервере (в `.gitignore`):

- `backup/.env` — `RESTIC_PASSWORD`. **Копия — в менеджере паролей:** без него снимки не расшифровать.
- `backup/rclone/rclone.conf` — доступ к Яндекс Диску, копия `~/.config/rclone/rclone.conf` с Mac.

## Команды

```sh
sv web
cd ~/server-setup
systemctl start backup.service          # бэкап сейчас
journalctl -u backup.service -n 50      # лог последнего запуска
systemctl list-timers backup.timer      # когда следующий
backup/backup.sh snapshots              # любые аргументы уходят в restic
```

## Восстановление

Базы — в пустую базу свежего контейнера (как после `docker compose up` сайта на новом сервере):

```sh
backup/backup.sh dump latest /root/server-setup/backup/staging/obsidiantime.sql \
    | docker exec -i obsidiantime-db psql -U postgres -d obsidiantime
backup/backup.sh dump latest /root/server-setup/backup/staging/doubleb.sql \
    | docker exec -i doubleb-db psql -U doubleb -d doubleb_db
```

Файлы — во временную папку, потом скопировать на место (`/restore` в контейнере = `/root/restore` на хосте):

```sh
backup/backup.sh restore latest --target /restore --include /root/server-setup/nginx
ls /root/restore/root/server-setup/nginx
```

sqlite NPM и Grafana брать из `staging/` (живые файлы в снимке могли попасть посреди записи):

```sh
backup/backup.sh dump latest /root/server-setup/backup/staging/npm.sqlite >/root/restore/database.sqlite
```

Вместо `latest` — ID снимка из `snapshots`.

Проверка, которой подтверждён первый снимок: оба дампа загружены во временные контейнеры `postgres:17`, число строк по каждой таблице совпало с живыми базами; `nginx/letsencrypt` восстановлен и совпал с оригиналом побайтно; `npm.sqlite` — `integrity_check: ok`, все хосты на месте.

### Новый сервер целиком

Ещё не проверялось — это этап 6 в roadmap.

1. Склонировать репу, `host/install.sh` (см. README).
2. `backup/rclone/rclone.conf` — с Mac, `backup/.env` — пароль restic из менеджера паролей.
3. `backup/backup.sh restore latest --target /restore`, затем из `/root/restore/root/server-setup/` скопировать в `~/server-setup/` то, чего нет в git: `nginx/data`, `nginx/letsencrypt`, `portainer/data`, `couchdb/data`, `couchdb/etc`, все `.env`, `monitoring/tg-relay-secrets`, `monitoring/prometheus-targets/mtproto.yml`. NPM: `database.sqlite` — из `staging/npm.sqlite`.
4. `./sv web deploy` с Mac.
5. Сайты: склонировать репы в `/root/projects`, вернуть `.env` из снимка, поднять, загрузить дампы баз. MinIO и Grafana — содержимое томов из снимка в `/var/lib/docker/volumes/<том>/_data` (Grafana — с `grafana.db` из `staging/`).

## Доступ к Яндекс Диску

Встроенный OAuth-ключ rclone Яндекс заблокировал 2026-10-11 (`410 Gone` на любые операции с файлами, [rclone#10067](https://github.com/rclone/rclone/issues/10067)). Поэтому — своё OAuth-приложение в [oauth.yandex.ru](https://oauth.yandex.ru/): его ClientID и secret лежат только в `rclone.conf`. Токен выдан до 2027-10-17 вместе с refresh_token — rclone продлевает его сам.

Если токен отозван или перестал работать:

1. В настройках приложения добавить Redirect URI `http://127.0.0.1:53682/`.
2. На Mac: `rclone config reconnect yadisk:` — откроется браузер, разрешить доступ. Проверка: `rclone lsf yadisk:backup/servers/web`.
3. `scp ~/.config/rclone/rclone.conf web:server-setup/backup/rclone/rclone.conf`.

Токен даёт доступ ко всему Диску. Аккуратнее держать бэкапы на отдельном аккаунте Яндекса: тогда взлом web не открывает личный Диск.

Папка `backup/servers` синхронизируется клиентом Яндекс Диска на Mac — это третья копия (зашифрованная).

## mtproto

Копировать нечего, кроме секрета прокси в `mtproto/.env` — продублируй его в менеджер паролей.
