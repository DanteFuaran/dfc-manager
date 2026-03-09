# ═══════════════════════════════════════════════
# УПРАВЛЕНИЕ СЕРВИСАМИ
# ═══════════════════════════════════════════════

manage_start() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return
    (
        cd "$rw_path"
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск сервисов"
    print_success "Сервисы запущены"
    echo
    show_continue_prompt || return 1
}

manage_stop() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return
    (
        cd "$rw_path"
        docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка сервисов"
    print_success "Сервисы остановлены"
    echo
    show_continue_prompt || return 1
}

manage_update() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔄 ОБНОВЛЕНИЕ КОМПОНЕНТОВ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if ! is_panel_installed && ! is_node_installed; then
        echo -e "${RED}✖  Не найдено установленных компонентов.${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return
    fi

    local rw_path
    rw_path=$(detect_remnawave_path) || return

    (
        cd "$rw_path"
        docker compose pull >/dev/null 2>&1
    ) &
    show_spinner "Скачивание обновлений"

    (
        cd "$rw_path"
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    (
        docker image prune -af >/dev/null 2>&1
    ) &
    show_spinner "Очистка старых образов"

    print_success "Обновление завершено"
    echo
    show_continue_prompt || return 1
}

manage_logs() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return
    clear
    echo -e "${YELLOW}Для выхода из логов нажмите Ctrl+C${NC}"
    sleep 1
    cd "$rw_path"
    docker compose logs -f -t --tail 100
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
        "❌  Назад"
    local choice=$?

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
