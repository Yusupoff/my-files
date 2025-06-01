#!/bin/sh

# Скачиваем скрипт
wget https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/send_data.sh -O /usr/bin/send_data.sh
chmod +x /usr/bin/send_data.sh

# Генерируем случайное время выполнения
random_hour=$(( RANDOM % 3 ))
random_min=$(( RANDOM % 50 + 10 ))
NEW_JOB="$random_min $random_hour * * * /usr/bin/send_data.sh"

# Временный файл для crontab
TEMP_FILE=$(mktemp)

# Получаем текущий crontab
crontab -l > $TEMP_FILE 2>/dev/null

# Проверяем, есть ли уже похожая задача (игнорируя время)
if grep -q "/usr/bin/send_data.sh" $TEMP_FILE; then
    echo "Похожее задание уже существует в crontab:"
    grep "/usr/bin/send_data.sh" $TEMP_FILE
else
    # Добавляем новую задачу
    echo "$NEW_JOB" >> $TEMP_FILE
    crontab $TEMP_FILE
    echo "Новое задание добавлено в crontab:"
    echo "$NEW_JOB"
fi

# Удаляем временный файл
rm -f $TEMP_FILE
