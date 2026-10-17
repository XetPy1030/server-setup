#!/bin/sh
# Раз в минуту проверяет WATCH_URLS. Пишет в Telegram, когда адрес не ответил
# 3 проверки подряд (~3 минуты) и когда ответил снова.
set -u

send() {
    curl -fsS -o /dev/null --max-time 20 \
        "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=$1" \
        || echo "не удалось отправить в Telegram: $1"
}

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
                send "✅ $url снова отвечает (проверка с mtproto)"
            fi
            echo 0 >"$f"
        else
            n=$((n + 1))
            echo "$n" >"$f"
            if [ "$n" -eq 3 ]; then
                echo "$url не отвечает"
                send "🔴 $url не отвечает 3 минуты (проверка с mtproto)"
            fi
        fi
    done
    sleep 60
done
