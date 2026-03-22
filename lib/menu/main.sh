# ═══════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════

main_menu() {
    alias rw="/usr/local/bin/remnawave" 2>/dev/null || true

    while true; do
        local menu_title="      🛠️  DFC Manager v$SCRIPT_VERSION\n${DARKGRAY}Проект развивается благодаря вашей поддержке\n    https://github.com/DanteFuaran${NC}"

        local -a items=() actions=()
        items+=("📦  Remnawave (Сервис)");         actions+=("remnawave")
        items+=("📊  Beszel (Мониторинг)");         actions+=("beszel")
        items+=("📡  MTProto (Прокси)");            actions+=("mtproto")
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("🧩  Дополнительные программы");   actions+=("extra")
        items+=("🧪  Тестирование сервера");         actions+=("testing")
        items+=("⚙️   Оптимизация сервера");          actions+=("optimization")
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
                    local has_panel=false has_node=false has_subpage=false
                    is_panel_installed && has_panel=true
                    is_node_installed  && has_node=true
                    is_subpage_remote_installed && has_subpage=true
                    local is_installed=false
                    { [ "$has_panel" = true ] || [ "$has_node" = true ] || [ "$has_subpage" = true ]; } && is_installed=true

                    if [ "$is_installed" = true ]; then
                        ln -sf "${DIR_REMNAWAVE}dfc-remna-install.sh" /usr/local/bin/remnawave 2>/dev/null || true
                        ln -sf /usr/local/bin/remnawave /usr/local/bin/rw 2>/dev/null || true
                    else
                        rm -f /usr/local/bin/remnawave /usr/local/bin/rw 2>/dev/null || true
                    fi

                    local update_notice="" install_status=""
                    if [ "$has_panel" = true ] && [ "$has_node" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Панель и Нода${NC}"
                    elif [ "$has_panel" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Панель${NC}"
                    elif [ "$has_node" = true ] && [ "$has_subpage" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Нода и Страница подписки${NC}"
                    elif [ "$has_node" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Нода${NC}"
                    elif [ "$has_subpage" = true ]; then
                        install_status="\n${DARKGRAY}    Установлено: ${GREEN}Страница подписки${NC}"
                    fi
                    if [ -f "${UPDATE_AVAILABLE_FILE}" ]; then
                        local new_version
                        new_version=$(cat "${UPDATE_AVAILABLE_FILE}")
                        update_notice=" ${YELLOW}(Доступно обновление до v$new_version)${NC}"
                    fi

                    local rw_title="    📦 Remnawave (Сервис)${install_status}"
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
                        rw_items+=("🔄  Обновить скрипт$update_notice"); rw_actions+=("update_script")
                        rw_items+=("──────────────────────────────────────"); rw_actions+=("sep")
                        rw_items+=("🗑️   Удаление компонентов");    rw_actions+=("remove")
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
                                local -a inst_items=() inst_actions=()
                                if ! is_panel_installed; then
                                    inst_items+=("🖥️   Панель управления Remnawave"); inst_actions+=("panel_wizard")
                                    inst_items+=("──────────────────────────────────────"); inst_actions+=("sep")
                                fi
                                inst_items+=("📄  Страница подписки"); inst_actions+=("subpage")
                                inst_items+=("🌐  Нода");               inst_actions+=("node")
                                inst_items+=("──────────────────────────────────────"); inst_actions+=("sep")
                                inst_items+=("⬅️   Назад"); inst_actions+=("back")

                                show_arrow_menu "📦  Выберите тип установки" "${inst_items[@]}"
                                local install_choice=$?
                                [[ $install_choice -eq 255 ]] && break
                                local inst_action="${inst_actions[$install_choice]:-back}"
                                case "$inst_action" in
                                    panel_wizard)
                                        while true; do
                                            show_arrow_menu "📄  Установка страницы подписки" \
                                                "✔️   Да, установить на этот сервер" \
                                                "❌  Нет, установлю на отдельный сервер" \
                                                "──────────────────────────────────────" \
                                                "⬅️   Назад"
                                            local sub_choice=$?
                                            [[ $sub_choice -eq 255 || $sub_choice -eq 3 ]] && break
                                            local with_subpage=true
                                            [[ $sub_choice -eq 1 ]] && with_subpage=false

                                            show_arrow_menu "🌐  Установка ноды" \
                                                "✔️   Да, установить на этот сервер" \
                                                "❌  Нет, установлю на отдельный сервер" \
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
                        update_script)     update_script ;;
                        remove)
                            local -a del_items=() del_actions=()
                            if [ "$is_installed" = true ]; then
                                del_items+=("💣  Удалить скрипт и все данные Remnawave"); del_actions+=("remove_all")
                            fi
                            del_items+=("🗑️   Удалить скрипт с сервера"); del_actions+=("remove_script")
                            del_items+=("──────────────────────────────────────");        del_actions+=("sep")
                            del_items+=("⬅️   Назад");                                      del_actions+=("back")

                            show_arrow_menu "🗑️  Удаление компонентов" "${del_items[@]}"
                            local del_choice=$?
                            local del_action="${del_actions[$del_choice]:-back}"
                            case "$del_action" in
                                remove_all)    remove_script_all ;;
                                remove_script) remove_script ;;
                                *) continue ;;
                            esac ;;
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
            sep)          continue ;;
            exit)         cleanup_terminal; clear; cleanup_uninstalled; exit 0 ;;
            *)            continue ;;
        esac
    done
}
