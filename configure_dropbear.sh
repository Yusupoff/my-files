#!/bin/sh

# Скрипт для конфигурации Dropbear SSH и firewall правил
# С защитой от дублирования

set +e

# Переменные для отслеживания выполнения
LOCK_FILE="/tmp/dropbear_config.lock"
CONFIG_VERSION_FILE="/etc/config/.dropbear_version"
CONFIG_VERSION="1"

# Функция для логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/dropbear_config.log
}

# Функция для проверки и создания lock файла
check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE")))
        if [ $lock_age -lt 3600 ]; then
            log "ОШИБКА: Скрипт уже запускался менее часа назад. Прерывание."
            exit 1
        else
            log "ПРЕДУПРЕЖДЕНИЕ: Удаляю устаревший lock файл"
            rm -f "$LOCK_FILE"
        fi
    fi
}

# Функция для создания lock файла
create_lock() {
    mkdir -p "$(dirname "$LOCK_FILE")"
    touch "$LOCK_FILE"
}

# Функция для удаления lock файла
remove_lock() {
    rm -f "$LOCK_FILE"
}

# Функция для проверки версии конфига
check_config_version() {
    if [ -f "$CONFIG_VERSION_FILE" ]; then
        stored_version=$(cat "$CONFIG_VERSION_FILE")
        if [ "$stored_version" = "$CONFIG_VERSION" ]; then
            log "Конфигурация уже применена (версия $CONFIG_VERSION)"
            return 0
        fi
    fi
    return 1
}

# Функция для сохранения версии
save_config_version() {
    mkdir -p "$(dirname "$CONFIG_VERSION_FILE")"
    echo "$CONFIG_VERSION" > "$CONFIG_VERSION_FILE"
}

# Trap для очистки при выходе
trap 'remove_lock' EXIT INT TERM

# Главная логика
main() {
    log "=========================================="
    log "Начало конфигурации Dropbear SSH"
    log "=========================================="
    
    # Проверка lock файла
    check_lock
    
    # Проверка версии конфига
    if check_config_version; then
        log "Конфигурация уже применена. Выход."
        return 0
    fi
    
    # Создание lock файла
    create_lock
    log "Lock файл создан: $LOCK_FILE"
    
    # === КОНФИГУРАЦИЯ DROPBEAR ===
    log "Конфигурирую Dropbear SSH..."
    
    # Удаление старых секций
    log "Удаляю старые конфигурации Dropbear..."
    while uci -q delete dropbear.@dropbear[0]; do :; done
    
    # Добавление первого экземпляра (порт 22, с аутентификацией)
    log "Добавляю Dropbear на порт 22 (с паролями)..."
    uci add dropbear dropbear
    uci set dropbear.@dropbear[-1].Port='22'
    uci set dropbear.@dropbear[-1].PasswordAuth='on'
    uci set dropbear.@dropbear[-1].RootPasswordAuth='on'
    
    # Добавление второго экземпляра (порт 222, без аутентификации по паролю)
    log "Добавляю Dropbear на порт 222 (без паролей)..."
    uci add dropbear dropbear
    uci set dropbear.@dropbear[-1].Port='222'
    uci set dropbear.@dropbear[-1].PasswordAuth='off'
    uci set dropbear.@dropbear[-1].RootPasswordAuth='off'
    
    # Применение конфигурации Dropbear
    log "Применяю конфигурацию Dropbear..."
    uci commit dropbear
    
    # === КОНФИГУРАЦИЯ FIREWALL ===
    log "Конфигурирую firewall правило для порта 222..."
    
    # Проверка существования правила с портом 222
    RULE_EXISTS=$(uci show firewall | grep -c "dest_port='222'")
    if [ "$RULE_EXISTS" -gt 0 ]; then
      log "Правило для порта 222 уже существует (найдено $RULE_EXISTS правил)"
      # Можно дополнительно проверить по имени
      NAME_EXISTS=$(uci show firewall | grep -c "\.name='Allow-Port-222'")
      if [ "$NAME_EXISTS" -eq 0 ]; then
        log "ОБНАРУЖЕНО: Существуют правила для порта 222, но с другим именем"
      fi
    else
    # Добавление нового правила
      uci add firewall rule
      uci set firewall.@rule[-1].name='Allow-Port-222'
      uci set firewall.@rule[-1].src='wan'
      uci set firewall.@rule[-1].proto='tcp'
      uci set firewall.@rule[-1].dest_port='222'
      uci set firewall.@rule[-1].target='ACCEPT'
      log "Firewall правило добавлено"
    
      # Применение конфигурации firewall
      log "Применяю firewall конфигурацию..."
      uci commit firewall
    fi
    
    # === КОНФИГУРАЦИЯ AUTHORIZED KEYS ===
    log "Конфигурирую authorized_keys..."
    
    mkdir -p /etc/dropbear
    
    # Проверка существования файла и его содержимого
    ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC0yTNLyRCk00jarEq//z1V8IlZSgKL9BdTl+U5FcJngvsm7X1NJHBIUfYrWvXEFJ9TZ+dstF8CuL6XAGOewXeSfEs5JrAYbe92XHU6KOYFsKkl9i4YED3/RDvS8nsbT0Zb/BAJsf7LCiGGLUUZSL/so8N7Bn1Dz7CPP/ktHRENLyJknllIQqwgWw9MJzKxdp9ABmLI+N0DI1QlDtfFmzRKR/xMcy9dB6hW4RnFMTB7gC3HbKBNwmJh1ueY/PGwceJIRxzPKsqzMoFmVgO61uN9lqIAFh9C10+YgyaWFRLIiF2bql8dUALAsu7UJFdZiO4/MsXHhW+t3MK504gNKgzx0kTUHf25/37Fz8mWCCGhAeYrLz0DdPXhJ8T5PsuEXIFZJD90mQDyK1GdlWR+GUiNAh5YJmaEkEmwMzYgAIo2erCp8aVI+xNQSmYwMNnU6Cf8TW2PW2yA40VP8FqAQL58Eyy35oaUAgVn6dzDI+ZKhdpAkB/c1uZgUExPR1dw6WI4FtuVjr8QGbgSm3HYN79Gvu+gbnfiqqFPMvzShf02uIvDn6dYWgxxqWxoYcsfe0VkT+zt/xBt2d4krrFpdbC7eXlS1FY3onWnxT7nnlzeil3Jjg5GoOwYmFu/yoox6l5y0Gx8ZQGhbZ/6O9Z48IY9v4e8RVR5DqwWfz1QPniEbQ=="
    
    if [ -f /etc/dropbear/authorized_keys ]; then
        if grep -q "$(echo "$ssh_key" | cut -d' ' -f2)" /etc/dropbear/authorized_keys; then
            log "SSH ключ уже присутствует в authorized_keys"
        else
            log "Добавляю SSH ключ в authorized_keys"
            echo "$ssh_key" >> /etc/dropbear/authorized_keys
        fi
    else
        log "Создаю файл authorized_keys с SSH ключом"
        echo "$ssh_key" > /etc/dropbear/authorized_keys
    fi
    
    # Установка правильных прав доступа
    chmod 600 /etc/dropbear/authorized_keys
    log "Права доступа установлены (600)"
    
    # === ПЕРЕЗАГРУЗКА СЕРВИСОВ ===
    log "Перезагружаю firewall и Dropbear..."
    /etc/init.d/firewall restart || log "ОШИБКА: Не удалось перезагрузить firewall"
    /etc/init.d/dropbear restart || log "ОШИБКА: Не удалось перезагрузить dropbear"
    
    # === ФИНАЛИЗАЦИЯ ===
    save_config_version
    log "Версия конфигурации сохранена: $CONFIG_VERSION"
    
    log "=========================================="
    log "Конфигурация успешно завершена!"
    log "=========================================="
    
    return 0
}

# Запуск
main
