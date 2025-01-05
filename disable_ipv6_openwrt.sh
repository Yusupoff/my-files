#!/bin/sh
# отключение IPv6 на интерфейсах
uci set 'network.lan.ipv6=0'  
uci set 'network.wan.ipv6=0'  
uci set 'dhcp.lan.dhcpv6=disabled'  
/etc/init.d/odhcpd disable  
uci commit
# Отключите RA и DHCPv6, чтобы IPv6-адреса не раздавались
uci -q delete dhcp.lan.dhcpv6  
uci -q delete dhcp.lan.ra  
uci commit dhcp  
/etc/init.d/odhcpd restart
# Теперь вы можете отключить делегирование локальной сети
uci set network.lan.delegate="0"  
uci commit network  
/etc/init.d/network restart
# Вы также можете отключить odhcpd:
/etc/init.d/odhcpd disable  
/etc/init.d/odhcpd stop
# И, наконец, вы можете удалить префикс ULA IPv6:
uci -q delete network.globals.ula_prefix  
uci commit network  
/etc/init.d/network restart
