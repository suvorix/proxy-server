# Quick start of the proxy server

Два варианта установки:

- `setup.sh` — прокси только с IPv4 (один IP-адрес сервера).
- `setupV6.sh` — прокси с IPv4 и IPv6, случайный исходящий IPv6 из подсети
  (`tcp_outgoing_address`), аутентификация.

## Вариант 1: IPv4 (setup.sh)

Установка:

```bash
git clone https://github.com/suvorix/proxy-server && cd proxy-server && sh setup.sh
```

По умолчанию:
- логин: `suvorix`;
- пароль: `suvorix`;
- порт: `3128` (IPv4).

Проверка:

```bash
curl --proxy http://suvorix:suvorix@SERVER_IP:3128 https://api.ipify.org
```

## Вариант 2: IPv4 + IPv6 (setupV6.sh)

Установка:

```bash
git clone https://github.com/suvorix/proxy-server && cd proxy-server && sh setupV6.sh
```

По умолчанию:
- IPv6-подсеть определяется автоматически по префиксу с сетевой карты;
- логин: `suvorix`;
- пароль: `suvorix`;
- порт: `3128` (IPv4 и IPv6).

### Запуск с параметрами

```bash
sh setupV6.sh [IPv6_CIDR] [LOGIN] [PASSWORD]
```

| Команда | CIDR | Логин | Пароль |
|---|---|---|---|
| `sh setupV6.sh` | авто | suvorix | suvorix |
| `sh setupV6.sh 2001:db8:1234::/64` | указан | suvorix | suvorix |
| `sh setupV6.sh 2001:db8:1234::/64 myuser secret` | указан | myuser | secret |
| `sh setupV6.sh "" myuser secret` | авто | myuser | secret |

Пароль со спецсимволами (`$`, `!`, `&`, `@`) заключать в одинарные кавычки:
