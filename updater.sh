#!/bin/sh

# Цветовые коды
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

PACKAGES="jq curl kmod-nft-queue"  # Пакеты для проверки

# Проверка наличия пакета в системе
packages_check() {
  for pkg in $PACKAGES; do
    if ! opkg list-installed | grep -q "^$pkg "; then
      NEED_INSTALL=1
      MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
  done
  if [ -n "$NEED_INSTALL" ]; then
    echo -e "${CYAN}Установка отсутствующих пакетов: ${YELLOW}$MISSING_PKGS${NC}"
    echo -e "${CYAN}Обновление списока доступных пакетов."
    opkg update >/dev/null 2>&1 && echo -e "${GREEN}Обновление списка пакетов выполнено!${NC}" || { echo -e "${RED}Ошибка при обновлении списка пакетов${NC}" >&2; exit 1; }
    opkg install $MISSING_PKGS 2>/dev/null
  fi
}

# Скачиваем скрипт
OUTPUT=$(wget https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/send_data.sh -O /usr/bin/send_data.sh 2>&1)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Версия скрипта обновлена!${NC}"
    chmod +x /usr/bin/send_data.sh
else
    echo -e "${RED}Произошла ошибка при обновлении скрипта: $OUTPUT${NC}"
fi

scheduler() {
    # Генерируем случайное время выполнения
    random_hour=$(( RANDOM % 3 ))        # 0-2 часа
    random_min=$(( RANDOM % 50 + 10 ))   # 10-59 минут
    NEW_JOB="$random_min $random_hour * * * /usr/bin/send_data.sh"

    # Временный файл для crontab
    TEMP_FILE=$(mktemp)
    # Получаем текущий crontab и удаляем все старые задания для send_data.sh
    crontab -l | grep -v "/usr/bin/send_data.sh" > $TEMP_FILE 2>/dev/null
    # Добавляем новое задание
    echo "$NEW_JOB" >> $TEMP_FILE
    # Устанавливаем обновленный crontab
    crontab $TEMP_FILE
    # Выводим результат
    echo -e "${GREEN}Задание в планировшик добавлен(обновлён)${NC}"
    echo -e "${CYAN}$NEW_JOB${NC}"
    # Удаляем временный файл
    rm -f $TEMP_FILE
}

packages_check
scheduler
if opkg list-installed | grep -q "^youtubeUnblock "; then
  sh <(wget -qO- https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/config_youtubeUnblock.sh)
fi
echo ""