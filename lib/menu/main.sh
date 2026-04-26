# ═══════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════

main_menu() {
    # Если stdin не является TTY — выходим без бесконечного цикла
    if ! [ -t 0 ]; then
        exit 0
    fi

    alias dfc="/usr/local/bin/dfc-manager" 2>/dev/null || true

    while true; do
        tput civis 2>/dev/null || true
        local menu_title="🛠️  DFC Manager v$SCRIPT_VERSION"

        local -a items=() actions=()
        local _rw_label="📦  Remnawave - Панель  " _bz_label="📊  Мониторинг Beszel " _mt_label="📡  MTProto - TG Прокси "
        { is_panel_installed || is_node_installed || is_subpage_remote_installed; } \
            && _rw_label="${_rw_label} ${GREEN}(установлено)${NC}" \
            || _rw_label="${_rw_label} ${DARKGRAY}(не установлено)${NC}"
        { is_beszel_installed || is_beszel_agent_installed; } \
            && _bz_label="${_bz_label} ${GREEN}(установлено)${NC}" \
            || _bz_label="${_bz_label} ${DARKGRAY}(не установлено)${NC}"
        _mt_installed \
            && _mt_label="${_mt_label} ${GREEN}(установлено)${NC}" \
            || _mt_label="${_mt_label} ${DARKGRAY}(не установлено)${NC}"
        items+=("$_rw_label");                     actions+=("remnawave")
        items+=("$_bz_label");                     actions+=("beszel")
        items+=("$_mt_label");                      actions+=("mtproto")
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("🧩  Дополнительные программы");   actions+=("extra")
        items+=("🧪  Тестирование сервера");         actions+=("testing")
        items+=("⚙️   Оптимизация сервера");          actions+=("optimization")
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("🗑️   Удаление компонентов");          actions+=("delete_all")
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("❌  Выход");                         actions+=("exit")

        MENU_ESC_LABEL="Выход"
        show_arrow_menu "$menu_title" "${items[@]}"
        local choice=$?
        unset MENU_ESC_LABEL
        [[ $choice -eq 255 ]] && { cleanup_terminal; clear; cleanup_uninstalled; exit 0; }
        local action="${actions[$choice]:-}"

        case "$action" in
            remnawave)
                while true; do
                    tput civis 2>/dev/null || true
                    local has_panel=false has_node=false has_subpage=false
                    is_panel_installed && has_panel=true
                    is_node_installed  && has_node=true
                    is_subpage_remote_installed && has_subpage=true
                    local is_installed=false
                    { [ "$has_panel" = true ] || [ "$has_node" = true ] || [ "$has_subpage" = true ]; } && is_installed=true

                    if [ "$is_installed" = true ]; then
                        _install_bin_wrappers
                    fi

                    local _c_panel _c_sub _c_node
                    [ "$has_panel" = true ]   && _c_panel="${GREEN}" || _c_panel="${DARKGRAY}"
                    [ "$has_subpage" = true ] && _c_sub="${GREEN}"   || _c_sub="${DARKGRAY}"
                    [ "$has_node" = true ]    && _c_node="${GREEN}"  || _c_node="${DARKGRAY}"
                    # Вторая строка заголовка — центрирует show_arrow_menu (ширина 38)
                    local install_status="\\n${_c_panel}Панель${DARKGRAY} | ${_c_sub}Подписка${DARKGRAY} | ${_c_node}Нода${NC}"

                    local rw_title="📦 Remnawave (Сервис)${install_status}"
                    local -a rw_items=() rw_actions=()
                    rw_items+=("📦  Установить компоненты");  rw_actions+=("install")
                    rw_items+=("──────────────────────────────────────"); rw_actions+=("sep")
                    if [ "$is_installed" = true ]; then
                        local _service_action_idx=${#rw_items[@]}
                        if remnawave_services_running; then
                            rw_items+=("⏹️   Остановить сервисы");      rw_actions+=("stop")
                        else
                            rw_items+=("▶️   Запустить сервисы");       rw_actions+=("start")
                        fi
                        rw_items+=("📋  Просмотр логов");          rw_actions+=("logs")
                        rw_items+=("──────────────────────────────────────"); rw_actions+=("sep")
                        rw_items+=("💾  Управление базой данных"); rw_actions+=("database")
                        rw_items+=("🔓  Настройки");               rw_actions+=("access")
                        rw_items+=("──────────────────────────────────────"); rw_actions+=("sep")
                        rw_items+=("🔄  Обновить панель/ноду");    rw_actions+=("update_components")
                        rw_items+=("──────────────────────────────────────"); rw_actions+=("sep")
                    fi
                    rw_items+=("⬅️   Назад"); rw_actions+=("back")

                    show_arrow_menu "$rw_title" "${rw_items[@]}"
                    local rw_choice=$?
                    [[ $rw_choice -eq 255 ]] && break
                    local rw_action="${rw_actions[$rw_choice]:-sep}"

                    case "$rw_action" in
                        install)
                            while true; do
                                tput civis 2>/dev/null || true
                                local -a inst_items=() inst_actions=()
                                if ! is_panel_installed; then
                                    inst_items+=("🖥️   Установить Панель Remnawave"); inst_actions+=("panel_wizard")
                                else
                                    inst_items+=("➕  Подключить ноду к панели"); inst_actions+=("add_node")
                                fi
                                if ! is_subpage_remote_installed || ! is_node_installed; then
                                    inst_items+=("──────────────────────────────────────"); inst_actions+=("sep")
                                fi
                                if ! is_subpage_remote_installed; then
                                    inst_items+=("📄  Установить Страницу подписки"); inst_actions+=("subpage")
                                fi
                                if ! is_node_installed; then
                                    inst_items+=("🌐  Установить Ноду");               inst_actions+=("node")
                                fi
                                inst_items+=("──────────────────────────────────────"); inst_actions+=("sep")
                                inst_items+=("⬅️   Назад"); inst_actions+=("back")

                                show_arrow_menu "📦 Выберите тип установки" "${inst_items[@]}"
                                local install_choice=$?
                                [[ $install_choice -eq 255 ]] && break
                                local inst_action="${inst_actions[$install_choice]:-back}"
                                case "$inst_action" in
                                    panel_wizard)
                                        while true; do
                                            tput civis 2>/dev/null || true
                                            show_arrow_menu "📄 Установка страницы подписки" \
                                                "✔️   Установить на этот сервер (рекомендуется)" \
                                                "❌  Установлю на отдельный сервер" \
                                                "──────────────────────────────────────" \
                                                "⬅️   Назад"
                                            local sub_choice=$?
                                            [[ $sub_choice -eq 255 || $sub_choice -eq 3 ]] && break
                                            local with_subpage=true
                                            [[ $sub_choice -eq 1 ]] && with_subpage=false

                                            show_arrow_menu "🌐 Установка ноды" \
                                                "✔️   Установлю на отдельный сервер (рекомендуется)" \
                                                "❌  Установить на этот сервер" \
                                                "──────────────────────────────────────" \
                                                "⬅️   Назад"
                                            local node_choice=$?
                                            [[ $node_choice -eq 255 || $node_choice -eq 3 ]] && continue
                                            local with_node=false
                                            [[ $node_choice -eq 1 ]] && with_node=true

                                            if [ "$with_subpage" = true ] && [ "$with_node" = true ]; then
                                                installation_full
                                            elif [ "$with_subpage" = true ]; then
                                                installation_panel true
                                            elif [ "$with_node" = true ]; then
                                                installation_panel_with_node
                                            else
                                                installation_panel false
                                            fi
                                            break
                                        done
                                        ;;
                                    subpage)    installation_subpage ;;
                                    node)       installation_node ;;
                                    add_node)   installation_node_connect ;;
                                    *) break ;;
                                esac
                            done ;;
                        reinstall)         manage_reinstall ;;
                        start)             manage_start; MENU_INITIAL_IDX=$_service_action_idx ;;
                        stop)              manage_stop; MENU_INITIAL_IDX=$_service_action_idx ;;
                        logs)              manage_logs ;;
                        database)          manage_database ;;
                        access)            manage_panel_access ;;
                        update_components) manage_update ;;
                        back) break ;;
                        sep)  continue ;;
                        *)    continue ;;
                    esac
                done ;;
            beszel)       manage_beszel ;;
            mtproto)      manage_mtproto ;;
            extra)        manage_extra_settings ;;
            testing)      manage_server_testing ;;
            optimization) manage_server_optimization ;;
            delete_all)   manage_delete_components ;;
            sep)          continue ;;
            exit)         cleanup_terminal; clear; cleanup_uninstalled; exit 0 ;;
            *)            continue ;;
        esac
    done
}
