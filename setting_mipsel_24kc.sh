#!/bin/sh

wget https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/luci-app-youtubeUnblock-1.0.0-10-f37c3dd.ipk -O /tmp/luci-app-youtubeUnblock-1.0.0-10-f37c3dd.ipk
wget https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/youtubeUnblock-1.0.0-10-f37c3dd-mipsel_24kc-openwrt-23.05.ipk -O /tmp/youtubeUnblock-1.0.0-10-f37c3dd-mipsel_24kc-openwrt-23.05.ipk
opkg install /tmp/*ipk
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
