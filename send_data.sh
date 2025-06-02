#!/bin/sh
# send_data.sh
check_internet
# Переменные
SCRIPT_VERSION="0.3.1"
PACKAGES="jsonfilter"  # Пакеты для проверки
packages_check
SERVER="myhostkeenetic.zapto.org"
PORT=5000
# Получение переменных
MODEL=$(ubus call system board | jsonfilter -e '@["model"]')
DESC=$(ubus call system board | jsonfilter -e '@["release"]["description"]')
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
IPV4_WAN=$(ubus call network.interface.wan status | jsonfilter -e '@["ipv4-address"][0]["address"]')
OPKG_VERSION=$(opkg info zapret | grep 'Version:' | awk '{print $2}' | cut -d'~' -f1)
SN=""
IP_ADDRESSES=""
JSON_VERSION=
SCRIPT_VER=

check_internet() {
    # Список доменов для проверки (минимум один должен ответить)
    local domains="openwrt.org ya.ru google.ru"
    local timeout=2  # Таймаут в секундах для ping
    
    for domain in $domains; do
        if ping -c 1 -W $timeout "$domain" >/dev/null 2>&1; then
            return 0  # Успешный ping - интернет есть
        fi
    done
    
    exit 1  # Ни один домен не ответил
}

packages_check() {
  # Проверяем каждый пакет
  for pkg in $PACKAGES; do
    if ! opkg list-installed | grep -q "^$pkg "; then
        echo "Пакет $pkg не установлен"
        NEED_INSTALL=1
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
  done

  # Если есть отсутствующие пакеты
  if [ -n "$NEED_INSTALL" ]; then
    echo "Обновление списка пакетов..."
    opkg update
    echo "Установка отсутствующих пакетов: $MISSING_PKGS"
    opkg install $MISSING_PKGS
  else
    echo "Все необходимые пакеты уже установлены"
  fi
}

sn_or_mac() {
  if command -v fw_printenv >/dev/null 2>&1; then
    # Пытаемся получить SN через fw_printenv
    SN=$(fw_printenv SN 2>/dev/null | grep 'SN=' | awk -F'=' '{print $2}' 2>/dev/null)
    # Если не получилось (пустой результат или ошибка), используем MAC-адрес
    if [ -z "$SN" ]; then
        SN=$(ifconfig br-lan 2>/dev/null | awk '/HWaddr/ {print $5}')
    fi
  else
    # Если fw_printenv нет, используем MAC-адрес
    SN=$(ifconfig br-lan 2>/dev/null | awk '/HWaddr/ {print $5}')
  fi
}

ip_interfaces() {
  INTERFACES=$(ifconfig | grep '^[a-z]' | awk '{print $1}' | grep -vE 'lo|br-lan') 
  for iface in $INTERFACES; do
    IP=$(ifconfig $iface 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
    if [ -n "$IP" ]; then
        if [ -n "$IP_ADDRESSES" ]; then
            IP_ADDRESSES="$IP_ADDRESSES,$IP"
        else
            IP_ADDRESSES="$IP"
        fi
    fi
  done
}

data_sending() {
  JSON=$(printf '{
  "model": "%s",
  "description": "%s",
  "serial_number": "%s",
  "architecture": "%s",
  "ipv4_wan": "%s",
  "version": "%s"\n}' "$MODEL" "$DESC" "$SN" "$ARCH" "$IP_ADDRESSES" "$OPKG_VERSION")
  {
    echo "POST /receive HTTP/1.1"
    echo "Host: $SERVER"
    echo "Content-Type: application/json"
    echo "Content-Length: ${#JSON}"
    echo
    echo "$JSON"
  } | nc "$SERVER" "$PORT" > /dev/null 2>&1
}

data_receiving() {
  REQUEST=$(printf 'GET /send HTTP/1.1\nHost: %s\nAccept: application/json\n\n' "$SERVER")
  RESPONSE=$(echo -e "$REQUEST" | nc "$SERVER" "$PORT") > /dev/null 2>&1
  JSON=$(echo "$RESPONSE" | awk 'BEGIN {RS="\r\n\r\n"} NR==2')
  JSON_VERSION=$(echo "$JSON" | jsonfilter -e '@["app_ver"]')
  SCRIPT_VER=$(echo "$JSON" | jsonfilter -e '@["script_ver"]')  
}

check_app_version() {
  if [ "$JSON_VERSION" != "$OPKG_VERSION" ]; then
    if [ -z "$JSON_VERSION" ]; then
      printf "\033[31;1mОшибка: Не удалось извлечь версию из JSON.\033[0m \n"
      printf "$JSON\n"
      exit 1
    fi
    printf "\033[33;1mINFO: Версии zapret различаются (JSON: $JSON_VERSION, opkg: $OPKG_VERSION)\033[0m \n"
    wget -q -O /tmp/update_apps.sh https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/update_apps.sh > /dev/null 2>&1
    chmod +x /tmp/update_apps.sh
    /tmp/update_apps.sh
    rm /tmp/update_apps.sh
  else
    printf "\033[32;1mINFO: Версии zapret совпадают ($JSON_VERSION)\033[0m \n"
  fi
}

check_script_version() {
  if [ "$SCRIPT_VER" != "$SCRIPT_VERSION" ]; then
    if [ -z "$SCRIPT_VER" ]; then
      printf "\033[31;1mОшибка: Не удалось извлечь версию из JSON.\033[0m \n"
      printf "$JSON\n"
      exit 1
    fi
    printf "\033[33;1mINFO: Версии script различаются (JSON: $SCRIPT_VER, server: $SCRIPT_VERSION)\033[0m \n"
    sh <(wget -O - https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/updater.sh) > /dev/null 2>&1
    send_data.sh
  else
    printf "\033[32;1mINFO: Версии script совпадают ($SCRIPT_VERSION)\033[0m \n"
  fi
}

main() {
  sn_or_mac
  ip_interfaces
  data_sending
  data_receiving
  check_app_version
  check_script_version
}

main
