# ═══════════════════════════════════════════════
# БАЗА ДАННЫХ: СОХРАНЕНИЕ/ЗАГРУЗКА/АВТОБЕКАП
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

    local mn_ts mn_dump mn_dir mn_final mn_tmp mn_bot_dump
    mn_ts=$(date +%Y-%m-%d_%H-%M)
    mn_tmp="/tmp/_rw_backup_$$"
    mkdir -p "$mn_tmp"
    mn_dump="${mn_tmp}/dump_${mn_ts}.sql.gz"
    mn_bot_dump="${mn_tmp}/bot_dump_${mn_ts}.sql.gz"
    mn_dir="${mn_tmp}/dir_${mn_ts}.tar.gz"
    mn_final="${backup_dir}/Remnawave_${mn_ts}.tar.gz"

    (
        docker exec remnawave-db pg_dumpall -c -U postgres 2>/dev/null | gzip -9 > "$mn_dump"
    ) &
    show_spinner "Создание дампа базы данных"

    if [ ! -s "$mn_dump" ]; then
        print_error "Не удалось создать дамп"
        rm -rf "$mn_tmp"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    # Бекап базы бота (remnasale-db), если контейнер запущен
    if docker ps --filter "name=remnasale-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnasale-db"; then
        (
            docker exec remnasale-db pg_dump -U remnasale -d remnasale 2>/dev/null | gzip -9 > "$mn_bot_dump"
        ) &
        show_spinner "Создание дампа базы бота"

        if [ ! -s "$mn_bot_dump" ]; then
            rm -f "$mn_bot_dump" 2>/dev/null
        fi
    fi

    (
        tar -czf "$mn_dir" --exclude='*.log' --exclude='*.tmp' --exclude='.git' --exclude='backups' -C /opt remnawave 2>/dev/null || true
    ) &
    show_spinner "Архивирование директории"

    local mn_size
    (
        tar -czf "$mn_final" -C "$mn_tmp" "$(basename "$mn_dump")" "$(basename "$mn_dir")" 2>/dev/null
        rm -rf "$mn_tmp" 2>/dev/null || true
    ) &
    show_spinner "Сохранение бекапа"

    if [ ! -s "$mn_final" ]; then
        rm -rf "$mn_tmp" 2>/dev/null || true
        print_error "Не удалось создать архив"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    mn_size=$(du -h "$mn_final" | awk '{print $1}')
    local mn_date
    mn_date=$(date '+%d.%m.%Y %H:%M')

    # Отправка в Telegram (если настроен автобекап)
    if [ -f "$AUTOBACKUP_CONFIG" ]; then
        local mn_token mn_chat
        mn_token=$(grep '^BACKUP_BOT_TOKEN=' "$AUTOBACKUP_CONFIG" 2>/dev/null | cut -d= -f2-)
        mn_chat=$(grep '^BACKUP_CHAT_ID=' "$AUTOBACKUP_CONFIG" 2>/dev/null | cut -d= -f2-)

        if [ -n "$mn_token" ] && [ -n "$mn_chat" ]; then
            local mn_caption
            mn_caption="📦 Приложение: Remnawave
📁 БД + Директория
📏 Размер: ${mn_size}
📅 ${mn_date} МСК

✅ Бекап создан вручную"
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

            if ! $send_ok; then
                print_error "Не удалось отправить в Telegram"
            fi
        fi
    fi

    echo
    print_success "Бекап успешно создан!"
    echo
    echo -e "  📄 $(basename "$mn_final")"
    echo -e "  📏 Размер: ${YELLOW}${mn_size}${NC}"
    echo

    # Удаляем бекапы старше 7 дней
    find "$backup_dir" -maxdepth 1 -name "Remnawave_*.tar.gz" -mtime +7 -delete 2>/dev/null || true

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
    local has_files=false

    # Проверяем наличие бекапов (.tar.gz и .sql.gz)
    if [ -d "$backup_dir" ]; then
        compgen -G "$backup_dir/*.tar.gz" > /dev/null 2>&1 && has_files=true
        compgen -G "$backup_dir/*.sql.gz" > /dev/null 2>&1 && has_files=true
        compgen -G "$backup_dir/*.sql" > /dev/null 2>&1 && has_files=true
    fi

    if [ "$has_files" = false ]; then
        echo -e "${YELLOW}⚠️  Бекапы не найдены в ${WHITE}${backup_dir}${NC}"
        echo
        echo -e "${WHITE}Поместите файл бекапа (.tar.gz, .sql.gz или .sql) в эту папку${NC}"
        echo -e "${WHITE}или укажите путь к файлу вручную.${NC}"
        echo

        tput cnorm 2>/dev/null || true
        reading "Путь к файлу бэкапа (или Enter для отмены):" custom_dump_path

        if [ -z "$custom_dump_path" ]; then
            return 0
        fi

        if [ ! -f "$custom_dump_path" ]; then
            print_error "Файл не найден: ${custom_dump_path}"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || return 1
            return 1
        fi

        # Копируем файл в папку бэкапов
        mkdir -p "$backup_dir"
        cp "$custom_dump_path" "$backup_dir/"
    fi

    # Собираем список бэкапов (.tar.gz и .sql.gz)
    local backup_files=()
    local menu_items=()
    while IFS= read -r file; do
        backup_files+=("$file")
        local fname fsize display_label
        fname=$(basename "$file")
        fsize=$(du -h "$file" | cut -f1)
        if [[ "$fname" =~ ^([A-Za-z]+)_([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})\.(tar\.gz|sql\.gz|sql)$ ]]; then
            local pname pyear pmon pday phour pmin
            pname="${BASH_REMATCH[1]}"
            pyear="${BASH_REMATCH[2]}"
            pmon="${BASH_REMATCH[3]}"
            pday="${BASH_REMATCH[4]}"
            phour="${BASH_REMATCH[5]}"
            pmin="${BASH_REMATCH[6]}"
            display_label="${pname} | ${pday}.${pmon}.${pyear} | ${phour}:${pmin} | ${fsize}"
        else
            display_label="${fname} (${fsize})"
        fi
        menu_items+=("📄  ${display_label}")
    done < <(find "$backup_dir" -maxdepth 1 \( -name "*.tar.gz" -o -name "*.sql.gz" -o -name "*.sql" \) | sort -r)

    if [ ${#backup_files[@]} -eq 0 ]; then
        print_error "Файлы бэкапов не найдены"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    menu_items+=("──────────────────────────────────────")
    menu_items+=("⬅️   Назад")

    show_arrow_menu "📥  Выберите бэкап для загрузки" "${menu_items[@]}"
    local choice=$?

    # Проверка — выбран ли разделитель или "Назад"
    if [ $choice -ge ${#backup_files[@]} ] || [ $choice -eq 255 ]; then
        return 0
    fi

    local selected_file="${backup_files[$choice]}"
    local selected_name
    selected_name=$(basename "$selected_file")

    # Определяем формат и извлекаем дамп
    local dump_to_restore=""
    local bot_dump_to_restore=""
    local tmp_extract=""
    local is_archive=false

    if [[ "$selected_name" == *.tar.gz ]] && [[ "$selected_name" != dump_* ]]; then
        # Архив Remnawave_*.tar.gz — извлекаем дамп
        is_archive=true
        tmp_extract="/tmp/_rw_restore_$$"
        mkdir -p "$tmp_extract"

        (
            tar -xzf "$selected_file" -C "$tmp_extract" 2>/dev/null
        ) &
        show_spinner "Распаковка архива"

        # Ищем дамп внутри
        dump_to_restore=$(find "$tmp_extract" -maxdepth 1 -name "dump_*.sql.gz" | head -1)
        bot_dump_to_restore=$(find "$tmp_extract" -maxdepth 1 -name "bot_dump_*.sql.gz" | head -1)

        if [ -z "$dump_to_restore" ] || [ ! -s "$dump_to_restore" ]; then
            print_error "Дамп БД не найден в архиве"
            rm -rf "$tmp_extract" 2>/dev/null
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || return 1
            return 1
        fi
    else
        # Обычный .sql.gz или .sql файл
        dump_to_restore="$selected_file"
    fi

    # Выбор типа восстановления
    echo
    show_arrow_menu "📥  Тип восстановления" \
        "📦  Полное восстановление — заменить все данные" \
        "👤  Только пользователи — сохранить настройки панели" \
        "──────────────────────────────────────" \
        "❌  Отмена"
    local restore_choice=$?

    if [ $restore_choice -ge 2 ] || [ $restore_choice -eq 255 ]; then
        rm -rf "$tmp_extract" 2>/dev/null
        return 0
    fi

    local restore_type="full"
    [ $restore_choice -eq 1 ] && restore_type="users_only"

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📥 ЗАГРУЗКА БАЗЫ ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Файл:${NC} ${DARKGRAY}${selected_name}${NC}"
    if [ "$restore_type" = "users_only" ]; then
        echo -e "${WHITE}Режим:${NC} ${YELLOW}Только пользователи${NC}"
    else
        echo -e "${WHITE}Режим:${NC} ${YELLOW}Полное восстановление${NC}"
    fi
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ!${NC}"
    if [ "$restore_type" = "users_only" ]; then
        echo -e "${WHITE}Пользователи будут заменены из бекапа.${NC}"
        echo -e "${WHITE}Настройки панели и администратор сохранятся.${NC}"
    else
        echo -e "${WHITE}Все текущие данные панели будут потеряны.${NC}"
        echo -e "${WHITE}Логин и пароль для входа в панель будут сброшены.${NC}"
    fi
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    if ! confirm_action; then
        print_error "Операция отменена"
        rm -rf "$tmp_extract" 2>/dev/null
        sleep 2
        return 0
    fi

    echo

    # Для "только пользователи" — сохраняем данные администратора и API токенов
    local admin_backup_file=""
    local referral_backup_file=""
    if [ "$restore_type" = "users_only" ]; then
        admin_backup_file="/tmp/_rw_admin_save_$$.sql"
        (
            docker exec remnawave-db pg_dump -U postgres -d postgres \
                --data-only --table=admin --table=api_tokens 2>/dev/null > "$admin_backup_file"
        ) &
        show_spinner "Сохранение данных администратора"

        # Сохраняем реферальные данные из базы бота
        if docker ps --filter "name=remnasale-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnasale-db"; then
            referral_backup_file="/tmp/_rw_referral_save_$$.sql"
            (
                docker exec remnasale-db pg_dump -U remnasale -d remnasale \
                    --data-only --table=referrals --table=referral_rewards 2>/dev/null > "$referral_backup_file"
            ) &
            show_spinner "Сохранение реферальных данных"
        fi
    fi

    # Останавливаем панель (и страницу подписки, если она в compose)
    (
        cd "$panel_dir"
        if grep -q 'remnawave-subscription-page' docker-compose.yml 2>/dev/null; then
            docker compose stop remnawave remnawave-subscription-page >/dev/null 2>&1
        else
            docker compose stop remnawave >/dev/null 2>&1
        fi
    ) &
    show_spinner "Остановка панели"

    # Делаем страховочный бэкап текущей БД перед восстановлением (тихо)
    local safety_backup="${panel_dir}/backups/pre_restore_$(date +%Y-%m-%d_%H-%M).sql.gz"
    mkdir -p "${panel_dir}/backups"
    docker exec remnawave-db pg_dumpall -c -U postgres 2>/dev/null | gzip -9 > "$safety_backup"
    [ ! -s "$safety_backup" ] && rm -f "$safety_backup" 2>/dev/null
    echo

    # Очищаем базу данных перед восстановлением
    (
        docker exec remnawave-db psql -U postgres -d postgres -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
    ) &
    show_spinner "Подготовка базы данных"

    # Восстанавливаем дамп
    (
        if [[ "$dump_to_restore" == *.gz ]]; then
            zcat "$dump_to_restore" | grep -v -E "^ALTER ROLE .* PASSWORD " | docker exec -i remnawave-db psql -U postgres -d postgres >/dev/null 2>&1
        else
            grep -v -E "^ALTER ROLE .* PASSWORD " "$dump_to_restore" | docker exec -i remnawave-db psql -U postgres -d postgres >/dev/null 2>&1
        fi
    ) &
    show_spinner "Загрузка данных из бэкапа"

    # Восстановление базы бота (remnasale-db), если дамп найден в архиве
    if [ -n "$bot_dump_to_restore" ] && [ -s "$bot_dump_to_restore" ]; then
        if docker ps --filter "name=remnasale-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnasale-db"; then
            (
                docker exec remnasale-db psql -U remnasale -d remnasale -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
                zcat "$bot_dump_to_restore" | docker exec -i remnasale-db psql -U remnasale -d remnasale >/dev/null 2>&1
            ) &
            show_spinner "Загрузка базы бота из бэкапа"
        fi
    fi

    # Очистка временных файлов извлечения
    rm -rf "$tmp_extract" 2>/dev/null

    # Очистка кеша Redis бота
    if docker ps --filter "name=remnasale-redis" --format "{{.Names}}" 2>/dev/null | grep -q "remnasale-redis"; then
        local redis_pass
        redis_pass=$(grep '^REDIS_PASSWORD=' /opt/remnasale/.env 2>/dev/null | cut -d= -f2-)
        if [ -n "$redis_pass" ]; then
            docker exec remnasale-redis valkey-cli -a "$redis_pass" FLUSHALL >/dev/null 2>&1 || \
            docker exec remnasale-redis redis-cli -a "$redis_pass" FLUSHALL >/dev/null 2>&1 || true
        fi
    fi

    if [ "$restore_type" = "users_only" ]; then
        # Восстанавливаем сохранённого администратора и API токены
        (
            docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE; TRUNCATE TABLE api_tokens CASCADE;" >/dev/null 2>&1
            if [ -s "$admin_backup_file" ]; then
                cat "$admin_backup_file" | docker exec -i remnawave-db psql -U postgres -d postgres >/dev/null 2>&1
            fi
        ) &
        show_spinner "Восстановление администратора"
        rm -f "$admin_backup_file" 2>/dev/null

        # Восстанавливаем реферальные данные в базу бота
        if [ -n "$referral_backup_file" ] && [ -s "$referral_backup_file" ]; then
            if docker ps --filter "name=remnasale-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnasale-db"; then
                (
                    docker exec remnasale-db psql -U remnasale -d remnasale -c "TRUNCATE TABLE referral_rewards CASCADE; TRUNCATE TABLE referrals CASCADE;" >/dev/null 2>&1
                    cat "$referral_backup_file" | docker exec -i remnasale-db psql -U remnasale -d remnasale >/dev/null 2>&1
                ) &
                show_spinner "Восстановление реферальных данных"
            fi
            rm -f "$referral_backup_file" 2>/dev/null
        fi

        # Запускаем панель
        (
            cd "$panel_dir"
            docker compose up -d remnawave >/dev/null 2>&1
            if grep -q 'remnawave-subscription-page' docker-compose.yml 2>/dev/null; then
                docker compose up -d remnawave-subscription-page >/dev/null 2>&1
            fi
        ) &
        show_spinner "Запуск панели"

        echo
        print_success "Пользователи успешно загружены!"
    else
        # Полное восстановление — стандартный процесс

        # Очищаем таблицу admin для перевода панели в режим регистрации
        (
            docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1
        ) &
        show_spinner "Подготовка к регистрации"
        echo

        # Запускаем панель (без subscription-page, т.к. токен ещё не обновлён)
        (
            cd "$panel_dir"
            docker compose up -d remnawave >/dev/null 2>&1
        ) &
        show_spinner "Запуск панели"

        # Ожидание готовности API (тихо)
        local domain_url="127.0.0.1:3000"
        local _api_wait=0
        while [ $_api_wait -lt 60 ]; do
            if curl -s -f --max-time 5 "http://$domain_url/api/auth/status" \
                --header 'X-Forwarded-For: 127.0.0.1' \
                --header 'X-Forwarded-Proto: https' > /dev/null 2>&1; then
                break
            fi
            sleep 2
            _api_wait=$((_api_wait + 2))
        done

        if [ $_api_wait -ge 60 ]; then
            print_error "API не отвечает после восстановления"
            echo -e "${YELLOW}Запустите панель вручную и создайте администратора${NC}"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || return 1
            return
        fi

        # Регистрация нового администратора и создание API токена (тихо)
        local SUPERADMIN_USERNAME SUPERADMIN_PASSWORD
        SUPERADMIN_USERNAME=$(generate_admin_username)
        SUPERADMIN_PASSWORD=$(generate_admin_password)

        local token
        token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

        if [ -n "$token" ]; then
            # Создание API токена для страницы подписки
            # Если токен с таким именем уже есть — переименовываем старый
            docker exec remnawave-db psql -U postgres -d postgres -c \
                "UPDATE api_tokens SET token_name = token_name || '_old' WHERE token_name = 'subscription-page';" >/dev/null 2>&1 || true

            if create_api_token "$domain_url" "$token" "$panel_dir" 2>/dev/null; then
                local api_token
                api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "$panel_dir/.env" 2>/dev/null | head -1)

                # Сброс администратора (CASCADE удалит и API токены)
                docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1

                # Восстанавливаем API токен напрямую в базу
                if [ -n "$api_token" ]; then
                    local token_uuid
                    token_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')")
                    docker exec remnawave-db psql -U postgres -d postgres -c \
                        "INSERT INTO api_tokens (uuid, token, token_name, created_at, updated_at) 
                         VALUES ('$token_uuid', '$api_token', 'subscription-page', NOW(), NOW());" >/dev/null 2>&1
                fi

                # Перезапуск subscription-page (если на этом сервере)
                if grep -q 'remnawave-subscription-page' "$panel_dir/docker-compose.yml" 2>/dev/null; then
                    (
                        cd "$panel_dir"
                        docker compose up -d remnawave-subscription-page >/dev/null 2>&1
                    ) &
                    show_spinner "Перезапуск страницы подписки"
                fi
            fi
        else
            print_error "Не удалось зарегистрировать администратора"
            echo -e "${YELLOW}Создайте администратора вручную через панель${NC}"
        fi

        echo
        print_success "База данных успешно загружена!"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ═══════════════════════════════════════════════
# АВТОБЕКАП
# ═══════════════════════════════════════════════

AUTOBACKUP_SCRIPT="${DIR_SCRIPT}autobackup.sh"
AUTOBACKUP_CONFIG="/opt/remnawave/.env"

# Создание скрипта автобекапа (только отправка в Telegram)
_rw_create_autobackup_script() {
    sudo mkdir -p "$(dirname "$AUTOBACKUP_SCRIPT")" 2>/dev/null || true
    cat > "$AUTOBACKUP_SCRIPT" << 'BACKUP_SCRIPT'
#!/bin/bash
set -euo pipefail

CONFIG="/opt/remnawave/.env"
[ -f "$CONFIG" ] || exit 0
BOT_TOKEN=$(grep '^BACKUP_BOT_TOKEN=' "$CONFIG" | cut -d= -f2-)
CHAT_ID=$(grep '^BACKUP_CHAT_ID=' "$CONFIG" | cut -d= -f2-)
[ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] && exit 1

TMPDIR="/tmp/_rw_autobackup_$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
DUMP_FILE="${TMPDIR}/dump_${TIMESTAMP}.sql.gz"
DIR_ARCHIVE="${TMPDIR}/dir_${TIMESTAMP}.tar.gz"
FINAL_FILE="${TMPDIR}/Remnawave_${TIMESTAMP}.tar.gz"

# Дамп БД
docker exec remnawave-db pg_dumpall -c -U postgres 2>/dev/null | gzip -9 > "$DUMP_FILE"
if [ ! -s "$DUMP_FILE" ]; then
    exit 1
fi

# Архив директории
tar -czf "$DIR_ARCHIVE" --exclude='*.log' --exclude='*.tmp' --exclude='.git' --exclude='backups' -C /opt remnawave 2>/dev/null || true

# Финальный архив
tar -czf "$FINAL_FILE" -C "$TMPDIR" "$(basename "$DUMP_FILE")" "$(basename "$DIR_ARCHIVE")" 2>/dev/null
rm -f "$DUMP_FILE" "$DIR_ARCHIVE"

if [ -s "$FINAL_FILE" ]; then
    SIZE=$(du -h "$FINAL_FILE" | awk '{print $1}')
    DATE=$(date '+%d.%m.%Y %H:%M')
    CAPTION="📦 Приложение: Remnawave
📁 БД + Директория
📏 Размер: ${SIZE}
📅 ${DATE} МСК

✅ Бекап создан автоматически"
    curl -s -F "chat_id=$CHAT_ID" \
         -F "document=@$FINAL_FILE" \
         -F "caption=$CAPTION" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" >/dev/null 2>&1
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

# Настройка автобекапа
_rw_configure_autobackup() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ⚙️  НАСТРОЙКА АВТОБЕКАПА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Токен бота
    local backup_bot_token=""
    if [ -f "$AUTOBACKUP_CONFIG" ]; then
        backup_bot_token=$(grep '^BACKUP_BOT_TOKEN=' "$AUTOBACKUP_CONFIG" 2>/dev/null | cut -d= -f2-)
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
        show_continue_prompt || return
        return
    fi

    # Chat ID
    local backup_chat_id=""
    if [ -f "$AUTOBACKUP_CONFIG" ]; then
        backup_chat_id=$(grep '^BACKUP_CHAT_ID=' "$AUTOBACKUP_CONFIG" 2>/dev/null | cut -d= -f2-)
    fi
    current_hint=""
    [ -n "$backup_chat_id" ] && current_hint=" (Enter = оставить текущий)"
    reading "Telegram ID для получения бекапов${current_hint}:" new_chat_id
    if [ -z "$new_chat_id" ] && [ -n "$backup_chat_id" ]; then
        new_chat_id="$backup_chat_id"
    fi
    if [ -z "$new_chat_id" ]; then
        print_error "ID не может быть пустым"
        show_continue_prompt || return
        return
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
        255) return ;;
    esac

    # Сохраняем настройки в .env
    mkdir -p "$(dirname "$AUTOBACKUP_CONFIG")" 2>/dev/null || true
    local _rw_envfile="$AUTOBACKUP_CONFIG"
    for _rw_pair in "BACKUP_BOT_TOKEN=$new_backup_token" "BACKUP_CHAT_ID=$new_chat_id" "BACKUP_FREQUENCY=$frequency"; do
        local _rw_key="${_rw_pair%%=*}" _rw_val="${_rw_pair#*=}"
        if grep -q "^${_rw_key}=" "$_rw_envfile" 2>/dev/null; then
            sed -i "s|^${_rw_key}=.*|${_rw_key}=${_rw_val}|" "$_rw_envfile"
        else
            echo "${_rw_key}=${_rw_val}" >> "$_rw_envfile"
        fi
    done

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
    show_continue_prompt || return
}

# Остановка автобекапа
_rw_stop_autobackup() {
    (crontab -l 2>/dev/null | grep -v "$AUTOBACKUP_SCRIPT") | crontab -
    sed -i '/^BACKUP_BOT_TOKEN=\|^BACKUP_CHAT_ID=\|^BACKUP_FREQUENCY=/d' "$AUTOBACKUP_CONFIG" 2>/dev/null || true
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       💾 АВТОБЕКАП${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}✅ Автобекап остановлен${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return
}

# ═══════════════════════════════════════════════
# МЕНЮ БАЗЫ ДАННЫХ
# ═══════════════════════════════════════════════

manage_database() {
    while true; do
        local menu_items=()
        local db_actions=()

        menu_items+=("💾  Сохранить базу данных");     db_actions+=("backup")
        menu_items+=("📥  Загрузить базу данных");     db_actions+=("restore")
        menu_items+=("──────────────────────────────────────"); db_actions+=("sep")

        if _rw_autobackup_is_active; then
            menu_items+=("⚙️   Изменить настройки автобекапа"); db_actions+=("ab_configure")
            menu_items+=("⛔  Остановить автобекап");           db_actions+=("ab_stop")
        else
            menu_items+=("⚙️   Включить автобекап");            db_actions+=("ab_configure")
        fi
        menu_items+=("──────────────────────────────────────"); db_actions+=("sep")
        menu_items+=("⬅️   Назад");                              db_actions+=("back")

        local menu_title="💾  Работа с базой данных"
        if _rw_autobackup_is_active; then
            local freq
            freq=$(_rw_autobackup_get_frequency)
            menu_title="   💾  Работа с базой данных\n   📊  Автобекап: ${GREEN}${freq}${NC}"
        fi

        show_arrow_menu "$menu_title" "${menu_items[@]}"
        local choice=$?
        [[ $choice -eq 255 ]] && return
        local db_action="${db_actions[$choice]:-back}"

        case "$db_action" in
            backup)       db_backup ;;
            restore)      db_restore ;;
            ab_configure) _rw_configure_autobackup ;;
            ab_stop)      _rw_stop_autobackup ;;
            back)         return ;;
            *)            continue ;;
        esac
    done
}
