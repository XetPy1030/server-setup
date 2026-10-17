# Оповещения

Работают с 2026-10-17 (этап 3 в [roadmap.md](roadmap.md)). **В Telegram — все алерты, на почту — только критичные** (`severity: critical`). Токен, chat id и адреса — в `monitoring/.env` на web и `watchdog/.env` на mtproto.

## Схема

```
web (РФ)
  blackbox-exporter ── сайты, сертификаты, порт прокси ─┐
  node-exporter + docker-metrics ── хост web ───────────┤
  tg-relay ══ssh══▶ mtproto: node-exporter + docker-metrics ── хост mtproto
                                                        ▼
                                Prometheus ──правила──▶ Alertmanager ─┬─▶ Telegram (через tg-relay)
                                                                      └─▶ почта, только critical

mtproto
  watchdog: раз в минуту проверяет сайты web ──▶ Telegram напрямую + почта
```

- **Через mtproto.** С web `api.telegram.org` не открывается. `tg-relay` держит `ssh -D` (SOCKS) до mtproto. Через него идут уведомления в Telegram и опрос node-exporter mtproto (тот слушает только 127.0.0.1). Новых открытых портов нет.
- **Почта — второй канал для критичного.** Если лёг mtproto, туннель рвётся и Telegram с web молчит, а письмо дойдёт: TelegramRelayDown и MtprotoUnreachable — critical.
- **Обратная проверка.** Если ляжет весь web, вместе с ним ляжет и Alertmanager. Поэтому `watchdog` на mtproto сам проверяет web и пишет в Telegram и на почту.
- **Контейнеры.** `docker-metrics` (скрипт [host-metrics/docker-metrics.sh](../host-metrics/docker-metrics.sh)) раз в минуту пишет состояние всех контейнеров в textfile node-exporter: запущен ли, healthcheck, число перезапусков. На web он в `monitoring/`, на mtproto — в `host-metrics/`.

## Алерты

Пока не прошло — повтор раз в 6 часов; когда прошло — приходит ✅. Правила — [monitoring/prometheus-rules/alerts.yaml](../monitoring/prometheus-rules/alerts.yaml).

| Алерт | Когда | Важность |
|-------|-------|----------|
| SiteDown | сайт из `prometheus-targets/sites.yml` 2 минуты не отвечает 2xx | critical |
| CertExpiresSoon | до конца сертификата меньше 14 дней — NPM не продлил сам | warning |
| CertExpiresCritical | меньше 3 дней | critical |
| MtprotoUnreachable | порт 443 прокси 5 минут не принимает соединения с web | critical |
| TelegramRelayDown | туннель до mtproto не поднят 5 минут — Telegram с web не работает | critical |
| NotificationsFailing | Alertmanager не смог отправить уведомление за 15 минут | critical |
| BackupStale | успешного бэкапа нет 26 часов ([backup.md](backup.md)) | warning |
| TargetDown | Prometheus 5 минут не может опросить цель | warning |
| DiskSpaceLow | на хосте свободно меньше 15% диска 10 минут | warning |
| DiskSpaceCritical | меньше 5% | critical |
| MemoryLow | свободно меньше 10% памяти 10 минут | warning |
| OOMKill | ядро убило процесс из-за нехватки памяти | warning |
| HighLoad | нагрузка (load15) больше 1.5 на ядро 15 минут | warning |
| HostRebooted | хост загрузился меньше 10 минут назад | warning |
| ContainerDown | контейнер с политикой перезапуска не запущен 3 минуты | warning |
| ContainerUnhealthy | healthcheck контейнера не проходит 5 минут | warning |
| ContainerRestarting | больше 2 перезапусков за 15 минут | warning |
| watchdog (с mtproto) | адрес web не ответил 3 проверки подряд (~3 минуты), и когда ответил снова | Telegram + почта |

Хостовые и контейнерные алерты — для обоих серверов, в тексте указан `host` (web или mtproto). Остановил контейнер руками — ContainerDown будет приходить, пока его не удалишь (`docker rm`).

## Где что лежит

| Файл | Что |
|------|-----|
| `monitoring/prometheus-rules/alerts.yaml` | правила, тексты и важность |
| `monitoring/prometheus-targets/sites.yml` | сайты для проверки. Включил хост в NPM — добавь строку и `sv web deploy` |
| `monitoring/alertmanager.yml` | маршруты: всё → Telegram, critical → ещё почта; `${…}` — из `monitoring/.env` |
| `monitoring/blackbox.yml` | модули проверок (HTTP, TCP) |
| `monitoring/tg-relay/` | образ туннеля (alpine + openssh-client) |
| `host-metrics/` | node-exporter и docker-metrics для mtproto |
| `watchdog/` | обратная проверка на mtproto, список адресов — в его `docker-compose.yml` |

Только на серверах (в `.gitignore`):

- web: `monitoring/.env`, `monitoring/prometheus-targets/mtproto.yml` (IP прокси), `monitoring/tg-relay-secrets/` (ключ и known_hosts туннеля);
- mtproto: `watchdog/.env`.

## Правки

- `sv web deploy` после `docker compose up` запускает `monitoring/reload.sh`: проверяет конфиг Prometheus и перезапускает Prometheus, blackbox и Alertmanager. Именно перезапуск, а не SIGHUP: конфиги примонтированы файлами, `git pull` заменяет файл новым, а работающий контейнер продолжает видеть старый.
- Loki, Promtail и Grafana `reload.sh` не трогает — после правки их конфигов на сервере `docker compose restart <сервис>`.
- `watchdog/watch.sh`, `host-metrics/docker-metrics.sh` — после правки на сервере `docker compose restart` в папке сервиса.
- Если mtproto лежит, `tg-relay` не станет healthy и `sv web deploy` закончится ошибкой на monitoring. Остальные сервисы к этому моменту уже подняты.

## Проверить, что доходит

Alertmanager (с web):

```sh
sv web
docker exec alertmanager amtool --alertmanager.url=http://localhost:9093 alert add \
    alertname=Test severity=critical --annotation='summary="Проверка оповещений"' \
    --end="$(date -u -d '+2 min' +%Y-%m-%dT%H:%M:%SZ)"
```

С `severity=critical` придёт в Telegram и на почту, без него — только в Telegram. Сколько ушло и сколько не дошло — `curl -s localhost:9093/metrics | grep alertmanager_notifications`. Куда пойдёт алерт с такими метками, без отправки: `docker exec alertmanager amtool config routes test --config.file=/tmp/alertmanager.yml severity=critical`.

watchdog (с mtproto): `docker exec watchdog sh /watch.sh test` — Telegram и почта.

## Туннель до mtproto: как настроен

На mtproto — пользователь `tgrelay` без shell и пароля. В его `authorized_keys` ключ web ограничен: `restrict,port-forwarding,permitopen="api.telegram.org:443",permitopen="127.0.0.1:9100"`. Войти в shell или открыть соединение куда-то ещё этим ключом нельзя. Ограничения читаются при подключении — после правки `authorized_keys` нужен `docker compose restart tg-relay` на web.

Повторить на новых серверах:

```sh
# web
d=~/server-setup/monitoring/tg-relay-secrets
install -d -m700 $d && ssh-keygen -q -t ed25519 -N "" -C tg-relay@web -f $d/id_ed25519
ssh-keyscan -t ed25519 <IP mtproto> >$d/known_hosts   # отпечаток сверить с ~/.ssh/known_hosts на Mac
chmod 600 $d/*

# mtproto
useradd --system --create-home --home-dir /var/lib/tgrelay --shell /usr/sbin/nologin tgrelay
usermod -p '*' tgrelay
install -d -m700 -o tgrelay -g tgrelay /var/lib/tgrelay/.ssh
echo 'restrict,port-forwarding,permitopen="api.telegram.org:443",permitopen="127.0.0.1:9100" <id_ed25519.pub с web>' \
    >/var/lib/tgrelay/.ssh/authorized_keys
chown tgrelay: /var/lib/tgrelay/.ssh/authorized_keys && chmod 600 /var/lib/tgrelay/.ssh/authorized_keys
```
