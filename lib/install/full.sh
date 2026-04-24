# ═══════════════════════════════════════════════
# УСТАНОВКА: ПАНЕЛЬ + НОДА
# ═══════════════════════════════════════════════

# Удаляет каталог, только если он существует и пустой (без rm -rf чужих данных).
_install_rmdir_if_empty() {
    local d="${1:-}"
    [ -z "$d" ] && return 0
    d="${d%/}"
    [ -d "$d" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ] && rmdir "$d" 2>/dev/null || true
}

# Откат первичной установки «панель + …»: панель целиком; нода/подписка — только если пустые
# (раньше mkdir -p оставлял пустые /opt/remnanode и /opt/subscribe-page при Ctrl+C).
_install_abort_fresh_panel_extras() {
    rm -rf "${DIR_PANEL}" 2>/dev/null
    _install_rmdir_if_empty "${DIR_NODE}"
    _install_rmdir_if_empty "${DIR_SUB}"
}

installation_full() {
    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Проверяем, не установлено ли уже
    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        print_warning "REMNAWAVE УЖЕ УСТАНОВЛЕН"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}На этом сервере уже установлен Remnawave.${NC}"
        echo -e "${WHITE}Используйте опцию ${GREEN}"🔄 Переустановить"${WHITE} в главном меню.${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi

    # Проверяем, это первичная установка?
    local is_fresh_install=false
    if [ ! -d "${DIR_PANEL}" ] || [ -z "$(ls -A "${DIR_PANEL}" 2>/dev/null)" ]; then
        is_fresh_install=true
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "$(center "📦 Установка панели, подписки и ноды" "$BLUE")"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    mkdir -p "${DIR_PANEL}" "${DIR_PANEL}/backups" && cd "${DIR_PANEL}"

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap '_install_abort_fresh_panel_extras; handle_interrupt' INT TERM
    fi

    # Домены
    prompt_domain_with_retry "Домен панели ${DARKGRAY}(например panel.example.com)${DARKGRAY}:${YELLOW}" PANEL_DOMAIN || { [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras; return; }
    prompt_domain_with_retry "Домен подписки ${DARKGRAY}(например sub.example.com)${DARKGRAY}:${YELLOW}" SUB_DOMAIN true || { [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras; return; }
    prompt_domain_with_retry "Домен ноды ${DARKGRAY}(например node.example.com)${DARKGRAY}:${YELLOW}" SELFSTEAL_DOMAIN true || { [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras; return; }

    # Автогенерация учётных данных администратора
    local SUPERADMIN_USERNAME
    local SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    # Название ноды
    local entity_name=""
    while true; do
        reading "Название ноды (Пример: Germany):" entity_name || { [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras; return; }
        if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
            if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                break
            else
                print_error "Название должно быть от 3 до 20 символов"
            fi
        else
            print_error "Допустимы только символы: a-zA-Z0-9 и дефис"
        fi
    done
    echo

    # Сертификаты
    declare -A domains_to_check
    domains_to_check["$PANEL_DOMAIN"]=1
    domains_to_check["$SUB_DOMAIN"]=1
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    local needs_certs=false
    if check_if_certificates_needed domains_to_check; then
        needs_certs=true
        echo
        show_arrow_menu "🔐 Метод получения сертификатов" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return

        case $cert_choice in
            0) CERT_METHOD=2 ;;
            1) CERT_METHOD=1 ;;
            2) : ;;
            3) return ;;
        esac

        reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        [[ $? -eq 2 ]] && return
        echo

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi
    else
        CERT_METHOD=$(detect_cert_method "$PANEL_DOMAIN")
        echo
        for domain in "${!domains_to_check[@]}"; do
            print_cert_exists "$domain"
        done
    fi

    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    if [ "$needs_certs" = true ]; then
        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras
            read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
            echo
            return
        fi
    fi

    # Определяем домены сертификатов
    local PANEL_CERT_DOMAIN SUB_CERT_DOMAIN NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        PANEL_CERT_DOMAIN=$(extract_domain "$PANEL_DOMAIN")
        SUB_CERT_DOMAIN=$(extract_domain "$SUB_DOMAIN")
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        PANEL_CERT_DOMAIN="$PANEL_DOMAIN"
        SUB_CERT_DOMAIN="$SUB_DOMAIN"
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # Копируем сертификаты в /opt/nginx/ssl/
    ensure_nginx
    nginx_copy_cert "$PANEL_CERT_DOMAIN" 2>/dev/null || true
    nginx_copy_cert "$SUB_CERT_DOMAIN" 2>/dev/null || true
    nginx_copy_cert "$NODE_CERT_DOMAIN" 2>/dev/null || true

    # Генерируем конфиги

    # Генерируем cookie для защиты панели
    local COOKIE_NAME COOKIE_VALUE
    COOKIE_NAME=$(generate_cookie_key)
    COOKIE_VALUE=$(generate_cookie_key)

    # Подсеть docker-сети панели (источник трафика к ноде на хосте, порт 2222)
    local network_info network_subnet
    network_info=$(get_remnawave_network_info)
    network_subnet=$(echo "$network_info" | awk '{print $2}')

    # Публичный IP сервера: при обращении панели к ноде по публичному адресу Docker
    # может подменить источник на этот IP (hairpin/SNAT) — отдельное правило для 2222.
    # Подсеть remnawave-network уже покрывает gateway и все контейнеры панели.
    local server_public_ip
    server_public_ip=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || \
                       curl -s4 --max-time 5 api.ipify.org 2>/dev/null || \
                       hostname -I | awk '{print $1}')

    local NODE_LISTEN_PORT=2222
    if ! prompt_remnanode_listen_port NODE_LISTEN_PORT 2222; then
        echo
        show_continue_prompt || true
        return
    fi

    local NODE_INBOUND_PORT=8443
    if ! prompt_host_inbound_port NODE_INBOUND_PORT 8443; then
        echo
        show_continue_prompt || true
        return
    fi

    (
        generate_env_file "$PANEL_DOMAIN" "$SUB_DOMAIN"
        generate_docker_compose_full "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN" "$NODE_CERT_DOMAIN" "$NODE_LISTEN_PORT"
        generate_nginx_conf_full "$PANEL_DOMAIN" "$SUB_DOMAIN" "$SELFSTEAL_DOMAIN" \
            "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN" "$NODE_CERT_DOMAIN" \
            "$COOKIE_NAME" "$COOKIE_VALUE"
    ) &
    show_spinner "Подготовка файлов" || true

    (
        setup_firewall
        ufw allow from "${network_subnet}" to any port "$NODE_LISTEN_PORT" >/dev/null 2>&1 || true
        [ -n "$server_public_ip" ] && ufw allow from "$server_public_ip" to any port "$NODE_LISTEN_PORT" >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        ufw allow "${NODE_INBOUND_PORT}/tcp" >/dev/null 2>&1 || true
    ) &
    show_spinner "Настройка файрвола" || true

    (
        # Удаляем старый том БД если остался от предыдущей установки
        docker volume rm remnawave-db-data 2>/dev/null || true
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1 || true
        sleep 5
    ) &
    show_spinner "Подготовка сервисов" || true

    (nginx_reload) &
    show_spinner "Запуск Nginx" || true

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"
    local node_dir="${DIR_NODE}"
    local sub_dir="${DIR_SUB}"

    if ! show_spinner_until_ready "http://127.0.0.1:3001/health" "Проверка доступности API" 60; then
        print_error "API не отвечает. Проверьте: docker compose -f /opt/remnawave/docker-compose.yml logs"
        echo
        show_continue_prompt || true
        return
    fi

    # ═══════════════════════════════════════════
    # АВТОНАСТРОЙКА: РЕГИСТРАЦИЯ И СОЗДАНИЕ НОДЫ
    # ═══════════════════════════════════════════

    # 1. Регистрация суперадмина → получение токена
    local token
    token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

    # Если register не сработал (панель уже была настроена ранее) — запросить логин/пароль вручную
    if [ -z "$token" ]; then
        echo
        echo -e "${YELLOW}Панель уже содержит суперадмина. Введите существующие данные для входа.${NC}"
        echo
        local _login_username="" _login_password=""
        while [ -z "$token" ]; do
            reading_inline "Введите логин панели:" _login_username
            local _rc=$?; if [[ $_rc -eq 2 ]]; then break; fi
            if [ -z "$_login_username" ]; then continue; fi

            reading_inline "Введите пароль панели:" _login_password
            _rc=$?; if [[ $_rc -eq 2 ]]; then break; fi
            if [ -z "$_login_password" ]; then continue; fi

            local login_response
            login_response=$(make_api_request "POST" "$domain_url/api/auth/login" "" \
                "$(jq -n --arg u "$_login_username" --arg p "$_login_password" '{username: $u, password: $p}')")
            token=$(echo "$login_response" | jq -r '.response.accessToken // empty' 2>/dev/null)

            if [ -z "$token" ] || [ "$token" = "null" ]; then
                token=""
                print_error "Неверный логин или пароль"
                echo
            else
                SUPERADMIN_USERNAME="$_login_username"
                SUPERADMIN_PASSWORD="$_login_password"
            fi
        done
    fi

    if [ -z "$token" ]; then
        print_error "Не удалось получить токен авторизации"
        print_error "Настройте ноду вручную через панель: https://$PANEL_DOMAIN"
        randomhtml
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        print_warning "УСТАНОВКА ЧАСТИЧНО ЗАВЕРШЕНА"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}Панель:${NC}       https://$PANEL_DOMAIN"
        echo -e "${WHITE}Подписка:${NC}     https://$SUB_DOMAIN"
        echo -e "${WHITE}SelfSteal:${NC}    https://$SELFSTEAL_DOMAIN"
        echo
        echo -e "${YELLOW}👤 ЛОГИН:${NC}    ${WHITE}$SUPERADMIN_USERNAME${NC}"
        echo -e "${YELLOW}🔑 ПАРОЛЬ:${NC}   ${WHITE}$SUPERADMIN_PASSWORD${NC}"
        echo
        print_warning "Нода не настроена автоматически. Настройте вручную."
        echo
        print_warning "ОБЯЗАТЕЛЬНО СКОПИРУЙТЕ И СОХРАНИТЕ ЭТИ ДАННЫЕ!"
        echo
        show_continue_prompt || return 1
        return
    fi

    # 2. Получение публичного ключа → SECRET_KEY для ноды
    print_action "Получение публичного ключа панели..."
    get_public_key "$domain_url" "$token" "$node_dir"

    # Проверяем, что SECRET_KEY реально обновлён
    if grep -q 'PUBLIC KEY FROM REMNAWAVE-PANEL' "$node_dir/docker-compose.yml" 2>/dev/null; then
        print_error "Не удалось установить публичный ключ"
        echo
        show_continue_prompt || true
        return
    fi

    # 3. Генерация ключей x25519 (REALITY)
    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")

    if [ -z "$private_key" ]; then
        print_error "Не удалось сгенерировать REALITY ключи"
        echo
        show_continue_prompt || true
        return
    fi

    # 4. Удаление дефолтного config profile
    print_action "Удаление дефолтного конфиг-профиля..."
    delete_config_profile "$domain_url" "$token"

    # 5. Создание config profile с VLESS REALITY
    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result
    config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name" "$NODE_INBOUND_PORT")

    local config_profile_uuid inbound_uuid
    read config_profile_uuid inbound_uuid <<< "$config_result"

    if [ -z "$config_profile_uuid" ] || [ "$config_profile_uuid" = "ERROR" ] || \
       [ -z "$inbound_uuid" ]; then
        print_error "Не удалось создать конфиг-профиль"
        echo
        show_continue_prompt || true
        return
    fi

    # 6. Создание ноды
    if ! create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$SELFSTEAL_DOMAIN" "$entity_name" "$NODE_LISTEN_PORT"; then
        print_error "Не удалось создать ноду"
    fi

    # 7. Создание хоста
    if ! create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$entity_name" "$SELFSTEAL_DOMAIN" "$NODE_INBOUND_PORT"; then
        print_error "Не удалось зарегистрировать хост"
    fi

    # 8. Получение и обновление сквадов
    local squad_uuids
    squad_uuids=$(get_default_squad "$domain_url" "$token")

    if [ -n "$squad_uuids" ]; then
        while IFS= read -r squad_uuid; do
            [ -z "$squad_uuid" ] && continue
            update_squad "$domain_url" "$token" "$squad_uuid" "$inbound_uuid"
        done <<< "$squad_uuids"
    fi

    # 9. Создание API токена для subscription-page
    create_api_token "$domain_url" "$token" "${DIR_PANEL}" >/dev/null 2>&1

    print_success "Обновление конфигураций"

    # 10. Шаблон selfsteal
    randomhtml

    # 11. Перезапуск Docker Compose (с обновлённым docker-compose.yml)
    echo
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1 && sleep 15
    ) &
    show_spinner "Запуск панели" || true

    (cd "${DIR_NODE}" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск ноды" || true

    (cd "${DIR_SUB}" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск страницы подписки" || true

    echo
    (cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1) &
    show_spinner "Запуск сервисов" || true

    # 12. Сброс суперадмина — при первом входе пользователь задаст свои данные
    docker exec -i remnawave-db psql -U postgres -d postgres -c "DELETE FROM admin;" >/dev/null 2>&1

    # Удаляем trap при успешном завершении
    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

    # Итог
    clear
    tput civis 2>/dev/null
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${GREEN}🎉 Установка завершена!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}🔗 Ссылка для входа в панель:${NC}"
    echo -e "${WHITE}https://${PANEL_DOMAIN}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}📋 Команды запуска меню управления:${NC} ${GREEN}rw${NC}, или ${GREEN}dfc${NC}"
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    print_warning "При первом входе в панель произойдет создание администратора."
    echo -e "${YELLOW}   Сбросить данные администратора и куки для входа можно в любое${NC}"
    echo -e "${YELLOW}   время в меню \"🔓  Доступ к панели\".${NC}"
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ═══════════════════════════════════════════════
# УСТАНОВКА: ПАНЕЛЬ + НОДА (без страницы подписки)
# ═══════════════════════════════════════════════

installation_panel_with_node() {
    cd /opt 2>/dev/null || cd / 2>/dev/null

    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        print_warning "REMNAWAVE УЖЕ УСТАНОВЛЕН"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}На этом сервере уже установлен Remnawave.${NC}"
        echo -e "${WHITE}Используйте опцию ${GREEN}"🔄 Переустановить"${WHITE} в главном меню.${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi

    local is_fresh_install=false
    if [ ! -d "${DIR_PANEL}" ] || [ -z "$(ls -A "${DIR_PANEL}" 2>/dev/null)" ]; then
        is_fresh_install=true
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "$(center "📦 Установка панели, подписки и ноды" "$BLUE")"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    mkdir -p "${DIR_PANEL}" "${DIR_PANEL}/backups" && cd "${DIR_PANEL}"

    if [ "$is_fresh_install" = true ]; then
        trap '_install_abort_fresh_panel_extras; handle_interrupt' INT TERM
    fi

    prompt_domain_with_retry "Домен панели ${DARKGRAY}(например panel.example.com)${DARKGRAY}:${YELLOW}" PANEL_DOMAIN || { [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras; return; }

    # Домен подписки для SUB_PUBLIC_DOMAIN — пользователь установит subpage отдельно
    echo
    echo -e "${DARKGRAY}Укажите домен страницы подписки, которая будет${NC}"
    echo -e "${DARKGRAY}установлена на удалённом сервере (для генерации ссылок подписки).${NC}"
    local SUB_DOMAIN=""
    while true; do
        reading "Домен страницы подписки ${DARKGRAY}(например sub.example.com)${DARKGRAY}:${YELLOW}" SUB_DOMAIN || { [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras; return; }
        if [[ "$SUB_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "Введите корректный домен"
        fi
    done

    prompt_domain_with_retry "Домен ноды ${DARKGRAY}(например node.example.com)${DARKGRAY}:${YELLOW}" SELFSTEAL_DOMAIN true || { [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras; return; }

    local SUPERADMIN_USERNAME SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    local entity_name=""
    while true; do
        reading "Название ноды (Пример: Germany):" entity_name || { [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras; return; }
        if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
            if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                break
            else
                print_error "Название должно быть от 3 до 20 символов"
            fi
        else
            print_error "Допустимы только символы: a-zA-Z0-9 и дефис"
        fi
    done
    echo

    declare -A domains_to_check
    domains_to_check["$PANEL_DOMAIN"]=1
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    local needs_certs=false
    if check_if_certificates_needed domains_to_check; then
        needs_certs=true
        echo
        show_arrow_menu "🔐 Метод получения сертификатов" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return
        case $cert_choice in
            0) CERT_METHOD=2 ;;
            1) CERT_METHOD=1 ;;
            2) : ;;
            3) return ;;
        esac
        reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        [[ $? -eq 2 ]] && return
        echo
        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi
    else
        CERT_METHOD=$(detect_cert_method "$PANEL_DOMAIN")
        echo
        for domain in "${!domains_to_check[@]}"; do
            print_cert_exists "$domain"
        done
    fi

    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    if [ "$needs_certs" = true ]; then
        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            [ "$is_fresh_install" = true ] && _install_abort_fresh_panel_extras
            read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
            echo
            return
        fi
    fi

    local PANEL_CERT_DOMAIN NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        PANEL_CERT_DOMAIN=$(extract_domain "$PANEL_DOMAIN")
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        PANEL_CERT_DOMAIN="$PANEL_DOMAIN"
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # Копируем сертификаты в /opt/nginx/ssl/
    ensure_nginx
    nginx_copy_cert "$PANEL_CERT_DOMAIN" 2>/dev/null || true
    nginx_copy_cert "$NODE_CERT_DOMAIN" 2>/dev/null || true

    local COOKIE_NAME COOKIE_VALUE
    COOKIE_NAME=$(generate_cookie_key)
    COOKIE_VALUE=$(generate_cookie_key)

    local network_info network_subnet
    network_info=$(get_remnawave_network_info)
    network_subnet=$(echo "$network_info" | awk '{print $2}')

    local server_public_ip
    server_public_ip=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || \
                       curl -s4 --max-time 5 api.ipify.org 2>/dev/null || \
                       hostname -I | awk '{print $1}')

    local NODE_LISTEN_PORT=2222
    if ! prompt_remnanode_listen_port NODE_LISTEN_PORT 2222; then
        echo
        show_continue_prompt || true
        return
    fi

    local NODE_INBOUND_PORT=8443
    if ! prompt_host_inbound_port NODE_INBOUND_PORT 8443; then
        echo
        show_continue_prompt || true
        return
    fi

    (
        generate_env_file "$PANEL_DOMAIN" "$SUB_DOMAIN"
        generate_docker_compose_panel_with_node "$PANEL_CERT_DOMAIN" "$NODE_CERT_DOMAIN" "$NODE_LISTEN_PORT"
        generate_nginx_conf_panel_with_node "$PANEL_DOMAIN" "$SELFSTEAL_DOMAIN" \
            "$PANEL_CERT_DOMAIN" "$NODE_CERT_DOMAIN" \
            "$COOKIE_NAME" "$COOKIE_VALUE"
    ) &
    show_spinner "Подготовка файлов" || true

    (
        setup_firewall
        ufw allow from "${network_subnet}" to any port "$NODE_LISTEN_PORT" >/dev/null 2>&1 || true
        [ -n "$server_public_ip" ] && ufw allow from "$server_public_ip" to any port "$NODE_LISTEN_PORT" >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        ufw allow "${NODE_INBOUND_PORT}/tcp" >/dev/null 2>&1 || true
    ) &
    show_spinner "Настройка файрвола" || true

    (
        docker volume rm remnawave-db-data 2>/dev/null || true
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1 || true
        sleep 5
    ) &
    show_spinner "Подготовка сервисов" || true

    (nginx_reload) &
    show_spinner "Запуск Nginx" || true

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"
    local node_dir="${DIR_NODE}"

    if ! show_spinner_until_ready "http://127.0.0.1:3001/health" "Проверка доступности API" 60; then
        print_error "API не отвечает. Проверьте: docker compose -f /opt/remnawave/docker-compose.yml logs"
        echo
        show_continue_prompt || true
        return
    fi

    local token
    token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

    # Если register не сработал (панель уже была настроена ранее) — запросить логин/пароль вручную
    if [ -z "$token" ]; then
        echo
        echo -e "${YELLOW}Панель уже содержит суперадмина. Введите существующие данные для входа.${NC}"
        echo
        local _login_username="" _login_password=""
        while [ -z "$token" ]; do
            reading_inline "Введите логин панели:" _login_username
            local _rc=$?; if [[ $_rc -eq 2 ]]; then break; fi
            if [ -z "$_login_username" ]; then continue; fi

            reading_inline "Введите пароль панели:" _login_password
            _rc=$?; if [[ $_rc -eq 2 ]]; then break; fi
            if [ -z "$_login_password" ]; then continue; fi

            local login_response
            login_response=$(make_api_request "POST" "$domain_url/api/auth/login" "" \
                "$(jq -n --arg u "$_login_username" --arg p "$_login_password" '{username: $u, password: $p}')")
            token=$(echo "$login_response" | jq -r '.response.accessToken // empty' 2>/dev/null)

            if [ -z "$token" ] || [ "$token" = "null" ]; then
                token=""
                print_error "Неверный логин или пароль"
                echo
            else
                SUPERADMIN_USERNAME="$_login_username"
                SUPERADMIN_PASSWORD="$_login_password"
            fi
        done
    fi

    if [ -z "$token" ]; then
        print_error "Не удалось получить токен авторизации"
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        print_warning "УСТАНОВКА ЧАСТИЧНО ЗАВЕРШЕНА"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}🔗 ССЫЛКА ВХОДА В ПАНЕЛЬ:${NC}"
        echo -e "${WHITE}https://${PANEL_DOMAIN}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
        echo
        echo -e "${YELLOW}👤 ЛОГИН:${NC}    ${WHITE}$SUPERADMIN_USERNAME${NC}"
        echo -e "${YELLOW}🔑 ПАРОЛЬ:${NC}   ${WHITE}$SUPERADMIN_PASSWORD${NC}"
        echo
        print_warning "Нода не настроена автоматически. Настройте вручную."
        echo
        print_warning "ОБЯЗАТЕЛЬНО СКОПИРУЙТЕ И СОХРАНИТЕ ЭТИ ДАННЫЕ!"
        echo
        show_continue_prompt || return 1
        return
    fi

    print_action "Получение публичного ключа панели..."
    get_public_key "$domain_url" "$token" "$node_dir"

    if grep -q 'PUBLIC KEY FROM REMNAWAVE-PANEL' "$node_dir/docker-compose.yml" 2>/dev/null; then
        print_error "Не удалось установить публичный ключ"
        echo
        show_continue_prompt || true
        return
    fi

    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")

    if [ -z "$private_key" ]; then
        print_error "Не удалось сгенерировать REALITY ключи"
        echo
        show_continue_prompt || true
        return
    fi

    print_action "Удаление дефолтного конфиг-профиля..."
    delete_config_profile "$domain_url" "$token"

    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result
    config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name" "$NODE_INBOUND_PORT")

    local config_profile_uuid inbound_uuid
    read config_profile_uuid inbound_uuid <<< "$config_result"

    if [ -z "$config_profile_uuid" ] || [ "$config_profile_uuid" = "ERROR" ] || \
       [ -z "$inbound_uuid" ]; then
        print_error "Не удалось создать конфиг-профиль"
        echo
        show_continue_prompt || true
        return
    fi

    if ! create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$SELFSTEAL_DOMAIN" "$entity_name" "$NODE_LISTEN_PORT"; then
        print_error "Не удалось создать ноду"
    fi

    if ! create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$entity_name" "$SELFSTEAL_DOMAIN" "$NODE_INBOUND_PORT"; then
        print_error "Не удалось зарегистрировать хост"
    fi

    local squad_uuids
    squad_uuids=$(get_default_squad "$domain_url" "$token")

    if [ -n "$squad_uuids" ]; then
        while IFS= read -r squad_uuid; do
            [ -z "$squad_uuid" ] && continue
            update_squad "$domain_url" "$token" "$squad_uuid" "$inbound_uuid"
        done <<< "$squad_uuids"
    fi

    create_api_token "$domain_url" "$token" "$target_dir" >/dev/null 2>&1

    print_success "Обновление конфигураций"

    randomhtml

    echo
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1 && sleep 15
    ) &
    show_spinner "Запуск панели" || true

    (cd "${DIR_NODE}" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск ноды" || true

    echo
    (cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1) &
    show_spinner "Запуск сервисов" || true

    docker exec -i remnawave-db psql -U postgres -d postgres -c "DELETE FROM admin;" >/dev/null 2>&1

    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

    clear
    tput civis 2>/dev/null
    local api_token_display
    api_token_display=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${GREEN}🎉 Установка завершена!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}🔗 Ссылка для входа в панель:${NC}"
    echo -e "${WHITE}https://${PANEL_DOMAIN}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}📄 Для установки страницы подписки на удалённом сервере:${NC}"
    echo -e "${WHITE}URL панели:${NC}   https://$PANEL_DOMAIN"
    if [ -n "$api_token_display" ]; then
        echo -e "${WHITE}API токен:${NC}    $api_token_display"
    fi
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}📋 Команды запуска меню управления:${NC} ${GREEN}rw${NC}, или ${GREEN}dfc${NC}"
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    print_warning "При первом входе в панель произойдет создание администратора."
    echo -e "${YELLOW}   Сбросить данные администратора и куки для входа можно в любое${NC}"
    echo -e "${YELLOW}   время в меню \"🔓  Доступ к панели\".${NC}"
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}
