# ═══════════════════════════════════════════════
# УСТАНОВКА: ТОЛЬКО ПАНЕЛЬ
# ═══════════════════════════════════════════════

installation_panel() {
    local with_subpage="${1:-true}"

    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Проверяем, не установлена ли уже панель
    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "   ${YELLOW}⚠️  ПАНЕЛЬ УЖЕ УСТАНОВЛЕНА${NC}"
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

    mkdir -p "${DIR_PANEL}" "${DIR_PANEL}/backups" && cd "${DIR_PANEL}"
    [ "$with_subpage" = true ] && mkdir -p "${DIR_SUB}"

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap 'echo; echo -e "${RED}Установка прервана пользователем${NC}"; echo; rm -rf "${DIR_PANEL}" 2>/dev/null; exit 1' INT TERM
    fi

    local cert_choice
    while true; do
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if [ "$with_subpage" = true ]; then
        echo -e "${GREEN}   📦 УСТАНОВКА ПАНЕЛИ + СТРАНИЦЫ ПОДПИСКИ${NC}"
    else
        echo -e "${GREEN}         📦 Установка панели${NC}"
    fi
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    prompt_domain_with_retry "Домен панели ${DARKGRAY}(например panel.example.com)${YELLOW}:" PANEL_DOMAIN || { [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" 2>/dev/null; return; }
    local SUB_DOMAIN=""
    if [ "$with_subpage" = true ]; then
        prompt_domain_with_retry "Домен подписки ${DARKGRAY}(например sub.example.com)${YELLOW}:" SUB_DOMAIN true || continue
    else
        local _sub_esc=false
        while true; do
            reading_inline "Домен страницы подписки ${DARKGRAY}(например sub.example.com)${YELLOW}:" SUB_DOMAIN
            local _rc=$?
            if [ $_rc -eq 2 ]; then _sub_esc=true; break; fi
            if [[ "$SUB_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                print_error "Введите корректный домен"
            fi
        done
        [ "$_sub_esc" = true ] && continue
        echo
    fi

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
        echo
        show_arrow_menu "🔐  Метод получения сертификатов" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        cert_choice=$?
        [[ $cert_choice -eq 255 || $cert_choice -eq 3 ]] && continue

        case $cert_choice in
            0) CERT_METHOD=2 ;;
            1) CERT_METHOD=1 ;;
        esac

        echo
        reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        [[ $? -eq 2 ]] && continue
        echo

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi

        echo
    else
        CERT_METHOD=$(detect_cert_method "$PANEL_DOMAIN")
        echo
        for domain in "${!domains_to_check[@]}"; do
            print_success "Сертификат для $domain уже существует"
        done
        echo
    fi
    break
    done

    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    if [ "$needs_certs" = true ]; then
        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" 2>/dev/null
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
        cp -f "${DIR_SCRIPT}version" "${DIR_PANEL}version" 2>/dev/null || true
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

    if ! show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности API" 120; then
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

    if [ -z "$token" ]; then
        print_error "Не удалось получить токен авторизации"
        print_error "Создайте API токен вручную через панель: https://$PANEL_DOMAIN"
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "   ${GREEN}⚠️  УСТАНОВКА ЧАСТИЧНО ЗАВЕРШЕНА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}🔗 ССЫЛКА ВХОДА В ПАНЕЛЬ:${NC}"
        echo -e "${WHITE}https://${PANEL_DOMAIN}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
        echo
        echo -e "${YELLOW}👤 ЛОГИН:${NC}    ${WHITE}$SUPERADMIN_USERNAME${NC}"
        echo -e "${YELLOW}🔑 ПАРОЛЬ:${NC}   ${WHITE}$SUPERADMIN_PASSWORD${NC}"
        echo
        echo -e "${RED}⚠️  API токен не создан автоматически. Создайте вручную.${NC}"
        echo
        echo -e "${RED}⚠️  ОБЯЗАТЕЛЬНО СКОПИРУЙТЕ И СОХРАНИТЕ ЭТИ ДАННЫЕ!${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi

    # 2. Создание API токена для subscription-page
    print_action "Создание API токена для страницы подписки..."
    if [ "$with_subpage" = true ]; then
        create_api_token "$domain_url" "$token" "${DIR_SUB}"
    else
        create_api_token "$domain_url" "$token" "$target_dir"
    fi

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

        # Ожидаем готовность после перезапуска
        show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
    fi

    # 4. Сброс суперадмина — при первом входе пользователь задаст свои данные
    print_action "Сброс суперадмина для первого входа..."
    if docker exec -i remnawave-db psql -U postgres -d postgres -c "DELETE FROM admin;" >/dev/null 2>&1; then
        print_success "Суперадмин сброшен"
    else
        print_error "Не удалось сбросить суперадмина"
    fi

    # Удаляем trap при успешном завершении
    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

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
    echo -e "${YELLOW}📋 Команды запуска меню управления:${NC}"
    echo -e "${GREEN}dfc-manager${NC} или ${GREEN}dfc${NC}"
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}⚠️  При первом входе в панель произойдет создание администратора.${NC}"
    echo -e "${YELLOW}   Сбросить данные администратора и куки для входа можно в любое${NC}"
    echo -e "${YELLOW}   время через главное меню скрипта.${NC}"
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}
