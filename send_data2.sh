#!/bin/sh
# send_data.sh
SCRIPT_VERSION="0.3.0"
# Variables
SERVER="myhostkeenetic.zapto.org"
PORT=5000
MODEL=$(ubus call system board | jsonfilter -e '@["model"]')
DESC=$(ubus call system board | jsonfilter -e '@["release"]["description"]')
if command -v fw_printenv > /dev/null 2>&1; then
    SN=$(fw_printenv SN 2>/dev/null | grep 'SN=' | awk -F'=' '{print $2}' 2>/dev/null)
fi
[ -z "$SN" ] && SN=$(ifconfig br-lan 2>/dev/null | awk '/HWaddr/ {print $5}')
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
IPV4_WAN=$(ubus call network.interface.wan status | jsonfilter -e '@["ipv4-address"][0]["address"]')
OPKG_VERSION=$(opkg info youtubeUnblock | grep 'Version:' | awk '{print $2}' | cut -d'~' -f1)
IP_ADDRESSES=""
JSON_VERSION=
SCRIPT_VER=

ip_interfaces() {
  INTERFACES=$(ifconfig | grep '^[a-z]' | awk '{print $1}' | grep -vE 'lo|br-lan')    # Getting a list of all interfaces, excluding local (lo) and internal (e.g., br-lan)
  for iface in $INTERFACES; do    # Iterating through all interfaces
    IP=$(ifconfig $iface 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)    # Getting the IP address for the interface
    if [ -n "$IP" ]; then    # If the IP address is found, we add it to the list
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
  else
    printf "\033[32;1mINFO: Версии zapret совпадают ($JSON_VERSION)\033[0m \n"
  fi
}

check_script_version() {
  # Comparison of versions
  if [ "$SCRIPT_VER" != "$SCRIPT_VERSION" ]; then
    if [ -z "$SCRIPT_VER" ]; then
      printf "\033[31;1mОшибка: Не удалось извлечь версию из JSON.\033[0m \n"
      printf "$JSON\n"
      exit 1
    fi
    printf "\033[33;1mINFO: Версии script различаются (JSON: $SCRIPT_VER, server: $SCRIPT_VERSION)\033[0m \n"
    sh <(wget -O - https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/updater.sh) > /dev/null 2>&1
  else
    printf "\033[32;1mINFO: Версии script совпадают ($SCRIPT_VERSION)\033[0m \n"
  fi
}

script_check() {
  if ! nc -z -w 5 "$SERVER" "$PORT"; then
    printf "\033[31;1mError: Cannot connect to $SERVER:$PORT\033[0m\n"
    exit 1
  fi
  for cmd in ubus jsonfilter nc awk grep ifconfig; do
    if ! command -v $cmd >/dev/null; then
      echo "Error: $cmd is not installed"
      exit 1
    fi
  done
}
main() {
  script_check
  ip_interfaces
  data_sending
  data_receiving
  check_app_version
  check_script_version
}

main
