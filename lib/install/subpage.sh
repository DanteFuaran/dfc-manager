# ═══════════════════════════════════════════════
# УСТАНОВКА: ТОЛЬКО СТРАНИЦА ПОДПИСКИ
# ═══════════════════════════════════════════════

installation_subpage() {
    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Определяем контекст установки
    local has_panel=false
    local has_node_remote=false
    local has_sub_already=false

    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        has_panel=true
        if grep -q "remnawave-subscription-page" /opt/remnawave/docker-compose.yml 2>/dev/null; then
            has_sub_already=true
        fi
    fi

    if [ -f "/opt/remnanode/docker-compose.yml" ]; then
        has_node_remote=true
        if grep -q "remnawave-subscription-page" /opt/remnanode/docker-compose.yml 2>/dev/null; then
            has_sub_already=true
        fi
    fi

    if [ -f "/opt/remnasubpage/docker-compose.yml" ] || [ -f "/opt/subscribe-page/docker-compose.yml" ]; then
        has_sub_already=true
    fi

    # Страница подписки уже установлена
    if [ "$has_sub_already" = true ]; then
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "   ${YELLOW}⚠️  СТРАНИЦА ПОДПИСКИ УЖЕ УСТАНОВЛЕНА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}На этом сервере уже установлена страница подписки.${NC}"
        echo -e "${WHITE}Используйте опцию ${GREEN}\"🔄 Переустановить\"${WHITE} в главном меню.${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi

    # Направляем в нужную подфункцию
    if [ "$has_panel" = true ]; then
        _installation_subpage_on_panel
    elif [ "$has_node_remote" = true ]; then
        _installation_subpage_on_node
    else
        _installation_subpage_standalone
    fi
}

# ─── Добавление страницы подписки на сервер с панелью (без sub-page) ───
_installation_subpage_on_panel() {
    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"

    # Сохраняем бэкап конфигов
    local backup_compose="" backup_nginx="" backup_node_compose=""
    backup_compose=$(cat /opt/remnawave/docker-compose.yml 2>/dev/null)
    backup_node_compose=$(cat /opt/remnanode/docker-compose.yml 2>/dev/null)
    backup_nginx=$(cat ${DIR_NGINX}nginx.conf 2>/dev/null)

    _restore_config() {
        if [ -n "$backup_compose" ]; then
            echo "$backup_compose" > /opt/remnawave/docker-compose.yml
        fi
        if [ -n "$backup_node_compose" ]; then
            echo "$backup_node_compose" > /opt/remnanode/docker-compose.yml
        fi
        if [ -n "$backup_nginx" ]; then
            echo "$backup_nginx" > ${DIR_NGINX}nginx.conf
        fi
        (
            cd /opt/remnawave && docker compose down >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1
            [ -n "$backup_node_compose" ] && { cd /opt/remnanode && docker compose up -d >/dev/null 2>&1; } || true
        ) &
        show_spinner "Восстановление конфигурации"
        (cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1) &
        show_spinner "Перезапуск nginx"
        show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
        tput cnorm 2>/dev/null || true
    }

    # Извлекаем домен панели из nginx.conf
    local panel_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' ${DIR_NGINX}nginx.conf | sed -n '1p')
    if [ -z "$panel_domain" ]; then
        print_error "Не удалось определить домен панели из nginx.conf"
        show_continue_prompt || return 1
        return
    fi

    # Извлекаем cookie
    local COOKIE_NAME COOKIE_VALUE
    if ! get_cookie_from_nginx; then
        print_error "Не удалось извлечь cookie из nginx.conf"
        show_continue_prompt || return 1
        return
    fi

    # Извлекаем домен сертификата панели
    local panel_cert_domain
    panel_cert_domain=$(grep -A5 "server_name ${panel_domain};" ${DIR_NGINX}nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
    [ -z "$panel_cert_domain" ] && panel_cert_domain="$panel_domain"

    local AUTO_CERT_METHOD
    AUTO_CERT_METHOD=$(detect_cert_method "$panel_domain")

    # Показываем заголовок и сразу запрашиваем авторизацию
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    📄 Установка страницы подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Авторизация в панели
    local _gpt_rc
    get_panel_token; _gpt_rc=$?
    if [[ $_gpt_rc -eq 2 ]]; then return; fi
    if [[ $_gpt_rc -ne 0 ]]; then
        echo -e "${YELLOW}Установка отменена${NC}"
        show_continue_prompt || return 1
        return
    fi
    local token
    token=$(cat "${DIR_SCRIPT}/token")

    # Запрашиваем домен подписки (inline, без clear)
    local SUB_DOMAIN
    local cert_choice
    local CERT_METHOD="$AUTO_CERT_METHOD"
    local LETSENCRYPT_EMAIL=""
    while true; do
    prompt_domain_with_retry "Домен страницы подписки ${DARKGRAY}(например sub.example.com)${YELLOW}:" SUB_DOMAIN true || return

    unset domains_to_check
    declare -A domains_to_check
    domains_to_check["$SUB_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then

        if [ "$CERT_METHOD" = "1" ]; then
            if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                show_arrow_menu "🔐  Метод получения сертификата" \
                    "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
                    "──────────────────────────────────────" \
                    "⬅️   Назад"
                cert_choice=$?
                case $cert_choice in
                    0) CERT_METHOD=2 ;;
                    1) CERT_METHOD=1 ;;
                    *) continue ;;
                esac
                setup_cloudflare_credentials || return
            fi
        fi

        LETSENCRYPT_EMAIL=$(grep -r "email" /etc/letsencrypt/accounts/ 2>/dev/null | grep -oP '"[^@]+@[^"]+' | head -1 | tr -d '"')
        if [ -z "$LETSENCRYPT_EMAIL" ]; then
            reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
            [[ $? -eq 2 ]] && continue
        else
            echo -e "${GREEN}✅${NC} Email для сертификата: $LETSENCRYPT_EMAIL"
        fi
        echo

        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            show_continue_prompt || true
            return
        fi
    else
        echo
        print_success "Сертификат для $SUB_DOMAIN уже существует"
    fi
    break
    done

    echo

    local SUB_CERT_DOMAIN
    if [ "$CERT_METHOD" = "1" ]; then
        SUB_CERT_DOMAIN=$(extract_domain "$SUB_DOMAIN")
    else
        SUB_CERT_DOMAIN="$SUB_DOMAIN"
    fi

    # Копируем сертификат подписки в /opt/nginx/ssl/
    nginx_copy_cert "$SUB_CERT_DOMAIN" 2>/dev/null || true

    # Обновляем .env — SUB_PUBLIC_DOMAIN
    if grep -q "^SUB_PUBLIC_DOMAIN=" /opt/remnawave/.env 2>/dev/null; then
        sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_DOMAIN|" /opt/remnawave/.env
    else
        echo "SUB_PUBLIC_DOMAIN=$SUB_DOMAIN" >> /opt/remnawave/.env
    fi

    # Определяем, есть ли нода (full/panel)
    local has_local_node=false
    if [ -n "$backup_node_compose" ] || is_node_installed; then
        has_local_node=true
    fi

    # Восстанавливаем существующие значения .env (SECRET_KEY в compose и API_TOKEN)
    local existing_api_token
    existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "${DIR_SUB}.env" 2>/dev/null | head -1)
    [ -z "$existing_api_token" ] && existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)

    # Остановка сервисов
    (
        cd /opt/remnawave 2>/dev/null && docker compose down >/dev/null 2>&1 || true
        [ -n "$backup_node_compose" ] && { cd /opt/remnanode 2>/dev/null && docker compose down >/dev/null 2>&1 || true; }
        [ -f "${DIR_SUB}docker-compose.yml" ] && { cd "${DIR_SUB}" 2>/dev/null && docker compose down >/dev/null 2>&1 || true; }
        true
    ) &
    show_spinner "Остановка сервисов"
    echo

    # Подготовка файлов (перегенерация docker-compose и nginx)
    if [ "$has_local_node" = true ]; then
        local selfsteal_domain node_cert_domain
        # Определяем домен ноды по маркеру selfsteal (try_files /index.html)
        selfsteal_domain=$(
            awk '/^\s*server_name\s/ && !/server_name\s+_/ {
                sn = $2; gsub(/;/, "", sn)
            }
            /try_files \/index\.html/ && sn != "" { print sn; exit }' "${DIR_NGINX}nginx.conf"
        )
        node_cert_domain=$(grep -A5 "server_name ${selfsteal_domain};" ${DIR_NGINX}nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
        [ -z "$node_cert_domain" ] && node_cert_domain="$selfsteal_domain"
        (
            generate_docker_compose_full "$panel_cert_domain" "$SUB_CERT_DOMAIN" "$node_cert_domain"
            generate_nginx_conf_full "$panel_domain" "$SUB_DOMAIN" "$selfsteal_domain" \
                "$panel_cert_domain" "$SUB_CERT_DOMAIN" "$node_cert_domain" \
                "$COOKIE_NAME" "$COOKIE_VALUE"
        ) &
    else
        (
            generate_docker_compose_panel "$panel_cert_domain" "$SUB_CERT_DOMAIN"
            generate_nginx_conf_panel "$panel_domain" "$SUB_DOMAIN" "$panel_cert_domain" "$SUB_CERT_DOMAIN" \
                "$COOKIE_NAME" "$COOKIE_VALUE"
        ) &
    fi
    show_spinner "Подготовка файлов" || true

    # Если SECRET_KEY был в старом compose, восстанавливаем его
    if [ "$has_local_node" = true ]; then
        local old_secret_key
        old_secret_key=$(echo "$backup_node_compose" | grep -oP 'SECRET_KEY=\K.*' | head -1 | tr -d '"')
        [ -z "$old_secret_key" ] && old_secret_key=$(echo "$backup_compose" | grep -oP 'SECRET_KEY=\K.*' | head -1 | tr -d '"')
        if [ -n "$old_secret_key" ] && [ "$old_secret_key" != "PUBLIC KEY FROM REMNAWAVE-PANEL" ]; then
            sed -i "s|SECRET_KEY=\"PUBLIC KEY FROM REMNAWAVE-PANEL\"|SECRET_KEY=$old_secret_key|" /opt/remnanode/docker-compose.yml 2>/dev/null || true
        fi
    fi

    # Обновление конфигурации (запуск сервисов)
    (
        cd /opt/remnawave && docker compose up -d >/dev/null 2>&1 || true
        [ "$has_local_node" = true ] && { cd "${DIR_NODE}" && docker compose up -d >/dev/null 2>&1 || true; }
        cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1 || true
    ) &
    show_spinner "Обновление конфигурации" || true

    echo
    if ! show_spinner_until_ready "http://127.0.0.1:3001/health" "Проверка доступности API" 120; then
        print_error "API не отвечает. Восстановление конфигурации..."
        _restore_config
        show_continue_prompt || return 1
        return
    fi

    # Создание API токена для subscription-page (если нет)
    if [ -z "$existing_api_token" ] || [ "$existing_api_token" = "\$api_token" ]; then
        create_api_token "$domain_url" "$token" "${DIR_SUB}" >/dev/null 2>&1 || true
    fi

    (
        cd "${DIR_SUB}" && docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
    tput cnorm 2>/dev/null || true

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "     ${GREEN}🎉 Страница подписки подключена!${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Панель:${NC}       https://$panel_domain"
    echo -e "${WHITE}Подписка:${NC}     https://$SUB_DOMAIN"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ─── Установка страницы подписки на сервер с нодой ───
_installation_subpage_on_node() {
    local NODE_DIR="/opt/remnanode"

    # Проверяем пакеты
    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    # Сохраняем бэкап конфигов ноды
    local backup_compose="" backup_nginx=""
    backup_compose=$(cat "${NODE_DIR}/docker-compose.yml" 2>/dev/null)
    backup_nginx=$(cat "${DIR_NGINX}nginx.conf" 2>/dev/null)

    _restore_node_config() {
        if [ -n "$backup_compose" ]; then
            echo "$backup_compose" > "${NODE_DIR}/docker-compose.yml"
        fi
        if [ -n "$backup_nginx" ]; then
            echo "$backup_nginx" > "${DIR_NGINX}nginx.conf"
        fi
        (cd "${NODE_DIR}" && docker compose down >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1) &
        show_spinner "Восстановление конфигурации ноды"
    }

    # Запрашиваем URL панели
    local PANEL_URL=""
    local cert_choice
    while true; do  # loop1: панель домен
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    📄 Установка страницы подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${DARKGRAY}Обнаружена нода на этом сервере.${NC}"
    echo -e "${DARKGRAY}Страница подписки будет добавлена к ноде.${NC}"
    echo
    PANEL_URL=""
    local _first_panel=true
    while true; do
        [ "$_first_panel" = true ] && echo
        _first_panel=false
        reading_inline "Домен панели ${DARKGRAY}(например panel.example.com)${YELLOW}:" PANEL_URL
        [[ $? -eq 2 ]] && return 1
        # Убираем протокол если введён
        PANEL_URL="${PANEL_URL#https://}"
        PANEL_URL="${PANEL_URL#http://}"
        # Убираем trailing slash
        PANEL_URL="${PANEL_URL%/}"
        if [[ "$PANEL_URL" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
            PANEL_URL="https://$PANEL_URL"
            break
        else
            print_error "Введите корректный домен, например: panel.example.com"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить   ${BLUE}Esc${DARKGRAY}: Назад${NC}"
            tput civis 2>/dev/null || true
            local _pk
            while true; do
                read -s -n 1 _pk
                if [[ "$_pk" == $'\x1b' ]]; then
                    tput cnorm 2>/dev/null || true
                    echo
                    return 1
                elif [[ "$_pk" == "" ]]; then
                    tput cnorm 2>/dev/null || true
                    for ((l=0; l<5; l++)); do
                        tput cuu1 2>/dev/null
                        tput el 2>/dev/null
                    done
                    break
                fi
            done
        fi
    done

    while true; do  # loop2: домен подписки
    # Запрашиваем домен подписки
    local SUB_DOMAIN
    prompt_domain_with_retry "Домен страницы подписки ${DARKGRAY}(например sub.example.com)${YELLOW}:" SUB_DOMAIN true || break

    while true; do  # loop3: API токен
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    📄 Установка страницы подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${DARKGRAY}Обнаружена нода на этом сервере.${NC}"
    echo -e "${DARKGRAY}Страница подписки будет добавлена к ноде.${NC}"
    echo
    echo -e "${BLUE}➜${NC}  ${YELLOW}Домен панели ${DARKGRAY}(например panel.example.com)${YELLOW}:${NC} ${GREEN}${PANEL_URL#https://}${NC}"
    echo -e "${BLUE}➜${NC}  ${YELLOW}Домен страницы подписки ${DARKGRAY}(например sub.example.com)${YELLOW}:${NC} ${GREEN}${SUB_DOMAIN}${NC}"
    # Запрашиваем API токен
    local API_TOKEN=""
    echo
    echo -e "${BLUE}➜${NC}  ${YELLOW}API токен панели (Настройки Remnawave) и нажмите Enter дважды:${NC}"
    while IFS= read -r line; do
        if [ -z "$line" ] && [ -n "$API_TOKEN" ]; then
            break
        fi
        if [ -n "$line" ]; then
            API_TOKEN="$API_TOKEN$line"
        fi
    done

    # Определяем метод сертификатов
    local CERT_METHOD
    local LETSENCRYPT_EMAIL=""
    CERT_METHOD=$(detect_cert_method "$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)" 2>/dev/null || echo "2")

    unset domains_to_check
    declare -A domains_to_check
    domains_to_check["$SUB_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then
        echo
        if [ "$CERT_METHOD" = "1" ]; then
            if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                show_arrow_menu "🔐  Метод получения сертификата" \
                    "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
                    "──────────────────────────────────────" \
                    "⬅️   Назад"
                cert_choice=$?
                case $cert_choice in
                    0) CERT_METHOD=2 ;;
                    1) CERT_METHOD=1 ;;
                    *) continue ;;
                esac
                setup_cloudflare_credentials || return
            fi
        fi

        LETSENCRYPT_EMAIL=$(grep -r "email" /etc/letsencrypt/accounts/ 2>/dev/null | grep -oP '"[^@]+@[^"]+' | head -1 | tr -d '"')
        if [ -z "$LETSENCRYPT_EMAIL" ]; then
            echo
            reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
            [[ $? -eq 2 ]] && continue
        else
            echo -e "${GREEN}✅${NC} Email для сертификата: $LETSENCRYPT_EMAIL"
        fi
        echo

        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            show_continue_prompt || true
            return
        fi
    else
        print_success "Сертификат для $SUB_DOMAIN уже существует"
        echo
    fi
    break 3  # все промпты пройдены — выход из всех циклов
    done  # loop3

    done  # loop2
    done  # loop1

    local SUB_CERT_DOMAIN
    if [ "$CERT_METHOD" = "1" ]; then
        SUB_CERT_DOMAIN=$(extract_domain "$SUB_DOMAIN")
    else
        SUB_CERT_DOMAIN="$SUB_DOMAIN"
    fi

    # Копируем сертификат подписки в /opt/nginx/ssl/
    nginx_copy_cert "$SUB_CERT_DOMAIN" 2>/dev/null || true

    # Извлекаем selfsteal домен и сертификат ноды
    local selfsteal_domain node_cert_domain
    selfsteal_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" | head -1)
    node_cert_domain=$(grep -oP '/ssl/\K[^/]+' "${DIR_NGINX}nginx.conf" | head -1)
    [ -z "$node_cert_domain" ] && node_cert_domain="$selfsteal_domain"

    # Остановка сервисов ноды
    echo
    print_action "Обновление конфигурации..."

    (cd "${NODE_DIR}" && docker compose down >/dev/null 2>&1; true) &
    show_spinner "Остановка сервисов"

    # Добавляем subscription-page сервис к docker-compose ноды
    (
        # Добавляем cert mount для sub_domain в nginx volumes
        sed -i "/privkey.pem:\/etc\/nginx\/ssl\/${node_cert_domain}/a\\
      - /etc/letsencrypt/live/${SUB_CERT_DOMAIN}/fullchain.pem:/etc/nginx/ssl/${SUB_CERT_DOMAIN}/fullchain.pem:ro\n      - /etc/letsencrypt/live/${SUB_CERT_DOMAIN}/privkey.pem:/etc/nginx/ssl/${SUB_CERT_DOMAIN}/privkey.pem:ro" \
            "${NODE_DIR}/docker-compose.yml"

        # Добавляем dependency на subscription-page в nginx
        sed -i '/depends_on:/a\      - remnawave-subscription-page' "${NODE_DIR}/docker-compose.yml"

        # Добавляем subscription-page сервис
        cat >> "${NODE_DIR}/docker-compose.yml" <<EOL

  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - REMNAWAVE_PANEL_URL=${PANEL_URL}
      - APP_PORT=3010
      - REMNAWAVE_API_TOKEN=${API_TOKEN}
    ports:
      - '127.0.0.1:3010:3010'
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 3010']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL

        # Обновляем nginx.conf — добавляем sub-page server block
        generate_nginx_conf_node_with_subpage "$selfsteal_domain" "$node_cert_domain" \
            "$SUB_DOMAIN" "$SUB_CERT_DOMAIN" "$NODE_DIR"
    ) &
    show_spinner "Обновление конфигурации" || true

    # Запуск сервисов
    (cd "${NODE_DIR}" && docker compose up -d >/dev/null 2>&1) &
    if ! show_spinner "Запуск контейнеров"; then
        print_error "Не удалось запустить контейнеры. Восстановление..."
        _restore_node_config
        show_continue_prompt || return 1
        return
    fi

    (cd "${DIR_NGINX}" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск nginx" || true

    show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
    tput cnorm 2>/dev/null || true

    # Проверка здоровья
    local health_ok=true
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-subscription-page$'; then
        health_ok=false
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
        health_ok=false
    fi

    if [ "$health_ok" = true ]; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "     ${GREEN}🎉 Страница подписки подключена!${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}Подписка:${NC}     https://$SUB_DOMAIN"
        echo -e "${WHITE}Панель:${NC}       $PANEL_URL"
        echo
        echo -e "${BLUE}──────────────────────────────────────${NC}"
        echo
        echo -e "${YELLOW}📋 Команды запуска меню управления:${NC}"
        echo -e "${GREEN}dfc-manager${NC} или ${GREEN}dfc${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
    else
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${YELLOW}   ⚠️  УСТАНОВКА С ПРЕДУПРЕЖДЕНИЯМИ${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}Диагностика:${NC}"
        echo -e "${WHITE}  docker logs remnawave-subscription-page${NC}"
        echo -e "${WHITE}  docker logs remnawave-nginx${NC}"
        echo -e "${WHITE}  cd ${NODE_DIR} && docker compose restart${NC}"
    fi
    show_continue_prompt || return 1
}

# ─── Установка страницы подписки на пустой сервер (standalone) ───
_installation_subpage_standalone() {
    local SUBPAGE_DIR="${DIR_SUB%/}"

    # Проверяем, это первичная установка?
    local is_fresh_install=false
    if [ ! -d "${SUBPAGE_DIR}" ] || [ -z "$(ls -A "${SUBPAGE_DIR}" 2>/dev/null)" ]; then
        is_fresh_install=true
    fi

    mkdir -p "${SUBPAGE_DIR}" && cd "${SUBPAGE_DIR}"

    # Устанавливаем trap для удаления при прерывании
    if [ "$is_fresh_install" = true ]; then
        trap 'echo; echo -e "${RED}Установка прервана пользователем${NC}"; echo; rm -rf "'"${SUBPAGE_DIR}"'" 2>/dev/null; exit 1' INT TERM
    fi

    # Запрашиваем URL панели
    local PANEL_URL=""
    local cert_choice
    while true; do  # loop1: панель домен
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    📄 Установка страницы подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    PANEL_URL=""
    local _first_panel=true
    while true; do
        [ "$_first_panel" = true ] && echo
        _first_panel=false
        reading_inline "Домен панели ${DARKGRAY}(например panel.example.com)${YELLOW}:" PANEL_URL
        [[ $? -eq 2 ]] && { [ "$is_fresh_install" = true ] && rm -rf "${SUBPAGE_DIR}" 2>/dev/null; return 1; }
        # Убираем протокол если введён
        PANEL_URL="${PANEL_URL#https://}"
        PANEL_URL="${PANEL_URL#http://}"
        # Убираем trailing slash
        PANEL_URL="${PANEL_URL%/}"
        if [[ "$PANEL_URL" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
            PANEL_URL="https://$PANEL_URL"
            break
        else
            print_error "Введите корректный домен, например: panel.example.com"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить   ${BLUE}Esc${DARKGRAY}: Назад${NC}"
            tput civis 2>/dev/null || true
            local _pk
            while true; do
                read -s -n 1 _pk
                if [[ "$_pk" == $'\x1b' ]]; then
                    tput cnorm 2>/dev/null || true
                    echo
                    [ "$is_fresh_install" = true ] && rm -rf "${SUBPAGE_DIR}" 2>/dev/null
                    return 1
                elif [[ "$_pk" == "" ]]; then
                    tput cnorm 2>/dev/null || true
                    for ((l=0; l<5; l++)); do
                        tput cuu1 2>/dev/null
                        tput el 2>/dev/null
                    done
                    break
                fi
            done
        fi
    done

    while true; do  # loop2: домен подписки
    # Запрашиваем домен подписки
    local SUB_DOMAIN
    prompt_domain_with_retry "Домен страницы подписки ${DARKGRAY}(например sub.example.com)${YELLOW}:" SUB_DOMAIN true || break

    while true; do  # loop3: API токен
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    📄 Установка страницы подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${BLUE}➜${NC}  ${YELLOW}Домен панели ${DARKGRAY}(например panel.example.com)${YELLOW}:${NC} ${GREEN}${PANEL_URL#https://}${NC}"
    echo -e "${BLUE}➜${NC}  ${YELLOW}Домен страницы подписки ${DARKGRAY}(например sub.example.com)${YELLOW}:${NC} ${GREEN}${SUB_DOMAIN}${NC}"
    # Запрашиваем API токен
    local API_TOKEN=""
    echo
    echo -e "${BLUE}➜${NC}  ${YELLOW}API токен панели (Настройки Remnawave) и нажмите Enter дважды:${NC}"
    while IFS= read -r line; do
        if [ -z "$line" ] && [ -n "$API_TOKEN" ]; then
            break
        fi
        if [ -n "$line" ]; then
            API_TOKEN="$API_TOKEN$line"
        fi
    done

    # Сертификаты
    unset domains_to_check
    declare -A domains_to_check
    domains_to_check["$SUB_DOMAIN"]=1

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
        CERT_METHOD=$(detect_cert_method "$SUB_DOMAIN")
        echo
        print_success "Сертификат для $SUB_DOMAIN уже существует"
    fi
    break 3  # все промпты пройдены — выход из всех циклов
    done  # loop3

    done  # loop2
    done  # loop1

    echo
    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    if [ "$needs_certs" = true ]; then
        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            [ "$is_fresh_install" = true ] && rm -rf "${SUBPAGE_DIR}" 2>/dev/null
            show_continue_prompt || true
            return
        fi
    fi

    local SUB_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        SUB_CERT_DOMAIN=$(extract_domain "$SUB_DOMAIN")
    else
        SUB_CERT_DOMAIN="$SUB_DOMAIN"
    fi

    # Проверяем сертификаты
    local cert_path="/etc/letsencrypt/live/$SUB_CERT_DOMAIN"
    if [ ! -f "$cert_path/fullchain.pem" ] || [ ! -f "$cert_path/privkey.pem" ]; then
        print_error "Сертификаты не найдены в $cert_path"
        [ "$is_fresh_install" = true ] && rm -rf "${SUBPAGE_DIR}" 2>/dev/null
        show_continue_prompt || true
        return
    fi

    # Копируем сертификат подписки в /opt/nginx/ssl/
    nginx_copy_cert "$SUB_CERT_DOMAIN" 2>/dev/null || true

    # Генерация конфигов
    (
        generate_docker_compose_subpage "$SUB_CERT_DOMAIN" "$PANEL_URL" "$API_TOKEN" "$SUBPAGE_DIR"
        generate_nginx_conf_subpage "$SUB_DOMAIN" "$SUB_CERT_DOMAIN" "$SUBPAGE_DIR"
        cp -f "${DIR_SCRIPT}version" "${SUBPAGE_DIR}/version" 2>/dev/null || true
    ) &
    show_spinner "Подготовка файлов" || true

    (
        ufw allow 443/tcp >/dev/null 2>&1 || true
        ufw reload >/dev/null 2>&1 || true
    ) &
    show_spinner "Настройка файрвола" || true

    echo
    (cd "${DIR_NGINX}" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск Nginx" || true

    (
        cd "${SUBPAGE_DIR}"
        docker compose up -d >/dev/null 2>&1
    ) &
    if ! show_spinner "Настройка сервисов"; then
        print_error "Не удалось запустить контейнеры"
        show_continue_prompt || true
        return
    fi

    echo
    show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
    tput cnorm 2>/dev/null || true

    # Проверка здоровья
    local health_ok=true
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-subscription-page$'; then
        health_ok=false
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
        health_ok=false
    fi

    # Удаляем trap при успешном завершении
    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

    if [ "$health_ok" = true ]; then
        clear
        tput civis 2>/dev/null
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e " ${GREEN}🎉 Страница подписки подключена!${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}Подписка:${NC}  https://$SUB_DOMAIN"
        echo -e "${WHITE}Панель:${NC}    $PANEL_URL"
        echo
        echo -e "${BLUE}──────────────────────────────────────${NC}"
        echo
        echo -e "${YELLOW}📋 Команды запуска меню управления:${NC}"
        echo -e "${GREEN}dfc-manager${NC} или ${GREEN}dfc${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
    else
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${YELLOW}   ⚠️  УСТАНОВКА С ПРЕДУПРЕЖДЕНИЯМИ${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}Диагностика:${NC}"
        echo -e "${WHITE}  docker logs remnawave-subscription-page${NC}"
        echo -e "${WHITE}  docker logs remnawave-nginx${NC}"
        echo -e "${WHITE}  cd ${SUBPAGE_DIR} && docker compose restart${NC}"
    fi
    show_continue_prompt || return 1
}
