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
| | [monitoring](monitoring/) | Grafana, Loki, Promtail, Prometheus, node-exporter | grafana.xetpy.ru | 8512, 3100, 9090, 9100 |
| vpn (vpn.xetpy.ru) | [vpn](vpn/) | WireGuard (wg-easy) | 51820/udp, панель 51821 | |
| vpn3 (vpn3.xetpy.ru) | [vpn-xray](vpn-xray/) | 3X-UI, VLESS + Reality | 443, панель | |
| — | [mtproto](mtproto/) | Telegram MTProto proxy | 443 | |

nginx, vpn-xray и mtproto все хотят 443 — на одном сервере уживается только один из них.

Сайты живут отдельными репами в `/root/projects/<имя>` на web и подключаются к NPM через общую сеть `web-network` — см. [nginx/template-compose.yml](nginx/template-compose.yml).

## Устройство

- `<сервис>/docker-compose.yml` — один сервис, одна папка. Поднимается через `./up.sh <сервис>` из корня.
- `<сервис>/.env` — секреты, только на сервере. Шаблон — `.env.example` рядом.
- Данные (`nginx/data`, `vpn/wireguard`, `vpn-xray/db` …) лежат внутри клона и перечислены в `.gitignore`. Никогда не делать `git clean -x` на сервере.
- Версии образов зафиксированы: обновление = поменять тег, commit, `./sv <хост> deploy`.
- [host/](host/) — настройки самой машины (ротация логов Docker, лимит journald), ставятся один раз: `host/install.sh`.

## Новый сервер

```sh
git clone https://github.com/XetPy1030/server-setup.git ~/server-setup
cd ~/server-setup && host/install.sh
cp <сервис>/.env.example <сервис>/.env   # и заполнить
```

На Mac: добавить `hosts/<имя>` со списком сервисов и алиас в `~/.ssh/config`, затем `./sv <имя> deploy`.
