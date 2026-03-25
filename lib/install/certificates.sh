# ═══════════════════════════════════════════════
# СЕРТИФИКАТЫ
# ═══════════════════════════════════════════════

# Парсинг ошибки certbot в человекочитаемое сообщение
_parse_cert_error() {
    local log_file="$1"
    local raw
    raw=$(cat "$log_file" 2>/dev/null)

    if echo "$raw" | grep -qiE "dns.*problem|NXDOMAIN|no valid A|Incorrect TXT|DNS problem"; then
        echo "DNS-запись не настроена или не указывает на этот сервер"
    elif echo "$raw" | grep -qiE "connection refused|Could not connect|Timeout|timed out|port 80"; then
        echo "Порт 80 недоступен — проверьте файрвол и NAT"
    elif echo "$raw" | grep -qiE "too many requests|rate.limit|rate limit"; then
        echo "Превышен лимит запросов Let's Encrypt — повторите через час"
    elif echo "$raw" | grep -qiE "unauthorized|403|invalid response"; then
        echo "Домен не прошёл проверку — убедитесь что DNS указывает на этот сервер"
    elif echo "$raw" | grep -qiE "invalid domain|not a FQDN|malformed"; then
        echo "Некорректное доменное имя"
    elif echo "$raw" | grep -qiE "cloudflare.*error|API Token|dns_cloudflare"; then
        echo "Ошибка Cloudflare API — проверьте токен и права доступа"
    else
        local detail
        detail=$(grep -iE "Detail:|Error:|FAILED|Problem|certbot: error" "$log_file" 2>/dev/null \
            | grep -v "^-\|Saving debug\|^$" | head -2 \
            | sed 's/.*Detail: *//;s/.*Error: *//;s/.*certbot: error: *//')
        if [ -n "$detail" ]; then
            echo "$detail"
        else
            # Последний шанс: любые непустые строки из хвоста лога
            local _tail
            _tail=$(grep -vE '^[[:space:]]*$|^-{5}|Saving debug log|^Cert is due|^IMPORTANT' \
                "$log_file" 2>/dev/null | tail -4 | tr '\n' ' ' | sed 's/  */ /g;s/^ //;s/ $//')
            if [ -n "$_tail" ]; then
                echo "$_tail"
            else
                echo "Не удалось определить причину — проверьте DNS и сетевые настройки"
            fi
        fi
    fi
}

handle_certificates() {
    local -n domains_ref=$1
    local cert_method="$2"
    local email="$3"

    for domain in "${!domains_ref[@]}"; do
        local base_domain
        base_domain=$(extract_domain "$domain")

        # Проверяем наличие сертификата
        if [ -d "/etc/letsencrypt/live/$domain" ] || [ -d "/etc/letsencrypt/live/$base_domain" ]; then
            print_success "Сертификат для $domain уже существует"
            continue
        fi

        case "$cert_method" in
            1)
                # Cloudflare DNS-01 (wildcard)
                get_cert_cloudflare "$base_domain" "$email" || return 1
                ;;
            2)
                # ACME HTTP-01
                get_cert_acme "$domain" "$email" || return 1
                ;;
            *)
                print_error "Неизвестный метод сертификации"
                return 1
                ;;
        esac
    done

    echo
}

detect_cert_method() {
    local domain="$1"
    local base_domain
    base_domain=$(extract_domain "$domain")

    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        echo "2"
    elif [ -d "/etc/letsencrypt/live/$base_domain" ] && [ -f "/etc/letsencrypt/live/$base_domain/fullchain.pem" ]; then
        echo "1"
    else
        echo "2"
    fi
}

check_if_certificates_needed() {
    local -n domains_ref=$1

    for domain in "${!domains_ref[@]}"; do
        local base_domain
        base_domain=$(extract_domain "$domain")

        if [ ! -d "/etc/letsencrypt/live/$domain" ] && [ ! -d "/etc/letsencrypt/live/$base_domain" ]; then
            return 0
        fi
    done

    return 1
}

# Устанавливает certbot если не установлен
_ensure_certbot() {
    if command -v certbot >/dev/null 2>&1; then
        return 0
    fi
    (
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq certbot python3-certbot-dns-cloudflare >/dev/null 2>&1
    ) &
    show_spinner "Установка certbot"
    if ! command -v certbot >/dev/null 2>&1; then
        print_error "certbot не удалось установить. Установите вручную: apt install certbot"
        return 1
    fi
}

get_cert_cloudflare() {
    local domain="$1"
    local email="$2"

    _ensure_certbot || return 1

    if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
        print_error "Файл /etc/letsencrypt/cloudflare.ini не найден"
        return 1
    fi

    local _tmp_log _exit_file
    _tmp_log=$(mktemp)
    _exit_file="${_tmp_log}.exit"

    (
        set +e
        certbot certonly --dns-cloudflare \
            --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
            --dns-cloudflare-propagation-seconds 30 \
            -d "$domain" -d "*.$domain" \
            --email "$email" --agree-tos --non-interactive \
            --key-type ecdsa > "$_tmp_log" 2>&1
        echo $? > "$_exit_file"
    ) &
    show_spinner "Получение wildcard сертификата для *.$domain"

    local _exit_code
    _exit_code=$(cat "$_exit_file" 2>/dev/null || echo 1)
    if [ "$_exit_code" -ne 0 ] || [ ! -d "/etc/letsencrypt/live/$domain" ]; then
        local _cert_reason _raw_log
        _cert_reason=$(_parse_cert_error "$_tmp_log")
        _raw_log=$(grep -vE '^[[:space:]]*$' "$_tmp_log" 2>/dev/null | tail -35)
        rm -f "$_tmp_log" "$_exit_file"
        echo
        print_error "Не удалось получить сертификат для $domain"
        echo -e "   ${DARKGRAY}Причина: ${_cert_reason}${NC}"
        # Показываем развёрнутый лог только если он содержит больше одной новой строки (=не дублирует Причину)
        local _raw_lines
        _raw_lines=$(echo "$_raw_log" | wc -l)
        if [ -n "$_raw_log" ] && [ "$_raw_lines" -gt 1 ]; then
            echo
            echo -e "${DARKGRAY}── Вывод certbot ───────────────────────${NC}"
            echo "$_raw_log"
            echo -e "${DARKGRAY}────────────────────────────────────────${NC}"
        fi
        return 1
    fi

    rm -f "$_tmp_log" "$_exit_file"

    # Добавляем cron для обновления
    local _deploy_hook='for d in /opt/nginx/ssl/*/; do dn=$(basename "$d"); src="/etc/letsencrypt/live/$dn"; [ -f "$src/fullchain.pem" ] && cp -fL "$src/fullchain.pem" "$d/fullchain.pem" && cp -fL "$src/privkey.pem" "$d/privkey.pem"; done; cd /opt/nginx 2>/dev/null && docker compose restart nginx 2>/dev/null'
    local cron_rule="0 3 * * * certbot renew --quiet --deploy-hook '${_deploy_hook}' 2>/dev/null"
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$cron_rule") | crontab -
    fi
}

get_cert_acme() {
    local domain="$1"
    local email="$2"

    _ensure_certbot || return 1

    local _tmp_log _exit_file
    _tmp_log=$(mktemp)
    _exit_file="${_tmp_log}.exit"

    # Открываем порт 80 синхронно — ДО запуска certbot
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true
    # iptables fallback если ufw не управляет правилами
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    sleep 1

    (
        set +e
        certbot certonly --standalone \
            -d "$domain" \
            --email "$email" --agree-tos --non-interactive \
            --http-01-port 80 \
            --key-type ecdsa > "$_tmp_log" 2>&1
        echo $? > "$_exit_file"
    ) &
    show_spinner "Получение сертификата для $domain"

    # Закрываем порт 80 синхронно — ПОСЛЕ завершения certbot
    ufw delete allow 80/tcp >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true
    iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true

    local _exit_code
    _exit_code=$(cat "$_exit_file" 2>/dev/null || echo 1)
    if [ "$_exit_code" -ne 0 ] || [ ! -d "/etc/letsencrypt/live/$domain" ]; then
        local _cert_reason _raw_log
        _cert_reason=$(_parse_cert_error "$_tmp_log")
        _raw_log=$(grep -vE '^[[:space:]]*$' "$_tmp_log" 2>/dev/null | tail -35)
        rm -f "$_tmp_log" "$_exit_file"
        echo
        print_error "Не удалось получить сертификат для $domain"
        echo -e "   ${DARKGRAY}Причина: ${_cert_reason}${NC}"
        local _raw_lines
        _raw_lines=$(echo "$_raw_log" | wc -l)
        if [ -n "$_raw_log" ] && [ "$_raw_lines" -gt 1 ]; then
            echo
            echo -e "${DARKGRAY}── Вывод certbot ────────────────────────────${NC}"
            echo "$_raw_log"
            echo -e "${DARKGRAY}────────────────────────────────────────────────${NC}"
        fi
        return 1
    fi

    rm -f "$_tmp_log" "$_exit_file"

    local _deploy_hook='for d in /opt/nginx/ssl/*/; do dn=$(basename "$d"); src="/etc/letsencrypt/live/$dn"; [ -f "$src/fullchain.pem" ] && cp -fL "$src/fullchain.pem" "$d/fullchain.pem" && cp -fL "$src/privkey.pem" "$d/privkey.pem"; done; cd /opt/nginx 2>/dev/null && docker compose restart nginx 2>/dev/null'
    local _pre_hook='ufw allow 80/tcp >/dev/null 2>&1; ufw reload >/dev/null 2>&1; iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true; sleep 2'
    local _post_hook='ufw delete allow 80/tcp >/dev/null 2>&1; ufw reload >/dev/null 2>&1; iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true'
    local cron_rule="0 3 * * * certbot renew --quiet --pre-hook '${_pre_hook}' --post-hook '${_post_hook}' --deploy-hook '${_deploy_hook}' 2>/dev/null"
    local existing_cron
    existing_cron=$(crontab -l 2>/dev/null)
    if echo "$existing_cron" | grep -q "certbot renew"; then
        # Если cron уже есть, но без pre-hook (например от Cloudflare) — обновляем его
        if ! echo "$existing_cron" | grep -q "pre-hook"; then
            echo "$existing_cron" | grep -v "certbot renew" | { cat; echo "$cron_rule"; } | crontab -
        fi
    else
        (echo "$existing_cron"; echo "$cron_rule") | crontab -
    fi
}

setup_cloudflare_credentials() {
    reading "Введите Cloudflare API Token:" CF_TOKEN || return 1

    # Проверяем токен
    local check
    check=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_TOKEN" | jq -r '.success' 2>/dev/null)

    if [ "$check" != "true" ]; then
        print_error "Cloudflare API Token невалиден"
        return 1
    fi
    print_success "Cloudflare API Token подтверждён"

    mkdir -p /etc/letsencrypt
    cat > /etc/letsencrypt/cloudflare.ini <<EOF
dns_cloudflare_api_token = $CF_TOKEN
EOF
    chmod 600 /etc/letsencrypt/cloudflare.ini
}
