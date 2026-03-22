# ═══════════════════════════════════════════════
# ОБНОВЛЕНИЕ И УДАЛЕНИЕ СКРИПТА
# ═══════════════════════════════════════════════

install_script() {
    mkdir -p "${DIR_SCRIPT}"

    cleanup_old_aliases

    # Уже установлен — только актуализируем симлинки
    if [ -d "${DIR_SCRIPT}lib" ]; then
        chmod +x "${DIR_SCRIPT}dfc-manager.sh"
        ln -sf "${DIR_SCRIPT}dfc-manager.sh" /usr/local/bin/dfc-manager
        ln -sf /usr/local/bin/dfc-manager /usr/local/bin/dfc
        return
    fi

    # Первичная установка — скачиваем полный архив (ветка берётся из $SCRIPT_BRANCH → version-файл)
    if ! curl -sL --connect-timeout 15 --max-time 120 "https://github.com/DanteFuaran/dfc-manager/archive/refs/heads/${SCRIPT_BRANCH}.tar.gz" \
        | tar -xz -C "${DIR_SCRIPT}" --strip-components=1; then
        echo -e "${RED}✖ Не удалось скачать скрипт${NC}"
        exit 1
    fi

    chmod +x "${DIR_SCRIPT}dfc-manager.sh"
    ln -sf "${DIR_SCRIPT}dfc-manager.sh" /usr/local/bin/dfc-manager
    ln -sf /usr/local/bin/dfc-manager /usr/local/bin/dfc
}

update_script() {
    local force_update="${1:-}"
    clear
    printf "\033[1;34m══════════════════════════════════════\033[0m\n"
    printf "\033[32m        🔄  Обновление скрипта\033[0m\n"
    printf "\033[1;34m══════════════════════════════════════\033[0m\n"
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

    printf "\033[37mУстановленная версия: v%s\033[0m\n" "$installed_version"

    if [ -n "$remote_version" ] && [ "$remote_version" != "$installed_version" ]; then
        printf "\033[37mДоступная версия:     \033[32mv%s\033[0m\n" "$remote_version"
    elif [ -n "$remote_version" ]; then
        printf "\033[37mДоступная версия:     v%s\033[0m\n" "$remote_version"
    else
        # Нет кеша и сеть недоступна — показываем установленную версию как актуальную
        remote_version="$installed_version"
        printf "\033[37mДоступная версия:     v%s\033[0m\n" "$remote_version"
    fi
    echo
    printf "\033[1;30m──────────────────────────────────────\033[0m\n"

    if [ "$force_update" != "force" ] && [ "$installed_version" = "$remote_version" ]; then
        echo
        print_success "У вас уже установлена последняя версия"
        echo
        printf "\033[1;34m══════════════════════════════════════\033[0m\n"
        show_continue_prompt
        return 0
    fi

    printf "\033[1;30m \033[1;34mEnter\033[1;30m: Обновить     \033[1;34mEsc\033[1;30m: Отмена\033[0m\n"
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
        rm -rf "${DIR_SCRIPT}"
        mkdir -p "$(dirname "${DIR_SCRIPT%/}")"
        git clone --depth 1 -b "${SCRIPT_BRANCH}" "${SCRIPT_REPO}" "${DIR_SCRIPT%/}" >/dev/null 2>&1
        chmod +x "${DIR_SCRIPT}dfc-manager.sh"
        ln -sf "${DIR_SCRIPT}dfc-manager.sh" /usr/local/bin/dfc-manager
        ln -sf /usr/local/bin/dfc-manager /usr/local/bin/dfc
    ) &
    show_spinner "Загрузка обновлений"

    if [ -f "${DIR_SCRIPT}dfc-manager.sh" ]; then
        # Гарантируем наличие version файла (в директории скрипта)
        if [ ! -f "${DIR_SCRIPT}version" ] || ! grep -q '^version:' "${DIR_SCRIPT}version" 2>/dev/null; then
            printf 'version: %s\nbranch: %s\nrepo: %s\n' \
                "${remote_version}" "${SCRIPT_BRANCH}" "${SCRIPT_REPO}" \
                > "${DIR_SCRIPT}version"
        fi
        # Копируем version файл в директорию панели (рядом с .env)
        if [ -d "${DIR_PANEL}" ]; then
            cp -f "${DIR_SCRIPT}version" "${DIR_PANEL}version" 2>/dev/null || true
        fi
        rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
        print_success "Скрипт успешно обновлён до версии v$remote_version"
        echo
        printf "\033[1;34m══════════════════════════════════════\033[0m\n"
        show_continue_prompt || return 0
        exec /usr/local/bin/dfc-manager
    else
        print_error "Ошибка при обновлении скрипта"
        echo
        printf "\033[1;34m══════════════════════════════════════\033[0m\n"
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

    # Beszel Hub
    if [ -f "/opt/beszel/docker-compose.yml" ]; then
        (
            cd /opt/beszel 2>/dev/null
            docker compose down -v --rmi all >/dev/null 2>&1 || true
            local NGINX_CONF="/opt/remnawave/nginx.conf"
            local DOCKER_COMPOSE_DEL="/opt/remnawave/docker-compose.yml"
            [ -f "$NGINX_CONF" ] && sed -i '/# >>> BESZEL/,/# <<< BESZEL/d' "$NGINX_CONF"
            [ -f "$DOCKER_COMPOSE_DEL" ] && sed -i '/# beszel-cert$/d' "$DOCKER_COMPOSE_DEL"
        ) &
        show_spinner "Удаление Beszel"
        rm -rf /opt/beszel
    fi

    # Beszel Agent
    if [ -f "/opt/beszel-agent/docker-compose.yml" ]; then
        local AGENT_PORT
        AGENT_PORT=$(cat /opt/beszel-agent/port 2>/dev/null)
        (
            cd /opt/beszel-agent 2>/dev/null
            docker compose down -v --rmi all >/dev/null 2>&1 || true
        ) &
        show_spinner "Удаление агента Beszel"
        [ -n "$AGENT_PORT" ] && ufw delete allow "${AGENT_PORT}/tcp" >/dev/null 2>&1 || true
        rm -rf /opt/beszel-agent
    fi

    # WARP
    if ip link show warp >/dev/null 2>&1; then
        (
            wg-quick down warp >/dev/null 2>&1 || true
            systemctl disable wg-quick@warp >/dev/null 2>&1 || true
            rm -f /etc/wireguard/warp.conf /usr/local/bin/wgcf \
                  /tmp/wgcf-account.toml /tmp/wgcf-profile.conf 2>/dev/null || true
            DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y wireguard >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
        ) &
        show_spinner "Удаление WARP"
        local WARP_PORT
        WARP_PORT=$(cat /etc/wireguard/.warp_port 2>/dev/null)
        [ -n "$WARP_PORT" ] && ufw delete allow "${WARP_PORT}/tcp" >/dev/null 2>&1 || true
        rm -f /etc/wireguard/.warp_port 2>/dev/null || true
    fi

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        (
            ufw disable >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get purge -y ufw >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
        ) &
        show_spinner "Удаление UFW"
    fi

    # Remnawave
    (
        [ -d "${DIR_PANEL}" ] && cd "${DIR_PANEL}" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        [ -d "/opt/remnasubpage" ] && cd "/opt/remnasubpage" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        [ -d "${DIR_NODE}" ] && cd "${DIR_NODE}" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        docker system prune -af >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление контейнеров Remnawave"
    rm -rf "${DIR_PANEL}"
    rm -rf "/opt/remnasubpage"
    rm -rf "${DIR_NODE}"
    rm -f /usr/local/bin/dfc-manager
    rm -f /usr/local/bin/dfc
    rm -rf "${DIR_SCRIPT}"
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

    rm -f /usr/local/bin/dfc-manager
    rm -f /usr/local/bin/dfc
    rm -rf "${DIR_SCRIPT}"
    rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
    cleanup_old_aliases
    echo
    print_success "Скрипт удалён с сервера"
    echo
    exit 0
}
