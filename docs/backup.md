# Бэкапы web → Яндекс Диск

Статус: **код готов, ждёт токен Яндекса** (этап 2 в [roadmap.md](roadmap.md)). С 2026-10-11 Яндекс отвечает `410 Gone` на запросы к файлам со встроенным OAuth-ключом rclone ([rclone#10067](https://github.com/rclone/rclone/issues/10067)). Работает со своим OAuth-приложением — см. «Подключение Яндекс Диска».

## Что копируем

| Что | Где на сервере | Как |
|-----|----------------|-----|
| Postgres obsidiantime | контейнер `obsidiantime-db` | `pg_dump` → `staging/obsidiantime.sql` |
| Postgres doubleb-shop | контейнер `doubleb-db` | `pg_dump` → `staging/doubleb.sql` |
| NPM: база хостов | `nginx/data/database.sqlite` | sqlite backup API → `staging/npm.sqlite` |
| Grafana | том `loki_grafana-storage` | `grafana.db` — sqlite backup API, остальное файлами |
| Весь `server-setup/` | конфиги, сертификаты NPM, Portainer, `.env`, ключ tg-relay | файлами, без логов и без `backup/rclone` |
| Файлы MinIO и media obsidiantime | тома `obsidiantime_minio_data`, `obsidiantime_media_volume` | файлами |
| `.env` сайтов | `/root/projects/*/.env` (до 3 уровней) | файлами |

Не копируем: Loki и Prometheus (логи и метрики, ~1.5 ГБ, восстанавливать не нужно), образы (собираются из реп), код сайтов (он в git; незакоммиченное на сервере пропадёт).

## Как устроено

- [backup/backup.sh](../backup/backup.sh) — делает дампы в `backup/staging/` и запускает restic в контейнере (образ из [backup/Dockerfile](../backup/Dockerfile): `restic/restic` + бинарник rclone). Источники смонтированы только на чтение.
- Репозиторий restic — `server-backups/web` на Яндекс Диске (`RESTIC_REPOSITORY=rclone:yadisk:server-backups/web`). Шифрование, дедупликация, сжатие — средствами restic.
- Хранение: 7 ежедневных, 4 недельных, 6 месячных снимков (`restic forget --prune`). По воскресеньям — `restic check`.
- После успеха пишет время в `monitoring/node-exporter-textfile/backup.prom`. Алерт **BackupStale** — если успешного бэкапа нет 26 часов ([alerts.md](alerts.md)).
- Расписание — systemd-таймер `backup.timer`, 04:00 по Москве; пропущенный запуск выполняется после загрузки. Ставится один раз: `backup/install.sh`.

Только на сервере (в `.gitignore`):

- `backup/.env` — `RESTIC_PASSWORD`. **Копию — в менеджер паролей:** без него снимки не расшифровать.
- `backup/rclone/rclone.conf` — доступ к Яндекс Диску (копия конфига с Mac).

## Команды

```sh
sv web
cd ~/server-setup
systemctl start backup.service          # бэкап сейчас
journalctl -u backup.service -n 50      # лог последнего запуска
systemctl list-timers backup.timer      # когда следующий
backup/backup.sh snapshots              # любые аргументы уходят в restic
```

Восстановление — команды допишу после пробного восстановления на первом снимке.

## Подключение Яндекс Диска

Нужно своё OAuth-приложение: встроенное в rclone Яндекс заблокировал.

1. [oauth.yandex.ru](https://oauth.yandex.ru/) → «Создать приложение». Если попросит верификацию через Госуслуги — можно пропустить, токен всё равно выдаётся.
2. Платформа «Веб-сервисы», Redirect URI: `http://127.0.0.1:53682/`.
3. Доступы: «Доступ к информации о Диске», «Чтение всего Диска», «Запись в любом месте на Диске».
4. Создать, скопировать ClientID и Client secret.
5. На Mac:
   ```sh
   rclone config update yadisk client_id=<ClientID> client_secret=<Client secret>
   rclone config reconnect yadisk:      # откроется браузер — разрешить доступ
   rclone lsd yadisk:server-backups     # должно отработать без 410
   ```
6. Перенести конфиг на web и запустить первый бэкап:
   ```sh
   scp ~/.config/rclone/rclone.conf web:server-setup/backup/rclone/rclone.conf
   ssh web systemctl start backup.service
   ```

Токен rclone даёт доступ ко всему Диску. Аккуратнее завести отдельный аккаунт Яндекса только под бэкапы: тогда взлом web не открывает личный Диск.

Яндекс Диск синхронизируется на Mac, так что зашифрованный репозиторий скачается и туда — это третья копия. Если место жалко, исключи папку `server-backups` в настройках клиента Диска.

## mtproto

Копировать нечего, кроме секрета прокси в `mtproto/.env` — продублируй его в менеджер паролей.
