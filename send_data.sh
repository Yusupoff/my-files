#!/bin/sh
SCRIPT_VERSION="0.3.2"
check_internet() {  # Список доменов для проверки (минимум один должен ответить)
    local domains="openwrt.org ya.ru google.ru"
    local timeout=2  # Таймаут в секундах для ping
    for domain in $domains; do
        if ping -c 1 -W $timeout "$domain" >/dev/null 2>&1; then
            return 0  # Успешный ping - интернет есть
        fi
    done
    printf "\033[31;1m Нет интернета \033[0m\n"
    exit 1  # Ни один домен не ответил
}

packages_check() { # Проверяем каждый пакет
  for pkg in $PACKAGES; do
    if ! opkg list-installed | grep -q "^$pkg "; then
        printf "\033[31;1m Пакет $pkg не установлен \033[0m\n"
        NEED_INSTALL=1
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
  done
  if [ -n "$NEED_INSTALL" ]; then   # Если есть отсутствующие пакеты
    printf "\033[33;1m Обновление списка пакетов... \033[0m\n"
    opkg update >/dev/null 2>&1 && printf "\033[32;1m Обновление списка пакетов выполнено успешно\033[0m\n" || { printf "\033[31;1m Ошибка при обновлении списка пакетов\033[0m\n" >&2; exit 1; }
    printf "\033[33;1m Установка отсутствующих пакетов: $MISSING_PKGS \033[0m\n"
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
OPKG_VERSION=$(opkg info zapret | grep 'Version:' | awk '{print $2}' | cut -d'~' -f1)
SN=""
IP_ADDRESSES=""
JSON_VERSION=
SCRIPT_VER=

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
  for iface in $INTERFACES; do # Для каждого интерфейса получаем его IP-адрес
    IP=$(ifconfig $iface 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
    if [ -n "$IP" ]; then # Если IP-адрес для интерфейса найден добавляем новый адрес
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
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://$SERVER:$PORT/receive" \
    -H "Content-Type: application/json" \
    -d "$JSON")
  
  # Проверка статуса ответа
  HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
  if [ "$HTTP_STATUS" != "200" ]; then
    echo "Error: Server responded with status $HTTP_STATUS"
    return 1
  fi
}

data_receiving() {
  # Проверка переменных SERVER и PORT
  if [ -z "$SERVER" ] || [ -z "$PORT" ]; then
    printf "\033[31;1mОшибка: SERVER или PORT не заданы\033[0m\n" >&2
    return 1
  fi

  # Отправка GET-запроса с помощью curl
  RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "http://$SERVER:$PORT/send" \
    -H "Accept: application/json" 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    printf "\033[31;1mОшибка: Не удалось подключиться к %s:%s\033[0m\n" "$SERVER" "$PORT" >&2
    return 1
  fi

  # Извлечение тела ответа и HTTP-статуса
  HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
  JSON=$(echo "$RESPONSE" | sed '$d') # Удаляем последнюю строку (HTTP-статус)

  # Проверка HTTP-статуса
  if [ "$HTTP_STATUS" != "200" ]; then
    printf "\033[31;1mОшибка: Сервер вернул статус %s\033[0m\n" "$HTTP_STATUS" >&2
    return 1
  fi

  # Проверка, что JSON не пустой
  if [ -z "$JSON" ]; then
    printf "\033[31;1mОшибка: Пустой JSON-ответ от сервера\033[0m\n" >&2
    return 1
  fi

  # Извлечение app_ver и script_ver с помощью jq
  JSON_VERSION=$(echo "$JSON" | jq -r '.app_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$JSON_VERSION" = "null" ]; then
    printf "\033[31;1mОшибка: Не удалось извлечь app_ver из JSON\033[0m\n" >&2
    return 1
  fi

  SCRIPT_VER=$(echo "$JSON" | jq -r '.script_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$SCRIPT_VER" = "null" ]; then
    printf "\033[31;1mОшибка: Не удалось извлечь script_ver из JSON\033[0m\n" >&2
    return 1
  fi

  # Вывод для отладки (можно убрать, если не нужен)
  # printf "Получены версии: app_ver=%s, script_ver=%s\n" "$JSON_VERSION" "$SCRIPT_VER"

  return 0
}

check_app_version() {
  # Проверка наличия версии в JSON
  if [ -z "$JSON_VERSION" ]; then
    printf "\033[31;1mОшибка: Не удалось извлечь версию из JSON.\033[0m\n"
    #printf "$JSON\n"
    exit 1
  fi

  # Если версия в opkg отсутствует - выполнить установку
  if [ -z "$OPKG_VERSION" ]; then
    printf "\033[33;1mВерсия пакета не установлена, выполняется установка ($JSON_VERSION)\033[0m\n"
    install_update
    return
  fi

  # Сравнение версий
  if [ "$JSON_VERSION" != "$OPKG_VERSION" ]; then
    printf "\033[33;1mВерсии различаются (JSON: $JSON_VERSION, opkg: $OPKG_VERSION)\033[0m\n"
    printf "\033[33;1mВыполняется установка ($JSON_VERSION)\033[0m\n"
    install_update
  else
    printf "\033[32;1mВерсии совпадают ($JSON_VERSION)\033[0m\n"
  fi
}

install_update() {
  wget -q -O /tmp/update_apps.sh https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/update_apps.sh >/dev/null 2>&1
  chmod +x /tmp/update_apps.sh
  /tmp/update_apps.sh
  rm -f /tmp/update_apps.sh
}

check_script_version() {
  if [ "$SCRIPT_VER" != "$SCRIPT_VERSION" ]; then
    if [ -z "$SCRIPT_VER" ]; then
      printf "\033[31;1m Ошибка: Не удалось извлечь версию из JSON. \033[0m\n"
      #printf "$JSON\n"
      exit 1
    fi
    printf "\033[33;1m Версии script различаются (JSON: $SCRIPT_VER, server: $SCRIPT_VERSION) \033[0m\n"
    sh <(wget -O - https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/updater.sh) > /dev/null 2>&1
  else
    printf "\033[32;1m Версии script совпадают ($SCRIPT_VERSION) \033[0m\n"
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
