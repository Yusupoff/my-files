#!/bin/sh
SCRIPT_VERSION="2.3"

msg_i() { printf "\033[32;1m%s\033[0m\n" "$1"; }
msg_e() { printf "\033[31;1m%s\033[0m\n" "$1"; }

SERVER="myhostkeenetic.zapto.org"
PORT=5000
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
VERSION=

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

  # Извлечение app_ver и script_ver с помощью jq
  VERSION=$(echo "$JSON" | jq -r '.app_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$VERSION" = "null" ]; then
    msg_e "Ошибка: Не удалось извлечь app_ver из JSON" >&2
    return 1
  fi
  
  return 0
}

download_install() {
  #msg_i "Обновление пакетов."
  #opkg update > /dev/null 2>&1
  msg_i "Загрузка пакетов:"
  wget "https://github.com/Yusupoff/my-files/raw/refs/heads/main/zapret_${VERSION}_${ARCH}.ipk" -O "/tmp/zapret_${ARCH}.ipk" >/dev/null 2>/dev/null && msg_i "\tzapret_${VERSION}_${ARCH}.ipk загружен" || {
    msg_e "Ошибка скачивания zapret_${VERSION}_${ARCH}.ipk"
  }
  wget "https://github.com/Yusupoff/my-files/raw/refs/heads/main/luci-app-zapret_${VERSION}-r1_all.ipk" -O "/tmp/luci-app-zapret_all.ipk" 2>/dev/null && msg_i "\tluci-app-zapret_${VERSION}-r1_all.ipk загружен" || {
    msg_e "Ошибка скачивания luci-app-zapret_${VERSION}_all.ipk"
  }
  msg_i "Устоновка пакетов"
  #opkg install libnetfilter-queue1 coreutils-sort coreutils-sleep gzip libcap curl zlib
  opkg install /tmp/zapret_${ARCH}.ipk && rm -f /tmp/zapret_${ARCH}.ipk
  opkg install /tmp/luci-app-zapret_all.ipk  && rm -f /tmp/luci-app-zapret_all.ipk
}

check_old_apps() {
  if opkg list-installed | grep -q "^luci-app-youtubeUnblock "; then
    msg_e "Обнаружен luci-app-youtubeUnblock, удаление..."
    opkg remove luci-app-youtubeUnblock
  fi
  if opkg list-installed | grep -q "^youtubeUnblock "; then
	  msg_e "Обнаружен youtubeUnblock, удаление..."
    opkg remove youtubeUnblock
  fi
}

config_apps() {
  msg_i "Преднастройка Zapret"
  msg_i "Загрузка zapret-hosts-user.txt"
  msg_i "Установка конфигурации zapret NFQWS_OPT"
  uci set zapret.config.NFQWS_OPT='
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--dpi-desync=fake,multidisorder
--dpi-desync-split-pos=1,midsld
--dpi-desync-repeats=11
--dpi-desync-fooling=md5sig
--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
--new
--filter-udp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--dpi-desync=fake
--dpi-desync-repeats=11
--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin
--new
--filter-tcp=80
--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
--dpi-desync=fake,fakedsplit
--dpi-desync-autottl=2
--dpi-desync-fooling=md5sig
--new
--filter-udp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
--dpi-desync=fake
--dpi-desync-repeats=11
--new
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
--dpi-desync=fake,multidisorder
--dpi-desync-split-pos=midsld
--dpi-desync-repeats=6
--dpi-desync-fooling=badseq,md5sig
'
  uci commit zapret
  msg_i "Перезапуск zapret: "
  /etc/init.d/zapret restart >/dev/null 2>&1 && msg_i " Zapret перезапущен" || { msg_e " Ошибка при перезапуске Zapret" 2>/dev/null; exit 1; }
}

main() {
  msg_i "Подготовка zapret."
  data_receiving
  check_old_apps
  download_install
  config_apps
  if pgrep -f "zapret" > /dev/null; then
    msg_i "Программа zapret запущена."
  else
    msg_e "Программа zapret не запущена."
  fi
}

main
