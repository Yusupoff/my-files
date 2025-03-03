#!/bin/sh
echo "Update youtubeUnblock"
ARCH=$(opkg info kernel | grep 'Architecture:' | awk '{print $2}')
echo $ARCH
ENDPOINT="myhostkeenetic.zapto.org"
PORT=5000
REQUEST=$(cat <<EOF
GET /send HTTP/1.1
Host: $ENDPOINT
Accept: application/json

EOF
)
# Отправка запроса и получение ответа
RESPONSE=$(echo -e "$REQUEST" | nc "$ENDPOINT" "$PORT") > /dev/null 2>&1

# Извлечение JSON из ответа
JSON=$(echo "$RESPONSE" | awk 'BEGIN {RS="\r\n\r\n"} NR==2')
VERSION=$(echo "$JSON" | awk -F'"' '/"version":/ {print $4}')

wget https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/youtubeUnblock-$VERSION-$ARCH-openwrt-23.05.ipk -O /tmp/youtubeUnblock-$VERSION-$ARCH-openwrt-23.05.ipk
wget https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/luci-app-youtubeUnblock-$VERSION.ipk -O /tmp/luci-app-youtubeUnblock-$VERSION.ipk

opkg install /tmp/youtubeUnblock-$VERSION-$ARCH-openwrt-23.05.ipk
opkg install /tmp/luci-app-youtubeUnblock-$VERSION.ipk
