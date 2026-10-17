#!/bin/sh
# Раз в минуту проверяет WATCH_URLS. Когда адрес не ответил 3 проверки подряд (~3 минуты)
# и когда ответил снова — пишет в Telegram и на почту: если лёг весь web, его
# Alertmanager молчит, и это единственное уведомление.
set -u

send() {
    curl -fsS -o /dev/null --max-time 20 \
        "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=$1" \
        || echo "не удалось отправить в Telegram: $1"
}

email() {
    subject="=?UTF-8?B?$(printf %s "$1" | base64 | tr -d '\n')?="
    printf 'From: %s\r\nTo: %s\r\nSubject: %s\r\nDate: %s\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n%s\r\n' \
        "$SMTP_USER" "$ALERT_EMAIL_TO" "$subject" "$(date -R)" "$1" |
        curl -fsS --max-time 30 --url smtp://smtp.mail.ru:587 --ssl-reqd \
            --user "$SMTP_USER:$SMTP_PASSWORD" --mail-from "$SMTP_USER" --mail-rcpt "$ALERT_EMAIL_TO" -T - \
        || echo "не удалось отправить письмо: $1"
}

alert() { send "$1"; email "$1"; }

# docker exec watchdog sh /watch.sh test — проверить оба канала
if [ "${1:-}" = test ]; then
    alert "🧪 Проверка watchdog на mtproto: Telegram и почта"
    exit
fi

mkdir -p /tmp/fails
echo "слежу за: $WATCH_URLS"
send "👀 watchdog на mtproto запущен, слежу за web: $WATCH_URLS"

while :; do
    for url in $WATCH_URLS; do
        f=/tmp/fails/$(printf %s "$url" | tr -c 'a-zA-Z0-9' _)
        n=$(cat "$f" 2>/dev/null || echo 0)
        if curl -fsS -o /dev/null --max-time 15 "$url" 2>/dev/null; then
            if [ "$n" -ge 3 ]; then
                echo "$url снова отвечает"
                alert "✅ $url снова отвечает (проверка с mtproto)"
            fi
            echo 0 >"$f"
        else
            n=$((n + 1))
            echo "$n" >"$f"
            if [ "$n" -eq 3 ]; then
                echo "$url не отвечает"
                alert "🔴 $url не отвечает 3 минуты (проверка с mtproto)"
            fi
        fi
    done
    sleep 60
done
