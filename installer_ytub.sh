#!/bin/sh

# GitHub репозиторий
REPO_OWNER="Waujito"
REPO_NAME="youtubeUnblock"
API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases"

# Получаем архитектуру системы
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
if [ -z "$ARCH" ]; then
    echo "Не удалось определить архитектуру системы!"
    exit 1
fi
echo "Архитектура системы: $ARCH"

# Получаем список релизов
echo "Получаем список релизов..."
releases=$(curl -s $API_URL | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p')

if [ -z "$releases" ]; then
    echo "Не удалось получить список релизов. Проверьте подключение к интернету."
    exit 1
fi

# Выводим список релизов для выбора
echo "Доступные релизы:"
i=1
for release in $releases; do
    echo "$i) $release"
    i=$((i+1))
done

# Выбор релиза
while true; do
    echo -n "Выберите номер релиза (1-$((i-1))): "
    read choice
    
    if [ "$choice" -eq "$choice" ] 2>/dev/null && [ "$choice" -ge 1 ] && [ "$choice" -lt $i ]; then
        break
    fi
    echo "Неверный выбор. Пожалуйста, введите число от 1 до $((i-1))"
done

# Получаем выбранный релиз
selected_release=$(echo "$releases" | sed -n "${choice}p")
echo "Выбран релиз: $selected_release"

# Получаем URL ассетов
assets_url=$(curl -s $API_URL | sed -n 's/.*"assets_url": "\([^"]*\)".*/\1/p' | sed -n "${choice}p")
if [ -z "$assets_url" ]; then
    echo "Не удалось получить URL ассетов."
    exit 1
fi

# Функция для установки пакета с перезаписью
install_package_force() {
    pkg_pattern=$1
    pkg_name=$(basename "$pkg_pattern" .ipk)
    echo "Ищем пакет $pkg_name..."
    
    pkg_url=$(curl -s $assets_url | sed -n 's/.*"browser_download_url": "\([^"]*\.ipk\)".*/\1/p' | grep "$pkg_pattern")
    
    if [ -z "$pkg_url" ]; then
        echo "Пакет $pkg_name не найден в этом релизе."
        return 1
    fi

    echo "Найден пакет: $pkg_url"
    echo "Скачиваем..."
    wget -q "$pkg_url" -O "/tmp/${pkg_name}.ipk"
    if [ $? -ne 0 ]; then
        echo "Ошибка при скачивании пакета $pkg_name"
        return 1
    fi

    echo "Устанавливаем с принудительной перезаписью..."
    opkg install --force-overwrite "/tmp/${pkg_name}.ipk"
    local status=$?
    if [ $status -ne 0 ]; then
        # Если ошибка, пробуем с дополнительными опциями перезаписи
        echo "Повторная попытка установки с расширенными опциями перезаписи..."
        opkg install --force-overwrite --force-depends "/tmp/${pkg_name}.ipk"
        status=$?
    fi

    if [ $status -ne 0 ]; then
        echo "Ошибка при установке пакета $pkg_name:"
        opkg install "/tmp/${pkg_name}.ipk" 2>&1 | grep -v "Collected errors"
        rm -f "/tmp/${pkg_name}.ipk"
        return 1
    fi

    rm -f "/tmp/${pkg_name}.ipk"
    echo "$pkg_name успешно установлен с перезаписью!"
    return 0
}

# Устанавливаем основной пакет (с учётом архитектуры)
if ! install_package_force "youtubeUnblock.*$ARCH"; then
    exit 1
fi

# Пытаемся найти и установить luci-app (без учёта архитектуры)
luci_found=$(curl -s $assets_url | sed -n 's/.*"browser_download_url": "\([^"]*\.ipk\)".*/\1/p' | grep "luci-app-youtubeUnblock")
if [ -n "$luci_found" ]; then
    echo "Найден пакет Luci-интерфейса, устанавливаем с перезаписью..."
    if install_package_force "luci-app-youtubeUnblock"; then
        echo "Luci-интерфейс успешно установлен!"
        echo "Доступен в веб-интерфейсе OpenWrt по адресу: http://адрес-роутера/cgi-bin/luci/admin/services/youtubeUnblock"
    fi
else
    echo "Пакет Luci-интерфейса не найден в этом релизе."
fi

echo "Установка завершена!"
