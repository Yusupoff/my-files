#!/bin/sh
SCRIPT_VERSION="3.0"

# Цветовые коды
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

API_URL="https://api.github.com/repos/Waujito/youtubeUnblock/releases"
SERVER="myhostkeenetic.zapto.org"
PORT=5000
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
PKG_VER=

main() {
  data_receiving
  check_old_apps
  install_release
  config_youtubeUnblock
  
  if pgrep -f "youtube" > /dev/null; then
   echo -e "${GREEN}Служба youtubeUnblock запущена.${NC}"
  else
    echo -e "${RED}Служба youtubeUnblock не запущена.${NC}"
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

  PKG_VER=$(echo "$JSON" | jq -r '.app_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$PKG_VER" = "null" ]; then
    echo -e "${RED}Ошибка: Не удалось извлечь app_ver из JSON${NC}" >&2
    return 1
  fi

  SCRIPT_VER=$(echo "$JSON" | jq -r '.script_ver' 2>/dev/null)
  if [ $? -ne 0 ] || [ "$SCRIPT_VER" = "null" ]; then
    echo -e "${RED}Ошибка: Не удалось извлечь script_ver из JSON${NC}" >&2
    return 1
  fi
  return 0
}

# Получаем список релизов
get_releases() {
    curl -s "$API_URL" | jq -r '.[].tag_name'
}

# Получаем ассеты для выбранного релиза
get_assets() {
    local tag="$1"
    curl -s "$API_URL" | jq -r --arg tag "$tag" '
        .[] | select(.tag_name == $tag) | .assets[].name
    '
}

# Получаем URL для скачивания ассета
get_download_url() {
    local tag="$1"
    local asset="$2"
    curl -s "$API_URL" | jq -r --arg tag "$tag" --arg asset "$asset" '
        .[] | select(.tag_name == $tag) | 
        .assets[] | select(.name == $asset) | .browser_download_url
    '
}

# Устанавливаем пакет
install_package() {
    local url="$1"
    local filename=$(basename "$url")
    
    echo -e "${CYAN}Скачивание пакета ${YELLOW}$filename${CYAN}...${NC}"
    wget "$url" -O "/tmp/$filename" 2>/dev/null
    
    echo -e "${CYAN}Установка пакета...${NC}"
    opkg install --force-overwrite "/tmp/$filename" 2>/dev/null
    rm -f "/tmp/$filename"
}

# Установка выбранного релиза
install_release() {
    local selected_tag=$PKG_VER
    # Получаем ассеты для выбранного релиза
    echo -e "${CYAN}Поиск подходящих пакетов...${NC}"
    local assets=$(get_assets "$selected_tag")
    if [ -z "$assets" ]; then
        echo -e "${RED}Не удалось получить список пакетов для этого релиза!${NC}"
        exit 1
    fi
    
    # Ищем основной пакет для нашей архитектуры
    local main_pkg=$(echo "$assets" | grep -m 1 "youtubeUnblock-.*-$ARCH-openwrt-.*\.ipk")
    
    # Ищем пакет Luci
    local luci_pkg=$(echo "$assets" | grep -m 1 "luci-app-youtubeUnblock")
    
    if [ -z "$main_pkg" ]; then
        echo -e "${RED}Не найден подходящий пакет для архитектуры $ARCH${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Найден основной пакет: ${YELLOW}$main_pkg${NC}"
    
    # Устанавливаем основной пакет
    local main_url=$(get_download_url "$selected_tag" "$main_pkg")
    install_package "$main_url"
    
    # Проверяем и устанавливаем Luci, если есть
    if [ -n "$luci_pkg" ]; then
        if ! is_installed "luci-app-youtubeUnblock"; then
            echo -e "${GREEN}Найден пакет Luci: ${YELLOW}$luci_pkg${NC}"
            local luci_url=$(get_download_url "$selected_tag" "$luci_pkg")
            install_package "$luci_url"
        else
            echo -e "${CYAN}Пакет Luci уже установлен, пропускаем${NC}"
        fi
    else
        echo -e "${YELLOW}Пакет Luci не найден в этом релизе${NC}"
    fi
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