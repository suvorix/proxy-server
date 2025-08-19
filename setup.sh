#!/bin/bash

# Проверка на root-права
if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт должен быть запущен с правами root" >&2
    exit 1
fi

# Обновление системы
echo "Обновление пакетов системы..."
apt update && apt upgrade -y

# Установка Squid
echo "Установка Squid..."
apt install -y squid apache2-utils

# Создание пользователя для аутентификации
echo "Создание пользователя suvorix..."
htpasswd -b -c /etc/squid/passwords suvorix suvorix

# Резервное копирование конфигурации Squid
echo "Создание резервной копии конфигурации Squid..."
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# Настройка Squid
echo "Настройка Squid..."
cat > /etc/squid/squid.conf <<EOF
http_port 0.0.0.0:3128

# Аутентификация
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm "Proxy Authentication Required"
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED

# Базовые ACL
acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16

# Разрешающие правила
http_access allow localnet
http_access allow localhost
http_access allow authenticated
http_access deny all

# Минимальные настройки кэша
cache_dir ufs /var/spool/squid 100 16 256
coredump_dir /var/spool/squid
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
EOF

# Проверка конфигурации
echo "Проверка конфигурации Squid..."
squid -k parse

# Перезапуск Squid
echo "Перезапуск Squid..."
systemctl restart squid

# Включение автозапуска
systemctl enable squid

# Проверка статуса
echo "Проверка статуса Squid..."
systemctl status squid --no-pager

# Настройка firewall (если установлен)
if command -v ufw >/dev/null 2>&1; then
    echo "Настройка UFW..."
    ufw allow 3128/tcp
    ufw reload
fi

# Получение текущего IP сервера
SERVER_IP=$(curl -s https://api.ipify.org/?format=json | jq -r .ip)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

echo "Настройка завершена!"
echo "=============================================="
echo "Прокси-сервер работает на: $SERVER_IP:3128"
echo "Логин: suvorix"
echo "Пароль: suvorix"
echo ""
echo "Проверить работу можно командой:"
echo "curl --proxy http://suvorix:suvorix@$SERVER_IP:3128 https://api.ipify.org/?format=json"
echo ""
echo "Или проверить через браузер:"
echo "http://$SERVER_IP:3128 (логин: suvorix, пароль: suvorix)"
echo "=============================================="