# ═══════════════════════════════════════════════
# УПРАВЛЕНИЕ СЕРВИСАМИ
# ═══════════════════════════════════════════════

manage_start() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return

    # Запускаем remnawave (панель + нода + subscription-page в одном compose)
    (
        cd "$rw_path"
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск remnawave"

    # Запускаем отдельную ноду (если установлена на том же сервере)
    if [ -f "/opt/remnanode/docker-compose.yml" ]; then
        (cd /opt/remnanode && docker compose up -d >/dev/null 2>&1) &
        show_spinner "Запуск remnanode" || true
    fi

    # Запускаем subscription-page (если установлена отдельно)
    for _sp in /opt/subscribe-page /opt/remnasubpage; do
        if [ -f "${_sp}/docker-compose.yml" ] && [ "$_sp" != "$rw_path" ]; then
            (cd "$_sp" && docker compose up -d >/dev/null 2>&1) &
            show_spinner "Запуск subscription-page" || true
            break
        fi
    done

    (cd "${DIR_NGINX}" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск nginx" || true

    print_success "Сервисы запущены"
    echo
    show_continue_prompt || return 1
}

manage_stop() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return

    # Останавливаем nginx первым
    (cd "${DIR_NGINX}" && docker compose down >/dev/null 2>&1) &
    show_spinner "Остановка nginx" || true

    # Останавливаем отдельную ноду (если есть)
    if [ -f "/opt/remnanode/docker-compose.yml" ]; then
        (cd /opt/remnanode && docker compose down >/dev/null 2>&1) &
        show_spinner "Остановка remnanode" || true
    fi

    # Останавливаем отдельный subscription-page (если есть)
    for _sp in /opt/subscribe-page /opt/remnasubpage; do
        if [ -f "${_sp}/docker-compose.yml" ] && [ "$_sp" != "$rw_path" ]; then
            (cd "$_sp" && docker compose down >/dev/null 2>&1) &
            show_spinner "Остановка subscription-page" || true
            break
        fi
    done

    # Останавливаем remnawave
    (
        cd "$rw_path"
        docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка remnawave"

    print_success "Сервисы остановлены"
    echo
    show_continue_prompt || return 1
}

manage_update() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}        🔄 ОБНОВЛЕНИЕ КОМПОНЕНТОВ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if ! is_panel_installed && ! is_node_installed; then
        echo -e "${RED}✖  Не найдено установленных компонентов.${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return
    fi

    local rw_path pull_tmp pull_count
    rw_path=$(detect_remnawave_path) || return
    pull_tmp=$(mktemp)

    (
        cd "$rw_path"
        docker compose pull > "$pull_tmp" 2>&1
    ) &
    show_spinner "Скачивание обновлений"

    pull_count=$(grep -cE 'Pull complete|Downloaded newer|Pulled' "$pull_tmp" 2>/dev/null || true)
    pull_count="${pull_count:-0}"
    rm -f "$pull_tmp"

    if [ "${pull_count}" -eq 0 ]; then
        echo
        print_success "Обновление компонентов не требуется."
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return
    fi

    (
        cd "$rw_path"
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    (cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1) &
    show_spinner "Перезапуск nginx" || true

    (
        docker image prune -af >/dev/null 2>&1
    ) &
    show_spinner "Очистка старых образов"

    echo
    print_success "Обновление завершено"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

manage_logs() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return

    # Убиваем любые ранее осиротевшие процессы docker logs
    pkill -f "docker logs -f" 2>/dev/null || true
    pkill -f "docker compose logs -f" 2>/dev/null || true
    sleep 0.1

    while true; do
        # Строим список доступных сервисов
        local -a log_items=() log_services=() log_dirs=()

        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave$'; then
            log_items+=("🌊  Remnawave (Панель)")
            log_services+=("remnawave")
            log_dirs+=("$rw_path")
        fi

        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^remnanode$'; then
            log_items+=("🔗  Remnawave (Нода)")
            log_services+=("remnanode")
            if [ -f "/opt/remnanode/docker-compose.yml" ]; then
                log_dirs+=("/opt/remnanode")
            else
                log_dirs+=("$rw_path")
            fi
        fi

        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE '^remnawave-subscription-page$|^remnasubpage$'; then
            log_items+=("📄  subscription-page")
            log_services+=("remnawave-subscription-page")
            for _sp in /opt/subscribe-page /opt/remnasubpage; do
                if [ -f "${_sp}/docker-compose.yml" ]; then
                    log_dirs+=("$_sp")
                    break
                fi
            done
            if [ ${#log_dirs[@]} -lt ${#log_services[@]} ]; then
                log_dirs+=("$rw_path")
            fi
        fi

        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
            log_items+=("🔀  Nginx")
            log_services+=("nginx")
            log_dirs+=("${DIR_NGINX%/}")
        fi

        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE '^remnasale(-|$)'; then
            local _rs_dir=""
            for _d in /opt/remnasale; do
                [ -f "${_d}/docker-compose.yml" ] && _rs_dir="$_d" && break
            done
            if [ -n "$_rs_dir" ]; then
                log_items+=("🤖  Remnasale (Бот)")
                log_services+=("__remnasale_all__")
                log_dirs+=("$_rs_dir")
            fi
        fi

        if [ ${#log_items[@]} -eq 0 ]; then
            clear
            echo -e "${RED}✖  Сервисы remnawave не найдены.${NC}"
            echo
            show_continue_prompt || return 1
            return
        fi

        log_items+=("──────────────────────────────────────")
        log_items+=("⬅️   Назад")

        local _sep_idx=${#log_services[@]}

        show_arrow_menu "📋  Просмотр логов" "${log_items[@]}"
        local choice=$?
        [[ $choice -eq 255 ]] && return
        # Назад или разделитель
        [[ $choice -ge $_sep_idx ]] && return

        local svc="${log_services[$choice]}"
        local dir="${log_dirs[$choice]}"
        local _display_svc="$svc"
        [[ "$svc" == "__remnasale_all__" ]] && _display_svc="Remnasale (все контейнеры)"

        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}  📋  Логи: ${WHITE}${_display_svc}${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${DARKGRAY}Для выхода нажмите Esc или Ctrl+C${NC}"
        echo

        # Запускаем docker logs в фоне — чтобы параллельно отслеживать нажатия клавиш
        local _logs_pid=""
        if [[ "$svc" == "__remnasale_all__" ]]; then
            # Все контейнеры compose (remnasale + taskiq-worker + taskiq-scheduler + db)
            (cd "$dir" && exec docker compose logs -f -t --tail 100 2>&1) &
            _logs_pid=$!
        elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$svc"; then
            docker logs -f -t --tail 100 "$svc" 2>&1 &
            _logs_pid=$!
        else
            # exec заменяет subshell процессом docker compose — kill корректно завершает его
            (cd "$dir" && exec docker compose logs -f -t --tail 100 "$svc" 2>&1) &
            _logs_pid=$!
        fi

        # Функция для надёжной остановки: SIGTERM → ждём → SIGKILL + дочерние
        _kill_logs() {
            kill "$_logs_pid" 2>/dev/null || true
            pkill -P "$_logs_pid" 2>/dev/null || true
            sleep 0.1
            kill -9 "$_logs_pid" 2>/dev/null || true
            pkill -9 -P "$_logs_pid" 2>/dev/null || true
        }

        # Ctrl+C — убиваем процесс логов и возвращаемся в меню выбора
        trap "_kill_logs; wait \$_logs_pid 2>/dev/null; trap - INT" INT

        # Опрашиваем stdin: Esc завершает просмотр логов и возвращает в меню
        local _key=""
        while kill -0 "$_logs_pid" 2>/dev/null; do
            IFS= read -r -s -n1 -t 0.2 _key 2>/dev/null || true
            if [[ "$_key" == $'\033' ]]; then
                _kill_logs
                break
            fi
        done

        wait "$_logs_pid" 2>/dev/null || true
        trap - INT
    done
}

manage_reinstall() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    🗑️  Переустановить компоненты${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    echo -e "${RED}⚠️  Все данные будут удалены!${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if ! confirm_action; then
        return
    fi

    local rw_path
    rw_path=$(detect_remnawave_path) || return

    (
        cd "$rw_path"
        docker compose down -v --rmi all 2>&1
        docker system prune -af 2>&1
    ) &
    show_spinner "Удаление контейнеров и данных" || true

    _nginx_extract_external_blocks 2>/dev/null || true
    nginx_ensure_conf_for_remaining

    (
        rm -rf "$rw_path"
    ) &
    show_spinner "Очистка конфигурации" || true

    print_success "Готово к переустановке"

    show_arrow_menu "📦  Выберите тип установки" \
        "📦  Панель + Нода (один сервер)" \
        "──────────────────────────────────────" \
        "🖥️   Только панель" \
        "🌐  Только нода" \
        "➕  Подключить ноду в панель" \
        "──────────────────────────────────────" \
        "⬅️   Назад"
    local choice=$?
    [[ $choice -eq 255 ]] && return

    case $choice in
        0) installation_full ;;
        1) : ;;
        2) installation_panel ;;
        3) installation_node ;;
        4) add_node_to_panel ;;
        5) : ;;
        6) return ;;
    esac
}
