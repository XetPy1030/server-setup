# Дашборд «Серверы»

Главная страница grafana.xetpy.ru: всё ли в порядке на web и mtproto. Файл — [monitoring/grafana-dashboards/servers.json](../monitoring/grafana-dashboards/servers.json).

## Что на нём

Сверху — плитки. Всё зелёное — всё в порядке.

| Плитка | Что значит |
|--------|------------|
| Critical, Warning | сколько алертов сработало сейчас ([alerts.md](alerts.md)) |
| Сайты | сколько сайтов из `prometheus-targets/sites.yml` не отвечают |
| Контейнеры | сколько контейнеров на обоих хостах остановлены или unhealthy. Одноразовые (`restart: no`) не считаются |
| Хосты | отвечает ли node-exporter на web и mtproto |
| Прокси mtproto | принимает ли порт 443 прокси соединения (проверка с web) |
| Уведомления | туннель tg-relay поднят и Alertmanager за 15 минут ни разу не ошибся при отправке |
| Бэкап | сколько часов прошло с последнего успешного бэкапа, красное — больше 26 |

Под плитками — таблица сработавших алертов: что случилось, на каком хосте, сколько длится. Ниже разделы:

- **Сайты** — статус, код ответа, время ответа и сколько дней осталось сертификату; история доступности за выбранный период.
- **Хосты** — CPU, память, swap, диск, аптайм сейчас и графики за период. Сети нет: node-exporter работает в сети контейнера и видит только её трафик.
- **Контейнеры** — все контейнеры обоих хостов, проблемные сверху, и сколько раз Docker перезапускал их за период; история состояний.
- **Ошибки в логах** — строки с error / exception / fatal / panic / traceback из логов контейнеров web (Loki). Строки уровня info и debug и 404 от сканеров в nginx сайтов отфильтрованы. Логов mtproto в Loki нет.

На графиках красными метками отмечено время, когда срабатывали алерты.

## Другие дашборды

- **obsidiantime** ([obsidiantime.json](../monitoring/grafana-dashboards/obsidiantime.json)) — Django сайта obsidiantime.ru: запросы в секунду, доля 5xx, время ответа, страницы за период. Метрики со всех воркеров gunicorn собираются через multiprocess-режим `prometheus_client` (`PROMETHEUS_MULTIPROC_DIR` в `docker-compose.prod.yml` сайта). Без него каждый воркер считал своё, Prometheus попадал в случайный и графики были бессмысленными.

## Правки

Дашборд подключён через provisioning ([monitoring/grafana-provisioning/dashboards/](../monitoring/grafana-provisioning/dashboards/)), сохранить его из интерфейса Grafana нельзя. Источник правды — JSON в репе:

1. В Grafana поменять панели как нужно, без сохранения.
2. Export → Export as JSON (без «Export for sharing externally») → скопировать в `servers.json`.
3. Commit и `sv web deploy monitoring`. Grafana перечитывает папку раз в 30 секунд, перезапуск не нужен.

Новый дашборд — ещё один `.json` в `grafana-dashboards/`. Источники данных в запросах — через скрытые переменные `$prom` и `$loki`, а не по uid: uid разный в каждой установке Grafana.

Правка `grafana-provisioning/` или переменных Grafana в `docker-compose.yml` применяется только при перезапуске контейнера: `sv web deploy monitoring` пересоздаёт его сам, если поменялся compose; после правки только provisioning — на сервере `docker compose restart grafana` в `monitoring/`.
