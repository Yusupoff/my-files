#!/bin/sh

# Пакеты для проверки
PACKAGES="jsonfilter awk grep"

# Проверяем каждый пакет
for pkg in $PACKAGES; do
    if ! opkg list-installed | grep -q "^$pkg "; then
        echo "Пакет $pkg не установлен"
        NEED_INSTALL=1
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done

# Если есть отсутствующие пакеты
if [ -n "$NEED_INSTALL" ]; then
    echo "Обновление списка пакетов..."
    opkg update
    echo "Установка отсутствующих пакетов: $MISSING_PKGS"
    opkg install $MISSING_PKGS
else
    echo "Все необходимые пакеты уже установлены"
fi