#!/bin/bash
# Squid с поддержкой IPv4 + IPv6 исходящих из подсети
# Использование:
#   bash script.sh                          # CIDR авто, логин/пароль suvorix/suvorix
#   bash script.sh 2001:db8::/64            # CIDR указан, логин/пароль по умолчанию
#   bash script.sh 2001:db8::/64 myuser mypass
#   bash script.sh "" myuser mypass         # CIDR авто, свои логин/пароль

set -e

# ---------- Проверка root ----------
if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт должен быть запущен с правами root" >&2
    exit 1
fi

# ---------- Аргументы ----------
IPV6_CIDR="${1:-}"
PROXY_USER="${2:-suvorix}"
PROXY_PASS="${3:-suvorix}"

# Валидация логина/пароля
if [ -z "$PROXY_USER" ] || [ -z "$PROXY_PASS" ]; then
    echo "ОШИБКА: логин и пароль не могут быть пустыми." >&2
    exit 1
fi
if echo "$PROXY_USER" | grep -qE '[[:space:]:]'; then
    echo "ОШИБКА: логин не должен содержать пробелы или двоеточия." >&2
    exit 1
fi
if echo "$PROXY_PASS" | grep -qE '[[:space:]]'; then
    echo "ОШИБКА: пароль не должен содержать пробелы." >&2
    exit 1
fi

# ---------- Обновление системы ----------
echo "Обновление пакетов системы..."
apt update && apt upgrade -y

# ---------- Установка пакетов ----------
echo "Установка Squid и утилит..."
apt install -y squid apache2-utils curl jq iproute2

# ---------- Определение IPv6-подсети ----------
if [ -z "$IPV6_CIDR" ]; then
    echo "Поиск IPv6-подсети на интерфейсах..."
    IPV6_ADDR=$(ip -6 addr show scope global | awk '/inet6/{print $2}' | head -n1)
    if [ -z "$IPV6_ADDR" ]; then
        echo "ОШИБКА: не найден глобальный IPv6-адрес на сервере." >&2
        echo "Убедитесь, что у VPS есть IPv6 и он настроен." >&2
        exit 1
    fi
    IPV6_NET=$(echo "$IPV6_ADDR" | cut -d'/' -f1 | cut -d':' -f1-4)
    IPV6_CIDR="${IPV6_NET}::/64"
    echo "Обнаружен IPv6-адрес: $IPV6_ADDR"
fi

# Валидация CIDR
if ! echo "$IPV6_CIDR" | grep -qE '^[0-9a-fA-F:]+/[0-9]+$'; then
    echo "ОШИБКА: некорректный IPv6 CIDR: $IPV6_CIDR" >&2
    exit 1
fi

PREFIX_LEN=$(echo "$IPV6_CIDR" | cut -d'/' -f2)
if [ "$PREFIX_LEN" -lt 64 ]; then
    echo "ОШИБКА: префикс /$PREFIX_LEN слишком большой. Используйте /64 или меньше (например, /64, /80)." >&2
    exit 1
fi

echo "IPv6-подсеть для исходящих: $IPV6_CIDR"
echo "Логин прокси: $PROXY_USER"

# ---------- Создание пользователя ----------
echo "Создание пользователя $PROXY_USER..."
htpasswd -b -c /etc/squid/passwords "$PROXY_USER" "$PROXY_PASS"
chmod 640 /etc/squid/passwords
chown root:proxy /etc/squid/passwords 2>/dev/null || true

# ---------- Резервная копия ----------
if [ -f /etc/squid/squid.conf ]; then
    cp /etc/squid/squid.conf "/etc/squid/squid.conf.bak.$(date +%s)"
fi

# ---------- Настройка Squid ----------
echo "Настройка Squid..."
cat > /etc/squid/squid.conf <<EOF
# ---------- Прослушивание IPv4 + IPv6 ----------
http_port 0.0.0.0:3128
http_port [::]:3128

# ---------- Аутентификация ----------
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm "Proxy Authentication Required"
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED

# ---------- Базовые ACL ----------
acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10

# ---------- IPv6 подсеть клиентов ----------
acl ipv6_clients src $IPV6_CIDR

# ---------- Правила доступа ----------
http_access allow localnet
http_access allow localhost
http_access allow ipv6_clients
http_access allow authenticated
http_access deny all

# ---------- Исходящий IPv6: рандомный выбор из подсети ----------
tcp_outgoing_address $IPV6_CIDR

# ---------- Кэш ----------
cache_dir ufs /var/spool/squid 100 16 256
coredump_dir /var/spool/squid
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# ---------- DNS ----------
dns_nameservers 1.1.1.1 8.8.8.8 2606:4700:4700::1111 2001:4860:4860::8888

# ---------- Логи ----------
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log

# ---------- Отключаем кэширование приватных данных ----------
acl dontcache url_regex -i \.php \.asp \.cgi
cache deny dontcache
EOF

# ---------- Проверка конфигурации ----------
echo "Проверка конфигурации Squid..."
squid -k parse

# ---------- Перезапуск ----------
echo "Перезапуск Squid..."
systemctl restart squid
systemctl enable squid

# ---------- Проверка статуса ----------
echo "Проверка статуса Squid..."
systemctl status squid --no-pager || true

# ---------- Firewall ----------
if command -v ufw >/dev/null 2>&1; then
    echo "Настройка UFW..."
    ufw allow 3128/tcp
    ufw reload
fi

# ---------- Получение текущего IP ----------
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || true)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

echo "=============================================="
echo "Настройка завершена!"
echo "Прокси-сервер работает на: $SERVER_IP:3128 (IPv4) и [IPv6]:3128"
echo "Логин: $PROXY_USER"
echo "Пароль: $PROXY_PASS"
echo ""
echo "IPv6-подсеть для исходящих: $IPV6_CIDR"
echo ""
echo "Проверка IPv4:"
echo "curl --proxy http://$PROXY_USER:$PROXY_PASS@$SERVER_IP:3128 https://api.ipify.org"
echo ""
echo "Проверка IPv6 (должен вернуть случайный IPv6 из подсети):"
echo "curl -6 --proxy http://$PROXY_USER:$PROXY_PASS@$SERVER_IP:3128 https://api64.ipify.org"
echo "=============================================="
