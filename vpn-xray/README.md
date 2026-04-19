Для условий РФ (DPI, блокировки по протоколам и SNI) оптимальным выбором **не-WireGuard** VPN является **Xray-core** с протоколом `VLESS + WebSocket + TLS`. 

Почему это работает в России:
- 🔒 **Полное шифрование**: TLS 1.3 + шифрование полезной нагрузки VLESS
- 🌐 **Маскировка под HTTPS**: WebSocket-трафик на порту 443 неразличим для DPI для обычного веб-трафика
- 🚫 **Не WireGuard**: обходит блокировки по статичным рукопожатиям WG
- ⚡ **Активная разработка**: поддерживается сообществом, регулярно обновляется сигнатуры обхода

Ниже готовый комплект файлов. Просто создайте папку, сохраните файлы и запустите.

---

### 📁 Структура проекта
```
vpn-xray/
├── docker-compose.yml
├── .env
├── config.json
└── certs/          # сюда положите cert.pem и key.pem
```

---

### 📄 `docker-compose.yml`
```yaml
version: "3.8"

services:
  xray:
    image: ghcr.io/xtls/xray-core:latest
    container_name: xray-vpn
    restart: unless-stopped
    ports:
      - "443:443/tcp"
    volumes:
      - ./config.json:/etc/xray/config.json:ro
      - ./certs:/etc/xray/certs:ro
    environment:
      - TZ=Europe/Moscow
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.rp_filter=0
    dns:
      - 8.8.8.8
      - 1.1.1.1
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

---

### 📄 `.env` (переименуйте из `.env-example`)
```env
# Уникальный идентификатор пользователя (сгенерируйте: uuidgen или openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/')
XRAY_UUID=ваш-uuid-здесь

# Домен, на который выданы TLS-сертификаты (обязательно должен резолвиться на IP сервера)
XRAY_DOMAIN=vpn.yourdomain.com

# Путь для WebSocket (можно оставить как есть)
XRAY_WS_PATH=/xray
```

---

### 📄 `config.json`
```json
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "__XRAY_UUID__",
            "flow": "",
            "email": "user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/xray/certs/cert.pem",
              "keyFile": "/etc/xray/certs/key.pem"
            }
          ],
          "minVersion": "1.2",
          "cipherSuites": "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384:TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        },
        "wsSettings": {
          "path": "__XRAY_WS_PATH__",
          "headers": {
            "Host": "__XRAY_DOMAIN__"
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
```

---

### 🛠 Инструкция по запуску

1. **Создайте директорию и файлы**
   ```bash
   mkdir -p vpn-xray/certs && cd vpn-xray
   ```

2. **Сгенерируйте UUID**
   ```bash
   uuidgen  # или используйте онлайн-генератор
   ```
   Вставьте его в `.env` вместо `ваш-uuid-здесь`.

3. **Получите TLS-сертификаты** (обязательно для работы)
   ```bash
   # Пример с Let's Encrypt (требует домена,指向щего на ваш сервер)
   certbot certonly --standalone -d vpn.yourdomain.com
   sudo cp /etc/letsencrypt/live/vpn.yourdomain.com/fullchain.pem certs/cert.pem
   sudo cp /etc/letsencrypt/live/vpn.yourdomain.com/privkey.pem certs/key.pem
   ```
   > ⚠️ Без валидного TLS-сертификата трафик не будет шифроваться корректно и может блокироваться DPI.

4. **Подставьте переменные в config.json**
   ```bash
   sed -i "s/__XRAY_UUID__/$XRAY_UUID/g" config.json
   sed -i "s/__XRAY_WS_PATH__/$XRAY_WS_PATH/g" config.json
   sed -i "s/__XRAY_DOMAIN__/$XRAY_DOMAIN/g" config.json
   ```

5. **Запустите**
   ```bash
   docker compose up -d
   ```

6. **Откройте порт в фаерволе**
   ```bash
   sudo ufw allow 443/tcp
   sudo ufw reload
   ```

---

### 📱 Настройка клиента (V2RayNG / Nekoray / Streisand / Sing-box)
Выберите тип протокола `VLESS` + `WebSocket` + `TLS`:
| Параметр | Значение |
|----------|----------|
| Адрес | `ваш-домен.com` или IP сервера |
| Порт | `443` |
| ID | ваш UUID из `.env` |
| Сеть | `ws` |
| Путь WS | `/xray` |
| Безопасность | `tls` |
| Домен сервера (SNI) | `ваш-домен.com` |

> ✅ Включите `Allow Insecure` только если используете самоподписанный сертификат (не рекомендуется для РФ).

---

### 🇷🇺 Важные нюансы для России
1. **Домен обязателен**: Бесплатные/публичные домены быстро попадают в реестры РКН. Используйте свой домен `.ru`/`.com`/`.net` и держите его на Cloudflare.
2. **Cloudflare Proxy**: Включите `Proxy status: Proxied` в Cloudflare. Это скроет реальный IP сервера и добавит дополнительную обфускацию.
3. **REALITY**: Если трафик всё ещё детектится, перейдите на протокол `VLESS + TCP + REALITY`. Он не требует сертификатов и обходит SNI-блокировки, но требует более сложной конфигурации.
4. **Обновление**: Раз в месяц обновляйте образ: `docker compose pull && docker compose up -d`
5. **Безопасность**: Никогда не публикуйте `.env` или `config.json` в публичных репозиториях.

Эта связка шифрует весь трафик, маскируется под обычный HTTPS и активно используется для обхода DPI в РФ. При необходимости могу предоставить версию с `REALITY` или автоматическим выпуском сертификатов внутри контейнера.