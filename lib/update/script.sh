# ═══════════════════════════════════════════════
# ОБНОВЛЕНИЕ И УДАЛЕНИЕ СКРИПТА
# ═══════════════════════════════════════════════

# ─── Удаление отдельных компонентов Remnawave ───────────────────────────────

_delete_component_panel() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🗑️  Удаление панели Remnawave${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${RED}⚠️  Все данные панели будут удалены!${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if ! confirm_action; then return; fi
    echo
    (
        cd /opt/remnawave 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление панели Remnawave"
    rm -rf /opt/remnawave

    # Обновляем nginx: минимальный конфиг или удаляем
    nginx_ensure_conf_for_remaining
    nginx_cleanup_unused_certs

    print_success "Панель Remnawave удалена"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || true
}

_delete_component_node() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}    🗑️  Удаление ноды Remnawave${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${RED}⚠️  Все данные ноды будут удалены!${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if ! confirm_action; then return; fi
    echo

    # Извлекаем инфо о sub-page до удаления (для перегенерации nginx.conf)
    local _sub_domain _sub_cert _sub_dir
    if [ -f "/opt/subscribe-page/docker-compose.yml" ]; then
        _sub_dir="/opt/subscribe-page"
    elif [ -f "/opt/remnasubpage/docker-compose.yml" ]; then
        _sub_dir="/opt/remnasubpage"
    fi
    if [ -n "$_sub_dir" ] && [ -f "${DIR_NGINX}nginx.conf" ]; then
        _sub_domain=$(sed -n '/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/{/server_name/{s/.*server_name\s\+//;s/;.*//;p;}}' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
        _sub_cert=$(sed -n '/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/{/ssl_certificate /{s|.*/ssl/||;s|/.*||;p;}}' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
    fi

    (
        cd /opt/remnanode 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление ноды Remnawave"
    rm -rf /opt/remnanode

    # Обновляем nginx: перегенерируем для оставшихся компонентов
    if [ -n "$_sub_dir" ] && [ -n "$_sub_domain" ] && [ -n "$_sub_cert" ]; then
        generate_nginx_conf_subpage "$_sub_domain" "$_sub_cert" "$_sub_dir"
        nginx_reload
    else
        nginx_ensure_conf_for_remaining
    fi
    nginx_cleanup_unused_certs

    print_success "Нода Remnawave удалена"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || true
}

_delete_component_subpage() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}  🗑️  Удаление страницы подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${RED}⚠️  Все данные страницы подписки будут удалены!${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if ! confirm_action; then return; fi
    echo
    echo

    # Извлекаем информацию для перегенерации nginx.conf до удаления
    local _panel_domain _panel_cert _node_domain _node_cert _cookie_name _cookie_value
    if [ -f "${DIR_NGINX}nginx.conf" ]; then
        _panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
        _panel_cert=$(grep -A5 "server_name ${_panel_domain};" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -oP '/ssl/\K[^/]+' | head -1)
        [ -z "$_panel_cert" ] && _panel_cert="$_panel_domain"

        # Извлекаем cookie
        _cookie_name=$(grep -oP '~\*\K[^=]+(?==[^"]+"\s+1)' "${DIR_NGINX}nginx.conf" | head -1)
        _cookie_value=$(grep -oP '~\*[^=]+=\K[^"]+(?="\s+1)' "${DIR_NGINX}nginx.conf" | head -1)

        # Извлекаем инфо о ноде (для перегенерации)
        if [ -f "/opt/remnanode/docker-compose.yml" ]; then
            _node_domain=$(awk '/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/{next} /server_name [^_]/{gsub(/.*server_name[[:space:]]+|;.*/,""); print; exit}' "${DIR_NGINX}nginx.conf" 2>/dev/null)
            _node_cert=$(awk '/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/{next} /ssl_certificate /{gsub(/.*\/ssl\/|\/fullchain.*|\/privkey.*/,""); print; exit}' "${DIR_NGINX}nginx.conf" 2>/dev/null)
        fi
    fi

    # Подготовка файлов: перегенерируем nginx.conf и останавливаем/удаляем subpage
    (
        # Останавливаем и удаляем subpage
        for _d in /opt/remnasubpage /opt/subscribe-page; do
            [ -d "$_d" ] || continue
            [ -f "${_d}/docker-compose.yml" ] && { cd "$_d" 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1 || true; }
            rm -rf "$_d" 2>/dev/null || true
        done

        # Также удаляем subscription-page из docker-compose панели/ноды если он встроен
        if is_panel_installed; then
            cd /opt/remnawave 2>/dev/null && docker compose rm -sf remnawave-subscription-page >/dev/null 2>&1 || true
            # Очищаем SUB_PUBLIC_DOMAIN из .env
            sed -i '/^SUB_PUBLIC_DOMAIN=/d' /opt/remnawave/.env 2>/dev/null || true
        fi
        if [ -f "/opt/remnanode/docker-compose.yml" ]; then
            cd /opt/remnanode 2>/dev/null && docker compose rm -sf remnawave-subscription-page >/dev/null 2>&1 || true
        fi

        # Перегенерируем конфиги для оставшихся компонентов
        if is_panel_installed && [ -n "$_panel_domain" ] && [ -n "$_cookie_name" ] && [ -n "$_cookie_value" ]; then
            if [ -f "/opt/remnanode/docker-compose.yml" ] && [ -n "$_node_domain" ] && [ -n "$_node_cert" ]; then
                # Панель + нода (без subpage)
                generate_docker_compose_panel_with_node "$_panel_cert" "$_node_cert"
                generate_nginx_conf_panel_with_node "$_panel_domain" "$_node_domain" \
                    "$_panel_cert" "$_node_cert" \
                    "$_cookie_name" "$_cookie_value"
            else
                # Только панель (без subpage)
                generate_docker_compose_panel_only "$_panel_cert"
                generate_nginx_conf_panel_only "$_panel_domain" "$_panel_cert" \
                    "$_cookie_name" "$_cookie_value"
            fi
            # Перезапускаем панель с обновлённым docker-compose
            cd /opt/remnawave 2>/dev/null && docker compose up -d >/dev/null 2>&1 || true
            nginx_reload
        elif [ -f "/opt/remnanode/docker-compose.yml" ] && [ -n "$_node_domain" ] && [ -n "$_node_cert" ]; then
            generate_nginx_conf_node "$_node_domain" "$_node_cert"
            cd /opt/remnanode 2>/dev/null && docker compose up -d >/dev/null 2>&1 || true
            nginx_reload
        fi
    ) &
    show_spinner "Подготовка файлов"

    nginx_cleanup_unused_certs

    print_success "Страница подписки удалена"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || true
}

# ─── Меню удаления всех компонентов ─────────────────────────────────────────

manage_delete_components() {
    while true; do
        tput civis 2>/dev/null || true
        local -a del_items=() del_actions=()

        is_panel_installed && {
            del_items+=("🖥️   Remnawave (Панель)"); del_actions+=("panel")
        }
        [ -f "/opt/remnanode/docker-compose.yml" ] && {
            del_items+=("🌐  Remnawave (Нода)"); del_actions+=("node")
        }
        ([ -f "/opt/remnasubpage/docker-compose.yml" ] || [ -f "/opt/subscribe-page/docker-compose.yml" ]) && {
            del_items+=("📄  Remnawave (Страница подписки)"); del_actions+=("subpage")
        }
        [ -f "/opt/beszel/docker-compose.yml" ] && {
            del_items+=("📊  Beszel (Мониторинг)"); del_actions+=("beszel")
        }
        [ -f "/opt/beszel-agent/docker-compose.yml" ] && {
            del_items+=("📊  Beszel (Агент)"); del_actions+=("beszel_agent")
        }
        _mt_installed && {
            del_items+=("📡  MTProto (Прокси)"); del_actions+=("mtproto")
        }

        # Ничего не осталось — показываем экран с сообщением
        if [ ${#del_actions[@]} -eq 0 ]; then
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${RED}   🗑️   Удаление компонентов${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo
            echo -e "  🔍  Компоненты не установлены"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || true
            return
        fi

        del_items+=("──────────────────────────────────────"); del_actions+=("sep")
        if [ ${#del_actions[@]} -gt 1 ]; then
            del_items+=("🗑️   Удалить всё"); del_actions+=("delete_all")
            del_items+=("──────────────────────────────────────"); del_actions+=("sep")
        fi
        del_items+=("⬅️   Назад"); del_actions+=("back")

        show_arrow_menu "🗑️  Удаление компонентов" "${del_items[@]}"
        local del_choice=$?
        [[ $del_choice -eq 255 ]] && return
        local del_action="${del_actions[$del_choice]:-sep}"

        case "$del_action" in
            panel)        _delete_component_panel ;;
            node)         _delete_component_node ;;
            subpage)      _delete_component_subpage ;;
            beszel)       uninstall_beszel ;;
            beszel_agent) uninstall_beszel_agent ;;
            mtproto)      _mt_do_uninstall || true ;;
            delete_all)
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${RED}     🗑️  Удаление всех компонентов${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                echo -e "${RED}⚠️  Удалить все установленные компоненты${NC}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                if ! confirm_action; then continue; fi
                echo
                echo
                if is_panel_installed; then
                    ( cd /opt/remnawave 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1 || true; rm -rf /opt/remnawave 2>/dev/null || true ) &
                    show_spinner "Удаление Remnawave" "Remnawave удалён"
                fi
                if is_node_installed; then
                    ( cd /opt/remnanode 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1 || true; rm -rf /opt/remnanode 2>/dev/null || true ) &
                    show_spinner "Удаление Ноды" "Нода удалена"
                fi
                if is_subpage_remote_installed || [ -d "/opt/subscribe-page" ] || [ -d "/opt/remnasubpage" ]; then
                    ( for _d in /opt/subscribe-page /opt/remnasubpage; do
                        [ -d "$_d" ] || continue
                        [ -f "${_d}/docker-compose.yml" ] && { cd "$_d" 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1 || true; }
                        rm -rf "$_d" 2>/dev/null || true
                      done; exit 0 ) &
                    show_spinner "Удаление Страницы подписки" "Страница подписки удалена"
                fi
                if [ -f "/opt/beszel/docker-compose.yml" ]; then
                    ( uninstall_beszel --force >/dev/null 2>&1 || true ) &
                    show_spinner "Удаление Beszel" "Beszel удалён"
                fi
                if [ -f "/opt/beszel-agent/docker-compose.yml" ]; then
                    ( uninstall_beszel_agent --force >/dev/null 2>&1 || true ) &
                    show_spinner "Удаление Beszel Agent" "Beszel Agent удалён"
                fi
                if _mt_installed; then
                    ( _mt_do_uninstall >/dev/null 2>&1 || true ) &
                    show_spinner "Удаление MTProto" "MTProto удалён"
                fi
                ( nginx_teardown 2>/dev/null || true; nginx_cleanup_unused_certs 2>/dev/null || true ) &
                show_spinner "Удаление Nginx" "Nginx удалён"
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "       ${RED}🗑️  Удаление завершено${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                echo -e "  ${GREEN}✅ Все компоненты были удалены${NC}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || true
                ;;
            back)         return ;;
            sep)          continue ;;
        esac
    done
}

install_script() {
    mkdir -p "${DIR_SCRIPT}"

    cleanup_old_aliases

    # Уже установлен — только актуализируем симлинки
    if [ -d "${DIR_SCRIPT}lib" ]; then
        chmod +x "${DIR_SCRIPT}dfc-manager.sh"
        ln -sf "${DIR_SCRIPT}dfc-manager.sh" /usr/local/bin/dfc-manager
        ln -sf /usr/local/bin/dfc-manager /usr/local/bin/dfc
        ln -sf /usr/local/bin/dfc-manager /usr/local/bin/rw
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
    ln -sf /usr/local/bin/dfc-manager /usr/local/bin/rw
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
        ln -sf /usr/local/bin/dfc-manager /usr/local/bin/rw
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
            nginx_remove_server_block "BESZEL" 2>/dev/null || true
            if nginx_has_users; then
                nginx_reload
            else
                nginx_teardown
            fi
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
        [ -d "/opt/subscribe-page" ] && cd "/opt/subscribe-page" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        [ -d "${DIR_NODE}" ] && cd "${DIR_NODE}" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        docker system prune -af >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление контейнеров Remnawave"
    nginx_teardown
    rm -rf "${DIR_PANEL}"
    rm -rf "/opt/remnasubpage"
    rm -rf "/opt/subscribe-page"
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
