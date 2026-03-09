# ═══════════════════════════════════════════════
# УСТАНОВКА: ПАНЕЛЬ + НОДА
# ═══════════════════════════════════════════════

installation_full() {
    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Проверяем, не установлено ли уже
    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "   ${YELLOW}⚠️  REMNAWAVE УЖЕ УСТАНОВЛЕН${NC}"
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
    echo -e "${GREEN}   📦 УСТАНОВКА ПАНЕЛИ + НОДЫ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    mkdir -p "${DIR_PANEL}" "${DIR_PANEL}/backups" && cd "${DIR_PANEL}"

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap 'echo; echo -e "${RED}Установка прервана пользователем${NC}"; echo; rm -rf "${DIR_PANEL}" 2>/dev/null; exit 1' INT TERM
    fi

    # Домены
    prompt_domain_with_retry "Домен панели (например panel.example.com):" PANEL_DOMAIN || { [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" 2>/dev/null; return; }
    prompt_domain_with_retry "Домен подписки (например sub.example.com):" SUB_DOMAIN true || { [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" 2>/dev/null; return; }
    prompt_domain_with_retry "Домен selfsteal/ноды (например node.example.com):" SELFSTEAL_DOMAIN true || { [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" 2>/dev/null; return; }

    # Автогенерация учётных данных администратора
    local SUPERADMIN_USERNAME
    local SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    # Название ноды
    local entity_name=""
    while true; do
        reading "Название ноды (Пример: Germany):" entity_name
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

    # Сертификаты
    declare -A domains_to_check
    domains_to_check["$PANEL_DOMAIN"]=1
    domains_to_check["$SUB_DOMAIN"]=1
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then
        echo
        show_arrow_menu "🔐  Метод получения сертификатов" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return

        case $cert_choice in
            0) CERT_METHOD=1 ;;
            1) CERT_METHOD=2 ;;
            2) : ;;
            3) return ;;
        esac

        reading "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        echo

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi

        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" 2>/dev/null
            read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
            echo
            return
        fi
    else
        CERT_METHOD=$(detect_cert_method "$PANEL_DOMAIN")
        echo
        for domain in "${!domains_to_check[@]}"; do
            print_success "Сертификат для $domain уже существует"
        done
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

    # Генерируем конфиги
    echo
    print_action "Генерация конфигурации..."

    # Генерируем cookie для защиты панели
    local COOKIE_NAME COOKIE_VALUE
    COOKIE_NAME=$(generate_cookie_key)
    COOKIE_VALUE=$(generate_cookie_key)

    (
        generate_env_file "$PANEL_DOMAIN" "$SUB_DOMAIN"
    ) &
    show_spinner "Создание .env файла" || true

    (
        generate_docker_compose_full "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN" "$NODE_CERT_DOMAIN"
    ) &
    show_spinner "Создание docker-compose.yml" || true

    # Определяем gateway и subnet сети (после генерации docker-compose.yml)
    local network_info network_gateway network_subnet
    network_info=$(get_remnawave_network_info)
    network_gateway=$(echo "$network_info" | awk '{print $1}')
    network_subnet=$(echo "$network_info" | awk '{print $2}')

    (
        generate_nginx_conf_full "$PANEL_DOMAIN" "$SUB_DOMAIN" "$SELFSTEAL_DOMAIN" \
            "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN" "$NODE_CERT_DOMAIN" \
            "$COOKIE_NAME" "$COOKIE_VALUE"
    ) &
    show_spinner "Создание nginx.conf" || true

    # UFW для ноды
    (
        ufw allow from "$network_subnet" to any port 2222 proto tcp >/dev/null 2>&1
    ) &
    show_spinner "Настройка файрвола" || true

    # Запуск
    echo
    print_action "Запуск сервисов..."

    (
        cd /opt/remnawave
        docker compose up -d 2>&1
    ) &
    if ! show_spinner "Запуск Docker контейнеров"; then
        print_error "Не удалось запустить контейнеры. Проверьте: docker compose -f /opt/remnawave/docker-compose.yml logs"
        return
    fi

    # Ожидание готовности
    show_spinner_timer 20 "Ожидание запуска Remnawave" "Запуск Remnawave"

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"

    if ! show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности API" 120; then
        print_error "API не отвечает. Проверьте: docker compose -f /opt/remnawave/docker-compose.yml logs"
        return
    fi

    # ═══════════════════════════════════════════
    # АВТОНАСТРОЙКА: РЕГИСТРАЦИЯ И СОЗДАНИЕ НОДЫ
    # ═══════════════════════════════════════════
    echo
    print_action "Автонастройка панели и ноды..."

    # 1. Регистрация суперадмина → получение токена
    print_action "Регистрация администратора..."
    local token
    token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

    if [ -z "$token" ]; then
        print_error "Не удалось получить токен авторизации"
        print_error "Настройте ноду вручную через панель: https://$PANEL_DOMAIN"
        randomhtml
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   ⚠️  УСТАНОВКА ЧАСТИЧНО ЗАВЕРШЕНА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}Панель:${NC}       https://$PANEL_DOMAIN"
        echo -e "${WHITE}Подписка:${NC}     https://$SUB_DOMAIN"
        echo -e "${WHITE}SelfSteal:${NC}    https://$SELFSTEAL_DOMAIN"
        echo
        echo -e "${YELLOW}👤 ЛОГИН:${NC}    ${WHITE}$SUPERADMIN_USERNAME${NC}"
        echo -e "${YELLOW}🔑 ПАРОЛЬ:${NC}   ${WHITE}$SUPERADMIN_PASSWORD${NC}"
        echo
        echo -e "${RED}⚠️  Нода не настроена автоматически. Настройте вручную.${NC}"
        echo
        echo -e "${RED}⚠️  ОБЯЗАТЕЛЬНО СКОПИРУЙТЕ И СОХРАНИТЕ ЭТИ ДАННЫЕ!${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi

    # 2. Получение публичного ключа → SECRET_KEY для ноды
    print_action "Получение публичного ключа панели..."
    get_public_key "$domain_url" "$token" "$target_dir"

    # Проверяем, что SECRET_KEY реально обновлён
    if grep -q 'PUBLIC KEY FROM REMNAWAVE-PANEL' "$target_dir/docker-compose.yml" 2>/dev/null; then
        print_error "Не удалось установить публичный ключ"
        return
    fi
    print_success "Установка публичного ключа"

    # 3. Генерация ключей x25519 (REALITY)
    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")

    if [ -z "$private_key" ]; then
        print_error "Не удалось сгенерировать REALITY ключи"
        return
    fi

    # 4. Удаление дефолтного config profile
    print_action "Удаление дефолтного конфиг-профиля..."
    delete_config_profile "$domain_url" "$token"

    # 5. Создание config profile с VLESS REALITY
    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result
    config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name")

    local config_profile_uuid inbound_uuid
    read config_profile_uuid inbound_uuid <<< "$config_result"

    if [ -z "$config_profile_uuid" ] || [ "$config_profile_uuid" = "ERROR" ] || \
       [ -z "$inbound_uuid" ]; then
        print_error "Не удалось создать конфиг-профиль"
        return
    fi

    # 6. Создание ноды
    print_action "Создание ноды ($entity_name)..."
    if create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$network_gateway" "$entity_name"; then
        print_success "Создание ноды"
    else
        print_error "Не удалось создать ноду"
    fi

    # 7. Создание хоста
    print_action "Создание хоста ($SELFSTEAL_DOMAIN)..."
    create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$entity_name" "$SELFSTEAL_DOMAIN"
    print_success "Регистрация хоста"

    # 8. Получение и обновление сквадов
    print_action "Настройка сквадов..."
    local squad_uuids
    squad_uuids=$(get_default_squad "$domain_url" "$token")

    if [ -n "$squad_uuids" ]; then
        while IFS= read -r squad_uuid; do
            [ -z "$squad_uuid" ] && continue
            update_squad "$domain_url" "$token" "$squad_uuid" "$inbound_uuid"
        done <<< "$squad_uuids"
        print_success "Обновление сквадов"
    else
        echo -e "${YELLOW}⚠️  Сквады не найдены (будут настроены при создании пользователей)${NC}"
    fi

    # 9. Создание API токена для subscription-page
    print_action "Создание API токена для страницы подписки..."
    create_api_token "$domain_url" "$token" "$target_dir"

    # 10. Перезапуск Docker Compose (с обновлённым docker-compose.yml)
    print_action "Перезапуск сервисов с обновлённой конфигурацией..."
    (
        cd /opt/remnawave
        docker compose down 2>&1
        docker compose up -d 2>&1
    ) &
    show_spinner "Запуск контейнеров" || true

    # 11. Шаблон selfsteal
    randomhtml

    # Ожидаем готовность после перезапуска
    show_spinner_timer 15 "Ожидание запуска сервисов" "Запуск сервисов"

    show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности панели" 120 || true

    # Верификация: ждём пока remnanode запустит xray на порту 443
    print_action "Ожидание подключения ноды (xray → порт 443)..."
    local verify_ok=false
    local verify_elapsed=0
    local verify_timeout=60
    while [ $verify_elapsed -lt $verify_timeout ]; do
        if ss -tuln 2>/dev/null | grep -q ':443 '; then
            verify_ok=true
            break
        fi
        sleep 2
        ((verify_elapsed+=2))
    done
    if [ "$verify_ok" = true ]; then
        print_success "Порт 443 активен — xray (remnanode) работает"
    else
        echo -e "${YELLOW}⚠️  Порт 443 пока не активен — нода может ещё подключаться${NC}"
    fi

    # 12. Сброс суперадмина — при первом входе пользователь задаст свои данные
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

    # Автоматически включаем доступ по 8443 для panel+node
    auto_enable_panel_access_8443 "$PANEL_DOMAIN" "$COOKIE_NAME" "$COOKIE_VALUE"

    # Итог
    clear
    tput civis 2>/dev/null
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${GREEN}🎉 УСТАНОВКА ЗАВЕРШЕНА!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}⚠️  ВАЖНО: XRAY (selfsteal) занимает порт 443 для работы VPN.${NC}"
    echo -e "${WHITE}   Панель доступна через порт 8443 (автоматически включен).${NC}"
    echo
    echo -e "${YELLOW}🔗 Ссылка для входа в панель:${NC}"
    echo -e "${WHITE}https://${PANEL_DOMAIN}:8443/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${YELLOW}📋 Команды запуска меню управления:${NC}"
    echo -e "${GREEN}dfc-remna-install${NC} или ${GREEN}dfc-ri${NC}"
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
