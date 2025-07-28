#!/bin/sh

# Находим интерфейс Zerotier
zt_interface=$(ifconfig | grep '^zt' | awk '{print $1}' | head -n 1)

if [ -z "$zt_interface" ]; then
    echo "Zerotier интерфейс не найден"
    exit 1
fi

echo "Найден Zerotier интерфейс: $zt_interface"

# Проверяем существует ли уже зона zerotier
zone_exists=$(uci show firewall | grep "firewall.@zone\[.*\].name='zerotier'")

if [ -n "$zone_exists" ]; then
    echo "Зона zerotier уже существует, проверяем актуальность интерфейса"
    
    # Получаем текущий список интерфейсов зоны
    current_interface=$(uci show firewall | grep -A 5 "firewall.@zone\[.*\].name='zerotier'" | grep "network='$zt_interface'" || echo "")
    
    if [ -z "$current_interface" ]; then
        echo "Обновляем интерфейс в зоне zerotier"
        uci add_list firewall.@zone[-1].network="$zt_interface"
        uci commit firewall
    else
        echo "Интерфейс в зоне актуален"
    fi
else
    echo "Добавляем новую зону zerotier"
    uci add firewall zone
    uci set firewall.@zone[-1].name='zerotier'
    uci set firewall.@zone[-1].input='ACCEPT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='ACCEPT'
    uci add_list firewall.@zone[-1].network="$zt_interface"
    uci commit firewall
fi

# Проверяем существует ли уже правило forwarding
forwarding_exists=$(uci show firewall | grep "firewall.@forwarding\[.*\].src='zerotier'.*dest='lan'")

if [ -n "$forwarding_exists" ]; then
    echo "Правило forwarding уже существует"
else
    echo "Добавляем правило forwarding"
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='zerotier'
    uci set firewall.@forwarding[-1].dest='lan'
    uci commit firewall
fi

echo "Применяем изменения"
/etc/init.d/firewall reload

echo "Готово. Текущая конфигурация:"
uci show firewall | grep -E "(zerotier|forwarding)"
