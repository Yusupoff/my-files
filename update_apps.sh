#!/bin/sh
SERVER="myhostkeenetic.zapto.org"
PORT=5000
ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
VERSION=

main() {
  printf "\033[33;1mUpdate zapret\033[0m \n"
  data_receiving
  download_install
  check_old_apps
  config_apps
  if pgrep -f "zapret" > /dev/null; then
    printf "\033[32;1mПрограмма zapret запущена.\033[0m\n"
  else
    printf "\033[31;1mПрограмма zapret не запущена.\033[0m\n"
  fi
}

data_receiving() {
  REQUEST=$(printf 'GET /send HTTP/1.1\nHost: %s\nAccept: application/json\n\n' "$SERVER")
  RESPONSE=$(echo -e "$REQUEST" | nc "$SERVER" "$PORT") > /dev/null 2>&1
  JSON=$(echo "$RESPONSE" | awk 'BEGIN {RS="\r\n\r\n"} NR==2')
  VERSION=$(echo "$JSON" | jsonfilter -e '@["version"]')
}

download_install() {
  opkg update > /dev/null 2>&1
  printf "\033[33;1mЗагрузка пакетов\033[0m \n"
  wget https://github.com/Yusupoff/my-files/raw/refs/heads/main/zapret_$VERSION_$ARCH.ipk -O /tmp/zapret_$VERSION_$ARCH.ipk  > /dev/null 2>&1
  wget https://github.com/Yusupoff/my-files/raw/refs/heads/main/luci-app-zapret_$VERSION_all.ipk -O /tmp/luci-app-zapret_$VERSION_all.ipk  > /dev/null 2>&1
  printf "\033[33;1mУстоновка пакетов\033[0m \n"
  opkg install /tmp/youtubeUnblock-$VERSION-$ARCH-openwrt-23.05.ipk  >> /var/log/youtubeUnblock-install.log 2>&1
  opkg install /tmp/luci-app-youtubeUnblock-$VERSION.ipk  >> /var/log/youtubeUnblock-install.log 2>&1
}

check_old_app() {
  if opkg list-installed luci-app-youtubeUnblock >/dev/null 2>&1; then
	printf "\033[33;1mУдаляю пакет luci-app-youtubeUnblock\033[0m\n"
    opkg remove luci-app-youtubeUnblock
  fi
  if opkg list-installed youtubeUnblock >/dev/null 2>&1; then
	printf "\033[33;1mУдаляю пакет youtubeUnblock\033[0m\n"
    opkg remove youtubeUnblock
  fi
}

config_apps() {
  printf "\033[33;1mНастройка пакетов\033[0m \n"
  wget http://myhostkeenetic.zapto.org:5000/files/zapret-hosts-user.txt -O /opt/zapret/ipset/zapret-hosts-user.txt

  uci set zapret.config.NFQWS_OPT='
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--dpi-desync=fake,multidisorder
--dpi-desync-split-pos=1,midsld
--dpi-desync-repeats=11
--dpi-desync-fooling=md5sig
--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
--new
--filter-udp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--dpi-desync=fake
--dpi-desync-repeats=11
--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin
--new
--filter-tcp=80
--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
--dpi-desync=fake,fakedsplit
--dpi-desync-autottl=2
--dpi-desync-fooling=md5sig
--new
--filter-udp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
--dpi-desync=fake
--dpi-desync-repeats=11
--new
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
--dpi-desync=fake,multidisorder
--dpi-desync-split-pos=midsld
--dpi-desync-repeats=6
--dpi-desync-fooling=badseq,md5sig
'
  uci commit zapret
  /etc/init.d/zapret restart
}

main
