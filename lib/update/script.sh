# ═══════════════════════════════════════════════
# ОБНОВЛЕНИЕ И УДАЛЕНИЕ СКРИПТА
# ═══════════════════════════════════════════════

install_script() {
    mkdir -p "${DIR_REMNAWAVE}"

    cleanup_old_aliases

    # Уже установлен — только актуализируем симлинки
    if [ -d "${DIR_REMNAWAVE}lib" ]; then
        chmod +x "${DIR_REMNAWAVE}dfc-remna-install.sh"
        ln -sf "${DIR_REMNAWAVE}dfc-remna-install.sh" /usr/local/bin/dfc-remna-install
        ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri
        return
    fi

    # Первичная установка — скачиваем полный архив
    if ! curl -sL --connect-timeout 15 --max-time 120 "https://github.com/DanteFuaran/dfc-remna-install/archive/refs/heads/main.tar.gz" \
        | tar -xz -C "${DIR_REMNAWAVE}" --strip-components=1; then
        echo -e "${RED}✖ Не удалось скачать скрипт${NC}"
        exit 1
    fi

    chmod +x "${DIR_REMNAWAVE}dfc-remna-install.sh"
    ln -sf "${DIR_REMNAWAVE}dfc-remna-install.sh" /usr/local/bin/dfc-remna-install
    ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri
}

update_script() {
    local force_update="${1:-}"
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}        🔄  Обновление скрипта${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local installed_version="${SCRIPT_VERSION}"

    # Читаем версию из кэша, который уже записал check_for_updates при запуске
    # Если файла нет — делаем свежий запрос к сети
    local remote_version
    if [ -f "${UPDATE_AVAILABLE_FILE}" ]; then
        remote_version=$(cat "${UPDATE_AVAILABLE_FILE}")
    else
        remote_version=$(get_remote_version)
    fi
    # Если не удалось получить — показываем текущую
    [ -z "$remote_version" ] && remote_version="$installed_version"

    printf "\033[0mУстановленная версия: v%s\n" "$installed_version"

    if [ -n "$remote_version" ] && [ "$remote_version" != "$installed_version" ]; then
        printf "\033[0mДоступная версия:     \033[32mv%s\033[0m\n" "$remote_version"
    elif [ -n "$remote_version" ]; then
        printf "\033[0mДоступная версия:     v%s\n" "$remote_version"
    else
        # Нет кеша и сеть недоступна — показываем установленную версию как актуальную
        remote_version="$installed_version"
        printf "\033[0mДоступная версия:     v%s\n" "$remote_version"
    fi
    
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"

    if [ "$force_update" != "force" ] && [ "$installed_version" = "$remote_version" ]; then
        echo
        print_success "У вас уже установлена последняя версия"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt
        return 0
    fi

    echo -e "${DARKGRAY} ${BLUE}Enter${DARKGRAY}: Обновить     ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
    # Сбрасываем буфер stdin — чтобы Enter из меню не засчитался как подтверждение
    read -s -r -t 0.1 _flush 2>/dev/null || true
    tput civis
    local _key
    while true; do
        read -s -n 1 _key
        if [[ "$_key" == $'\x1b' ]]; then
            tput cnorm
            return 0
        elif [[ "$_key" == "" ]]; then
            tput cnorm
            # Возвращаемся на строку навигации и очищаем её
            tput cuu1
            printf "\033[K\n"
            break
        fi
    done

    (
        rm -rf "${DIR_REMNAWAVE}"
        mkdir -p "$(dirname "${DIR_REMNAWAVE%/}")"
        git clone --depth 1 -b main "https://github.com/DanteFuaran/dfc-remna-install.git" "${DIR_REMNAWAVE%/}" >/dev/null 2>&1
        chmod +x "${DIR_REMNAWAVE}dfc-remna-install.sh"
        ln -sf "${DIR_REMNAWAVE}dfc-remna-install.sh" /usr/local/bin/dfc-remna-install
        ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri
    ) &
    show_spinner "Загрузка обновлений"

    if [ -f "${DIR_REMNAWAVE}dfc-remna-install.sh" ]; then
        rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
        print_success "Скрипт успешно обновлён до версии v$remote_version"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 0
        exec /usr/local/bin/dfc-remna-install
    else
        print_error "Ошибка при обновлении скрипта"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt
        return 1
    fi
}

remove_script_all() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   💣 УДАЛЕНИЕ СКРИПТА И ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    echo -e "${RED}⚠️  ВСЕ ДАННЫЕ REMNAWAVE БУДУТ УДАЛЕНЫ!${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if ! confirm_action; then
        return 1
    fi

    echo
    (
        cd "${DIR_PANEL}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
        docker system prune -af >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление контейнеров"
    rm -rf "${DIR_PANEL}"
    rm -rf "${DIR_NODE}"
    rm -f /usr/local/bin/dfc-remna-install
    rm -f /usr/local/bin/dfc-ri
    rm -rf "${DIR_REMNAWAVE}"
    rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
    cleanup_old_aliases
    print_success "Скрипт и все данные удалены"
    echo
    exit 0
}

remove_script() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🗑️   УДАЛЕНИЕ СКРИПТА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    echo -e "${YELLOW}⚠️  Данные скрипта будут удалены.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if ! confirm_action; then
        return
    fi

    rm -f /usr/local/bin/dfc-remna-install
    rm -f /usr/local/bin/dfc-ri
    rm -rf "${DIR_REMNAWAVE}"
    rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
    cleanup_old_aliases
    echo
    print_success "Скрипт удалён с сервера"
    echo
    exit 0
}
