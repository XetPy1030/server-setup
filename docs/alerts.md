# Оповещения

Работают с 2026-10-17 (этап 3 в [roadmap.md](roadmap.md)). Каналы: Telegram-бот и почта mail.ru. Токен, chat id и адреса — в `monitoring/.env` на web.

## Схема

```
web (РФ)
  blackbox-exporter ─┐
  node-exporter ─────┼─▶ Prometheus ──правила──▶ Alertmanager ─┬─▶ почта (smtp.mail.ru:587)
  alertmanager ──────┘                                         └─▶ tg-relay ══ssh══▶ mtproto ──▶ api.telegram.org

mtproto
  watchdog: раз в минуту проверяет сайты web ──▶ api.telegram.org напрямую
```

- **Telegram через mtproto.** С web `api.telegram.org` не открывается, с mtproto открывается. `tg-relay` держит `ssh -D` (SOCKS) до mtproto, Alertmanager ходит через него (`proxy_url: socks5://tg-relay:1080`). Новых открытых портов нет.
- **Почта — второй канал.** Если лёг mtproto, туннель рвётся и Telegram с web молчит, а письмо дойдёт.
- **Обратная проверка.** Если ляжет весь web, вместе с ним ляжет и Alertmanager. Поэтому `watchdog` на mtproto сам проверяет web и пишет в Telegram.
- **Alertmanager, а не алерты Grafana:** правила лежат в git, у Telegram-получателя есть явный прокси.

## Алерты

Все алерты web уходят в оба канала. Пока не прошло — повтор раз в 6 часов; когда прошло — тоже приходит сообщение.

| Алерт | Когда срабатывает |
|-------|-------------------|
| SiteDown | сайт из `prometheus-targets/sites.yml` 2 минуты не отвечает 2xx |
| CertExpiresSoon | до конца сертификата меньше 14 дней (держится час) |
| MtprotoUnreachable | порт 443 прокси 5 минут не принимает соединения с web |
| TelegramRelayDown | туннель до Telegram не поднят 5 минут — уведомления идут только на почту |
| NotificationsFailing | Alertmanager не смог отправить уведомление за последние 15 минут |
| TargetDown | Prometheus 5 минут не может опросить цель. Если это blackbox — проверки сайтов тоже не работают |
| DiskSpaceLow | на web свободно меньше 15% диска 10 минут |
| MemoryLow | на web свободно меньше 10% памяти 10 минут |
| watchdog (с mtproto) | адрес web не ответил 3 проверки подряд (~3 минуты), и когда ответил снова |

## Где что лежит

| Файл | Что |
|------|-----|
| `monitoring/prometheus-rules/alerts.yaml` | правила алертов и тексты |
| `monitoring/prometheus-targets/sites.yml` | сайты для проверки. Включил хост в NPM — добавь строку и `sv web deploy` |
| `monitoring/alertmanager.yml` | куда и как слать; `${…}` подставляются из `monitoring/.env` |
| `monitoring/blackbox.yml` | модули проверок (HTTP, TCP) |
| `monitoring/tg-relay/` | образ туннеля (alpine + openssh-client) |
| `watchdog/` | обратная проверка на mtproto, список адресов — в его `docker-compose.yml` |

Только на серверах (в `.gitignore`):

- web: `monitoring/.env`, `monitoring/prometheus-targets/mtproto.yml` (IP прокси), `monitoring/tg-relay-secrets/` (ключ и known_hosts туннеля);
- mtproto: `watchdog/.env`.

## Правки

- `sv web deploy` после `docker compose up` запускает `monitoring/reload.sh`: Prometheus проверяет и перечитывает конфиг и правила, blackbox перечитывает модули, Alertmanager перезапускается (его конфиг собирается из шаблона при старте).
- Loki, Promtail и Grafana `reload.sh` не трогает — после правки их конфигов на сервере `docker compose restart <сервис>`.
- `watchdog/watch.sh` — после правки на mtproto `docker compose restart watchdog`.
- Если mtproto лежит, `tg-relay` не станет healthy и `sv web deploy` закончится ошибкой на monitoring. Остальные сервисы к этому моменту уже подняты.

## Проверить, что доходит

```sh
sv web
docker exec alertmanager amtool --alertmanager.url=http://localhost:9093 alert add \
    alertname=Test --annotation='summary="Проверка оповещений"' \
    --end="$(date -u -d '+2 min' +%Y-%m-%dT%H:%M:%SZ)"
```

Через ~30 секунд придёт 🔴 в Telegram и письмо, через несколько минут — ✅. Сколько ушло и сколько не дошло — `curl -s localhost:9093/metrics | grep alertmanager_notifications`. Если не дошло: `docker logs alertmanager` и `docker logs tg-relay`.

## Туннель до Telegram: как настроен

На mtproto — пользователь `tgrelay` без shell и пароля. В его `authorized_keys` ключ web ограничен: `restrict,port-forwarding,permitopen="api.telegram.org:443"`. Войти в shell или открыть соединение куда-то ещё этим ключом нельзя.

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
echo 'restrict,port-forwarding,permitopen="api.telegram.org:443" <id_ed25519.pub с web>' >/var/lib/tgrelay/.ssh/authorized_keys
chown tgrelay: /var/lib/tgrelay/.ssh/authorized_keys && chmod 600 /var/lib/tgrelay/.ssh/authorized_keys
```
