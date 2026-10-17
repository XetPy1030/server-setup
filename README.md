# server-setup

Конфиги всех серверов в одной репе. Правки — только на Mac, сервер делает `git pull` и ничего не коммитит.

```sh
./sv web                     # зайти по ssh
./sv web deploy              # git push → на сервере git pull + up всех сервисов из hosts/web
./sv web deploy monitoring   # только один сервис
./sv web ps                  # что запущено
./sv web logs grafana        # хвост логов
```

`<хост>` — это файл в [hosts/](hosts/) (список сервисов) и алиас в `~/.ssh/config`:

```
Host web
    HostName xetpy.ru
    User root
```

## Серверы и сервисы

| Хост | Сервис | Что это | Снаружи | Только 127.0.0.1 |
|------|--------|---------|---------|------------------|
| web (xetpy.ru, РФ) | [nginx](nginx/) | Nginx Proxy Manager | 80, 443; админка npm.xetpy.ru | 81 |
| | [portainer](portainer/) | Portainer | portainer.xetpy.ru | 9443 |
| | [monitoring](monitoring/) | Grafana, Loki, Promtail, Prometheus, node-exporter, blackbox, Alertmanager, tg-relay — [оповещения](docs/alerts.md) | grafana.xetpy.ru | 8512, 3100, 9090, 9093, 9100 |
| — | [vpn](vpn/) | WireGuard (wg-easy) | 51820/udp, панель 51821 | |
| — | [vpn-xray](vpn-xray/) | 3X-UI, VLESS + Reality | 443, панель | |
| mtproto | [mtproto](mtproto/) | Telegram MTProto proxy, fake TLS | 443 | |
| | [watchdog](watchdog/) | обратная проверка: живы ли сайты web → Telegram и почта | | |
| | [host-metrics](host-metrics/) | node-exporter и состояние контейнеров для Prometheus на web | | 9100 |

vpn и vpn-xray сейчас нигде не развёрнуты — конфиги лежат на будущее. Под каждый VPN нужен свой сервер: nginx, vpn-xray и mtproto все хотят 443.

Сайты живут отдельными репами в `/root/projects/<имя>` на web и подключаются к NPM через общую сеть `web-network` — см. [nginx/template-compose.yml](nginx/template-compose.yml).

## Устройство

- `<сервис>/docker-compose.yml` — один сервис, одна папка. Поднимается через `./up.sh <сервис>` из корня; скрипт ждёт, пока контейнеры станут healthy, иначе падает с ошибкой.
- `<сервис>/.env` — секреты, только на сервере. Шаблон — `.env.example` рядом.
- Данные (`nginx/data`, `vpn/wireguard`, `vpn-xray/db` …) лежат внутри клона и перечислены в `.gitignore`. Никогда не делать `git clean -x` на сервере.
- Версии образов зафиксированы: обновление = поменять тег, commit, `./sv <хост> deploy`.
- [host/](host/) — настройки самой машины (лимит journald, ротация логов Docker, автообновления), ставятся один раз: `host/install.sh` целиком или по частям, см. начало скрипта.

## Документация

- [docs/roadmap.md](docs/roadmap.md) — план работ по этапам: что сделано, что дальше, что нужно от тебя.
- [docs/backup.md](docs/backup.md) — бэкапы web на Яндекс Диск.
- [docs/alerts.md](docs/alerts.md) — оповещения в Telegram и на почту.
- [mtproto/README.md](mtproto/README.md), [vpn-xray/README.md](vpn-xray/README.md) — заметки по отдельным сервисам.

## Новый сервер

```sh
git clone https://github.com/XetPy1030/server-setup.git ~/server-setup
cd ~/server-setup && host/install.sh
cp <сервис>/.env.example <сервис>/.env   # и заполнить
```

На Mac: добавить `hosts/<имя>` со списком сервисов и алиас в `~/.ssh/config`, затем `./sv <имя> deploy`.
