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
    local _db_user _db_name
    _db_user=$(grep '^POSTGRES_USER=' /opt/remnawave/.env 2>/dev/null | cut -d= -f2); _db_user="${_db_user:-postgres}"
    _db_name=$(grep '^POSTGRES_DB='   /opt/remnawave/.env 2>/dev/null | cut -d= -f2); _db_name="${_db_name:-postgres}"
    (
        docker exec remnawave-db psql -U "$_db_user" -d "$_db_name" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
    ) &
    show_spinner "Подготовка базы данных"

    # Восстанавливаем дамп
    (
        zcat "$selected_dump" | docker exec -i remnawave-db psql -U "$_db_user" -d "$_db_name" >/dev/null 2>&1
    ) &
    show_spinner "Загрузка данных из бэкапа"

    # Очищаем таблицу admin для перевода панели в режим регистрации
    (
        docker exec remnawave-db psql -U "$_db_user" -d "$_db_name" -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1
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
                docker exec remnawave-db psql -U "$_db_user" -d "$_db_name" -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1
            ) &
            show_spinner "Сброс данных суперадмина"

            # Восстанавливаем API токен напрямую в базу
            if [ -n "$api_token" ]; then
                local token_uuid
                token_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')")
                (
                    docker exec remnawave-db psql -U "$_db_user" -d "$_db_name" -c \
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
