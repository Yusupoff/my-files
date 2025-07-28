#!/bin/sh

# Находим интерфейс Zerotier
zt_interface=$(ifconfig | grep '^zt' | awk '{print $1}' | head -n 1)

if [ -z "$zt_interface" ]; then
    echo "Zerotier интерфейс не найден"
    exit 1
fi

echo "Найден Zerotier интерфейс: $zt_interface"

# Проверяем существует ли уже зона zerotier
zone_exists=$(uci -q get firewall.@zone[-1].name)

# Ищем зону zerotier среди всех зон
found_zone=0
zone_index=0
while uci -q get firewall.@zone[$zone_index] > /dev/null; do
    if [ "$(uci -q get firewall.@zone[$zone_index].name)" = "zerotier" ]; then
        found_zone=1
        break
    fi
    zone_index=$((zone_index + 1))
done

if [ $found_zone -eq 1 ]; then
    echo "Зона zerotier уже существует, проверяем актуальность интерфейса"
    
    # Получаем текущий список интерфейсов зоны
    current_interface_found=0
    network_index=0
    while uci -q get firewall.@zone[$zone_index].network[$network_index] > /dev/null; do
        if [ "$(uci -q get firewall.@zone[$zone_index].network[$network_index])" = "$zt_interface" ]; then
            current_interface_found=1
            break
        fi
        network_index=$((network_index + 1))
    done
    
    if [ $current_interface_found -eq 0 ]; then
        echo "Добавляем интерфейс $zt_interface в зону zerotier"
        uci add_list firewall.@zone[$zone_index].network="$zt_interface"
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

# Проверяем существует ли уже правило forwarding zerotier->lan
forwarding_exists=0
forwarding_index=0
while uci -q get firewall.@forwarding[$forwarding_index] > /dev/null; do
    src=$(uci -q get firewall.@forwarding[$forwarding_index].src)
    dest=$(uci -q get firewall.@forwarding[$forwarding_index].dest)
    
    if [ "$src" = "zerotier" ] && [ "$dest" = "lan" ]; then
        forwarding_exists=1
        break
    fi
    forwarding_index=$((forwarding_index + 1))
done

if [ $forwarding_exists -eq 0 ]; then
    echo "Добавляем правило forwarding"
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='zerotier'
    uci set firewall.@forwarding[-1].dest='lan'
    uci commit firewall
else
    echo "Правило forwarding уже существует"
fi

echo "Применяем изменения"
/etc/init.d/firewall reload

echo "Готово. Текущая конфигурация:"
uci show firewall | grep -E "(zerotier|forwarding)"
