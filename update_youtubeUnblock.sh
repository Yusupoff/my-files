#!/bin/sh
SCRIPT_VERSION="2.1"

msg_i() { printf "\033[32;1m%s\033[0m\n" "$1"; }
msg_e() { printf "\033[31;1m%s\033[0m\n" "$1"; }

SERVER="myhostkeenetic.zapto.org"
PORT=5000
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
VERSION=

main() {
  data_receiving
  check_old_apps
  download_install
  config_youtubeUnblock
  
  if pgrep -f "youtube" > /dev/null; then
    msg_i "Служба youtubeUnblock запущена."
  else
    msg_e "Служба youtubeUnblock не запущена."
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

  # Извлечение app_ver и script_ver с помощью jq
  VERSION=$(echo "$JSON" | jq -r '.version' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$VERSION" = "null" ]; then
    msg_e "Ошибка: Не удалось извлечь version из JSON" >&2
    return 1
  fi
  
  return 0
}

download_install() {
  msg_i "Загрузка пакетов:"
  wget "https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/youtubeUnblock-${VERSION}-${ARCH}-openwrt-23.05.ipk" -O "/tmp/youtubeUnblock_${ARCH}.ipk" >/dev/null 2>/dev/null && msg_i " youtubeUnblock_${VERSION}_${ARCH}.ipk загружен" || {
    msg_e " Ошибка скачивания youtubeUnblock_${VERSION}_${ARCH}.ipk"
  }
  wget "https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/luci-app-youtubeUnblock-${VERSION}.ipk" -O "/tmp/luci-app-youtubeUnblock.ipk" 2>/dev/null && msg_i " luci-app-youtubeUnblock_${VERSION}.ipk загружен" || {
    msg_e " Ошибка скачивания luci-app-youtubeUnblock_${VERSION}.ipk"
  }
  msg_i "Устоновка пакетов"
  opkg install /tmp/youtubeUnblock_${ARCH}.ipk && rm -f /tmp/youtubeUnblock_${ARCH}.ipk
  opkg install /tmp/luci-app-youtubeUnblock.ipk  && rm -f /tmp/luci-app-youtubeUnblock.ipk

}

config_youtubeUnblock() {
  msg_i "Настройка пакетов"
  uci del youtubeUnblock.cfg02d2da.sni_domains
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='googlevideo.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='ggpht.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='ytimg.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='youtube.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='play.google.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='youtu.be'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='googleapis.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='googleusercontent.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='gstatic.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='l.google.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='facebook.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='fbcdn.net'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='fb.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='messenger.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='yt3.ggpht.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.fhrk1-1.fna.fbcdn.net'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.fkun2-1.fna.fbcdn.net'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.frix7-1.fna.fbcdn.net'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.fvno2-1.fna.fbcdn.net'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='cdninstagram.com'
  uci add_list youtubeUnblock.cfg02d2da.sni_domains='1e100.net'
  uci set youtubeUnblock.youtubeUnblock.post_args='--silent'
  uci commit
  /etc/init.d/youtubeUnblock restart
}

check_old_apps() {
  if opkg list-installed | grep -q "^luci-app-zapret "; then
    msg_e "Обнаружен luci-app-zapret, удаление..."
    opkg remove luci-app-zapret
  fi
  if opkg list-installed | grep -q "^zapret "; then
	  msg_e "Обнаружен zapret, удаление..."
    opkg remove zapret
  fi
}

main
