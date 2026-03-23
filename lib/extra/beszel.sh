# ═══════════════════════════════════════════════════
# BESZEL — МОНИТОРИНГ СЕРВЕРА
# ═══════════════════════════════════════════════════

DIR_BESZEL="/opt/beszel/"
DIR_BESZEL_AGENT="/opt/beszel-agent/"

is_beszel_installed() {
    [ -f "${DIR_BESZEL}docker-compose.yml" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "beszel"
}

is_beszel_agent_installed() {
    [ -f "${DIR_BESZEL_AGENT}docker-compose.yml" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "beszel-agent"
}

manage_beszel() {
    local -a items=()
    local -a actions=()

    if ! is_beszel_installed; then
        items+=("📊  Установить панель Beszel"); actions+=("install_hub")
    fi

    if is_beszel_agent_installed; then
        items+=("🗑️   Удалить агент Beszel");   actions+=("uninstall_agent")
    else
        items+=("🖥️   Подключить агент (ноду)"); actions+=("install_agent")
    fi

    items+=("──────────────────────────────────────"); actions+=("sep")
    items+=("⬅️   Назад");                             actions+=("back")

    show_arrow_menu "📊  Beszel" "${items[@]}"
    local choice=$?
    local action="${actions[$choice]:-back}"

    case "$action" in
        install_hub)     install_beszel ;;
        uninstall_hub)   uninstall_beszel ;;
        install_agent)   install_beszel_agent ;;
        uninstall_agent) uninstall_beszel_agent ;;
        *) return 0 ;;
    esac
}

install_beszel() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       📊 УСТАНОВКА BESZEL${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if is_beszel_installed; then
        echo
        print_success "Beszel уже установлен"
        echo
        show_continue_prompt || return 0
        return 0
    fi

    # ─── Домен ───
    local BESZEL_DOMAIN
    prompt_domain_with_retry "Домен для Beszel (например monitor.example.com):" BESZEL_DOMAIN true || return 1
    echo

    # ─── Сертификат ───
    local BESZEL_PORT="8090"
    local SSL_CERT SSL_KEY CERT_DOMAIN CERT_HOST_FULLCHAIN CERT_HOST_KEY
    local base_domain
    base_domain=$(extract_domain "$BESZEL_DOMAIN")

    if [ -f "/etc/letsencrypt/live/${BESZEL_DOMAIN}/fullchain.pem" ]; then
        print_success "Сертификат для ${BESZEL_DOMAIN} уже существует"
        CERT_DOMAIN="$BESZEL_DOMAIN"
        CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${BESZEL_DOMAIN}/fullchain.pem"
        CERT_HOST_KEY="/etc/letsencrypt/live/${BESZEL_DOMAIN}/privkey.pem"
    elif [ -f "/etc/letsencrypt/live/${base_domain}/fullchain.pem" ]; then
        print_success "Сертификат для ${base_domain} уже существует"
        CERT_DOMAIN="$base_domain"
        CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${base_domain}/fullchain.pem"
        CERT_HOST_KEY="/etc/letsencrypt/live/${base_domain}/privkey.pem"
    else
        show_arrow_menu "🔒  SSL сертификат" \
            "🌐  ACME (Let's Encrypt HTTP-01)" \
            "☁️   Cloudflare (DNS-01 Wildcard)" \
            "🔐  Самоподписанный сертификат" \
            "──────────────────────────────────────" \
            "❌  Отмена"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return 0

        case $cert_choice in
            0) # ACME
                reading "Email для Let's Encrypt:" BESZEL_EMAIL
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    return 1
                fi
                echo
                get_cert_acme "$BESZEL_DOMAIN" "$BESZEL_EMAIL" || return 1
                CERT_DOMAIN="$BESZEL_DOMAIN"
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${BESZEL_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${BESZEL_DOMAIN}/privkey.pem"
                ;;
            1) # Cloudflare
                reading "Email для Let's Encrypt:" BESZEL_EMAIL
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    return 1
                fi
                if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                    setup_cloudflare_credentials || return 1
                fi
                echo
                get_cert_cloudflare "$base_domain" "$BESZEL_EMAIL" || return 1
                CERT_DOMAIN="$base_domain"
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${base_domain}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${base_domain}/privkey.pem"
                ;;
            2) # Самоподписанный
                local SELF_SIGNED_DIR="${DIR_BESZEL}ssl"
                mkdir -p "$SELF_SIGNED_DIR"
                (
                    openssl req -x509 -nodes -days 3650 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
                        -keyout "${SELF_SIGNED_DIR}/privkey.pem" \
                        -out "${SELF_SIGNED_DIR}/fullchain.pem" \
                        -subj "/CN=${BESZEL_DOMAIN}" >/dev/null 2>&1
                ) &
                show_spinner "Генерация самоподписанного сертификата"
                CERT_DOMAIN="$BESZEL_DOMAIN"
                CERT_HOST_FULLCHAIN="${SELF_SIGNED_DIR}/fullchain.pem"
                CERT_HOST_KEY="${SELF_SIGNED_DIR}/privkey.pem"
                ;;
            *) return 0 ;;
        esac
    fi
    # ─── SSL-пути для nginx ───
    local NGINX_SSL_CERT NGINX_SSL_KEY
    if [[ "$CERT_HOST_FULLCHAIN" == /etc/letsencrypt/* ]]; then
        # Let's Encrypt — путь внутри контейнера совпадает с хостом
        NGINX_SSL_CERT="$CERT_HOST_FULLCHAIN"
        NGINX_SSL_KEY="$CERT_HOST_KEY"
    else
        # Самоподписанный — копируем в /opt/nginx/ssl/
        mkdir -p "${DIR_NGINX}ssl/${CERT_DOMAIN}"
        cp -f "$CERT_HOST_FULLCHAIN" "${DIR_NGINX}ssl/${CERT_DOMAIN}/fullchain.pem"
        cp -f "$CERT_HOST_KEY" "${DIR_NGINX}ssl/${CERT_DOMAIN}/privkey.pem"
        NGINX_SSL_CERT="/etc/nginx/ssl/${CERT_DOMAIN}/fullchain.pem"
        NGINX_SSL_KEY="/etc/nginx/ssl/${CERT_DOMAIN}/privkey.pem"
    fi

    # ─── Определяем listen-режим до запуска ensure_nginx ───
    local LISTEN_BLOCK REAL_IP_BLOCK
    if [ -f "${DIR_NGINX}nginx.conf" ] && grep -q 'listen unix:/dev/shm/nginx.sock' "${DIR_NGINX}nginx.conf"; then
        LISTEN_BLOCK="    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;"
        REAL_IP_BLOCK=$'\n    real_ip_header proxy_protocol;\n    set_real_ip_from unix:;'
    else
        LISTEN_BLOCK="    listen 443 ssl;\n    listen [::]:443 ssl;"
        REAL_IP_BLOCK=""
    fi

    local BESZEL_BLOCK
    BESZEL_BLOCK=$(cat <<NGINX
server {
    server_name ${BESZEL_DOMAIN};
$(echo -e "$LISTEN_BLOCK")
    http2 on;
${REAL_IP_BLOCK}

    ssl_certificate     ${NGINX_SSL_CERT};
    ssl_certificate_key ${NGINX_SSL_KEY};
    ssl_trusted_certificate ${NGINX_SSL_CERT};

    access_log /dev/stdout combined;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
)

    # ─── Подготовка файлов (директория, docker-compose, nginx conf.d) ───
    (
        mkdir -p "${DIR_BESZEL}"
        cat > "${DIR_BESZEL}docker-compose.yml" <<YAML
services:
  beszel:
    image: henrygd/beszel:latest
    container_name: beszel
    restart: unless-stopped
    ports:
      - "127.0.0.1:8090:8090"
    volumes:
      - ./beszel_data:/beszel_data
      - ./beszel_socket:/beszel_socket
    healthcheck:
      test: ["CMD", "/beszel", "health", "--url", "http://127.0.0.1:8090"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
YAML
        ensure_nginx
        nginx_add_block "beszel" "$BESZEL_BLOCK"
        if [ ! -f "${DIR_NGINX}nginx.conf" ]; then
            nginx_generate_minimal_conf
        fi
    ) &
    show_spinner "Подготовка файлов"

    # ─── Запускаем Beszel ───
    echo
    (
        cd "${DIR_BESZEL}" && docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Установка Beszel"

    # Запускаем/перезапускаем nginx
    (nginx_reload) &
    show_spinner "Запуск Nginx"

    echo
    print_success "Beszel успешно установлен"
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}🔗 Панель мониторинга:${NC}"
    echo -e "${WHITE}https://${BESZEL_DOMAIN}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

uninstall_beszel() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}       🗑️  УДАЛЕНИЕ BESZEL${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    echo -e "${YELLOW}⚠️  Beszel и все данные мониторинга будут удалены.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if ! confirm_action; then
        return
    fi

    echo
    (
        cd "${DIR_BESZEL}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление контейнеров Beszel"

    # Удаляем conf.d блок из nginx
    nginx_remove_block "beszel"

    # Перезапускаем или удаляем nginx
    if nginx_has_users; then
        (nginx_reload) &
        show_spinner "Перезапуск nginx"
    else
        (nginx_teardown) &
        show_spinner "Удаление nginx"
    fi

    rm -rf "${DIR_BESZEL}"

    print_success "Beszel удалён"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

install_beszel_agent() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    🖥️  ПОДКЛЮЧЕНИЕ АГЕНТА BESZEL${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if is_beszel_agent_installed; then
        echo
        print_success "Агент Beszel уже установлен"
        echo
        show_continue_prompt || return 0
        return 0
    fi

    echo
    echo -e "${DARKGRAY}Агент собирает метрики и отправляет их на панель Beszel.${NC}"
    echo -e "${DARKGRAY}В панели управления Beszel нажмите Добавить систему → скопируйте Ключ и Токен.${NC}"
    echo

    # ─── URL панели ───
    local BESZEL_HUB_URL
    reading_inline "URL панели Beszel (например https://monitor.example.com):" BESZEL_HUB_URL
    [[ $? -eq 2 ]] && return 1
    if [ -z "$BESZEL_HUB_URL" ]; then
        print_error "URL не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    # ─── Порт агента ───
    local BESZEL_AGENT_PORT
    reading_inline "Порт агента (по умолчанию 45876):" BESZEL_AGENT_PORT
    [[ $? -eq 2 ]] && return 1
    [ -z "$BESZEL_AGENT_PORT" ] && BESZEL_AGENT_PORT="45876"

    # ─── Публичный ключ (KEY) ───
    local BESZEL_KEY
    reading_inline "Ключ (публичный ключ из панели):" BESZEL_KEY
    [[ $? -eq 2 ]] && return 1
    if [ -z "$BESZEL_KEY" ]; then
        print_error "Ключ не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    # ─── TOKEN ───
    local BESZEL_TOKEN
    reading_inline "Токен (токен из панели):" BESZEL_TOKEN
    [[ $? -eq 2 ]] && return 1
    if [ -z "$BESZEL_TOKEN" ]; then
        print_error "Токен не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    # ─── Создаём docker-compose ───
    mkdir -p "${DIR_BESZEL_AGENT}"

    cat > "${DIR_BESZEL_AGENT}docker-compose.yml" <<YAML
services:
  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./beszel_agent_data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      LISTEN: "${BESZEL_AGENT_PORT}"
      KEY: "${BESZEL_KEY}"
      TOKEN: "${BESZEL_TOKEN}"
      HUB_URL: "${BESZEL_HUB_URL}"
    healthcheck:
      test: ["CMD", "/agent", "health"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
YAML

    # Сохраняем порт для удаления
    echo "$BESZEL_AGENT_PORT" > "${DIR_BESZEL_AGENT}port"

    # Открываем порт агента в UFW
    ufw allow "${BESZEL_AGENT_PORT}/tcp" >/dev/null 2>&1 || true

    echo
    (
        cd "${DIR_BESZEL_AGENT}" && docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Добавление агента Beszel"

    print_success "Агент Beszel добавлен и запущен"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

uninstall_beszel_agent() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}    🗑️  УДАЛЕНИЕ АГЕНТА BESZEL${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    echo -e "${YELLOW}⚠️  Агент Beszel будет остановлен и удалён.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if ! confirm_action; then
        return
    fi

    echo
    local AGENT_PORT_STORED
    AGENT_PORT_STORED=$(cat "${DIR_BESZEL_AGENT}port" 2>/dev/null)

    (
        cd "${DIR_BESZEL_AGENT}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление агента Beszel"

    if [ -n "$AGENT_PORT_STORED" ]; then
        ufw delete allow "${AGENT_PORT_STORED}/tcp" >/dev/null 2>&1 || true
    fi

    rm -rf "${DIR_BESZEL_AGENT}"

    print_success "Агент Beszel удалён"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}
