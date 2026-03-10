# ═══════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════

main_menu() {
    alias dfc-ri="/usr/local/bin/dfc-remna-install" 2>/dev/null || true

    while true; do
        local has_panel=false
        local has_node=false
        is_panel_installed && has_panel=true
        is_node_installed  && has_node=true
        local is_installed=false
        { [ "$has_panel" = true ] || [ "$has_node" = true ]; } && is_installed=true

        # Заголовок
        local update_notice=""
        local install_status=""
        if [ "$has_panel" = true ] && [ "$has_node" = true ]; then
            install_status="\n${DARKGRAY}    Установлено: ${GREEN}Панель и Нода${NC}"
        elif [ "$has_panel" = true ]; then
            install_status="\n${DARKGRAY}    Установлено: ${GREEN}Панель${NC}"
        elif [ "$has_node" = true ]; then
            install_status="\n${DARKGRAY}    Установлено: ${GREEN}Нода${NC}"
        fi
        local menu_title="    🚀 DFC REMNA-INSTALL v$SCRIPT_VERSION${install_status}\n${DARKGRAY}Проект развивается благодаря вашей поддержке\n    https://github.com/DanteFuaran${NC}"
        if [ -f "${UPDATE_AVAILABLE_FILE}" ]; then
            local new_version
            new_version=$(cat "${UPDATE_AVAILABLE_FILE}")
            update_notice=" ${YELLOW}(Доступно обновление до v$new_version)${NC}"
        fi

        # Динамическое построение меню
        local -a items=()
        local -a actions=()

        items+=("📦  Установить компоненты");  actions+=("install")
        if [ "$is_installed" = true ]; then
            items+=("🔄  Переустановить");      actions+=("reinstall")
        fi
        items+=("──────────────────────────────────────"); actions+=("sep")

        if [ "$is_installed" = true ]; then
            items+=("▶️   Запустить сервисы");       actions+=("start")
            items+=("⏹️   Остановить сервисы");      actions+=("stop")
            items+=("📋  Просмотр логов");            actions+=("logs")
            items+=("──────────────────────────────────────"); actions+=("sep")
            items+=("💾  База данных");               actions+=("database")
            items+=("🔓  Доступ к панели");           actions+=("access")
            items+=("🎨  Сменить сайт-заглушку");     actions+=("template")
            items+=("──────────────────────────────────────"); actions+=("sep")
        fi

        items+=("⚙️   Дополнительные настройки"); actions+=("extra")
        items+=("──────────────────────────────────────"); actions+=("sep")

        if [ "$is_installed" = true ]; then
            items+=("🔄  Обновить панель/ноду");    actions+=("update_components")
        fi
        items+=("🔄  Обновить скрипт$update_notice"); actions+=("update_script")
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("🗑️   Удаление компонентов");        actions+=("remove")
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("❌  Выход");                         actions+=("exit")

        MENU_ESC_LABEL="Выход"
        show_arrow_menu "$menu_title" "${items[@]}"
        local choice=$?
        unset MENU_ESC_LABEL
        [[ $choice -eq 255 ]] && { cleanup_terminal; clear; exit 0; }
        local action="${actions[$choice]:-}"

        case "$action" in
            install)
                while true; do
                    local -a inst_items=() inst_actions=()
                    if ! is_panel_installed && ! is_node_installed; then
                        inst_items+=("📦  Панель + Нода (один сервер)"); inst_actions+=("full")
                        inst_items+=("──────────────────────────────────────"); inst_actions+=("sep")
                    fi
                    if ! is_panel_installed; then
                        inst_items+=("🖥️   Только панель"); inst_actions+=("panel")
                    fi
                    inst_items+=("🌐  Только нода");    inst_actions+=("node")
                    if is_panel_installed; then
                        inst_items+=("➕  Подключить ноду в панель"); inst_actions+=("add_node")
                    fi
                    inst_items+=("──────────────────────────────────────"); inst_actions+=("sep")
                    inst_items+=("❌  Назад"); inst_actions+=("back")

                    show_arrow_menu "📦  Выберите тип установки" "${inst_items[@]}"
                    local install_choice=$?
                    [[ $install_choice -eq 255 ]] && break
                    local inst_action="${inst_actions[$install_choice]:-back}"
                    case "$inst_action" in
                        full)  installation_full  || break ;;
                        panel) installation_panel || break ;;
                        node)  installation_node  || break ;;
                        add_node) add_node_to_panel || break ;;
                        *) break ;;
                    esac
                done ;;
            reinstall)        manage_reinstall ;;
            start)            manage_start ;;
            stop)             manage_stop ;;
            logs)             manage_logs ;;
            database)         manage_database ;;
            access)           manage_panel_access ;;
            template)         manage_random_template ;;
            extra)            manage_extra_settings ;;
            update_components) manage_update ;;
            update_script)    update_script ;;
            remove)
                # Удаление — разное меню в зависимости от установки
                local -a del_items=()
                local -a del_actions=()
                if [ "$is_installed" = true ]; then
                    del_items+=("💣  Удалить скрипт и все данные Remnawave"); del_actions+=("remove_all")
                fi
                del_items+=("🗑️   Удалить скрипт с сервера"); del_actions+=("remove_script")
                del_items+=("──────────────────────────────────────");        del_actions+=("sep")
                del_items+=("❌  Назад");                                      del_actions+=("back")

                show_arrow_menu "🗑️  Удаление компонентов" "${del_items[@]}"
                local del_choice=$?
                local del_action="${del_actions[$del_choice]:-back}"
                case "$del_action" in
                    remove_all)    remove_script_all ;;
                    remove_script) remove_script ;;
                    *) continue ;;
                esac ;;
            sep)    continue ;;
            exit)   cleanup_terminal; clear; exit 0 ;;
            *)      continue ;;
        esac
    done
}
