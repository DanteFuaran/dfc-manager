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
     ) </dev/null &    show_spinner "Создание дампа базы данных"

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
         ) </dev/null &        show_spinner "Создание дампа базы бота"

        if [ ! -s "$mn_bot_dump" ]; then
            rm -f "$mn_bot_dump" 2>/dev/null
        fi
    fi

    (
        tar -czf "$mn_dir" --exclude='*.log' --exclude='*.tmp' --exclude='.git' --exclude='backups' -C /opt remnawave 2>/dev/null || true
     ) </dev/null &    show_spinner "Архивирование директории"

    local mn_size
    (
        tar -czf "$mn_final" -C "$mn_tmp" "$(basename "$mn_dump")" "$(basename "$mn_dir")" 2>/dev/null
        rm -rf "$mn_tmp" 2>/dev/null || true
     ) </dev/null &    show_spinner "Сохранение бекапа"

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
             ) </dev/null &            show_spinner "Отправка в Telegram"

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

# ═══════════════════════════════════════════════
# ЧАСТИЧНОЕ ВОССТАНОВЛЕНИЕ ИЗ БЭКАПА
# ═══════════════════════════════════════════════

_get_restore_tables() {
    case "$1" in
        users)           echo "users user_traffic user_subscription_request_history hwid_user_devices" ;;
        profiles)        echo "config_profiles config_profile_inbounds config_profile_inbounds_to_nodes config_profile_snippets" ;;
        templates)       echo "subscription_templates" ;;
        nodes)           echo "nodes hosts hosts_to_nodes nodes_traffic_usage_history nodes_usage_history nodes_user_usage_history" ;;
        billing)         echo "infra_providers infra_billing_nodes infra_billing_history" ;;
        internal_squads) echo "internal_squads internal_squad_members internal_squad_inbounds internal_squad_host_exclusions" ;;
        external_squads) echo "external_squads external_squads_templates" ;;
        settings)        echo "remnawave_settings subscription_settings subscription_page_config keygen" ;;
    esac
}

_db_partial_restore() {
    local dump_file="$1"
    local restore_label="$2"
    local table_group="$3"
    local panel_dir="$4"
    local selected_name="$5"

    local tables
    tables=$(_get_restore_tables "$table_group")

    # Build table flags for pg_dump
    local table_flags=""
    for t in $tables; do
        table_flags="$table_flags --table=$t"
    done

    CONFIRM_WARN_LINE="$(echo -e "${WHITE}Файл:${NC} ${DARKGRAY}${selected_name}${NC}\n${WHITE}Режим:${NC} ${YELLOW}${restore_label}${NC}\n\n${YELLOW}⚠️  ВНИМАНИЕ!${NC}\n${WHITE}Данные из бэкапа будут ДОБАВЛЕНЫ к текущим.${NC}\n${WHITE}Существующие записи не будут изменены.${NC}")"
    if ! confirm_nav "📥 Частичное восстановление" "Подтвердить" "Отменить"; then
        unset CONFIRM_WARN_LINE
        print_error "Операция отменена"
        sleep 2
        return 0
    fi
    unset CONFIRM_WARN_LINE

    echo

    # Создаём временную базу данных
    (
        docker exec remnawave-db psql -U postgres -c "DROP DATABASE IF EXISTS _rw_restore_tmp;" >/dev/null 2>&1
        docker exec remnawave-db psql -U postgres -c "CREATE DATABASE _rw_restore_tmp;" >/dev/null 2>&1
     ) </dev/null &    show_spinner "Подготовка временной базы"

    # Загружаем дамп во временную базу
    (
        if [[ "$dump_file" == *.gz ]]; then
            zcat "$dump_file"
        else
            cat "$dump_file"
        fi | grep -v '^DROP DATABASE' | \
            grep -v '^CREATE DATABASE' | \
            grep -v '^ALTER DATABASE' | \
            grep -v -E "^ALTER ROLE .* PASSWORD " | \
            sed 's/\\connect postgres/\\connect _rw_restore_tmp/g' | \
            docker exec -i remnawave-db psql -U postgres >/dev/null 2>&1
     ) </dev/null &    show_spinner "Загрузка бэкапа во временную базу"

    # Страховочный бэкап текущей БД
    local safety_backup="${panel_dir}/backups/pre_partial_$(date +%Y-%m-%d_%H-%M).sql.gz"
    mkdir -p "${panel_dir}/backups"
    docker exec remnawave-db pg_dumpall -c -U postgres 2>/dev/null | gzip -9 > "$safety_backup"
    [ ! -s "$safety_backup" ] && rm -f "$safety_backup" 2>/dev/null

    # Останавливаем панель
    (
        cd "$panel_dir"
        if grep -q 'remnawave-subscription-page' docker-compose.yml 2>/dev/null; then
            docker compose stop remnawave remnawave-subscription-page >/dev/null 2>&1
        else
            docker compose stop remnawave >/dev/null 2>&1
        fi
     ) </dev/null &    show_spinner "Остановка панели"

    # Извлекаем данные из временной БД и применяем к основной с ON CONFLICT DO NOTHING
    (
        {
            echo "SET session_replication_role = 'replica';"
            docker exec remnawave-db pg_dump -U postgres -d _rw_restore_tmp \
                --data-only --column-inserts $table_flags 2>/dev/null | \
                sed '/^INSERT INTO /s/);$/) ON CONFLICT DO NOTHING;/'
            echo "SET session_replication_role = 'origin';"
        } | docker exec -i remnawave-db psql -U postgres -d postgres >/dev/null 2>&1
     ) </dev/null &    show_spinner "Восстановление данных"

    # Удаляем временную базу
    docker exec remnawave-db psql -U postgres -c "DROP DATABASE IF EXISTS _rw_restore_tmp;" >/dev/null 2>&1

    # После восстановления нод — чистим оборванные FK на config_profiles
    if [ "$table_group" = "nodes" ]; then
        (
            docker exec remnawave-db psql -U postgres -d postgres -c \
                "DELETE FROM config_profile_inbounds_to_nodes
                 WHERE config_profile_inbound_uuid NOT IN (SELECT uuid FROM config_profile_inbounds);" >/dev/null 2>&1
            docker exec remnawave-db psql -U postgres -d postgres -c \
                "UPDATE nodes SET active_config_profile_uuid = NULL
                 WHERE active_config_profile_uuid IS NOT NULL
                   AND active_config_profile_uuid NOT IN (SELECT uuid FROM config_profiles);" >/dev/null 2>&1
         ) </dev/null &        show_spinner "Очистка оборванных ссылок на профили"
    fi

    # Запускаем панель и ждём готовности API
    (
        cd "$panel_dir"
        docker compose up -d >/dev/null 2>&1
        _w=0
        while [ $_w -lt 120 ]; do
            curl -s -f --max-time 5 "http://127.0.0.1:3000/api/auth/status" \
                --header 'X-Forwarded-For: 127.0.0.1' \
                --header 'X-Forwarded-Proto: https' > /dev/null 2>&1 && break
            sleep 2
            _w=$((_w + 2))
        done
     ) </dev/null &    show_spinner "Запуск панели"

    # Перезапуск мониторинга (если установлен)
    if [ -f "${DIR_BESZEL}docker-compose.yml" ]; then
        (cd "${DIR_BESZEL}" && docker compose restart >/dev/null 2>&1 ) </dev/null &        show_spinner "Перезапуск мониторинга"
    fi

    echo
    print_success "Данные успешно восстановлены!"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

db_restore() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   📥 Загрузка базы данных${NC}"
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

    # Проверяем наличие бекапов (.tar.gz, .sql.gz и split-архивов)
    if [ -d "$backup_dir" ]; then
        compgen -G "$backup_dir/*.tar.gz" > /dev/null 2>&1 && has_files=true
        compgen -G "$backup_dir/*.sql.gz" > /dev/null 2>&1 && has_files=true
        compgen -G "$backup_dir/*.sql" > /dev/null 2>&1 && has_files=true
        compgen -G "$backup_dir/*.tar.gz.part1" > /dev/null 2>&1 && has_files=true
        compgen -G "$backup_dir/*_part1.tar.gz" > /dev/null 2>&1 && has_files=true
        compgen -G "$backup_dir/*.tar.gz.000.part" > /dev/null 2>&1 && has_files=true
    fi

    if [ "$has_files" = false ]; then
        print_warning "Бекапы не найдены в ${backup_dir}"
        echo
        echo -e "${WHITE}Поместите файл бекапа (.tar.gz, .sql.gz или .sql) в эту папку${NC}"
        echo -e "${WHITE}или укажите путь к файлу вручную.${NC}"
        echo

        tput cnorm 2>/dev/null || true
        reading "Путь к файлу бэкапа (или Enter для отмены):" custom_dump_path || return 0

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

    # Собираем список бэкапов (.tar.gz, .sql.gz и split-архивов), исключая технические файлы
    local backup_files=()
    local menu_items=()
    while IFS= read -r file; do
        local fname fsize display_label
        fname=$(basename "$file")
        # Пропускаем технические файлы страховочных бэкапов
        if [[ "$fname" =~ ^pre_ ]]; then
            continue
        fi
        # Обрабатываем split-архивы (part1 + part2)
        if [[ "$fname" == *.tar.gz.part1 ]] || [[ "$fname" == *_part1.tar.gz ]]; then
            local _part2_path=""
            if [[ "$fname" == *.tar.gz.part1 ]]; then
                _part2_path="${file%.part1}.part2"
            else
                _part2_path="${file/_part1.tar.gz/_part2.tar.gz}"
            fi
            [ -f "$_part2_path" ] || continue  # нет part2 — пропускаем
            backup_files+=("SPLIT:${file}:${_part2_path}")
            local _p1sz _p2sz _total_mb _base_fname
            _p1sz=$(stat -c%s "$file" 2>/dev/null || echo 0)
            _p2sz=$(stat -c%s "$_part2_path" 2>/dev/null || echo 0)
            _total_mb=$(( (_p1sz + _p2sz) / 1024 / 1024 ))
            if [[ "$fname" == *.tar.gz.part1 ]]; then
                _base_fname="${fname%.part1}"
            else
                _base_fname="${fname/_part1.tar.gz/.tar.gz}"
            fi
            if [[ "$_base_fname" =~ ^([A-Za-z]+)_([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})\.tar\.gz$ ]]; then
                local _pn _py _pm _pd _ph _pmin
                _pn="${BASH_REMATCH[1]}"; _py="${BASH_REMATCH[2]}"; _pm="${BASH_REMATCH[3]}"
                _pd="${BASH_REMATCH[4]}"; _ph="${BASH_REMATCH[5]}"; _pmin="${BASH_REMATCH[6]}"
                display_label="${_pn} | ${_pd}.${_pm}.${_py} | ${_ph}:${_pmin} | ${_total_mb}M (✂ 2 части)"
            else
                display_label="${_base_fname} (${_total_mb}M ✂ 2 части)"
            fi
            menu_items+=("📦  ${display_label}")
            continue
        fi
        # Обрабатываем N-частевые split-архивы (*.tar.gz.000.part ... *.tar.gz.NNN.part)
        if [[ "$fname" == *.tar.gz.000.part ]]; then
            local _base_path _base_tgz _base_dir
            _base_tgz=$(basename "${file%.000.part}")
            _base_dir=$(dirname "$file")
            local _all_parts=() _total_sz=0 _pf _psz
            while IFS= read -r _pf; do
                _all_parts+=("$_pf")
                _psz=$(stat -c%s "$_pf" 2>/dev/null || echo 0)
                _total_sz=$(( _total_sz + _psz ))
            done < <(find "$_base_dir" -maxdepth 1 -name "${_base_tgz}.*.part" | sort)
            local _nparts=${#_all_parts[@]}
            [ "$_nparts" -lt 2 ] && continue
            local _total_mb=$(( _total_sz / 1024 / 1024 ))
            backup_files+=("SPLITN:${_base_dir}:${_base_tgz}")
            # Парсим дату из имени: remnawave_backup_YYYY-MM-DD_HH_MM_SS
            local _bcore="${_base_tgz%.tar.gz}"
            if [[ "$_bcore" =~ ^(.+)_([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})_([0-9]{2})_[0-9]{2}$ ]]; then
                local _spn _spy _spm _spd _sph _spmin
                _spn="${BASH_REMATCH[1]}"; _spy="${BASH_REMATCH[2]}"; _spm="${BASH_REMATCH[3]}"
                _spd="${BASH_REMATCH[4]}"; _sph="${BASH_REMATCH[5]}"; _spmin="${BASH_REMATCH[6]}"
                display_label="${_spn} | ${_spd}.${_spm}.${_spy} | ${_sph}:${_spmin} | ${_total_mb}M (✂ ${_nparts} части)"
            else
                display_label="${_base_tgz} (${_total_mb}M ✂ ${_nparts} части)"
            fi
            menu_items+=("📦  ${display_label}")
            continue
        fi
        backup_files+=("$file")
        fsize=$(du -h "$file" | cut -f1)
        # Формат: Remnawave_2026-03-24_16-48.tar.gz
        if [[ "$fname" =~ ^([A-Za-z]+)_([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})\.(tar\.gz|sql\.gz|sql)$ ]]; then
            local pname pyear pmon pday phour pmin
            pname="${BASH_REMATCH[1]}"
            pyear="${BASH_REMATCH[2]}"
            pmon="${BASH_REMATCH[3]}"
            pday="${BASH_REMATCH[4]}"
            phour="${BASH_REMATCH[5]}"
            pmin="${BASH_REMATCH[6]}"
            display_label="${pname} | ${pday}.${pmon}.${pyear} | ${phour}:${pmin} | ${fsize}"
        # Формат: backup_remnawave_23.03.26_18-39-48.sql.gz
        elif [[ "$fname" =~ ^backup_([A-Za-z]+)_([0-9]{2})\.([0-9]{2})\.([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})\.(tar\.gz|sql\.gz|sql)$ ]]; then
            local pname pday pmon pyear phour pmin psec
            pname="${BASH_REMATCH[1]^}"      # заглавная первая буква
            pday="${BASH_REMATCH[2]}"
            pmon="${BASH_REMATCH[3]}"
            pyear="20${BASH_REMATCH[4]}"
            phour="${BASH_REMATCH[5]}"
            pmin="${BASH_REMATCH[6]}"
            psec="${BASH_REMATCH[7]}"
            display_label="${pname} | ${pday}.${pmon}.${pyear} | ${phour}:${pmin}:${psec} | ${fsize}"
        else
            display_label="${fname} (${fsize})"
        fi
        menu_items+=("📄  ${display_label}")
    done < <(find "$backup_dir" -maxdepth 1 \( -name "*.tar.gz" -o -name "*.sql.gz" -o -name "*.sql" -o -name "*.tar.gz.part1" -o -name "*_part1.tar.gz" -o -name "*.tar.gz.000.part" \) | sort -r)

    if [ ${#backup_files[@]} -eq 0 ]; then
        print_error "Файлы бэкапов не найдены"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    menu_items+=("──────────────────────────────────────")
    menu_items+=("⬅️   Назад")

    show_arrow_menu "📥 Выберите бэкап для загрузки" "${menu_items[@]}"
    local choice=$?

    # Проверка — выбран ли разделитель или "Назад"
    if [ $choice -ge ${#backup_files[@]} ] || [ $choice -eq 255 ]; then
        return 0
    fi

    local selected_file="${backup_files[$choice]}"
    local selected_name
    local _is_split=false _split_p1="" _split_p2=""
    local _is_splitn=false _splitn_dir="" _splitn_base="" _splitn_parts=()
    # Обработка 2-частевых split-архивов
    if [[ "$selected_file" == SPLIT:* ]]; then
        _is_split=true
        local _sinfo="${selected_file#SPLIT:}"
        _split_p1="${_sinfo%%:*}"
        _split_p2="${_sinfo#*:}"
        local _bfn
        _bfn=$(basename "$_split_p1")
        if [[ "$_bfn" == *.tar.gz.part1 ]]; then
            selected_name="${_bfn%.part1}"
        else
            selected_name="${_bfn/_part1.tar.gz/.tar.gz}"
        fi
        selected_file="$_split_p1"
    # Обработка N-частевых split-архивов (*.tar.gz.000.part ...)
    elif [[ "$selected_file" == SPLITN:* ]]; then
        _is_splitn=true
        local _sninfo="${selected_file#SPLITN:}"
        _splitn_dir="${_sninfo%%:*}"
        _splitn_base="${_sninfo#*:}"
        selected_name="$_splitn_base"
        while IFS= read -r _snpf; do
            _splitn_parts+=("$_snpf")
        done < <(find "$_splitn_dir" -maxdepth 1 -name "${_splitn_base}.*.part" | sort)
    else
        selected_name=$(basename "$selected_file")
    fi

    # Определяем формат и извлекаем дамп
    local dump_to_restore=""
    local bot_dump_to_restore=""
    local tmp_extract=""
    local is_archive=false

    if [ "$_is_split" = true ] || [ "$_is_splitn" = true ] || { [[ "$selected_name" == *.tar.gz ]] && [[ "$selected_name" != dump_* ]]; }; then
        # Архив Remnawave_*.tar.gz — извлекаем дамп
        is_archive=true
        tmp_extract="/tmp/_rw_restore_$$"
        mkdir -p "$tmp_extract"

        (
            if [ "$_is_splitn" = true ]; then
                cat "${_splitn_parts[@]}" | tar -xz -C "$tmp_extract" 2>/dev/null
            elif [ "$_is_split" = true ]; then
                cat "$_split_p1" "$_split_p2" | tar -xz -C "$tmp_extract" 2>/dev/null
            else
                tar -xzf "$selected_file" -C "$tmp_extract" 2>/dev/null
            fi
         ) </dev/null &        if [ "$_is_splitn" = true ]; then
            show_spinner "Объединение и распаковка ${#_splitn_parts[@]} частей архива"
        elif [ "$_is_split" = true ]; then
            show_spinner "Объединение и распаковка частей архива"
        else
            show_spinner "Распаковка архива"
        fi

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
    show_arrow_menu "📥 Тип восстановления" \
        "📦  Полное восстановление" \
        "──────────────────────────────────────" \
        "👤  Восстановить Пользователей" \
        "📄  Восстановить Профили Xray" \
        "📋  Восстановить Шаблоны Xray JSON" \
        "🌐  Восстановить Ноды и Хосты" \
        "💰  Восстановить Данные биллинга" \
        "👥  Восстановить Внутренние сквады" \
        "🌍  Восстановить Внешние сквады" \
        "⚙️   Восстановить Настройки" \
        "──────────────────────────────────────" \
        "❌  Отмена"
    local restore_choice=$?

    if [ $restore_choice -eq 255 ] || [ $restore_choice -ge 10 ]; then
        rm -rf "$tmp_extract" 2>/dev/null
        return 0
    fi

    # Частичное восстановление
    if [ $restore_choice -ge 2 ]; then
        local _partial_group="" _partial_label=""
        case $restore_choice in
            2) _partial_group="users";           _partial_label="Пользователи" ;;
            3) _partial_group="profiles";        _partial_label="Профили Xray" ;;
            4) _partial_group="templates";       _partial_label="Шаблоны Xray JSON" ;;
            5) _partial_group="nodes";           _partial_label="Ноды и Хосты" ;;
            6) _partial_group="billing";         _partial_label="Данные биллинга" ;;
            7) _partial_group="internal_squads"; _partial_label="Внутренние сквады" ;;
            8) _partial_group="external_squads"; _partial_label="Внешние сквады" ;;
            9) _partial_group="settings";        _partial_label="Настройки" ;;
        esac
        _db_partial_restore "$dump_to_restore" "$_partial_label" "$_partial_group" "$panel_dir" "$selected_name"
        rm -rf "$tmp_extract" 2>/dev/null
        return
    fi

    if ! confirm_nav --delete "📥 Полное восстановление базы"; then
        print_error "Операция отменена"
        rm -rf "$tmp_extract" 2>/dev/null
        sleep 2
        return 0
    fi

    echo

    # Останавливаем панель (и страницу подписки, если она в compose)
    (
        cd "$panel_dir"
        if grep -q 'remnawave-subscription-page' docker-compose.yml 2>/dev/null; then
            docker compose stop remnawave remnawave-subscription-page >/dev/null 2>&1
        else
            docker compose stop remnawave >/dev/null 2>&1
        fi
     ) </dev/null &    show_spinner "Остановка панели"

    # Сохраняем текущий API токен (чтобы не сломать удалённую sub-page при восстановлении)
    local _saved_api_token=""
    _saved_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "$panel_dir/.env" 2>/dev/null | head -1)

    # Сохраняем текущий SUB_PUBLIC_DOMAIN (для случая когда sub-page на удалённом сервере)
    local _saved_sub_domain=""
    _saved_sub_domain=$(grep -oP '^SUB_PUBLIC_DOMAIN=\K\S+' "$panel_dir/.env" 2>/dev/null | head -1)

    # Делаем страховочный бэкап текущей БД перед восстановлением (тихо)
    local safety_backup="${panel_dir}/backups/pre_restore_$(date +%Y-%m-%d_%H-%M).sql.gz"
    mkdir -p "${panel_dir}/backups"
    docker exec remnawave-db pg_dumpall -c -U postgres 2>/dev/null | gzip -9 > "$safety_backup"
    [ ! -s "$safety_backup" ] && rm -f "$safety_backup" 2>/dev/null
    echo

    # Очищаем базу данных перед восстановлением
    (
        docker exec remnawave-db psql -U postgres -d postgres -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
     ) </dev/null &    show_spinner "Подготовка базы данных"

    # Восстанавливаем дамп
    (
        if [[ "$dump_to_restore" == *.gz ]]; then
            zcat "$dump_to_restore" | grep -v -E "^ALTER ROLE .* PASSWORD " | docker exec -i remnawave-db psql -U postgres -d postgres >/dev/null 2>&1
        else
            grep -v -E "^ALTER ROLE .* PASSWORD " "$dump_to_restore" | docker exec -i remnawave-db psql -U postgres -d postgres >/dev/null 2>&1
        fi
     ) </dev/null &    show_spinner "Загрузка данных из бэкапа"

    # Восстановление базы бота (remnasale-db), если дамп найден в архиве
    if [ -n "$bot_dump_to_restore" ] && [ -s "$bot_dump_to_restore" ]; then
        if docker ps --filter "name=remnasale-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnasale-db"; then
            (
                docker exec remnasale-db psql -U remnasale -d remnasale -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
                zcat "$bot_dump_to_restore" | docker exec -i remnasale-db psql -U remnasale -d remnasale >/dev/null 2>&1
             ) </dev/null &            show_spinner "Загрузка базы бота из бэкапа"
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

    # Полное восстановление — стандартный процесс

    # Очищаем таблицу admin для перевода панели в режим регистрации
    (
        docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1
     ) </dev/null &    show_spinner "Подготовка к регистрации"
    echo

    # Запускаем панель и ожидаем готовность API
    local domain_url="127.0.0.1:3000"
    local _api_ready="/tmp/.api_ready_$$"
    rm -f "$_api_ready"
    (
        cd "$panel_dir"
        docker compose up -d remnawave >/dev/null 2>&1
        _w=0
        while [ $_w -lt 120 ]; do
            curl -s -f --max-time 5 "http://127.0.0.1:3000/api/auth/status" \
                --header 'X-Forwarded-For: 127.0.0.1' \
                --header 'X-Forwarded-Proto: https' > /dev/null 2>&1 && { touch "$_api_ready"; break; }
            sleep 2
            _w=$((_w + 2))
        done
     ) </dev/null &    show_spinner "Запуск панели"

    if [ ! -f "$_api_ready" ]; then
        rm -f "$_api_ready"
        print_error "API не отвечает после восстановления"
        echo -e "${YELLOW}Запустите панель вручную и создайте администратора${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return
    fi
    rm -f "$_api_ready"

    # Регистрация нового администратора и создание API токена (тихо)
    local SUPERADMIN_USERNAME SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    local token
    token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

    if [ -n "$token" ]; then
        # Определяем API токен: сохранённый (для удалённой sub-page) или новый
        local _use_token=""
        if [ -n "$_saved_api_token" ]; then
            # Используем сохранённый токен (чтобы не сломать удалённую sub-page)
            _use_token="$_saved_api_token"
        else
            # Токена не было — создаём новый через API
            docker exec remnawave-db psql -U postgres -d postgres -c \
                "UPDATE api_tokens SET token_name = token_name || '_old' WHERE token_name = 'subscription-page';" >/dev/null 2>&1 || true
            if create_api_token "$domain_url" "$token" "$panel_dir" 2>/dev/null; then
                _use_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "$panel_dir/.env" 2>/dev/null | head -1)
            fi
        fi

        # Сброс администратора (CASCADE удалит и API токены)
        docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1

        # Восстанавливаем API токен напрямую в базу
        if [ -n "$_use_token" ]; then
            # Извлекаем uuid из JWT-токена (панель ищет токен по uuid из JWT)
            local token_uuid
            token_uuid=$(echo "$_use_token" | cut -d'.' -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | grep -oP '"uuid"\s*:\s*"\K[^"]+' 2>/dev/null)
            if [ -z "$token_uuid" ]; then
                token_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
            fi

            # Удаляем старые subscription-page токены и вставляем сохранённый
            docker exec remnawave-db psql -U postgres -d postgres -c \
                "DELETE FROM api_tokens WHERE token_name = 'subscription-page';" >/dev/null 2>&1
            docker exec remnawave-db psql -U postgres -d postgres -c \
                "INSERT INTO api_tokens (uuid, token, token_name, created_at, updated_at) 
                 VALUES ('$token_uuid', '$_use_token', 'subscription-page', NOW(), NOW());" >/dev/null 2>&1
        fi

        # Перезапуск subscription-page (ищем во всех возможных местах)
        local _sub_page_dir="" _dir
        for _dir in "/opt/remnawave" "/opt/remnanode" "/opt/remnasubpage" "/opt/subscribe-page"; do
            if grep -q 'remnawave-subscription-page' "$_dir/docker-compose.yml" 2>/dev/null; then
                _sub_page_dir="$_dir"
                break
            fi
        done

        if [ -n "$_sub_page_dir" ]; then
            (
                cd "$_sub_page_dir"
                docker compose up -d remnawave-subscription-page >/dev/null 2>&1
                _w=0
                while [ $_w -lt 60 ]; do
                    docker inspect --format='{{.State.Health.Status}}' remnawave-subscription-page 2>/dev/null | grep -q 'healthy' && break
                    sleep 2
                    _w=$((_w + 2))
                done
             ) </dev/null &            show_spinner "Перезапуск страницы подписки"
        else
            # Страницы подписки нет на этом сервере — восстанавливаем SUB_PUBLIC_DOMAIN
            if [ -n "$_saved_sub_domain" ]; then
                local _cur_sub_dom
                _cur_sub_dom=$(grep -oP '^SUB_PUBLIC_DOMAIN=\K\S+' "$panel_dir/.env" 2>/dev/null | head -1)
                if [ "$_cur_sub_dom" != "$_saved_sub_domain" ]; then
                    sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$_saved_sub_domain|" "$panel_dir/.env"
                    (
                        cd "$panel_dir" && docker compose up -d remnawave >/dev/null 2>&1
                        _w=0
                        while [ $_w -lt 60 ]; do
                            curl -s -f --max-time 5 "http://127.0.0.1:3000/api/auth/status" \
                                --header 'X-Forwarded-For: 127.0.0.1' \
                                --header 'X-Forwarded-Proto: https' > /dev/null 2>&1 && break
                            sleep 2
                            _w=$((_w + 2))
                        done
                     ) </dev/null &                    show_spinner "Обновление SUB_PUBLIC_DOMAIN"
                fi
            fi
        fi
    else
        print_error "Не удалось зарегистрировать администратора"
        echo -e "${YELLOW}Создайте администратора вручную через панель${NC}"
    fi

    # Перезапуск мониторинга (если установлен)
    if [ -f "${DIR_BESZEL}docker-compose.yml" ]; then
        (cd "${DIR_BESZEL}" && docker compose restart >/dev/null 2>&1 ) </dev/null &        show_spinner "Перезапуск мониторинга"
    fi

    echo
    print_success "База данных успешно загружена!"
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
    reading "Токен бота для бекапов${current_hint}:" new_backup_token || return
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
    reading "Telegram ID для получения бекапов${current_hint}:" new_chat_id || return
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
    print_success "Автобекап успешно настроен"
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
    print_success "Автобекап остановлен"
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

        local menu_title="💾 Работа с базой данных"
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
