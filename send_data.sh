#!/bin/sh
SCRIPT_VERSION="0.3.12"
# Обновление методов уведомлотладки и подсказок
# Отказ от Zapret
# Перенов проверки пакетов в скрипт обновления 
# 
# Алгоритм выполнения
#     Проверка интернета                          check_internet
#     Получение переменных                        get_variables
#     Отправка данных об устройстве               data_sending
#     Получение данных для обновлений             data_receiving
#     Провека актуальности и обновление пакета    check_app_version
#     Провека актуальностии обновление скрипта    check_script_version
#     Скачивание скрипта конфигурации и выполнение 

# Цветовые коды
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Список доменов для проверки соединения (минимум один должен ответить)
check_internet() {
    local domains="openwrt.org ya.ru google.ru"
    local timeout=2
    for domain in $domains; do
        if ping -c 1 -W $timeout "$domain" >/dev/null 2>&1; then
            return 0
        fi
    done
    echo -e "${RED}Нет интернета!${NC}"
    exit 1
}

# Проверяем установлен ли пакет
is_installed() {
    local pkg="$1"
    opkg list-installed | grep -q "^$pkg "
}

# Проверка наличия интернета
check_internet

# Переменные
SERVER="myhostkeenetic.zapto.org"
PORT=5000
MODEL=""
DESC=""
ARCH=""
IPV4_WAN=""
OPKG_VERSION=""
SN=""
IP_ADDRESSES=""
JSON_VERSION=""
APPS1_VERSION=""
SCRIPT_VER=""
MD5_HOSTLIST=""

# Получение SN или MAC
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

# Получение списока всех сетевых интерфейсов за исключением интерфейсы lo и br-lan
ip_interfaces() { 
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

# Получаем некоторые переменные  
get_variables(){
  sn_or_mac
  ip_interfaces
  MODEL=$(ubus call system board | jq -r '.model // empty')
  DESC=$(ubus call system board | jq -r '.release?.description? // empty')
  ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
  IPV4_WAN=$IP_ADDRESSES
  OPKG_VERSION=$(opkg status youtubeUnblock | grep 'Version:' | awk '{print $2}' | cut -d'~' -f1)
}

# Отправка данных об устройстве
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
    echo -e "${RED}Ошибка: сервер ответил статусом ${YELLOW}$HTTP_STATUS${NC}"
    return 1
  fi
}

# Получение данных для обновлений
data_receiving() {
  # Отправка GET-запроса с помощью curl
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    --max-time 10 \
    --connect-timeout 5 \
    -X GET "http://$SERVER:$PORT/send" \
    -H "Accept: application/json" 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}Ошибка: Не удалось подключиться к ${YELLOW}%s:%s!!${NC}" "$SERVER" "$PORT" >&2
    return 1
  fi

  # Извлечение тела ответа и HTTP-статуса
  HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
  # Удаляем последнюю строку (HTTP-статус)
  JSON=$(echo "$RESPONSE" | sed '$d')

  # Проверка HTTP-статуса
  if [ "$HTTP_STATUS" != "200" ]; then
    echo -e "${RED}Ошибка: Сервер вернул статус ${YELLOW}$HTTP_STATUS${NC}" >&2
    return 1
  fi

  # Проверка, что JSON не пустой
  if [ -z "$JSON" ]; then
    echo -e "${RED}Ошибка: Пустой JSON-ответ от сервера${NC}" >&2
    return 1
  fi

  APPS1_VERSION=$(echo "$JSON" | jq -r '.version' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$APPS1_VERSION" = "null" ]; then
    echo -e "${RED}Ошибка: Не удалось извлечь version из JSON${NC}" >&2
    return 1
  fi

  SCRIPT_VER=$(echo "$JSON" | jq -r '.script_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$SCRIPT_VER" = "null" ]; then
    echo -e "${RED}Ошибка: Не удалось извлечь script_ver из JSON${NC}" >&2
    return 1
  fi
  return 0
}

# Провека актуальности и обновление пакета
check_app_version() {
  # Проверка наличия версии youtubeUnblock в JSON
  if [ -z "$APPS1_VERSION" ]; then
    echo -e "${RED}Ошибка: Не удалось извлечь версию youtubeUnblock из JSON.${NC}"
    #printf "$JSON\n"
    exit 1
  fi
  # Проверка и обновление youtubeUnblock
  if [ -z "$OPKG_VERSION" ]; then
    echo -e "${CYAN}Версия пакета не установлена, выполняется установка ${YELLOW}$APPS1_VERSION${NC}"
    install_update
    return
  fi
  # Сравнение версий
  if [ "$APPS1_VERSION" != "$OPKG_VERSION" ]; then
    echo -e "${YELLOW}Есть обновление для youtubeUnblock новая верия: ${CYAN}$APPS1_VERSION${YELLOW}, установленная: ${CYAN}$OPKG_VERSION${NC}"
    echo -e "${CYAN}Выполняется установка ${CYAN}$APPS1_VERSION${NC}"
    install_update
  else
    echo -e "${GREEN}Версии youtubeUnblock ${CYAN}$APPS1_VERSION ${GREEN}актуальна${NC}"
  fi
}

# Вызов скрипта установки youtubeUnblock
install_update() {
  wget -q -O /tmp/update_apps.sh https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/update_apps.sh >/dev/null 2>&1
  chmod +x /tmp/update_apps.sh
  /tmp/update_apps.sh
  rm -f /tmp/update_apps.sh
}

# Провека актуальностии и обновление скрипта
check_script_version() {
  if [ "$SCRIPT_VER" != "$SCRIPT_VERSION" ]; then
    if [ -z "$SCRIPT_VER" ]; then
      echo -e "${RED}Ошибка: Не удалось извлечь версию из JSON.${NC}"
      #printf "$JSON\n"
      exit 1
    fi
    echo -e "${CYAN}Версия скрипта обновления скрипта: ${YELLOW}$SCRIPT_VER ${CYAN}Текущая версия: ${YELLOW}$SCRIPT_VERSION.${NC}"
    sh <(wget -qO- https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/updater.sh)
    #OUTPUT=$(wget -O - https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/updater.sh 2>&1)
    # Проверка на успешное обновление скрипта
    #if [ $? -eq 0 ]; then
      # Если команда выполнена успешно, выполняем скачанный скрипт
    #  OUTPUT=$(echo "$OUTPUT" | tail -n +4)
    #  OUTPUT=$(echo "$OUTPUT" | head -n -3)
    #  sh <(echo "$OUTPUT")
    #else
    #  echo -e "${RED}Произошла ошибка при обновлении скрипта: $OUTPUT${NC}"
    #fi
  else
    echo -e "${GREEN}Версии скрипта ${CYAN}$SCRIPT_VERSION ${GREEN}актуальна.${NC}"
  fi
}

main() {
  get_variables
  data_sending
  data_receiving
  check_app_version
  check_script_version
  sh <(wget -qO- https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/config_youtubeUnblock.sh)
  sh <(wget -qO- https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/configure_dropbear.sh)
}

main