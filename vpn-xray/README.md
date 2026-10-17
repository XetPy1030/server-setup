# vpn-xray — 3X-UI (VLESS + Reality)

Работает на vpn3. `network_mode: host`, занимает 443 — с nginx и mtproto на одном сервере не уживается.

1. `cp .env.example .env`, затем `./sv vpn3 deploy` с Mac (или `./up.sh vpn-xray` на сервере).
2. Панель: `http://<IP>:2053`, вход `admin` / `admin` — сразу сменить логин и пароль.
3. «Настройки панели» → порт панели на случайный > 10000. Открыть в ufw его и `443/tcp`, закрыть 2053.
4. Inbound: VLESS, порт 443, транспорт TCP, Security Reality, SNI `www.microsoft.com`, Dest `www.microsoft.com:443`; ID, ключи и Short Id — «Сгенерировать».
5. Клиенту — ссылка `vless://…` из панели (кнопка QR), fingerprint `chrome`.

Сертификат для панели по домену (пути в панели: `/root/cert/cert.pem`, `/root/cert/privkey.pem`):

```sh
certbot certonly --standalone -d vpn3.xetpy.ru
cp /etc/letsencrypt/live/vpn3.xetpy.ru/fullchain.pem cert/cert.pem
cp /etc/letsencrypt/live/vpn3.xetpy.ru/privkey.pem cert/privkey.pem
```

Бэкап: `tar czf xui-$(date +%F).tar.gz db/`. Логи: `docker logs 3x-ui`.
