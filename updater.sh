#!/bin/sh

wget https://raw.githubusercontent.com/Yusupoff/my-files/refs/heads/main/send_data.sh -O /usr/bin/send_data.sh
chmod +x /usr/bin/send_data.sh

# Строка, которую нужно добавить в crontab
random_hour=$(( RANDOM % 3 ))
random_min=$(( RANDOM % 50 + 10 ))
NEW_JOB="$random_min $random_hour * * * /usr/bin/send_data.sh"

# Временный файл для хранения текущего crontab
TEMP_FILE=$(mktemp)

# Получаем текущий crontab и сохраняем его во временный файл
crontab -l > $TEMP_FILE 2>/dev/null

# Проверяем, существует ли уже такая строка в crontab
if ! grep -Fxq "$NEW_JOB" $TEMP_FILE; then
    # Добавляем новую строку в файл
    echo "$NEW_JOB" >> $TEMP_FILE

    # Загружаем обновленный crontab из временного файла
    crontab $TEMP_FILE

    # Выводим сообщение об успехе
    echo "Задание добавлено в crontab:"
    echo "$NEW_JOB"
else
    echo "Задание уже существует в crontab."
fi

# Удаляем временный файл
rm -f $TEMP_FILE
