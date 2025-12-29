#!/bin/sh
SCRIPT_VERSION="3.0"
# Алгоритм выполнения
#     Получение данных для обновлений             data_receiving
#     Провека проверка наличия пакета zapret      check_app_version
#     Обновление нужного релиза youtubeUnblock    install_release
#     Конфигурация youtubeUnblock                 config_youtubeUnblock
#set -x
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
      echo -e "${GREEN}Найден пакет Luci: ${YELLOW}$luci_pkg${NC}"
      local luci_url=$(get_download_url "$selected_tag" "$luci_pkg")
      install_package "$luci_url"
    else
      echo -e "${YELLOW}Пакет Luci не найден в этом релизе${NC}"
    fi
}

check_old_apps() {
  if opkg list-installed | grep -q "^luci-app-zapret "; then
    echo -e "${RED}Обнаружен luci-app-zapret, удаление...${NC}"
    opkg remove luci-app-zapret
  fi
  if opkg list-installed | grep -q "^zapret "; then
	  echo -e "${RED}Обнаружен zapret, удаление...${NC}"
    opkg remove zapret
  fi
}

main