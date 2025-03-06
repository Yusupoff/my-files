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
VERSION=$(echo "$JSON" | jsonfilter -e '@["version"]')

wget https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/youtubeUnblock-$VERSION-$ARCH-openwrt-23.05.ipk -O /tmp/youtubeUnblock-$VERSION-$ARCH-openwrt-23.05.ipk
wget https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/luci-app-youtubeUnblock-$VERSION.ipk -O /tmp/luci-app-youtubeUnblock-$VERSION.ipk

opkg install /tmp/youtubeUnblock-$VERSION-$ARCH-openwrt-23.05.ipk
opkg install /tmp/luci-app-youtubeUnblock-$VERSION.ipk

sleep 2
uci del youtubeUnblock.cfg02d2da.sni_domains
uci add_list youtubeUnblock.cfg02d2da.sni_domains='googlevideo.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='ggpht.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='ytimg.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='youtube.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='play.google.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='youtu.be'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='googleapis.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='googleusercontent.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='gstatic.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='l.google.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='facebook.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='fbcdn.net'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='fb.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='messenger.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='yt3.ggpht.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.fhrk1-1.fna.fbcdn.net'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.fkun2-1.fna.fbcdn.net'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.frix7-1.fna.fbcdn.net'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='instagram.fvno2-1.fna.fbcdn.net'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='cdninstagram.com'
uci add_list youtubeUnblock.cfg02d2da.sni_domains='1e100.net'
#uci set youtubeUnblock.youtubeUnblock.post_args='--silent'
uci commit
/etc/init.d/youtubeUnblock restart
