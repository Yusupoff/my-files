#!/bin/sh

# Цветовые коды
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# GitHub API URL
API_URL="https://api.github.com/repos/Waujito/youtubeUnblock/releases"

# Проверяем наличие jq
if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}Ошибка: jq не установлен.${NC} Установите его командой: ${CYAN}opkg install jq${NC}"
    exit 1
fi

# Получаем архитектуру системы
get_arch() {
    ARCH=$(grep -m 1 "/packages/" /etc/opkg/distfeeds.conf | sed -n 's/.*\/packages\/\([^\/]*\).*/\1/p')
    echo "$ARCH"
}

# Проверяем установлен ли пакет
is_installed() {
    local pkg="$1"
    opkg list-installed | grep -q "^$pkg "
}

# Проверяем наличие установленных пакетов
check_installed() {
    is_installed "youtubeUnblock" || is_installed "luci-app-youtubeUnblock"
}

# Удаляем пакеты
uninstall_packages() {
    clear
    echo -e "${YELLOW}Удаление пакетов...${NC}"
    if is_installed "luci-app-youtubeUnblock"; then
        echo -e "${CYAN}Удаляем luci-app-youtubeUnblock...${NC}"
        opkg remove luci-app-youtubeUnblock
    fi
    if is_installed "youtubeUnblock"; then
        echo -e "${CYAN}Удаляем youtubeUnblock...${NC}"
        opkg remove youtubeUnblock
        rm /etc/config/youtubeUnblock
    fi
    echo -e "${GREEN}Пакеты успешно удалены${NC}"
}

# Получаем список релизов
get_releases() {
    curl -s "$API_URL" | jq -r '.[].tag_name'
}

# Получаем ассеты для выбранного релиза
get_assets() {
    local tag="$1"
    curl -s "$API_URL" | jq -r --arg tag "$tag" '
        .[] | select(.tag_name == $tag) | .assets[].name
    '
}

# Получаем URL для скачивания ассета
get_download_url() {
    local tag="$1"
    local asset="$2"
    curl -s "$API_URL" | jq -r --arg tag "$tag" --arg asset "$asset" '
        .[] | select(.tag_name == $tag) | 
        .assets[] | select(.name == $asset) | .browser_download_url
    '
}

# Устанавливаем пакет
install_package() {
    local url="$1"
    local filename=$(basename "$url")
    
    echo -e "${CYAN}Скачивание пакета ${YELLOW}$filename${CYAN}...${NC}"
    wget "$url" -O "/tmp/$filename" 2>/dev/null
    
    echo -e "${CYAN}Установка пакета...${NC}"
    opkg install --force-overwrite "/tmp/$filename" 2>/dev/null
    rm -f "/tmp/$filename"
}

# Отображаем заголовок
show_header() {
    clear
    echo -e "${BLUE}"
    echo "========================================"
    echo "  YouTubeUnblock Установщик/Удалятор"
    echo "========================================"
    echo -e "${NC}"
}

# Установка выбранного релиза
install_release() {
    clear
    # Получаем архитектуру
    ARCH=$(get_arch)
    echo -e "${GREEN}Архитектура системы: ${YELLOW}$ARCH${NC}"
    
    echo -e "${CYAN}Доступные релизы:${NC}"
    local releases=$(get_releases)
    local i=1
    
    # Выводим список релизов
    for release in $releases; do
        echo -e "${BLUE}$i) ${YELLOW}$release${NC}"
        i=$((i+1))
    done
    
    # Выбираем релиз
    echo -ne "${GREEN}Выберите номер релиза: ${NC}"
    read choice
    
    local selected_tag=$(echo "$releases" | sed -n "${choice}p")
    if [ -z "$selected_tag" ]; then
        echo -e "${RED}Неверный выбор!${NC}"
        exit 1
    fi
    clear
    echo -e "${GREEN}Выбран релиз: ${YELLOW}$selected_tag${NC}"
    
    # Получаем ассеты для выбранного релиза
    echo -e "${CYAN}Поиск подходящих пакетов...${NC}"
    local assets=$(get_assets "$selected_tag")
    if [ -z "$assets" ]; then
        echo -e "${RED}Не удалось получить список пакетов для этого релиза!${NC}"
        exit 1
    fi
    
    # Ищем основной пакет для нашей архитектуры
    local main_pkg=$(echo "$assets" | grep -m 1 "youtubeUnblock-.*-$ARCH-openwrt-.*\.ipk")
    
    # Ищем пакет Luci
    local luci_pkg=$(echo "$assets" | grep -m 1 "luci-app-youtubeUnblock")
    
    if [ -z "$main_pkg" ]; then
        echo -e "${RED}Не найден подходящий пакет для архитектуры $ARCH${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Найден основной пакет: ${YELLOW}$main_pkg${NC}"
    
    # Устанавливаем основной пакет
    local main_url=$(get_download_url "$selected_tag" "$main_pkg")
    install_package "$main_url"
    
    # Проверяем и устанавливаем Luci, если есть
    if [ -n "$luci_pkg" ]; then
        if ! is_installed "luci-app-youtubeUnblock"; then
            echo -e "${GREEN}Найден пакет Luci: ${YELLOW}$luci_pkg${NC}"
            local luci_url=$(get_download_url "$selected_tag" "$luci_pkg")
            install_package "$luci_url"
        else
            echo -e "${CYAN}Пакет Luci уже установлен, пропускаем${NC}"
        fi
    else
        echo -e "${YELLOW}Пакет Luci не найден в этом релизе${NC}"
    fi
    
    echo -e "${GREEN}Установка завершена успешно!${NC}"
    read -s -n 1
    main_menu
}

# Функция конфигурации youtubeUnblock
config_youtubeUnblock() {
    while true; do
        clear
        echo -e "\n${CYAN}Меню конфигурации youtubeUnblock:${NC}"
        echo -e "${BLUE}1) ${GREEN}Конфигурация новой версии${NC}"
        echo -e "${BLUE}2) ${GREEN}Конфигурация старой версии${NC}"
        echo -e "${BLUE}0) ${YELLOW}Выход в главное меню${NC}"
        echo -ne "${GREEN}Ваш выбор [0-2]: ${NC}"
        read choice

        case $choice in
            1)
                clear
                echo -e "${YELLOW}Конфигурация для новой версии...${NC}"
                while uci -q delete youtubeUnblock.@section[0]; do :; done
                uci set youtubeUnblock.youtubeUnblock.conf_strat='ui_flags'
                uci set youtubeUnblock.youtubeUnblock.packet_mark='32768'
                uci set youtubeUnblock.youtubeUnblock.queue_num='537'
                uci set youtubeUnblock.youtubeUnblock.silent='0'
                uci set youtubeUnblock.youtubeUnblock.no_ipv6='1'
                uci add youtubeUnblock section # =cfg02d2da
                uci set youtubeUnblock.@section[-1].name='youtube'
                uci set youtubeUnblock.@section[-1].enabled='1'
                uci set youtubeUnblock.@section[-1].tls_enabled='1'
                uci set youtubeUnblock.@section[-1].fake_sni='1'
                uci set youtubeUnblock.@section[-1].faking_strategy='pastseq'
                uci set youtubeUnblock.@section[-1].fake_sni_seq_len='1'
                uci set youtubeUnblock.@section[-1].fake_sni_type='default'
                uci set youtubeUnblock.@section[-1].frag='tcp'
                uci set youtubeUnblock.@section[-1].frag_sni_reverse='1'
                uci set youtubeUnblock.@section[-1].frag_sni_faked='0'
                uci set youtubeUnblock.@section[-1].frag_middle_sni='1'
                uci set youtubeUnblock.@section[-1].frag_sni_pos='1'
                uci set youtubeUnblock.@section[-1].seg2delay='0'
                uci set youtubeUnblock.@section[-1].fk_winsize='0'
                uci set youtubeUnblock.@section[-1].synfake='0'
                uci set youtubeUnblock.@section[-1].sni_detection='parse'
                uci set youtubeUnblock.@section[-1].all_domains='0'
                uci add_list youtubeUnblock.@section[-1].sni_domains='googlevideo.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='ggpht.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='ytimg.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='youtube.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='play.google.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='youtu.be'
                uci add_list youtubeUnblock.@section[-1].sni_domains='googleapis.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='googleusercontent.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='gstatic.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='l.google.com'
                uci set youtubeUnblock.@section[-1].quic_drop='1'
                uci add youtubeUnblock section # =cfg03d2da
                uci set youtubeUnblock.@section[-1].name='other_zapret'
                uci set youtubeUnblock.@section[-1].enabled='1'
                uci set youtubeUnblock.@section[-1].tls_enabled='1'
                uci set youtubeUnblock.@section[-1].fake_sni='1'
                uci set youtubeUnblock.@section[-1].faking_strategy='pastseq'
                uci set youtubeUnblock.@section[-1].fake_sni_seq_len='1'
                uci set youtubeUnblock.@section[-1].fake_sni_type='default'
                uci set youtubeUnblock.@section[-1].frag='tcp'
                uci set youtubeUnblock.@section[-1].frag_sni_reverse='1'
                uci set youtubeUnblock.@section[-1].frag_sni_faked='0'
                uci set youtubeUnblock.@section[-1].frag_middle_sni='1'
                uci set youtubeUnblock.@section[-1].frag_sni_pos='1'
                uci set youtubeUnblock.@section[-1].seg2delay='0'
                uci set youtubeUnblock.@section[-1].fk_winsize='0'
                uci set youtubeUnblock.@section[-1].synfake='0'
                uci set youtubeUnblock.@section[-1].all_domains='0'
                uci set youtubeUnblock.@section[-1].sni_detection='parse'
                uci set youtubeUnblock.@section[-1].quic_drop='0'
                uci set youtubeUnblock.@section[-1].udp_mode='fake'
                uci set youtubeUnblock.@section[-1].udp_faking_strategy='none'
                uci set youtubeUnblock.@section[-1].udp_fake_seq_len='6'
                uci set youtubeUnblock.@section[-1].udp_fake_len='64'
                uci add_list youtubeUnblock.@section[-1].udp_dport_filter='50000-50100'
                uci set youtubeUnblock.@section[-1].udp_filter_quic='disabled'
                uci add_list youtubeUnblock.@section[-1].sni_domains='discord.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='discordapp.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='discord.gg'
                uci add_list youtubeUnblock.@section[-1].sni_domains='discordapp.net'
                uci add_list youtubeUnblock.@section[-1].sni_domains='discord.media'
                uci add_list youtubeUnblock.@section[-1].sni_domains='cdninstagram.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='instagram.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='ig.me'
                uci add_list youtubeUnblock.@section[-1].sni_domains='fbcdn.net'
                uci add_list youtubeUnblock.@section[-1].sni_domains='facebook.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='facebook.net'
                uci add_list youtubeUnblock.@section[-1].sni_domains='fb.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='rutracker.org'
                uci add_list youtubeUnblock.@section[-1].sni_domains='rutracker.net'
                uci add_list youtubeUnblock.@section[-1].sni_domains='rutracker.cc'
                uci add_list youtubeUnblock.@section[-1].sni_domains='rutor.info'
                uci add_list youtubeUnblock.@section[-1].sni_domains='rutor.is'
                uci add_list youtubeUnblock.@section[-1].sni_domains='nnmclub.to'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twitter.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='t.co'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twimg.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='ads-twitter.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='x.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='pscp.tv'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twtrdns.net'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twttr.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='periscope.tv'
                uci add_list youtubeUnblock.@section[-1].sni_domains='tweetdeck.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twitpic.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twitter.co'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twitterinc.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twitteroauth.com'
                uci add_list youtubeUnblock.@section[-1].sni_domains='twitterstat.us'
                uci commit youtubeUnblock
                echo -e "${GREEN}Конфигурация выполнена.${NC}"
                read -s -n 1
                main_menu
                ;;
            2)
                clear
                echo -e "${YELLOW}Конфигурация для старой версии...${NC}"
                while uci -q delete youtubeUnblock.@section[0]; do :; done
                uci set youtubeUnblock.youtubeUnblock='youtubeUnblock'
                uci set youtubeUnblock.youtubeUnblock.frag='tcp'
                uci set youtubeUnblock.youtubeUnblock.frag_sni_reverse='1'
                uci set youtubeUnblock.youtubeUnblock.frag_middle_sni='1'
                uci set youtubeUnblock.youtubeUnblock.frag_sni_pos='1'
                uci set youtubeUnblock.youtubeUnblock.fk_winsize='0'
                uci set youtubeUnblock.youtubeUnblock.seg2delay='0'
                uci set youtubeUnblock.youtubeUnblock.packet_mark='32768'
                uci set youtubeUnblock.youtubeUnblock.fake_sni='1'
                uci set youtubeUnblock.youtubeUnblock.faking_strategy='pastseq'
                uci set youtubeUnblock.youtubeUnblock.fake_sni_seq_len='1'
                uci del youtubeUnblock.youtubeUnblock.sni_domains
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='googlevideo.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='ggpht.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='ytimg.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='youtube.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='play.google.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='youtu.be'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='googleapis.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='googleusercontent.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='gstatic.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='l.google.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='facebook.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='fbcdn.net'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='fb.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='messenger.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='yt3.ggpht.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='instagram.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='fna.fbcdn.net'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='cdninstagram.com'
                uci add_list youtubeUnblock.youtubeUnblock.sni_domains='1e100.net'
                uci set youtubeUnblock.youtubeUnblock.silent='1'
                uci commit youtubeUnblock
                echo -e "${GREEN}Конфигурация выполнена.${NC}"
                read -s -n 1
                main_menu
                ;;
            0)
                echo -e "${YELLOW}Возвращаемся в главное меню...${NC}"
                main_menu
                ;;
            *)
                echo -e "${RED}Неверный выбор! Пожалуйста, введите 0, 1 или 2${NC}"
                ;;
        esac
    done
}

# Главное меню
main_menu() {
    show_header
    
    if check_installed; then
        echo -e "${YELLOW}Обнаружены установленные пакеты youtubeUnblock${NC}"
        echo -e "${CYAN}Выберите действие:${NC}"
        echo -e "${BLUE}1) ${GREEN}Установить другой релиз${NC}"
        echo -e "${BLUE}2) ${GREEN}Конфигурация youtubeUnblock${NC}"
        echo -e "${BLUE}3) ${RED}Удалить пакеты${NC}"
        echo -e "${BLUE}0) ${GREEN}Выход${NC}"
        echo -ne "${GREEN}Ваш выбор [1-2]: ${NC}"
        read choice
        
        case $choice in
            0) exit 1 ;;
            1) install_release ;;
            2) config_youtubeUnblock ;;
            3) uninstall_packages ;;
            *) echo -e "${RED}Неверный выбор!${NC}"; exit 1 ;;
        esac
    else
        install_release
    fi
}

# Запускаем главное меню
main_menu
