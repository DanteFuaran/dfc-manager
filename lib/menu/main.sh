# ═══════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════

main_menu() {
    alias rw="/usr/local/bin/remnawave" 2>/dev/null || true

    while true; do
        local has_panel=false
        local has_node=false
        local has_subpage=false
        is_panel_installed && has_panel=true
        is_node_installed  && has_node=true
        is_subpage_remote_installed && has_subpage=true
        local is_installed=false
        { [ "$has_panel" = true ] || [ "$has_node" = true ] || [ "$has_subpage" = true ]; } && is_installed=true

        # Управляем симлинками в зависимости от установки
        if [ "$is_installed" = true ]; then
            ln -sf "${DIR_REMNAWAVE}dfc-remna-install.sh" /usr/local/bin/remnawave 2>/dev/null || true
            ln -sf /usr/local/bin/remnawave /usr/local/bin/rw 2>/dev/null || true
        else
            rm -f /usr/local/bin/remnawave /usr/local/bin/rw 2>/dev/null || true
        fi

        # Заголовок
        local update_notice=""
        local install_status=""
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
        local menu_title="    🚀 REMNAWAVE INSTALLER v$SCRIPT_VERSION${install_status}\n${DARKGRAY}Проект развивается благодаря вашей поддержке\n    https://github.com/DanteFuaran${NC}"
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
            items+=("🔓  Доступ к панели");            actions+=("access")
            items+=("🎨  Сменить сайт-заглушку");     actions+=("template")
            items+=("──────────────────────────────────────"); actions+=("sep")
        fi

        items+=("🧩  Дополнительные программы"); actions+=("extra")
        items+=("──────────────────────────────────────"); actions+=("sep")

        if [ "$is_installed" = true ]; then
            items+=("🔄  Обновить панель/ноду");    actions+=("update_components")
        fi
        if [ "$is_installed" = true ]; then
            items+=("🔄  Обновить скрипт$update_notice"); actions+=("update_script")
            items+=("──────────────────────────────────────"); actions+=("sep")
            items+=("🗑️   Удаление компонентов");        actions+=("remove")
            items+=("──────────────────────────────────────"); actions+=("sep")
        fi
        items+=("❌  Выход");                         actions+=("exit")

        MENU_ESC_LABEL="Выход"
        show_arrow_menu "$menu_title" "${items[@]}"
        local choice=$?
        unset MENU_ESC_LABEL
        [[ $choice -eq 255 ]] && { cleanup_terminal; clear; cleanup_uninstalled; exit 0; }
        local action="${actions[$choice]:-}"

        case "$action" in
            install)
                while true; do
                    local -a inst_items=() inst_actions=()
                    if ! is_panel_installed; then
                        inst_items+=("🖥️   Панель"); inst_actions+=("panel_wizard")
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
                            # Шаг 1: страница подписки на этом сервере?
                            show_arrow_menu "📄  Установка страницы подписки" \
                                "✔️   Да, установить на этот сервер" \
                                "❌  Нет, установлю на отдельный сервер" \
                                "──────────────────────────────────────" \
                                "⬅️   Назад"
                            local sub_choice=$?
                            [[ $sub_choice -eq 255 || $sub_choice -eq 3 ]] && continue
                            local with_subpage=true
                            [[ $sub_choice -eq 1 ]] && with_subpage=false

                            # Шаг 2: нода на этом сервере?
                            show_arrow_menu "🌐  Установка ноды" \
                                "🌐  Да, установить на этот сервер" \
                                "🖥️   Нет, установлю на отдельный сервер" \
                                "──────────────────────────────────────" \
                                "⬅️   Назад"
                            local node_choice=$?
                            [[ $node_choice -eq 255 || $node_choice -eq 3 ]] && continue
                            local with_node=false
                            [[ $node_choice -eq 0 ]] && with_node=true

                            # Запуск нужного варианта установки
                            if [ "$with_subpage" = true ] && [ "$with_node" = true ]; then
                                installation_full || break
                            elif [ "$with_subpage" = true ]; then
                                installation_panel true || break
                            elif [ "$with_node" = true ]; then
                                installation_panel_with_node || break
                            else
                                installation_panel false || break
                            fi
                            ;;
                        subpage)    installation_subpage || break ;;
                        node)       installation_node  || break ;;
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
                del_items+=("⬅️   Назад");                                      del_actions+=("back")

                show_arrow_menu "🗑️  Удаление компонентов" "${del_items[@]}"
                local del_choice=$?
                local del_action="${del_actions[$del_choice]:-back}"
                case "$del_action" in
                    remove_all)    remove_script_all ;;
                    remove_script) remove_script ;;
                    *) continue ;;
                esac ;;
            sep)    continue ;;
            exit)   cleanup_terminal; clear; cleanup_uninstalled; exit 0 ;;
            *)      continue ;;
        esac
    done
}
