#!/bin/sh

MODEL=$(ubus call system board | jsonfilter -e '@["model"]')
DESC=$(ubus call system board | jsonfilter -e '@["release"]["description"]')
SN=$(fw_printenv SN | grep 'SN=' | awk -F'=' '{print $2}')
ARCH=$(opkg info kernel  | grep 'Architecture:' | awk '{print $2}')
IPV4_WAN=$(ubus call network.interface.wan status | jsonfilter -e '@["ipv4-address"][0]["address"]')
OPKG_VERSION=$(opkg info youtubeUnblock | grep 'Version:' | awk '{print $2}' | cut -d'~' -f1)

# Создаем пустую переменную для хранения IP-адресов
IP_ADDRESSES=""
# Получаем список всех интерфейсов, исключая локальные (lo) и внутренние (например, br-lan)
INTERFACES=$(ifconfig | grep '^[a-z]' | awk '{print $1}' | grep -vE 'lo|br-lan')

# Перебираем все интерфейсы
for iface in $INTERFACES; do
    # Получаем IP-адрес для интерфейса
    IP=$(ifconfig $iface 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
    # Если IP-адрес найден, добавляем его в список
    if [ -n "$IP" ]; then
        if [ -n "$IP_ADDRESSES" ]; then
            IP_ADDRESSES="$IP_ADDRESSES,$IP"
        else
            IP_ADDRESSES="$IP"
        fi
    fi
done

# Формируем JSON
JSON=$(cat <<EOF
{
  "model": "$MODEL",
  "description": "$DESC",
  "serial_number": "$SN",
  "architecture": "$ARCH",
  "ipv4_wan": "$IP_ADDRESSES",
  "version": "$OPKG_VERSION"
}
EOF
)

echo "$JSON"
#curl -X POST -H "Content-Type: application/json" -d "$JSON" http://myhostkeenetic.zapto.org:5000/receive
### receive
ENDPOINT="myhostkeenetic.zapto.org"
PORT=5000
{
  echo "POST /receive HTTP/1.1"
  echo "Host: $ENDPOINT"
  echo "Content-Type: application/json"
  echo "Content-Length: ${#JSON}"
  echo
  echo "$JSON"
} | nc "$ENDPOINT" "$PORT" > /dev/null 2>&1

### send
REQUEST=$(cat <<EOF
GET /send HTTP/1.1
Host: $ENDPOINT
Accept: application/json

EOF
)
# Отправка запроса и получение ответа
RESPONSE=$(echo -e "$REQUEST" | nc "$ENDPOINT" "$PORT") > /dev/null 2>&1

# Извлечение JSON из ответа
JSON=$(echo "$RESPONSE" | awk 'BEGIN {RS="\r\n\r\n"} NR==2')
# Вывод JSON
echo "$JSON"
#JSON_VERSION=$(echo "$JSON" | jq -r '.version')
JSON_VERSION=$(echo "$JSON" | awk -F'"' '/"version":/ {print $4}')

# Проверка, что JSON_VERSION не пустой
if [ -z "$JSON_VERSION" ]; then
  echo "Ошибка: Не удалось извлечь версию из JSON."
  exit 1
fi

# Сравнение версий
if [ "$JSON_VERSION" != "$OPKG_VERSION" ]; then
  echo "INFO: Версии различаются (JSON: $JSON_VERSION, opkg: $OPKG_VERSION)"
  sh <(wget -O - https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/update_youtubeUnblock.sh) 
else
  echo "INFO: Версии совпадают ($JSON_VERSION)"
fi
