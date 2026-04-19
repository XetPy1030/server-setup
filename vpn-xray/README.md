                                                                                                                                                                                                                            Вот **полный, готовый к запуску комплект** для 3X-UI. В России в 2026 году оптимально использовать протокол **VLESS + Reality** (не требует домена/сертификатов, маскируется под реальный HTTPS-трафик, устойчив к DPI). Конфигурация WebSocket+TLS тоже описана как fallback.

---

## 📁 Структура проекта

```
3x-ui-vpn/
├── docker-compose.yml
├── .env-example
├── db/          # создастся автоматически
└── cert/        # создастся автоматически (для TLS, если понадобится)
```

---

## 📄 `docker-compose.yml`

```yaml
version: "3.8"

services:
  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    restart: unless-stopped
    network_mode: host  # Обязательно для корректной работы портов и Reality
    env_file: .env
    volumes:
      - ./db:/etc/x-ui/
      - ./cert:/root/cert/
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.tcp_congestion_control=bbr
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

---

## 📄 `.env-example` (переименуйте в `.env`)

```env
# Часовой пояс сервера
TZ=Europe/Moscow

# Порт веб-панели (по умолчанию 2053, смените на случайный >10000)
PANEL_PORT=2053

# Ядро Xray (не менять)
XRAY_VMESS_AEAD_FORCED=false
```

---

## 🚀 Пошаговый запуск

1. **Создайте папку и файлы**
   ```bash
   mkdir -p 3x-ui-vpn && cd 3x-ui-vpn
   # Вставьте docker-compose.yml и .env (из .env-example)
   ```

2. **Запустите контейнер**
   ```bash
   docker compose up -d
   ```

3. **Убедитесь, что работает**
   ```bash
   docker ps | grep 3x-ui
   curl -s http://localhost:2053 | head -5
   ```

4. **Откройте порт в фаерволе**
   ```bash
   sudo ufw allow 443/tcp   # Для VPN трафика
   sudo ufw allow 2053/tcp  # Для панели (временно, потом сменим)
   sudo ufw reload
   ```

---

## 🌐 Настройка веб-панели (первичная)

1. Откройте `http://<IP_ВАШЕГО_СЕРВЕРА>:2053`
2. Войдите с `admin` / `admin` (при первом входе система попросит сменить логин/пароль)
3. **Сразу смените порт панели**: `Панель` → `Настройки панели` → `Порт панели` → введите `15832` (или любой
   случайный) → `Сохранить`
4. Теперь панель доступна по `http://IP:15832`
5. Закройте старый порт: `sudo ufw delete allow 2053/tcp`

---

## ⚙️ Создание Inbound (VLESS + Reality)

> 💡 **Почему Reality?** Не нужны домен, сертификаты, Cloudflare. Трафик выглядит как обычный HTTPS к `microsoft.com` или
`google.com`. DPI не детектит.

1. В панели: `Inbounds` → `+` (Добавить)
2. Заполните:
   | Поле | Значение |
   |------|----------|
   | `Протокол` | `VLESS` |
   | `Порт` | `443` |
   | `ID` | 📋 `Сгенерировать` |
   | `Flow` | Оставьте пустым (или `xtls-rprx-vision` для Linux/Android) |
   | `Транспорт` | `TCP` |
   | `TLS` | `Reality` |
   | `SNI` | `www.microsoft.com` (или `www.google.com`) |
   | `Dest` | `www.microsoft.com:443` |
   | `Private Key` | 📋 `Сгенерировать` |
   | `Public Key` | Скопируйте после генерации (понадобится клиенту) |
   | `Short Id` | 📋 `Сгенерировать` (или оставьте `*`) |
   | `SpiderX` | `/` |

3. Нажмите `Добавить` → `Сохранить`
4. В списке появится ваш inbound. Нажмите `👁` (QR/Ссылка) → скопируйте `vless://...` или запишите параметры вручную.

---

## 📱 Настройка клиентов

### 🔹 Android / Windows / iOS (Hiddify / v2rayNG / Streisand / Nekoray)

| Параметр    | Значение                                  |
|-------------|-------------------------------------------|
| Протокол    | `VLESS`                                   |
| Адрес       | `IP_вашего_сервера`                       |
| Порт        | `443`                                     |
| UUID        | Ваш `ID` из панели                        |
| Flow        | (пусто или `xtls-rprx-vision`)            |
| Security    | `Reality`                                 |
| SNI         | `www.microsoft.com`                       |
| PublicKey   | Скопированный из панели                   |
| ShortId     | Скопированный из панели                   |
| Fingerprint | `chrome` (обязательно для обхода JA3/JA4) |
| Transport   | `TCP`                                     |

> ✅ Включите `Allow Insecure` только если клиент ругается на сертификат Reality (обычно не требуется).

---

## 🛡 Безопасность и оптимизация для РФ

### 1. Включите BBR (ускорение TCP)

```bash
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 2. Закройте всё, кроме нужного

```bash
sudo ufw default deny incoming
sudo ufw allow 22/tcp    # SSH (лучше сменить порт!)
sudo ufw allow 443/tcp   # VPN
sudo ufw allow 15832/tcp # Панель (по желанию, можно скрыть за IP-whitelist)
sudo ufw enable
```

### 3. Авто-обновление контейнера

```bash
# Раз в месяц выполняйте:
cd /путь/к/3x-ui-vpn && docker compose pull && docker compose up -d
```

### 4. Бэкап базы данных

```bash
# В панели: Настройки → Бэкап → Скачать
# Или вручную:
tar -czf xui-backup-$(date +%F).tar.gz ./db
```

---

## 🔄 Альтернатива: VLESS + WebSocket + TLS (если нужен домен)

Если вы хотите использовать свой домен и Cloudflare:

1. В панели создайте inbound с `TLS` вместо `Reality`
2. `SNI` = ваш домен
3. `Порт` = `443`
4. `Транспорт` = `WebSocket` → `Path` = `/xray`
5. Загрузите `cert.pem` и `key.pem` в папку `./cert/` контейнера
6. В клиенте укажите `SNI = ваш_домен`, `Security = TLS`, `Path = /xray`

> ⚠️ В РФ TLS+WS часто детектится по SNI и поведению заголовков. Reality стабильнее.

---

## 🆘 Диагностика проблем

```bash
# Логи панели
docker logs 3x-ui

# Логи ядра Xray
docker exec 3x-ui cat /etc/x-ui/xray.log | tail -20

# Проверка порта 443
sudo ss -tlnp | grep 443

# Тест Reality-рукопожатия (с клиента)
openssl s_client -connect IP_СЕРВЕРА:443 -servername www.microsoft.com
```

| Ошибка                 | Решение                                                      |
|------------------------|--------------------------------------------------------------|
| `connection refused`   | Откройте порт 443 в `ufw` и у хостинг-провайдера             |
| `invalid reality key`  | Скопируйте `PublicKey` и `ShortId` точно из панели           |
| `tls handshake failed` | Убедитесь, что `Fingerprint = chrome` в клиенте              |
| Панель не открывается  | Проверьте `docker logs 3x-ui`, смените порт, проверьте `ufw` |

---

Этот комплект **полностью автономен**, не требует внешних скриптов установки и работает из коробки. Если нужно добавить:

- Автоматический ротационный `ShortId`
- Интеграцию с Telegram-ботом для уведомлений
- Reverse Proxy для панели с Cloudflare
- Скрипт мониторинга блокировок

Напишите — дополню под ваш сценарий. 🛡️