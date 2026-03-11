# ═══════════════════════════════════════════════════
# BESZEL — МОНИТОРИНГ СЕРВЕРА
# ═══════════════════════════════════════════════════

DIR_BESZEL="/opt/beszel/"

is_beszel_installed() {
    [ -f "${DIR_BESZEL}docker-compose.yml" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "beszel"
}

manage_beszel() {
    local -a items=()
    local -a actions=()

    if is_beszel_installed; then
        items+=("🗑️   Удалить Beszel");    actions+=("uninstall")
    else
        items+=("📥  Установить Beszel");  actions+=("install")
    fi
    items+=("──────────────────────────────────────"); actions+=("sep")
    items+=("❌  Назад");                              actions+=("back")

    show_arrow_menu "📊  Beszel" "${items[@]}"
    local choice=$?
    local action="${actions[$choice]:-back}"

    case "$action" in
        install)   install_beszel ;;
        uninstall) uninstall_beszel ;;
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
        print_success "Beszel уже установлен"
        echo
        show_continue_prompt || return 0
        return 0
    fi

    # ─── Домен ───
    echo -e "${YELLOW}Укажите домен для панели мониторинга Beszel${NC}"
    echo -e "${DARKGRAY}Пример: monitor.example.com${NC}"
    reading "Домен для Beszel:" BESZEL_DOMAIN

    if [ -z "$BESZEL_DOMAIN" ]; then
        print_error "Домен не может быть пустым"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    # Проверяем DNS
    if ! check_domain "$BESZEL_DOMAIN" "true"; then
        echo
        show_continue_prompt || return 1
        return 1
    fi

    # ─── Сертификат ───
    echo
    echo -e "${YELLOW}Выберите способ получения SSL сертификата:${NC}"
    echo
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
