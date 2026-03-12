# ═══════════════════════════════════════════════
# БАЗА ДАННЫХ: СОХРАНЕНИЕ/ЗАГРУЗКА
# ═══════════════════════════════════════════════

db_backup() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       💾  Сохранение базы данных${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    # Проверяем что контейнер БД запущен
    if ! docker ps --filter "name=remnawave-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnawave-db"; then
        print_error "Контейнер remnawave-db не запущен"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    local backup_dir="${panel_dir}/backups"
    mkdir -p "$backup_dir"

    local timestamp
    timestamp=$(date +%d.%m.%y)
    local dump_file="${backup_dir}/backup_remnawave_${timestamp}.sql.gz"

    # Если файл с таким именем уже существует, добавляем время
    if [ -f "$dump_file" ]; then
        timestamp=$(date +%d.%m.%y_%H-%M-%S)
        dump_file="${backup_dir}/backup_remnawave_${timestamp}.sql.gz"
    fi

    echo -e "${WHITE}Директория бэкапа:${NC} ${DARKGRAY}${backup_dir}${NC}"
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo

    (
        docker exec remnawave-db pg_dump -U postgres -d postgres 2>/dev/null | gzip > "$dump_file"
    ) &
    show_spinner "Создание дампа базы данных"

    if [ -f "$dump_file" ] && [ -s "$dump_file" ]; then
        local dump_name
        dump_name=$(basename "$dump_file")
        echo
        print_success "Бекап успешно создан!"
        echo
        echo -e "📄 ${WHITE}Файл бекапа:${NC} ${DARKGRAY}${dump_name}${NC}"
    else
        print_error "Не удалось создать дамп базы данных"
        rm -f "$dump_file" 2>/dev/null
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

db_restore() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📥 ЗАГРУЗКА БАЗЫ ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
        return 1
    fi

    # Проверяем что контейнер БД запущен
    if ! docker ps --filter "name=remnawave-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnawave-db"; then
        print_error "Контейнер remnawave-db не запущен"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
        return 1
    fi

    local backup_dir="${panel_dir}/backups"

    # Ищем дампы в папке backups
    if [ ! -d "$backup_dir" ] || ! compgen -G "$backup_dir/*.sql.gz" > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Дампы не найдены в ${WHITE}${backup_dir}${NC}"
        echo
        echo -e "${WHITE}Поместите файл дампа (.sql.gz) в эту папку${NC}"
        echo -e "${WHITE}или укажите путь к файлу вручную.${NC}"
        echo

        reading "Путь к файлу бэкапа (или Enter для отмены):" custom_dump_path

        if [ -z "$custom_dump_path" ]; then
            return 0
        fi

        if [ ! -f "$custom_dump_path" ]; then
            print_error "Файл не найден: ${custom_dump_path}"
            echo
            read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
            echo
            return 1
        fi

        # Копируем файл в папку бэкапов
        mkdir -p "$backup_dir"
        cp "$custom_dump_path" "$backup_dir/"
    fi

    # Собираем список бэкапов
    local dump_files=()
    local menu_items=()
    while IFS= read -r file; do
        dump_files+=("$file")
        local fname
        fname=$(basename "$file")
        local fsize
        fsize=$(du -h "$file" | cut -f1)
        menu_items+=("📄  ${fname} (${fsize})")
    done < <(find "$backup_dir" -maxdepth 1 -name "*.sql.gz" | sort -r)

    if [ ${#dump_files[@]} -eq 0 ]; then
        print_error "Файлы бэкапов не найдены"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
        return 1
    fi

    menu_items+=("──────────────────────────────────────")
    menu_items+=("❌  Назад")

    show_arrow_menu "📥  Выберите бэкап для загрузки" "${menu_items[@]}"
    local choice=$?

    # Проверка — выбран ли разделитель или "Назад"
    if [ $choice -ge ${#dump_files[@]} ]; then
        return 0
    fi

    local selected_dump="${dump_files[$choice]}"
    local selected_name
    selected_name=$(basename "$selected_dump")

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📥 ЗАГРУЗКА БАЗЫ ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Файл:${NC} ${DARKGRAY}${selected_name}${NC}"
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${WHITE}Все текущие данные панели будут потеряны.${NC}"
    echo -e "${WHITE}Логин и пароль для входа в панель будут сброшены.${NC}"

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 0
    fi

    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"

    # Останавливаем панель и страницу подписки
    (
        cd "$panel_dir"
        docker compose stop remnawave remnawave-subscription-page >/dev/null 2>&1
    ) &
    show_spinner "Остановка панели"

    # Очищаем базу данных перед восстановлением
    (
        docker exec remnawave-db psql -U postgres -d postgres -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
    ) &
    show_spinner "Подготовка базы данных"

    # Восстанавливаем дамп
    (
        zcat "$selected_dump" | docker exec -i remnawave-db psql -U postgres -d postgres >/dev/null 2>&1
    ) &
    show_spinner "Загрузка данных из бэкапа"

    # Очищаем таблицу admin для перевода панели в режим регистрации
    (
        docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1
    ) &
    show_spinner "Подготовка к регистрации"

    # Запускаем панель (без subscription-page, т.к. токен ещё не обновлён)
    (
        cd "$panel_dir"
        docker compose up -d remnawave >/dev/null 2>&1
    ) &
    show_spinner "Запуск панели"

    # Ожидание готовности API
    show_spinner_timer 10 "Ожидание запуска панели" "Запуск панели"

    local domain_url="127.0.0.1:3000"

    if ! show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности API" 60; then
        print_error "API не отвечает после восстановления"
        echo -e "${YELLOW}Запустите панель вручную и создайте администратора${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
        return
    fi

    # Регистрация нового администратора и создание API токена
    local SUPERADMIN_USERNAME
    local SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    print_action "Регистрация администратора..."
    local token
    token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

    if [ -n "$token" ]; then
        print_success "Регистрация администратора"

        # Создание API токена для страницы подписки
        print_action "Создание API токена для страницы подписки..."
        if create_api_token "$domain_url" "$token" "$panel_dir"; then
            # Извлекаем созданный токен из .env
            local api_token
            api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "$panel_dir/.env" 2>/dev/null | head -1)

            # Сброс администратора (CASCADE удалит и API токены)
            (
                docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1
            ) &
            show_spinner "Сброс данных суперадмина"

            # Восстанавливаем API токен напрямую в базу
            if [ -n "$api_token" ]; then
                local token_uuid
                token_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')")
                (
                    docker exec remnawave-db psql -U postgres -d postgres -c \
                        "INSERT INTO api_tokens (uuid, token, token_name, created_at, updated_at) 
                         VALUES ('$token_uuid', '$api_token', 'subscription-page', NOW(), NOW());" >/dev/null 2>&1
                ) &
                show_spinner "Восстановление API токена"
            fi

            # Перезапуск subscription-page с обновлённым токеном
            (
                cd "$panel_dir"
                docker compose up -d remnawave-subscription-page >/dev/null 2>&1
            ) &
            show_spinner "Перезапуск страницы подписки"
        else
            print_error "Не удалось создать API токен"
        fi
    else
        print_error "Не удалось зарегистрировать администратора"
        echo -e "${YELLOW}Создайте администратора вручную через панель${NC}"
    fi

    echo
    print_success "База данных успешно загружена!"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
    echo
}

manage_database() {
    while true; do
        show_arrow_menu "💾  Работа с базой данных" \
            "💾  Сохранить базу данных" \
            "📥  Загрузить базу данных" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return
        case $choice in
            0) db_backup || break ;;
            1) db_restore || break ;;
            2) : ;;
            3) return ;;
        esac
    done
}

# ═══════════════════════════════════════════════
# АВТОБЕКАП
# ═══════════════════════════════════════════════

AUTOBACKUP_SCRIPT="${DIR_REMNAWAVE}autobackup.sh"
AUTOBACKUP_CONFIG="/opt/remnawave/.autobackup"

# Создание скрипта автобекапа
_rw_create_autobackup_script() {
    sudo mkdir -p "$(dirname "$AUTOBACKUP_SCRIPT")" 2>/dev/null || true
    cat > "$AUTOBACKUP_SCRIPT" << 'BACKUP_SCRIPT'
#!/bin/bash
set -euo pipefail

CONFIG="/opt/remnawave/.autobackup"
[ -f "$CONFIG" ] || exit 0
BOT_TOKEN=$(grep '^bot_token:' "$CONFIG" | cut -d: -f2- | tr -d ' ')
CHAT_ID=$(grep '^chat_id:' "$CONFIG" | cut -d: -f2- | tr -d ' ')
[ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] && exit 1

BACKUP_DIR="/opt/remnawave/backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
DUMP_FILE="${BACKUP_DIR}/dump_${TIMESTAMP}.sql.gz"
DIR_ARCHIVE="${BACKUP_DIR}/dir_${TIMESTAMP}.tar.gz"
FINAL_FILE="${BACKUP_DIR}/Remnawave_${TIMESTAMP}.tar.gz"

# Дамп БД
docker exec remnawave-db pg_dumpall -c -U postgres 2>/dev/null | gzip -9 > "$DUMP_FILE"
if [ ! -s "$DUMP_FILE" ]; then
    rm -f "$DUMP_FILE"
    exit 1
fi

# Архив директории
tar -czf "$DIR_ARCHIVE" --exclude='*.log' --exclude='*.tmp' --exclude='.git' --exclude='backups' -C /opt remnawave 2>/dev/null || true

# Финальный архив
tar -czf "$FINAL_FILE" -C "$BACKUP_DIR" "$(basename "$DUMP_FILE")" "$(basename "$DIR_ARCHIVE")" 2>/dev/null
rm -f "$DUMP_FILE" "$DIR_ARCHIVE"

if [ -s "$FINAL_FILE" ]; then
    SIZE=$(du -h "$FINAL_FILE" | awk '{print $1}')
    DATE=$(date '+%d.%m.%Y %H:%M')
    CAPTION="💾 #remnawave_backup
➖➖➖➖➖➖➖➖➖
✅ Бекап успешно создан
📁 БД + Директория
📏 Размер: ${SIZE}
📅 ${DATE} MSK"
    curl -s -F "chat_id=$CHAT_ID" \
         -F "document=@$FINAL_FILE" \
         -F "caption=$CAPTION" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" >/dev/null 2>&1
    find "$BACKUP_DIR" -name "Remnawave_*.tar.gz" -mtime +7 -delete 2>/dev/null || true
fi
BACKUP_SCRIPT
    chmod +x "$AUTOBACKUP_SCRIPT"
}

# Получение cron-выражения по частоте
_rw_get_cron_schedule() {
    local freq="$1"
    case "$freq" in
        hourly)  echo "0 * * * *" ;;
        daily)   echo "0 21 * * *" ;;
        weekly)  echo "0 21 * * 0" ;;
        monthly) echo "0 21 1 * *" ;;
    esac
}

# Проверка активности автобекапа
_rw_autobackup_is_active() {
    crontab -l 2>/dev/null | grep -q "$AUTOBACKUP_SCRIPT"
}

# Получение текущей частоты
_rw_autobackup_get_frequency() {
    if ! _rw_autobackup_is_active; then
        echo ""
        return
    fi
    local cron_line
    cron_line=$(crontab -l 2>/dev/null | grep "$AUTOBACKUP_SCRIPT")
    case "$cron_line" in
        "0 * * * *"*)    echo "Каждый час" ;;
        "0 21 * * *"*)   echo "Каждый день (00:00 МСК)" ;;
        "0 21 * * 0"*)   echo "Каждую неделю (Вс 00:00 МСК)" ;;
        "0 21 1 * *"*)   echo "Каждый месяц (1-е число, 00:00 МСК)" ;;
        *)               echo "Пользовательское расписание" ;;
    esac
}

manage_autobackup() {
    while true; do
        local status_label
        if _rw_autobackup_is_active; then
            local freq
            freq=$(_rw_autobackup_get_frequency)
            status_label="📊 Статус: ${GREEN}Активен${NC} (${freq})"
        else
            status_label="📊 Статус: ${RED}Не настроен${NC}"
        fi

        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}       💾 АВТОБЕКАП REMNAWAVE${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "  $status_label"
        echo

        local menu_items=()
        local -a _ab_actions=()

        if _rw_autobackup_is_active; then
            menu_items+=("⚙️   Изменить настройки");    _ab_actions+=("configure")
            menu_items+=("📤  Создать бекап сейчас");   _ab_actions+=("backup_now")
            menu_items+=("⛔  Остановить автобекап");   _ab_actions+=("stop")
        else
            menu_items+=("⚙️   Настройка автобекапа");  _ab_actions+=("configure")
        fi
        menu_items+=("──────────────────────────────────────"); _ab_actions+=("sep")
        menu_items+=("❌  Назад");                             _ab_actions+=("back")

        show_arrow_menu "💾 АВТОБЕКАП" "${menu_items[@]}"
        local choice=$?
        [[ $choice -eq 255 ]] && return
        local _ab_action="${_ab_actions[$choice]:-back}"

        case "$_ab_action" in
            configure)
                # Настройка / Изменение
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}   ⚙️  НАСТРОЙКА АВТОБЕКАПА${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo

                # Токен бота
                local backup_bot_token=""
                if [ -f "$AUTOBACKUP_CONFIG" ]; then
                    backup_bot_token=$(grep '^bot_token:' "$AUTOBACKUP_CONFIG" 2>/dev/null | cut -d: -f2- | tr -d ' ')
                fi
                local current_hint=""
                [ -n "$backup_bot_token" ] && current_hint=" (Enter = оставить текущий)"
                tput cnorm 2>/dev/null || true
                reading "Токен бота для бекапов${current_hint}:" new_backup_token
                if [ -z "$new_backup_token" ] && [ -n "$backup_bot_token" ]; then
                    new_backup_token="$backup_bot_token"
                fi
                if [ -z "$new_backup_token" ]; then
                    print_error "Токен не может быть пустым"
                    show_continue_prompt || continue
                    continue
                fi

                # Chat ID
                local backup_chat_id=""
                if [ -f "$AUTOBACKUP_CONFIG" ]; then
                    backup_chat_id=$(grep '^chat_id:' "$AUTOBACKUP_CONFIG" 2>/dev/null | cut -d: -f2- | tr -d ' ')
                fi
                current_hint=""
                [ -n "$backup_chat_id" ] && current_hint=" (Enter = оставить текущий)"
                reading "Telegram ID для получения бекапов${current_hint}:" new_chat_id
                if [ -z "$new_chat_id" ] && [ -n "$backup_chat_id" ]; then
                    new_chat_id="$backup_chat_id"
                fi
                if [ -z "$new_chat_id" ]; then
                    print_error "ID не может быть пустым"
                    show_continue_prompt || continue
                    continue
                fi

                # Частота
                echo
                show_arrow_menu "Частота бекапа" \
                    "⏱️   Каждый час" \
                    "📅  Каждый день (00:00 МСК)" \
                    "📆  Каждую неделю (Вс 00:00 МСК)" \
                    "🗓️   Каждый месяц (1-е число, 00:00 МСК)"
                local freq_choice=$?

                local frequency=""
                case $freq_choice in
                    0) frequency="hourly" ;;
                    1) frequency="daily" ;;
                    2) frequency="weekly" ;;
                    3) frequency="monthly" ;;
                    255) continue ;;
                esac

                # Сохраняем конфиг
                mkdir -p "$(dirname "$AUTOBACKUP_CONFIG")" 2>/dev/null || true
                cat > "$AUTOBACKUP_CONFIG" << EOF
bot_token: $new_backup_token
chat_id: $new_chat_id
frequency: $frequency
EOF

                # Создаём скрипт бекапа
                _rw_create_autobackup_script

                # Устанавливаем cron
                local cron_schedule
                cron_schedule=$(_rw_get_cron_schedule "$frequency")
                (crontab -l 2>/dev/null | grep -v "$AUTOBACKUP_SCRIPT"; echo "$cron_schedule $AUTOBACKUP_SCRIPT") | crontab -

                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}       💾 АВТОБЕКАП НАСТРОЕН${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                echo -e "${GREEN}✅ Автобекап успешно настроен${NC}"
                echo
                local freq_label
                case $frequency in
                    hourly)  freq_label="Каждый час" ;;
                    daily)   freq_label="Каждый день (00:00 МСК)" ;;
                    weekly)  freq_label="Каждую неделю (Вс 00:00 МСК)" ;;
                    monthly) freq_label="Каждый месяц (1-е число, 00:00 МСК)" ;;
                esac
                echo -e "  Частота: ${YELLOW}${freq_label}${NC}"
                echo -e "  Получатель: ${YELLOW}${new_chat_id}${NC}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || continue
                ;;
            backup_now)
                # Ручной бекап с отправкой в Telegram
                local mn_token mn_chat
                mn_token=$(grep '^bot_token:' "$AUTOBACKUP_CONFIG" 2>/dev/null | cut -d: -f2- | tr -d ' ')
                mn_chat=$(grep '^chat_id:' "$AUTOBACKUP_CONFIG" 2>/dev/null | cut -d: -f2- | tr -d ' ')

                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}       📤 СОЗДАНИЕ БЕКАПА${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo

                local mn_ts mn_dump mn_dir mn_final mn_tmp
                mn_ts=$(date +%Y-%m-%d_%H-%M)
                mn_tmp="/tmp/_rw_backup_$$"
                mkdir -p "$mn_tmp"
                mn_dump="${mn_tmp}/dump_${mn_ts}.sql.gz"
                mn_dir="${mn_tmp}/dir_${mn_ts}.tar.gz"
                mn_final="${mn_tmp}/Remnawave_${mn_ts}.tar.gz"

                (
                    docker exec remnawave-db pg_dumpall -c -U postgres 2>/dev/null | gzip -9 > "$mn_dump"
                ) &
                show_spinner "Создание дампа базы данных"

                if [ ! -s "$mn_dump" ]; then
                    print_error "Не удалось создать дамп"
                    rm -rf "$mn_tmp"
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || continue
                    continue
                fi

                (
                    tar -czf "$mn_dir" --exclude='*.log' --exclude='*.tmp' --exclude='.git' --exclude='backups' -C /opt remnawave 2>/dev/null || true
                ) &
                show_spinner "Архивирование директории"

                (
                    tar -czf "$mn_final" -C "$mn_tmp" "$(basename "$mn_dump")" "$(basename "$mn_dir")" 2>/dev/null
                ) &
                show_spinner "Создание финального архива"
                rm -f "$mn_dump" "$mn_dir" 2>/dev/null

                if [ ! -s "$mn_final" ]; then
                    print_error "Не удалось создать архив"
                    rm -rf "$mn_tmp"
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || continue
                    continue
                fi

                local mn_size
                mn_size=$(du -h "$mn_final" | awk '{print $1}')
                local mn_date
                mn_date=$(date '+%d.%m.%Y %H:%M')
                local mn_caption
                mn_caption="💾 #remnawave_backup
➖➖➖➖➖➖➖➖➖
✅ Бекап создан вручную
📁 БД + Директория
📏 Размер: ${mn_size}
📅 ${mn_date} MSK"

                (
                    curl -s \
                        -F "chat_id=$mn_chat" \
                        -F "document=@$mn_final" \
                        -F "caption=$mn_caption" \
                        "https://api.telegram.org/bot${mn_token}/sendDocument" > /tmp/_rw_ab_result 2>&1
                ) &
                show_spinner "Отправка в Telegram"

                local send_ok=false
                grep -q '"ok":true' /tmp/_rw_ab_result 2>/dev/null && send_ok=true
                rm -f /tmp/_rw_ab_result 2>/dev/null || true
                rm -rf "$mn_tmp" 2>/dev/null || true

                if $send_ok; then
                    print_success "Бекап успешно отправлен в Telegram"
                    echo -e "  📏 Размер: ${YELLOW}${mn_size}${NC}"
                else
                    print_error "Не удалось отправить бекап (проверьте токен/chat_id)"
                fi
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || continue
                ;;
            stop)
                (crontab -l 2>/dev/null | grep -v "$AUTOBACKUP_SCRIPT") | crontab -
                rm -f "$AUTOBACKUP_CONFIG" 2>/dev/null || true
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}       💾 АВТОБЕКАП${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                echo -e "${GREEN}✅ Автобекап остановлен${NC}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || continue
                ;;
            *) return ;;
        esac
    done
}
