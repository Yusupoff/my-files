#!/bin/sh
SCRIPT_VERSION="2.2"
SERVER="myhostkeenetic.zapto.org"
PORT=5000
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
VERSION=

main() {
  printf "\033[32;1mПодготовка zapret\033[0m \n"
  data_receiving
  check_old_apps
  download_install
  config_apps
  if pgrep -f "zapret" > /dev/null; then
    printf "\033[32;1mПрограмма zapret запущена.\033[0m\n"
  else
    printf "\033[31;1mПрограмма zapret не запущена.\033[0m\n"
  fi
}

data_receiving() {
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
  VERSION=$(echo "$JSON" | jq -r '.app_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$VERSION" = "null" ]; then
    printf "\033[31;1mОшибка: Не удалось извлечь app_ver из JSON\033[0m\n" >&2
    return 1
  fi
  
  # Вывод для отладки (можно убрать, если не нужен)
  # printf "Получены версии: app_ver=%s, script_ver=%s\n" "$JSON_VERSION" "$SCRIPT_VER"

  return 0
}

download_install() {
  #printf "\033[32;1mОбновление пакетов.\033[0m\n"
  #opkg update > /dev/null 2>&1
  printf "\033[32;1mЗагрузка пакетов:\033[0m \n"
  wget "https://github.com/Yusupoff/my-files/raw/refs/heads/main/zapret_${VERSION}_${ARCH}.ipk" -O "/tmp/zapret_${VERSION}_${ARCH}.ipk" >/dev/null 2>&1 && printf "\033[32;1m\tzapret_${VERSION}_${ARCH}.ipk загружен\033[0m\n" || {
    printf "\033[31;1m\tОшибка скачивания zapret_${VERSION}_${ARCH}.ipk\033[0m\n"
  }
  wget "https://github.com/Yusupoff/my-files/raw/refs/heads/main/luci-app-zapret_${VERSION}_all.ipk" -O "/tmp/luci-app-zapret_${VERSION}-r1_all.ipk" >/dev/null 2>&1 && printf "\033[32;1m\tluci-app-zapret_${VERSION}_all.ipk загружен\033[0m\n" || {
    printf "\033[31;1m\tОшибка скачивания luci-app-zapret_${VERSION}_all.ipk\033[0m\n"
  }
  printf "\033[33;1mУстоновка пакетов\033[0m \n"
  #opkg install libnetfilter-queue1 coreutils-sort coreutils-sleep gzip libcap curl zlib
  opkg install /tmp/zapret_${VERSION}_${ARCH}.ipk && rm -f /tmp/zapret_${VERSION}_${ARCH}.ipk
  opkg install /tmp/luci-app-zapret_${VERSION}_all.ipk  && rm -f /tmp/luci-app-zapret_${VERSION}_all.ipk
}

check_old_apps() {
  if opkg list-installed | grep -q "^luci-app-youtubeUnblock "; then
    printf "\033[33;1mОбнаружен luci-app-youtubeUnblock, удаление...\033[0m\n"
    opkg remove luci-app-youtubeUnblock
  fi
  if opkg list-installed | grep -q "^youtubeUnblock "; then
	  printf "\033[33;1mОбнаружен youtubeUnblock, удаление...\033[0m\n"
    opkg remove youtubeUnblock
  fi
}

config_apps() {
  printf "\033[33;1mПреднастройка Zapret\033[0m\n"
  printf "\033[33;1mЗагрузка zapret-hosts-user.txt\033[0m\n"
  wget https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/zapret-hosts-user.txt -O /opt/zapret/ipset/zapret-hosts-user.txt > /dev/null 2>&1
  printf "\033[33;1mУстановка конфигурации zapret NFQWS_OPT\033[0m\n"
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
  printf "\033[33;1m Перезапуск zapret: \033[0m"
  /etc/init.d/zapret restart >/dev/null 2>&1 && printf "\033[32;1mZapret перезапущен\033[0m\n" || { printf "\033[31;1mОшибка при перезапуске Zapret\033[0m\n" >&2; exit 1; }
  
}

main
