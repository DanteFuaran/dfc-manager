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
        local menu_title="      🛠️  DFC Manager v$SCRIPT_VERSION\n${DARKGRAY}Проект развивается благодаря вашей поддержке\n    https://github.com/DanteFuaran${NC}"

        local -a items=() actions=()
        local _rw_label="📦  Remnawave" _bz_label="📊  Beszel" _mt_label="📡  MTProto"
        { is_panel_installed || is_node_installed || is_subpage_remote_installed; } \
            && _rw_label="📦  Remnawave ${GREEN}(установлено)${NC}" \
            || _rw_label="📦  Remnawave ${DARKGRAY}(сервис)${NC}"
        is_beszel_installed \
            && _bz_label="📊  Beszel ${GREEN}(установлено)${NC}" \
            || _bz_label="📊  Beszel ${DARKGRAY}(мониторинг)${NC}"
        _mt_installed \
            && _mt_label="📡  MTProto ${GREEN}(установлено)${NC}" \
            || _mt_label="📡  MTProto ${DARKGRAY}(прокси)${NC}"
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
                        ln -sf "${DIR_SCRIPT}dfc-manager.sh" /usr/local/bin/dfc-manager 2>/dev/null || true
                        ln -sf /usr/local/bin/dfc-manager /usr/local/bin/dfc 2>/dev/null || true
                    fi

                    local install_status=""
                    if [ "$has_panel" = true ] && [ "$has_node" = true ] && [ "$has_subpage" = true ]; then
                        install_status="\n${DARKGRAY}   Установлено: ${GREEN}Панель | Подписка | Нода${NC}"
                    elif [ "$has_panel" = true ] && [ "$has_node" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Панель | Нода${NC}"
                    elif [ "$has_panel" = true ] && [ "$has_subpage" = true ]; then
                        install_status="\n${DARKGRAY}   Установлено: ${GREEN}Панель | Подписка${NC}"
                    elif [ "$has_panel" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Панель${NC}"
                    elif [ "$has_node" = true ] && [ "$has_subpage" = true ]; then
                        install_status="\n${DARKGRAY}   Установлено: ${GREEN}Нода | Подписка${NC}"
                    elif [ "$has_node" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Нода${NC}"
                    elif [ "$has_subpage" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Страница подписки${NC}"
                    fi

                    local rw_title="📦 Remnawave (Сервис)${install_status}"
                    local -a rw_items=() rw_actions=()
                    rw_items+=("📦  Установить компоненты");  rw_actions+=("install")
                    if [ "$is_installed" = true ]; then
                        rw_items+=("🔄  Переустановить");      rw_actions+=("reinstall")
                    fi
                    rw_items+=("──────────────────────────────────────"); rw_actions+=("sep")
                    if [ "$is_installed" = true ]; then
                        rw_items+=("▶️   Запустить сервисы");       rw_actions+=("start")
                        rw_items+=("⏹️   Остановить сервисы");      rw_actions+=("stop")
                        rw_items+=("📋  Просмотр логов");           rw_actions+=("logs")
                        rw_items+=("──────────────────────────────────────"); rw_actions+=("sep")
                        rw_items+=("💾  База данных");              rw_actions+=("database")
                        rw_items+=("🔓  Доступ к панели");          rw_actions+=("access")
                        rw_items+=("🎨  Сменить сайт-заглушку");    rw_actions+=("template")
                        rw_items+=("──────────────────────────────────────"); rw_actions+=("sep")
                        rw_items+=("🔄  Обновить панель/ноду");     rw_actions+=("update_components")
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
                                    inst_items+=("🖥️   Панель управления Remnawave"); inst_actions+=("panel_wizard")
                                    inst_items+=("──────────────────────────────────────"); inst_actions+=("sep")
                                else
                                    inst_items+=("➕  Подключить ноду к панели"); inst_actions+=("add_node")
                                fi
                                if ! is_subpage_remote_installed; then
                                    inst_items+=("📄  Страница подписки"); inst_actions+=("subpage")
                                fi
                                if ! is_node_installed; then
                                    inst_items+=("🌐  Нода");               inst_actions+=("node")
                                fi
                                inst_items+=("──────────────────────────────────────"); inst_actions+=("sep")
                                inst_items+=("⬅️   Назад"); inst_actions+=("back")

                                show_arrow_menu "📦  Выберите тип установки" "${inst_items[@]}"
                                local install_choice=$?
                                [[ $install_choice -eq 255 ]] && break
                                local inst_action="${inst_actions[$install_choice]:-back}"
                                case "$inst_action" in
                                    panel_wizard)
                                        while true; do
                                            tput civis 2>/dev/null || true
                                            show_arrow_menu "📄  Установка страницы подписки" \
                                                "✔️   Установить на этот сервер (рекомендуется)" \
                                                "❌  Установлю на отдельный сервер" \
                                                "──────────────────────────────────────" \
                                                "⬅️   Назад"
                                            local sub_choice=$?
                                            [[ $sub_choice -eq 255 || $sub_choice -eq 3 ]] && break
                                            local with_subpage=true
                                            [[ $sub_choice -eq 1 ]] && with_subpage=false

                                            show_arrow_menu "🌐  Установка ноды" \
                                                "✔️   Установить на этот сервер" \
                                                "❌  Установлю на отдельный сервер (рекомендуется)" \
                                                "──────────────────────────────────────" \
                                                "⬅️   Назад"
                                            local node_choice=$?
                                            [[ $node_choice -eq 255 || $node_choice -eq 3 ]] && continue
                                            local with_node=false
                                            [[ $node_choice -eq 0 ]] && with_node=true

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
                                    subpage)    installation_subpage || break ;;
                                    node)       installation_node  || break ;;
                                    add_node)   installation_node_local || break ;;
                                    *) break ;;
                                esac
                            done ;;
                        reinstall)         manage_reinstall ;;
                        start)             manage_start ;;
                        stop)              manage_stop ;;
                        logs)              manage_logs ;;
                        database)          manage_database ;;
                        access)            manage_panel_access ;;
                        template)          manage_random_template ;;
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
