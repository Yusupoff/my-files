#!/bin/sh
# ============================================================================
#  Установщик luci-app-ssclash + ядро Mihomo для OpenWrt
#  Источник: https://github.com/zerolabnet/SSClash
#
#  Скрипт автоматически:
#   - определяет пакетный менеджер (apk / opkg);
#   - определяет архитектуру устройства и сетевую подсистему (nft/iptables);
#   - ставит необходимые зависимости;
#   - скачивает и устанавливает последнюю версию luci-app-ssclash;
#   - скачивает и устанавливает последнее (или указанное) ядро Mihomo;
#   - запускает/перезапускает службу SSClash.
#
#  Запуск (от root):
#     sh install-ssclash.sh
#
#  Необязательные переменные окружения:
#     SSCLASH_VERSION   - версия luci-app-ssclash (например 4.5.2), по умолчанию "latest"
#     MIHOMO_VERSION    - версия ядра Mihomo (например 1.19.24), по умолчанию "latest"
#     MIHOMO_ARCH       - принудительно задать архитектуру ядра Mihomo
#                         (amd64, arm64, armv5, armv6, armv7,
#                          mipsle-softfloat, mipsle-hardfloat,
#                          mips-softfloat, mips-hardfloat, 386, riscv64)
#     MIHOMO_COMPAT     - суффикс "-compatible" (например "-compatible" или "")
#
#  Пример: указать конкретную версию ядра
#     MIHOMO_VERSION=1.19.21 sh install-ssclash.sh
# ============================================================================

# --- цвета ---
RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
BOLD=$(printf '\033[1m')
NC=$(printf '\033[0m')

step() { echo; echo "${YELLOW}${BOLD}==> $1${NC}"; }
ok()   { echo "${GREEN}[OK]${NC} $1"; }
warn() { echo "${YELLOW}[!]${NC} $1"; }
err()  { echo "${RED}[ERROR]${NC} $1"; }
die()  { err "$1"; exit 1; }

# --- проверка root ---
[ "$(id -u)" = "0" ] || die "Скрипт необходимо запускать от пользователя root"

SSCLASH_VERSION="${SSCLASH_VERSION:-latest}"
MIHOMO_VERSION="${MIHOMO_VERSION:-latest}"

SSCLASH_REPO="zerolabnet/ssclash"
MIHOMO_REPO="MetaCubeX/mihomo"

CLASH_DIR="/opt/clash"
CLASH_BIN_DIR="$CLASH_DIR/bin"
TMP_DIR="/tmp/ssclash-install.$$"

mkdir -p "$TMP_DIR"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

# ----------------------------------------------------------------------------
# Вспомогательные функции
# ----------------------------------------------------------------------------

# fetch_url <url> [outfile]
#   без outfile (или "-") - вывод в stdout
fetch_url() {
    url="$1"
    out="${2:--}"
    if command -v curl >/dev/null 2>&1; then
        if [ "$out" = "-" ]; then
            curl -fsSL "$url"
        else
            curl -fsSL "$url" -o "$out"
        fi
    else
        if [ "$out" = "-" ]; then
            wget -qO- "$url"
        else
            wget -qO "$out" "$url"
        fi
    fi
}

# gh_release_json <owner/repo> <tag|latest>
gh_release_json() {
    repo="$1"
    tag="$2"
    if [ "$tag" = "latest" ]; then
        fetch_url "https://api.github.com/repos/$repo/releases/latest"
    else
        fetch_url "https://api.github.com/repos/$repo/releases/tags/$tag"
    fi
}

# extract_tag_name <json>
extract_tag_name() {
    printf '%s' "$1" | grep -o '"tag_name": *"[^"]*"' | head -n1 | sed 's/.*"\([^"]*\)"$/\1/'
}

# extract_asset_url <json> <substring1> [substring2]
# Возвращает первый browser_download_url, содержащий обе подстроки
extract_asset_url() {
    json="$1"
    s1="$2"
    s2="${3:-}"
    printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*"' \
        | sed 's/.*"\(https[^"]*\)"/\1/' \
        | grep -F "$s1" \
        | { [ -n "$s2" ] && grep -F "$s2" || cat; } \
        | head -n1
}

# normalize_tag <version|latest> -> добавляет "v" если версия задана без него
normalize_tag() {
    case "$1" in
        latest) echo "latest" ;;
        v*)     echo "$1" ;;
        *)      echo "v$1" ;;
    esac
}

# install_pkg <package_name>
install_pkg() {
    pkg="$1"
    case "$PKG_MGR" in
        apk)
            if apk info -e "$pkg" >/dev/null 2>&1; then
                ok "$pkg уже установлен"
            elif apk add "$pkg" >/dev/null 2>&1; then
                ok "$pkg установлен"
            else
                warn "Не удалось установить $pkg (пакет может отсутствовать в репозитории)"
            fi
            ;;
        opkg)
            if opkg list-installed | grep -q "^$pkg "; then
                ok "$pkg уже установлен"
            elif opkg install "$pkg" >/dev/null 2>&1; then
                ok "$pkg установлен"
            else
                warn "Не удалось установить $pkg (пакет может отсутствовать в репозитории)"
            fi
            ;;
    esac
}

# ----------------------------------------------------------------------------
# Шаг 1: определение пакетного менеджера
# ----------------------------------------------------------------------------
step "Шаг 1/7: Определение пакетного менеджера"

if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    SSCLASH_EXT="apk"
    ok "Обнаружен apk (OpenWrt >= 25)"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    SSCLASH_EXT="ipk"
    ok "Обнаружен opkg (OpenWrt < 25)"
else
    die "Не найден ни apk, ни opkg. Это точно OpenWrt?"
fi

# ----------------------------------------------------------------------------
# Шаг 2: обновление списка пакетов
# ----------------------------------------------------------------------------
step "Шаг 2/7: Обновление списка пакетов"

case "$PKG_MGR" in
    apk)   apk update ;;
    opkg)  opkg update ;;
esac

# ----------------------------------------------------------------------------
# Шаг 3: определение архитектуры устройства и сетевого стека
# ----------------------------------------------------------------------------
step "Шаг 3/7: Определение архитектуры устройства"

ARCH_RAW=""
if [ -f /etc/openwrt_release ]; then
    # shellcheck disable=SC1091
    . /etc/openwrt_release
    ARCH_RAW="$DISTRIB_ARCH"
fi
[ -z "$ARCH_RAW" ] && ARCH_RAW="$(uname -m)"

ok "Архитектура устройства (OpenWrt): $ARCH_RAW"

if [ -z "$MIHOMO_ARCH" ]; then
    case "$ARCH_RAW" in
        x86_64)
            MIHOMO_ARCH="amd64"; MIHOMO_COMPAT="-compatible" ;;
        i386|i486|i586|i686)
            MIHOMO_ARCH="386"; MIHOMO_COMPAT="" ;;
        aarch64*|arm64*)
            MIHOMO_ARCH="arm64"; MIHOMO_COMPAT="" ;;
        mipsel_*)
            MIHOMO_ARCH="mipsle-softfloat"; MIHOMO_COMPAT="" ;;
        mips_*)
            MIHOMO_ARCH="mips-softfloat"; MIHOMO_COMPAT="" ;;
        riscv64*)
            MIHOMO_ARCH="riscv64"; MIHOMO_COMPAT="" ;;
        arm_arm1176*|arm_arm926*|arm_fa526*|arm_xscale*)
            MIHOMO_ARCH="armv5"; MIHOMO_COMPAT="" ;;
        arm_*)
            # Большинство современных ARM-роутеров (cortex-a5/a7/a8/a9/a15...)
            MIHOMO_ARCH="armv7"; MIHOMO_COMPAT="" ;;
        *)
            MIHOMO_ARCH=""; MIHOMO_COMPAT="" ;;
    esac
else
    MIHOMO_COMPAT="${MIHOMO_COMPAT:-}"
fi

if [ -z "$MIHOMO_ARCH" ]; then
    die "Не удалось определить архитектуру ядра Mihomo для '$ARCH_RAW'. \
Задайте её вручную, например: MIHOMO_ARCH=armv7 sh $0 \
(список доступных архитектур: https://github.com/MetaCubeX/mihomo/releases)"
fi

ok "Архитектура ядра Mihomo: ${MIHOMO_ARCH}${MIHOMO_COMPAT}"

# Определение firewall-стека (nftables/iptables) для выбора tproxy-модуля
if command -v fw4 >/dev/null 2>&1 || command -v nft >/dev/null 2>&1; then
    TPROXY_PKG="kmod-nft-tproxy"
    ok "Обнаружен firewall4 (nftables) -> $TPROXY_PKG"
else
    TPROXY_PKG="iptables-mod-tproxy"
    ok "Обнаружен firewall3 (iptables) -> $TPROXY_PKG"
fi

# ----------------------------------------------------------------------------
# Шаг 4: установка зависимостей
# ----------------------------------------------------------------------------
step "Шаг 4/7: Установка зависимостей"

for pkg in coreutils-base64 kmod-tun "$TPROXY_PKG"; do
    install_pkg "$pkg"
done

# ----------------------------------------------------------------------------
# Шаг 5: получение информации о релизах
# ----------------------------------------------------------------------------
step "Шаг 5/7: Получение информации о последних версиях"

echo "  Запрос информации о релизе luci-app-ssclash..."
SSCLASH_TAG_REQ="$(normalize_tag "$SSCLASH_VERSION")"
SSCLASH_JSON="$(gh_release_json "$SSCLASH_REPO" "$SSCLASH_TAG_REQ")"
[ -n "$SSCLASH_JSON" ] || die "Не удалось получить данные релиза $SSCLASH_REPO с GitHub API"

SSCLASH_TAG="$(extract_tag_name "$SSCLASH_JSON")"
[ -n "$SSCLASH_TAG" ] || die "Не удалось определить версию luci-app-ssclash (репозиторий: $SSCLASH_REPO, запрошено: $SSCLASH_TAG_REQ)"

SSCLASH_URL="$(extract_asset_url "$SSCLASH_JSON" "luci-app-ssclash" ".$SSCLASH_EXT")"
[ -n "$SSCLASH_URL" ] || die "Не найден файл .$SSCLASH_EXT для luci-app-ssclash в релизе $SSCLASH_TAG"

ok "luci-app-ssclash: $SSCLASH_TAG ($(basename "$SSCLASH_URL"))"

echo "  Запрос информации о релизе Mihomo..."
MIHOMO_TAG_REQ="$(normalize_tag "$MIHOMO_VERSION")"
MIHOMO_JSON="$(gh_release_json "$MIHOMO_REPO" "$MIHOMO_TAG_REQ")"
[ -n "$MIHOMO_JSON" ] || die "Не удалось получить данные релиза $MIHOMO_REPO с GitHub API"

MIHOMO_TAG="$(extract_tag_name "$MIHOMO_JSON")"
[ -n "$MIHOMO_TAG" ] || die "Не удалось определить версию Mihomo (репозиторий: $MIHOMO_REPO, запрошено: $MIHOMO_TAG_REQ)"

MIHOMO_PATTERN="mihomo-linux-${MIHOMO_ARCH}${MIHOMO_COMPAT}-${MIHOMO_TAG}"
MIHOMO_URL="$(extract_asset_url "$MIHOMO_JSON" "$MIHOMO_PATTERN" ".gz")"

if [ -z "$MIHOMO_URL" ]; then
    # запасной вариант: без точного совпадения версии в имени файла
    MIHOMO_URL="$(extract_asset_url "$MIHOMO_JSON" "mihomo-linux-${MIHOMO_ARCH}${MIHOMO_COMPAT}-v" ".gz")"
fi

[ -n "$MIHOMO_URL" ] || die "Не найден файл ядра Mihomo для архитектуры '${MIHOMO_ARCH}${MIHOMO_COMPAT}' в релизе $MIHOMO_TAG. \
Проверьте доступные архитектуры на https://github.com/MetaCubeX/mihomo/releases и задайте MIHOMO_ARCH/MIHOMO_COMPAT вручную."

ok "Mihomo: $MIHOMO_TAG ($(basename "$MIHOMO_URL"))"

# ----------------------------------------------------------------------------
# Шаг 6: установка luci-app-ssclash
# ----------------------------------------------------------------------------
step "Шаг 6/7: Загрузка и установка luci-app-ssclash"

SSCLASH_PKG_FILE="$TMP_DIR/$(basename "$SSCLASH_URL")"
echo "  Загрузка: $SSCLASH_URL"
fetch_url "$SSCLASH_URL" "$SSCLASH_PKG_FILE" || die "Ошибка загрузки $SSCLASH_URL"

case "$PKG_MGR" in
    apk)
        apk add --allow-untrusted "$SSCLASH_PKG_FILE" || die "Ошибка установки luci-app-ssclash"
        ;;
    opkg)
        opkg install "$SSCLASH_PKG_FILE" || die "Ошибка установки luci-app-ssclash"
        ;;
esac

ok "luci-app-ssclash $SSCLASH_TAG установлен"

# ----------------------------------------------------------------------------
# Шаг 7: установка ядра Mihomo
# ----------------------------------------------------------------------------
step "Шаг 7/7: Загрузка и установка ядра Mihomo"

mkdir -p "$CLASH_BIN_DIR"

# Останавливаем службу перед заменой бинарника ядра
if [ -x /etc/init.d/ssclash ]; then
    /etc/init.d/ssclash stop >/dev/null 2>&1
fi

MIHOMO_GZ="$TMP_DIR/clash.gz"
echo "  Загрузка: $MIHOMO_URL"
fetch_url "$MIHOMO_URL" "$MIHOMO_GZ" || die "Ошибка загрузки $MIHOMO_URL"

gunzip -f -c "$MIHOMO_GZ" > "$CLASH_BIN_DIR/clash" || die "Ошибка распаковки ядра Mihomo"
chmod +x "$CLASH_BIN_DIR/clash"

ok "Ядро Mihomo $MIHOMO_TAG установлено в $CLASH_BIN_DIR/clash"

# ----------------------------------------------------------------------------
# Запуск службы
# ----------------------------------------------------------------------------
step "Запуск службы SSClash"

if [ -x /etc/init.d/ssclash ]; then
    /etc/init.d/ssclash enable >/dev/null 2>&1
    /etc/init.d/ssclash restart
    ok "Служба ssclash запущена/перезапущена"
else
    warn "Init-скрипт /etc/init.d/ssclash не найден. \
Перезапустите службу Clash вручную через LuCI: Сервисы -> SSClash."
fi

# ----------------------------------------------------------------------------
# Итог
# ----------------------------------------------------------------------------
echo
echo "${GREEN}${BOLD}Установка завершена!${NC}"
echo
echo "  luci-app-ssclash: ${YELLOW}$SSCLASH_TAG${NC}"
echo "  Mihomo:           ${YELLOW}$MIHOMO_TAG${NC} (${MIHOMO_ARCH}${MIHOMO_COMPAT})"
echo
echo "  Дальнейшие шаги:"
echo "   1. Откройте LuCI -> Сервисы -> SSClash"
echo "   2. Настройте конфигурацию Clash (раздел редактора конфигурации)"
echo "   3. Настройте режим обработки интерфейсов (исключение/явный режим)"
echo "   4. Перезапустите службу Clash при необходимости"
echo
