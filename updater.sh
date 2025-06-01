#!/bin/sh

# Скачиваем скрипт
wget https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/send_data.sh -O /usr/bin/send_data.sh
chmod +x /usr/bin/send_data.sh

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
echo "Старые задания удалены. Добавлено новое задание:"
echo "$NEW_JOB"

# Удаляем временный файл
rm -f $TEMP_FILE
