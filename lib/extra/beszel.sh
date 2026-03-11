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

    if is_beszel_installed; then
        items+=("🗑️   Удалить панель Beszel"); actions+=("uninstall_hub")
    else
        items+=("📊  Установить панель Beszel"); actions+=("install_hub")
    fi

    items+=("──────────────────────────────────────"); actions+=("sep")

    if is_beszel_agent_installed; then
        items+=("🗑️   Удалить агент Beszel");   actions+=("uninstall_agent")
    else
        items+=("🖥️   Подключить агент (ноду)"); actions+=("install_agent")
    fi

    items+=("──────────────────────────────────────"); actions+=("sep")
    items+=("❌  Назад");                             actions+=("back")

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

    # ─── Сертификат ───
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
            local SSL_CERT="/etc/letsencrypt/live/${BESZEL_DOMAIN}/fullchain.pem"
            local SSL_KEY="/etc/letsencrypt/live/${BESZEL_DOMAIN}/privkey.pem"
            ;;
        1) # Cloudflare
            local base_domain
            base_domain=$(extract_domain "$BESZEL_DOMAIN")
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
            local SSL_CERT="/etc/letsencrypt/live/${base_domain}/fullchain.pem"
            local SSL_KEY="/etc/letsencrypt/live/${base_domain}/privkey.pem"
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
            local SSL_CERT="${SELF_SIGNED_DIR}/fullchain.pem"
            local SSL_KEY="${SELF_SIGNED_DIR}/privkey.pem"
            ;;
        *) return 0 ;;
    esac

    # ─── Создаём директорию и docker-compose ───
    mkdir -p "${DIR_BESZEL}data"

    cat > "${DIR_BESZEL}docker-compose.yml" <<YAML
services:
  beszel:
    image: henrygd/beszel:latest
    container_name: beszel
    restart: unless-stopped
    ports:
      - "127.0.0.1:8090:8090"
    volumes:
      - ./data:/beszel_data
YAML

    # ─── Добавляем server block в nginx.conf ───
    local NGINX_CONF="/opt/remnawave/nginx.conf"
    if [ -f "$NGINX_CONF" ]; then
        # Удаляем существующий блок beszel если есть
        sed -i '/# >>> BESZEL/,/# <<< BESZEL/d' "$NGINX_CONF"

        # Вставляем перед закрывающей скобкой http {}
        local BESZEL_BLOCK
        BESZEL_BLOCK=$(cat <<NGINX
# >>> BESZEL
server {
    listen 443 ssl;
    server_name ${BESZEL_DOMAIN};

    ssl_certificate     ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;

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
# <<< BESZEL
NGINX
)
        # Вставляем перед последней закрывающей } (конец http блока)
        awk -v block="$BESZEL_BLOCK" '
        {lines[NR]=$0}
        END {
            for(i=NR;i>=1;i--) {
                if(lines[i] ~ /^}/) { insert_at=i; break }
            }
            for(i=1;i<=NR;i++) {
                if(i==insert_at) { print block }
                print lines[i]
            }
        }' "$NGINX_CONF" > "${NGINX_CONF}.tmp" && mv "${NGINX_CONF}.tmp" "$NGINX_CONF"
    fi

    # ─── Запускаем ───
    echo
    (
        cd "${DIR_BESZEL}" && docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск Beszel"

    # Перезапускаем nginx если он есть
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "remnawave-nginx"; then
        (docker restart remnawave-nginx >/dev/null 2>&1) &
        show_spinner "Перезапуск nginx"
    fi

    echo
    print_success "Beszel установлен"
    echo
    echo -e "${YELLOW}🔗 Панель мониторинга:${NC}"
    echo -e "${WHITE}https://${BESZEL_DOMAIN}${NC}"
    echo
    echo -e "${DARKGRAY}При первом входе создайте администратора.${NC}"
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

    # Удаляем блок из nginx
    local NGINX_CONF="/opt/remnawave/nginx.conf"
    if [ -f "$NGINX_CONF" ]; then
        sed -i '/# >>> BESZEL/,/# <<< BESZEL/d' "$NGINX_CONF"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "remnawave-nginx"; then
            (docker restart remnawave-nginx >/dev/null 2>&1) &
            show_spinner "Перезапуск nginx"
        fi
    fi

    rm -rf "${DIR_BESZEL}"

    echo
    print_success "Beszel удалён"
    echo
    show_continue_prompt || return 0
}

install_beszel_agent() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    🖥️  ПОДКЛЮЧЕНИЕ АГЕНТА BESZEL${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    if is_beszel_agent_installed; then
        echo
        print_success "Агент Beszel уже установлен"
        echo
        show_continue_prompt || return 0
        return 0
    fi

    echo
    echo -e "${DARKGRAY}Агент собирает метрики и отправляет их на панель Beszel.${NC}"
    echo -e "${DARKGRAY}Получите публичный ключ в панели: Настройки → Добавить сервер.${NC}"
    echo

    # ─── Адрес панели ───
    local BESZEL_HUB
    reading_inline "Адрес панели Beszel (например monitor.example.com):" BESZEL_HUB
    [[ $? -eq 2 ]] && return 1
    if [ -z "$BESZEL_HUB" ]; then
        print_error "Адрес не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    # ─── Порт агента ───
    local BESZEL_AGENT_PORT
    reading_inline "Порт агента (по умолчанию 45876):" BESZEL_AGENT_PORT
    [[ $? -eq 2 ]] && return 1
    [ -z "$BESZEL_AGENT_PORT" ] && BESZEL_AGENT_PORT="45876"

    # ─── Публичный ключ ───
    local BESZEL_KEY
    reading_inline "Публичный ключ из панели Beszel:" BESZEL_KEY
    [[ $? -eq 2 ]] && return 1
    if [ -z "$BESZEL_KEY" ]; then
        print_error "Публичный ключ не может быть пустым"
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
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      PORT: "${BESZEL_AGENT_PORT}"
      KEY: "${BESZEL_KEY}"
YAML

    # Открываем порт агента
    ufw allow "${BESZEL_AGENT_PORT}/tcp" >/dev/null 2>&1 || true

    echo
    (
        cd "${DIR_BESZEL_AGENT}" && docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск агента Beszel"

    echo
    print_success "Агент Beszel запущен"
    echo
    echo -e "${YELLOW}📋 Агент подключён к:${NC} ${WHITE}${BESZEL_HUB}${NC}"
    echo -e "${YELLOW}🔌 Порт агента:${NC}        ${WHITE}${BESZEL_AGENT_PORT}${NC}"
    echo -e "${DARKGRAY}Убедитесь, что порт ${BESZEL_AGENT_PORT} открыт в файрволе.${NC}"
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
    (
        cd "${DIR_BESZEL_AGENT}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление агента Beszel"

    rm -rf "${DIR_BESZEL_AGENT}"

    echo
    print_success "Агент Beszel удалён"
    echo
    show_continue_prompt || return 0
}
