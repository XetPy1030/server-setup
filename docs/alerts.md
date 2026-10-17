# Оповещения

Статус: **план** (этап 3 в [roadmap.md](roadmap.md)).

## Схема

```
web (РФ)
  blackbox-exporter ─┐
  node-exporter ─────┼─▶ Prometheus ──правила──▶ Alertmanager ─┬─▶ почта (smtp.mail.ru)
  бэкап (метрика) ───┘                                         └─▶ tg-relay ══ssh══▶ mtproto ──▶ api.telegram.org

mtproto (Telegram доступен)
  cron раз в 5 минут: живы ли сайты web ──▶ api.telegram.org напрямую
```

- **Telegram через mtproto.** С web `api.telegram.org` не открывается, с mtproto открывается. `tg-relay` — контейнер в `monitoring/` с `ssh -D` (SOCKS) на mtproto под отдельным пользователем. В его `authorized_keys` стоит `restrict,port-forwarding,permitopen="api.telegram.org:443"` — ничего, кроме соединения с Telegram, этот ключ не умеет. Новых открытых портов нет, Alertmanager ходит в Telegram через `proxy_url: socks5://tg-relay:1080`.
- **Почта — второй канал.** Если лёг mtproto, туннель рвётся и Telegram с web молчит. Письмо через smtp.mail.ru (с web доступен) дойдёт.
- **Обратная проверка.** Если ляжет весь web, вместе с ним ляжет и Alertmanager. Поэтому mtproto сам раз в 5 минут проверяет сайты web и пишет в Telegram напрямую.
- **Alertmanager, а не алерты Grafana:** правила лежат в git рядом с конфигом Prometheus, у получателя Telegram есть явный `proxy_url`.

## Что проверяем

| Алерт | Условие | Каналы |
|-------|---------|--------|
| Сайт не отвечает | blackbox `http_2xx` неуспешен 2 минуты — для каждого включённого хоста NPM | Telegram, почта |
| Сертификат скоро истекает | осталось меньше 14 дней | Telegram, почта |
| mtproto недоступен из РФ | blackbox `tcp_connect` к mtproto.ru:443 с web неуспешен 5 минут | почта (Telegram мог лечь вместе с mtproto) |
| Мало места на диске | свободно меньше 15% | Telegram, почта |
| Мало памяти | доступно меньше 10% в течение 10 минут | Telegram, почта |
| Цель Prometheus не отвечает | `up == 0` 5 минут | Telegram, почта |
| Нет свежего бэкапа | последний успешный старше 26 часов ([backup.md](backup.md)) | Telegram, почта |
| web недоступен | проверка с mtproto | Telegram |

Список сайтов для blackbox — в `monitoring/` рядом с конфигом Prometheus, обновляется при добавлении хоста в NPM.

## Что нужно от тебя

1. В Telegram: @BotFather → `/newbot` → токен бота.
2. Написать боту любое сообщение (или добавить его в группу) — по этому узнаем chat id.
3. Почта: в настройках mail.ru → «Безопасность» → «Пароли для внешних приложений» создать пароль для SMTP. И адрес, куда слать — можно тот же ящик.

Токен бота, пароль приложения и адреса лежат только на сервере (`monitoring/alertmanager-secrets/`, в `.gitignore`). Удобнее всего положить их туда самому через `sv web`, чтобы они не проходили через чат.
