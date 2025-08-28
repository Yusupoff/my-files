#!/bin/sh
SCRIPT_VERSION="2.2"

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
  wget "https://github.com/Waujito/youtubeUnblock/releases/download/v1.1.0/youtubeUnblock-${VERSION}-${ARCH}-openwrt-23.05.ipk" -O "/tmp/youtubeUnblock_${ARCH}.ipk" >/dev/null 2>/dev/null && msg_i " youtubeUnblock_${VERSION}_${ARCH}.ipk загружен" || {
    msg_e " Ошибка скачивания youtubeUnblock_${VERSION}_${ARCH}.ipk"
  }
  wget "https://github.com/Waujito/youtubeUnblock/releases/download/v1.1.0/luci-app-youtubeUnblock-1.1.0-1-473af29.ipk" -O "/tmp/luci-app-youtubeUnblock.ipk" 2>/dev/null && msg_i " luci-app-youtubeUnblock_${VERSION}.ipk загружен" || {
    msg_e " Ошибка скачивания luci-app-youtubeUnblock_${VERSION}.ipk"
  }
  msg_i "Устоновка пакетов"
  opkg install /tmp/youtubeUnblock_${ARCH}.ipk && rm -f /tmp/youtubeUnblock_${ARCH}.ipk
  opkg install /tmp/luci-app-youtubeUnblock.ipk  && rm -f /tmp/luci-app-youtubeUnblock.ipk

}

config_youtubeUnblock() {
  msg_i "Настройка youtubeUnblock"
  while uci -q delete youtubeUnblock.@section[0]; do :; done
  uci set youtubeUnblock.youtubeUnblock.conf_strat='ui_flags'
  uci set youtubeUnblock.youtubeUnblock.packet_mark='32768'
  uci set youtubeUnblock.youtubeUnblock.queue_num='537'
  uci set youtubeUnblock.youtubeUnblock.silent='0'
  uci set youtubeUnblock.youtubeUnblock.no_ipv6='1'
  uci add youtubeUnblock section # =cfg02d2da
  uci set youtubeUnblock.@section[-1].name='youtube'
  uci set youtubeUnblock.@section[-1].enabled='1'
  uci set youtubeUnblock.@section[-1].tls_enabled='1'
  uci set youtubeUnblock.@section[-1].fake_sni='1'
  uci set youtubeUnblock.@section[-1].faking_strategy='pastseq'
  uci set youtubeUnblock.@section[-1].fake_sni_seq_len='1'
  uci set youtubeUnblock.@section[-1].fake_sni_type='default'
  uci set youtubeUnblock.@section[-1].frag='tcp'
  uci set youtubeUnblock.@section[-1].frag_sni_reverse='1'
  uci set youtubeUnblock.@section[-1].frag_sni_faked='0'
  uci set youtubeUnblock.@section[-1].frag_middle_sni='1'
  uci set youtubeUnblock.@section[-1].frag_sni_pos='1'
  uci set youtubeUnblock.@section[-1].seg2delay='0'
  uci set youtubeUnblock.@section[-1].fk_winsize='0'
  uci set youtubeUnblock.@section[-1].synfake='0'
  uci set youtubeUnblock.@section[-1].sni_detection='parse'
  uci set youtubeUnblock.@section[-1].all_domains='0'
  uci add_list youtubeUnblock.@section[-1].sni_domains='googlevideo.com'
  uci add_list youtubeUnblock.@section[-1].sni_domains='ggpht.com'
  uci add_list youtubeUnblock.@section[-1].sni_domains='ytimg.com'
  uci add_list youtubeUnblock.@section[-1].sni_domains='youtube.com'
  uci add_list youtubeUnblock.@section[-1].sni_domains='play.google.com'
  uci add_list youtubeUnblock.@section[-1].sni_domains='youtu.be'
  uci add_list youtubeUnblock.@section[-1].sni_domains='googleapis.com'
  uci add_list youtubeUnblock.@section[-1].sni_domains='googleusercontent.com'
  uci add_list youtubeUnblock.@section[-1].sni_domains='gstatic.com'
  uci add_list youtubeUnblock.@section[-1].sni_domains='l.google.com'
  uci set youtubeUnblock.@section[-1].quic_drop='1'
  uci commit youtubeUnblock
  /etc/init.d/youtubeUnblock restart >/dev/null 2>&1
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
