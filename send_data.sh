#!/bin/sh
# Проверка наличия podkop и установка youtubeUnblock или zapret
# 

SCRIPT_VERSION="0.3.5"

msg_i() { printf "\033[32;1m%s\033[0m\n" "$1"; }
msg_e() { printf "\033[31;1m%s\033[0m\n" "$1"; }
                  # Список доменов для проверки (минимум один должен ответить)
check_internet() {
    local domains="openwrt.org ya.ru google.ru"
    local timeout=2
    for domain in $domains; do
        if ping -c 1 -W $timeout "$domain" >/dev/null 2>&1; then
            return 0
        fi
    done
    msg_e "Нет интернета!"
    exit 1
}
                  # Проверяем каждый пакет
packages_check() {
  for pkg in $PACKAGES; do
    if ! opkg list-installed | grep -q "^$pkg "; then
        msg_e "Пакет $pkg не установлен."
        NEED_INSTALL=1
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
  done
                  # Если есть отсутствующие пакеты?
  if [ -n "$NEED_INSTALL" ]; then   
    msg_i "Обновление списка пакетов..."
    opkg update >/dev/null 2>&1 && msg_i "Обновление списка пакетов выполнено успешно!" || { msg_e "Ошибка при обновлении списка пакетов" >&2; exit 1; }
    msg_i "Установка отсутствующих пакетов: $MISSING_PKGS"
    opkg install $MISSING_PKGS 2>/dev/null
  fi
}

check_internet
# Переменные
PACKAGES="jq jsonfilter libnetfilter-queue1 coreutils-sort coreutils-sleep gzip libcap curl zlib kmod-nft-queue"  # Пакеты для проверки
packages_check
SERVER="myhostkeenetic.zapto.org"
PORT=5000
# Получение переменных
MODEL=$(ubus call system board | jsonfilter -e '@["model"]')
DESC=$(ubus call system board | jsonfilter -e '@["release"]["description"]')
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
IPV4_WAN=$(ubus call network.interface.wan status | jsonfilter -e '@["ipv4-address"][0]["address"]')
OPKG_VERSION=$(opkg status zapret | grep 'Version:' | awk '{print $2}' | cut -d'~' -f1)
if [ -z "$OPKG_VERSION" ]; then
  OPKG_VERSION=$(opkg status youtubeUnblock | grep 'Version:' | awk '{print $2}' | cut -d'~' -f1)
fi
SN=""
IP_ADDRESSES=""
JSON_VERSION=""
APPS1_VERSION=""
SCRIPT_VER=""
MD5_HOSTLIST=""

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
  # Получаем список всех сетевых интерфейсов исключает интерфейсы lo и br-lan
  INTERFACES=$(ifconfig | grep '^[a-z]' | awk '{print $1}' | grep -vE 'lo|br-lan')
  # Для каждого интерфейса получаем его IP-адрес-
  for iface in $INTERFACES; do
    IP=$(ifconfig $iface 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
    # Если IP-адрес для интерфейса найден добавляем новый адрес?
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
  # Формирование JSON с помощью jq
  JSON=$(jq -n \
    --arg model "$MODEL" \
    --arg desc "$DESC" \
    --arg sn "$SN" \
    --arg arch "$ARCH" \
    --arg ip "$IP_ADDRESSES" \
    --arg ver "$OPKG_VERSION" \
    '{model: $model, description: $desc, serial_number: $sn, architecture: $arch, ipv4_wan: $ip, version: $ver}')
  # Отправка запроса с помощью curl
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    --max-time 10 \
    --connect-timeout 5 \
    -X POST "http://$SERVER:$PORT/receive" \
    -H "Content-Type: application/json" \
    -d "$JSON")
  
  # Проверка статуса ответа
  HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
  if [ "$HTTP_STATUS" != "200" ]; then
    msg_e "Ошибка: сервер ответил статусом $HTTP_STATUS"
    return 1
  fi
}

data_receiving() {
  # Отправка GET-запроса с помощью curl
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    --max-time 10 \
    --connect-timeout 5 \
    -X GET "http://$SERVER:$PORT/send" \
    -H "Accept: application/json" 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    msg_e "Ошибка: Не удалось подключиться к %s:%s!!" "$SERVER" "$PORT" >&2
    return 1
  fi

  # Извлечение тела ответа и HTTP-статуса
  HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
  # Удаляем последнюю строку (HTTP-статус)
  JSON=$(echo "$RESPONSE" | sed '$d')

  # Проверка HTTP-статуса
  if [ "$HTTP_STATUS" != "200" ]; then
    msg_e "Ошибка: Сервер вернул статус %s" "$HTTP_STATUS" >&2
    return 1
  fi

  # Проверка, что JSON не пустой
  if [ -z "$JSON" ]; then
    msg_e "Ошибка: Пустой JSON-ответ от сервера" >&2
    return 1
  fi

  JSON_VERSION=$(echo "$JSON" | jq -r '.app_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$JSON_VERSION" = "null" ]; then
    msg_e "Ошибка: Не удалось извлечь app_ver из JSON" >&2
    return 1
  fi

  APPS1_VERSION=$(echo "$JSON" | jq -r '.version' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$APPS1_VERSION" = "null" ]; then
    msg_e "Ошибка: Не удалось извлечь version из JSON" >&2
    return 1
  fi

  SCRIPT_VER=$(echo "$JSON" | jq -r '.script_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$SCRIPT_VER" = "null" ]; then
    msg_e "Ошибка: Не удалось извлечь script_ver из JSON" >&2
    return 1
  fi

  MD5_HOSTLIST=$(echo "$JSON" | jq -r '.md5_hostlist' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$MD5_HOSTLIST" = "null" ]; then
    msg_e "Ошибка: Не удалось извлечь md5_hostlist из JSON" >&2
    return 1
  fi

  return 0
}

check_app_version() {
  # Проверка наличия версии в JSON
  if [ -z "$JSON_VERSION" ]; then
    msg_e "Ошибка: Не удалось извлечь версию из JSON."
    #printf "$JSON\n"
    exit 1
  fi
  
  if [ -z "$APPS1_VERSION" ]; then
    msg_e "Ошибка: Не удалось извлечь версию APPS1_VERSION из JSON."
    #printf "$JSON\n"
    exit 1
  fi

  # Если установлен podkop установить youtubeUnblock
  if opkg list-installed | grep -q "^podkop "; then
    msg_i "Пакет podkop установлен, установка youtubeUnblock"
    if [ -z "$OPKG_VERSION" ]; then
      msg_i "Версия пакета не установлена, выполняется установка ($APPS1_VERSION)"
      install_update "2"
      return
    fi
    # Сравнение версий
    if [ "$APPS1_VERSION" != "$OPKG_VERSION" ]; then
      msg_i "Версии различаются (JSON: $APPS1_VERSION, opkg: $OPKG_VERSION)"
      msg_i "Выполняется установка ($APPS1_VERSION)"
      install_update "2"
    else
      msg_i "Версии совпадают ($APPS1_VERSION)"
    fi
  else
    msg_i "Пакет podkop не установлен, установка Zapret"
    if [ -z "$OPKG_VERSION" ]; then
      msg_i "Версия пакета не установлена, выполняется установка ($JSON_VERSION)"
      install_update "1"
      return
    fi
    # Сравнение версий
    if [ "$JSON_VERSION" != "$OPKG_VERSION" ]; then
      msg_i "Версии различаются (JSON: $JSON_VERSION, opkg: $OPKG_VERSION)"
      msg_i "Выполняется установка ($JSON_VERSION)"
      install_update "1"
    else
      msg_i "Версии совпадают ($JSON_VERSION)"
    fi
  fi
}

install_update() {
  if [ "$1" -eq 1 ]; then
    wget -q -O /tmp/update_apps.sh https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/update_apps.sh >/dev/null 2>&1
    chmod +x /tmp/update_apps.sh
    #/tmp/update_apps.sh
    rm -f /tmp/update_apps.sh
  elif [ "$1" -eq 2 ]; then
    wget -q -O /tmp/update_apps.sh https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/update_youtubeUnblock.sh >/dev/null 2>&1
    chmod +x /tmp/update_apps.sh
    #/tmp/update_apps.sh
    rm -f /tmp/update_apps.sh
  else
    echo "Неизвестный аргумент!"
  fi
}

check_script_version() {
  if [ "$SCRIPT_VER" != "$SCRIPT_VERSION" ]; then
    if [ -z "$SCRIPT_VER" ]; then
      msg_e "Ошибка: Не удалось извлечь версию из JSON."
      #printf "$JSON\n"
      exit 1
    fi
    msg_e "Версия скрипта обновления различается (JSON: $SCRIPT_VER, Router: $SCRIPT_VERSION)."
    OUTPUT=$(wget -O - https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/updater.sh 2>&1)
                  # Проверка на успешное выполнение
    if [ $? -eq 0 ]; then
      # Если команда выполнена успешно, выполняем скачанный скрипт
      OUTPUT=$(echo "$OUTPUT" | tail -n +4)
      OUTPUT=$(echo "$OUTPUT" | head -n -3)
      sh <(echo "$OUTPUT")
    else
      # Если wget завершился с ошибкой, выводим ошибку
      msg_e "Произошла ошибка при обновлении скрипта: $OUTPUT"
    fi
  else
    msg_i "Версии скрипта актуальна ($SCRIPT_VERSION)."
  fi
}

check_hostlist() {
  LOCAL_FILE="/opt/zapret/ipset/zapret-hosts-user.txt"
  REMOTE_URL="http://myhostkeenetic.zapto.org:5000/files/zapret-hosts-user.txt"
  
  # Проверяем существование файла и что он не пустой
  if [ ! -s "$LOCAL_FILE" ]; then
    msg_e "Пользовательский список хостов для Zapret не существует."
    exit 1
  fi

  # Проверяем, что в файле хотя бы две строки
  LINE_COUNT=$(wc -l < "$LOCAL_FILE")
  if [ "$LINE_COUNT" -lt 2 ]; then
    msg_e "Пользовательский список хостов для Zapret не нужно обновлять."
    exit 1
  fi

  MD5_LOCAL=$(md5sum "$LOCAL_FILE" | awk '{print $1}')
  # Если хеши не совпадают, качаем новый файл
  if [ "$MD5_LOCAL" != "$MD5_HOSTLIST" ]; then
    OUTPUT=$(wget "$REMOTE_URL" -O "$LOCAL_FILE" 2>&1)
    if [ $? -eq 0 ]; then
      msg_i "Пользовательский список хостов для Zapret успешно обновлён."
    else
      msg_e "Произошла ошибка при обновлении списка хостов: $OUTPUT"
    fi
  else
    msg_i "Пользовательский список хостов для Zapret актуален."
  fi
}

main() {
  sn_or_mac
  ip_interfaces
  data_sending
  data_receiving
  check_app_version
  check_script_version
  if opkg list-installed | grep -q "^zapret "; then
    check_hostlist
  fi
}

main