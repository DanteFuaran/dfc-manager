# ═══════════════════════════════════════════════
# УСТАНОВКА: ТОЛЬКО ПАНЕЛЬ
# ═══════════════════════════════════════════════

installation_panel() {
    local with_subpage="${1:-true}"
    local install_completed=false

    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Проверяем, не установлена ли уже панель
    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        print_warning "ПАНЕЛЬ УЖЕ УСТАНОВЛЕНА"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}На этом сервере уже установлена панель.${NC}"
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

    # При отмене первичной установки удаляем и панель, и каталог страницы подписки (если он создавался)
    _abort_fresh_panel_install() {
        [ "$is_fresh_install" != true ] && return 0
        [ "$install_completed" = true ] && return 0
        rm -rf "${DIR_PANEL}" 2>/dev/null || true
        if [ "$with_subpage" = true ]; then
            rm -rf "${DIR_SUB}" 2>/dev/null || true
        fi
    }

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap '_abort_fresh_panel_install; handle_interrupt' INT TERM
    fi

    local cert_choice
    while true; do
    mkdir -p "${DIR_PANEL}" "${DIR_PANEL}/backups" && cd "${DIR_PANEL}"
    [ "$with_subpage" = true ] && mkdir -p "${DIR_SUB}"
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if [ "$with_subpage" = true ]; then
        echo -e "$(center "📦 Установка панели и страницы подписки" "$BLUE")"
    else
        echo -e "$(center "📦 Установка панели" "$BLUE")"
    fi
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    prompt_domain_with_retry "Домен панели ${DARKGRAY}(например panel.example.com)${DARKGRAY}:" PANEL_DOMAIN || { _abort_fresh_panel_install; return; }
    local SUB_DOMAIN=""
    if [ "$with_subpage" = true ]; then
        prompt_domain_with_retry "Домен подписки ${DARKGRAY}(например sub.example.com)${DARKGRAY}:" SUB_DOMAIN true || { rm -rf "${DIR_SUB}" 2>/dev/null || true; continue; }
    else
        local _sub_esc=false
        while true; do
            reading_inline "Домен страницы подписки ${DARKGRAY}(например sub.example.com)${DARKGRAY}:" SUB_DOMAIN
            local _rc=$?
            if [ $_rc -eq 2 ]; then _sub_esc=true; break; fi
            if [[ "$SUB_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                print_error "Введите корректный домен"
            fi
        done
        [ "$_sub_esc" = true ] && continue
    fi

    echo
    echo

    # Автогенерация учётных данных администратора
    local SUPERADMIN_USERNAME
    local SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    unset domains_to_check
    declare -A domains_to_check
    domains_to_check["$PANEL_DOMAIN"]=1
    if [ "$with_subpage" = true ]; then
        domains_to_check["$SUB_DOMAIN"]=1
    fi

    local needs_certs=false
    if check_if_certificates_needed domains_to_check; then
        needs_certs=true
        show_arrow_menu "🔐 Метод получения сертификатов" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "🔷  Gcore DNS-01 (wildcard)" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        cert_choice=$?
        if [[ $cert_choice -eq 255 || $cert_choice -eq 3 || $cert_choice -eq 4 ]]; then
            [ "$with_subpage" = true ] && rm -rf "${DIR_SUB}" 2>/dev/null || true
            continue
        fi

        case $cert_choice in
            0) CERT_METHOD=2 ;;
            1) CERT_METHOD=1 ;;
            2) CERT_METHOD=3 ;;
        esac

        reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        if [[ $? -eq 2 ]]; then
            [ "$with_subpage" = true ] && rm -rf "${DIR_SUB}" 2>/dev/null || true
            continue
        fi
        echo

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || { _abort_fresh_panel_install; return; }
        elif [ "$CERT_METHOD" -eq 3 ]; then
            setup_gcore_credentials || { _abort_fresh_panel_install; return; }
        fi
    else
        CERT_METHOD=$(detect_cert_method "$PANEL_DOMAIN")
        tput cnorm 2>/dev/null || true
        for domain in "${!domains_to_check[@]}"; do
            print_cert_exists "$domain"
        done
    fi
    break
    done

    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    if [ "$needs_certs" = true ]; then
        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            _abort_fresh_panel_install
            read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
            echo
            return
        fi
    fi

    local PANEL_CERT_DOMAIN SUB_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        PANEL_CERT_DOMAIN=$(extract_domain "$PANEL_DOMAIN")
        [ "$with_subpage" = true ] && SUB_CERT_DOMAIN=$(extract_domain "$SUB_DOMAIN")
    else
        PANEL_CERT_DOMAIN="$PANEL_DOMAIN"
        [ "$with_subpage" = true ] && SUB_CERT_DOMAIN="$SUB_DOMAIN"
    fi

    # Копируем сертификаты в /opt/nginx/ssl/
    ensure_nginx
    nginx_copy_cert "$PANEL_CERT_DOMAIN" 2>/dev/null || true
    [ "$with_subpage" = true ] && nginx_copy_cert "$SUB_CERT_DOMAIN" 2>/dev/null || true

    # Генерируем cookie для защиты панели
    local COOKIE_NAME COOKIE_VALUE
    COOKIE_NAME=$(generate_cookie_key)
    COOKIE_VALUE=$(generate_cookie_key)

    (
        generate_env_file "$PANEL_DOMAIN" "$SUB_DOMAIN"
        if [ "$with_subpage" = true ]; then
            generate_docker_compose_panel "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN"
            generate_nginx_conf_panel "$PANEL_DOMAIN" "$SUB_DOMAIN" "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN" \
                "$COOKIE_NAME" "$COOKIE_VALUE"
        else
            generate_docker_compose_panel_only "$PANEL_CERT_DOMAIN"
            generate_nginx_conf_panel_only "$PANEL_DOMAIN" "$PANEL_CERT_DOMAIN" \
                "$COOKIE_NAME" "$COOKIE_VALUE"
        fi
    ) &
    show_spinner "Подготовка файлов" || true

    (setup_firewall) &
    show_spinner "Настройка файрвола" || true

    echo
    (
        # Удаляем старый том БД если остался от предыдущей установки
        docker volume rm remnawave-db-data 2>/dev/null || true
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1 || true
        sleep 5
    ) &
    show_spinner "Запуск сервисов" || true

    (nginx_reload) &
    show_spinner "Запуск Nginx" || true

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"

    if ! show_spinner_until_ready "http://127.0.0.1:3001/health" "Проверка доступности API" 120; then
        print_error "API не отвечает"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || true
        return
    fi

    # ═══════════════════════════════════════════
    # АВТОНАСТРОЙКА: РЕГИСТРАЦИЯ И СОЗДАНИЕ API
    # ═══════════════════════════════════════════
    echo
    print_action "Автонастройка панели..."

    # 1. Регистрация суперадмина → получение токена
    print_action "Регистрация администратора..."
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
        install_completed=true
        print_error "Не удалось получить токен авторизации"
        print_error "Создайте API токен вручную через панель: https://$PANEL_DOMAIN"
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        print_warning "Установка частично завершена"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}🔗 Ссылка входа в панель:${NC}"
        echo -e "${WHITE}https://${PANEL_DOMAIN}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
        echo
        echo -e "${YELLOW}👤 Логин:${NC}    ${WHITE}$SUPERADMIN_USERNAME${NC}"
        echo -e "${YELLOW}🔑 Пароль:${NC}   ${WHITE}$SUPERADMIN_PASSWORD${NC}"
        echo
        print_warning "API токен не создан автоматически. Создайте вручную."
        echo
        print_warning "Обязательно скопируйте и сохраните эти данные!"
        echo
        show_continue_prompt || return 1
        return
    fi

    # 2. Создание API токена для subscription-page
    print_action "Создание API токена для страницы подписки..."
    create_api_token "$domain_url" "$token" "$target_dir"

    if [ "$with_subpage" = true ]; then
        # 3. Перезапуск Docker Compose (с обновлённым docker-compose.yml)
        print_action "Перезапуск сервисов с обновлённой конфигурацией..."
        (
            cd /opt/remnawave
            docker compose down >/dev/null 2>&1
            docker compose up -d >/dev/null 2>&1
        ) &
        show_spinner "Запуск контейнеров" || true

        (cd "${DIR_SUB}" && docker compose up -d >/dev/null 2>&1) &
        show_spinner "Запуск страницы подписки" || true

        (cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1) &
        show_spinner "Перезапуск nginx" || true

        echo
        # Ожидаем готовность после перезапуска
        show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
        tput cnorm 2>/dev/null || true
    fi

    # 4. Сброс суперадмина — при первом входе пользователь задаст свои данные
    print_action "Сброс суперадмина для первого входа..."
    if docker exec -i remnawave-db psql -U postgres -d postgres -c "DELETE FROM admin;" >/dev/null 2>&1; then
        print_success "Суперадмин сброшен"
    else
        print_error "Не удалось сбросить суперадмина"
    fi

    # Финальный экран достигнут: при Ctrl+C только корректно завершаем скрипт
    # через handle_interrupt, без отката уже завершённой установки.
    install_completed=true

    clear
    tput civis 2>/dev/null
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "              ${GREEN}🎉 Панель Remnawave установлена!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}🔗 Ссылка для первого входа в панель:${NC}"
    echo -e "${WHITE}https://${PANEL_DOMAIN}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    if [ "$with_subpage" = false ]; then
        local api_token_display
        api_token_display=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)
        echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
        echo
        echo -e "${WHITE}Теперь запустите установку страницы подписки на удаленном сервере.${NC}"
        echo
        echo -e "${YELLOW}📄 Для установки страницы подписки на удалённом сервере:${NC}"
        echo -e "${WHITE}URL панели:${NC}   https://$PANEL_DOMAIN"
        echo
        if [ -n "$api_token_display" ]; then
            echo -e "${WHITE}API токен:${NC}    $api_token_display"
        fi
        echo
        echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
        echo
    fi
    echo -e "${YELLOW}📋 Команды запуска меню управления:${NC} ${GREEN}rw${NC}, или ${GREEN}dfc${NC}"
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    print_warning "При первом входе в панель произойдет создание администратора."
    echo -e "${YELLOW}   Сбросить данные администратора и куки для входа можно в любое${NC}"
    echo -e "${YELLOW}   время через главное меню скрипта.${NC}"
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}
