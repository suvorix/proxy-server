#!/bin/bash
# =============================================================================
# Установщик 3proxy с несколькими IP
#
# Использование:
#   chmod +x install-proxy.sh
#   ./install-proxy.sh <логин> <пароль> <IP1,IP2,IP3...>
#
# Пример:
#   ./install-proxy.sh suvorix MyStrongPass 1.2.3.4,1.2.3.5,1.2.3.6
#
# Результат:
#   Для каждого IP создаются два порта:
#     SOCKS5: начиная с 1080
#     HTTP:   начиная с 3080
#   Все порты открываются в UFW (если он установлен).
# =============================================================================

set -e

# --- Проверка аргументов ---
if [ "$#" -ne 3 ]; then
    echo "Ошибка: неверное количество аргументов."
    echo "Использование: $0 <логин> <пароль> <IP1,IP2,...>"
    exit 1
fi

PROXY_USER="$1"
PROXY_PASS="$2"
IP_LIST="$3"

if [ "$(id -u)" -ne 0 ]; then
    echo "Ошибка: скрипт должен быть запущен от root (sudo)." >&2
    exit 1
fi

# --- Установка 3proxy ---
echo ">>> Установка 3proxy..."
apt update
apt install -y 3proxy ufw curl

# --- Формирование конфигурации ---
echo ">>> Генерация конфигурации..."

CONFIG_FILE="/etc/3proxy/3proxy.cfg"

# Базовые настройки
cat > "$CONFIG_FILE" <<EOF
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
log /var/log/3proxy/3proxy.log D
rotate 60

users ${PROXY_USER}:CL:${PROXY_PASS}
auth strong
allow ${PROXY_USER}
EOF

# Переменные для нумерации портов
SOCKS_PORT=1080
HTTP_PORT=3080

# Разбор IP-адресов и добавление блоков
IFS=',' read -ra IPS <<< "$IP_LIST"
for IP in "${IPS[@]}"; do
    # Убираем возможные пробелы
    IP=$(echo "$IP" | xargs)
    if [ -z "$IP" ]; then
        continue
    fi

    echo "    Добавляю IP: $IP (SOCKS: $SOCKS_PORT, HTTP: $HTTP_PORT)"

    cat >> "$CONFIG_FILE" <<EOF

# --- IP: $IP ---
external ${IP}
socks -p${SOCKS_PORT}
proxy -p${HTTP_PORT}
EOF

    # Открываем порты в UFW
    ufw allow "${SOCKS_PORT}/tcp" >/dev/null 2>&1 || true
    ufw allow "${HTTP_PORT}/tcp" >/dev/null 2>&1 || true

    SOCKS_PORT=$((SOCKS_PORT + 1))
    HTTP_PORT=$((HTTP_PORT + 1))
done

# --- Перезапуск сервиса ---
echo ">>> Перезапуск 3proxy..."
systemctl restart 3proxy
systemctl enable 3proxy

# --- Перезагрузка UFW (если активен) ---
if ufw status | grep -q "Status: active"; then
    echo ">>> Перезагрузка UFW..."
    ufw reload
fi

# --- Итоговый вывод ---
echo ""
echo "=============================================="
echo "Готово!"
echo ""
echo "Пользователь: $PROXY_USER"
echo "Пароль:       $PROXY_PASS"
echo ""
echo "Назначенные порты:"
SOCKS_PORT=1080
HTTP_PORT=3080
for IP in "${IPS[@]}"; do
    IP=$(echo "$IP" | xargs)
    if [ -z "$IP" ]; then
        continue
    fi
    echo "  IP $IP -> SOCKS5: $SOCKS_PORT, HTTP: $HTTP_PORT"
    SOCKS_PORT=$((SOCKS_PORT + 1))
    HTTP_PORT=$((HTTP_PORT + 1))
done
echo ""
echo "Проверка (пример для первого IP):"
FIRST_IP=$(echo "$IP_LIST" | cut -d',' -f1 | xargs)
echo "  curl --socks5-hostname $PROXY_USER:$PROXY_PASS@IP_СЕРВЕРА:1080 https://api.ipify.org"
echo "  curl -x http://$PROXY_USER:$PROXY_PASS@IP_СЕРВЕРА:3080 https://api.ipify.org"
echo ""
echo "Ожидаемый IP в ответе: $FIRST_IP"
echo "=============================================="
