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
    elif echo "$raw" | grep -qiE "gcore.*error|dns_gcore|apitoken.*gcore"; then
        echo "Ошибка Gcore API — проверьте токен"
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

# Реальное имя подкаталога в /etc/letsencrypt/live/ (регистр, линия -0001 не ищем).
le_live_basename() {
    local d="$1"
    local low cand
    low=$(printf '%s' "$d" | tr '[:upper:]' '[:lower:]')
    for cand in "$d" "$low"; do
        if [ -f "/etc/letsencrypt/live/${cand}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${cand}/privkey.pem" ]; then
            printf '%s' "$cand"
            return 0
        fi
    done
    if [ -d /etc/letsencrypt/live ]; then
        for dir in /etc/letsencrypt/live/*/; do
            [ -d "$dir" ] || continue
            cand=$(basename "$dir")
            if [ "$(printf '%s' "$cand" | tr '[:upper:]' '[:lower:]')" = "$low" ]; then
                if [ -f "${dir}fullchain.pem" ] && [ -f "${dir}privkey.pem" ]; then
                    printf '%s' "$cand"
                    return 0
                fi
            fi
        done
    fi
    return 1
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
            print_cert_exists "$domain"
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
            3)
                # Gcore DNS-01 (wildcard)
                get_cert_gcore "$base_domain" "$email" || return 1
                ;;
            *)
                print_error "Неизвестный метод сертификации"
                return 1
                ;;
        esac
    done

    # Не добавляем лишние пустые строки — следующий шаг должен идти сразу.
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

# Устанавливает certbot и docker если не установлены
_ensure_system_deps() {
    local _need_certbot=false _need_docker=false
    command -v certbot >/dev/null 2>&1 || _need_certbot=true
    { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; } || _need_docker=true

    [ "$_need_certbot" = false ] && [ "$_need_docker" = false ] && return 0

    (
        export DEBIAN_FRONTEND=noninteractive
        local DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'
        systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
        local _lw=0
        while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock \
              /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend \
              >/dev/null 2>&1; do
            sleep 2; _lw=$(( _lw + 2 )); [ "$_lw" -ge 120 ] && break
        done
        apt-get update -qq >/dev/null 2>&1
        if [ "$_need_certbot" = true ]; then
            apt-get install -y -qq $DPKG_OPTS certbot python3-certbot-dns-cloudflare >/dev/null 2>&1
        fi
        if [ "$_need_docker" = true ]; then
            apt-get install -y -qq $DPKG_OPTS ca-certificates curl >/dev/null 2>&1
            dfc_install_docker_engine_official >/dev/null 2>&1 || true
        fi
     ) </dev/null &    show_spinner --step "Обновление пакетов системы"

    if [ "$_need_certbot" = true ] && ! command -v certbot >/dev/null 2>&1; then
        print_error "certbot не удалось установить. Установите вручную: apt install certbot"
        return 1
    fi
    if [ "$_need_docker" = true ] && { ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; }; then
        print_error "Docker не удалось установить. Установите вручную: curl -fsSL https://get.docker.com | sh"
        return 1
    fi
}

# Для обратной совместимости: вызывает _ensure_system_deps
_ensure_certbot() { _ensure_system_deps; }

# Устанавливает плагин certbot-dns-gcore через pip3 если ещё не установлен
_ensure_gcore_plugin() {
    if python3 -c "import certbot_dns_gcore" >/dev/null 2>&1; then
        return 0
    fi
    (
        export DEBIAN_FRONTEND=noninteractive
        local DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'
        # Устанавливаем pip3 если отсутствует
        if ! command -v pip3 >/dev/null 2>&1; then
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y -qq $DPKG_OPTS python3-pip >/dev/null 2>&1
        fi
        pip3 install --quiet certbot-dns-gcore >/dev/null 2>&1
     ) </dev/null &    show_spinner --step "Установка плагина Gcore DNS"
    if ! python3 -c "import certbot_dns_gcore" >/dev/null 2>&1; then
        print_error "Не удалось установить certbot-dns-gcore. Установите вручную: pip3 install certbot-dns-gcore"
        return 1
    fi
}

get_cert_cloudflare() {
    local domain="$1"
    local email="$2"
    local dnorm
    dnorm=$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')

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
            --dns-cloudflare-propagation-seconds 60 \
            -d "$dnorm" -d "*.$dnorm" \
            --email "$email" --agree-tos --non-interactive \
            --key-type ecdsa > "$_tmp_log" 2>&1
        _ec=$?
        if [ "$_ec" -ne 0 ] && [ -f "$_tmp_log" ] && le_live_basename "$dnorm" >/dev/null 2>&1; then
            if grep -qiE 'Certificate not yet due for renewal|not yet due for renewal; no action taken' "$_tmp_log" 2>/dev/null; then
                _ec=0
            fi
        fi
        echo "$_ec" > "$_exit_file"
     ) </dev/null &    show_spinner --step "Получение wildcard сертификата для *.$dnorm"
    echo

    local _exit_code
    _exit_code=$(cat "$_exit_file" 2>/dev/null || echo 1)
    local _lebn
    _lebn=$(le_live_basename "$dnorm" 2>/dev/null) || _lebn=""
    if [ "$_exit_code" -ne 0 ] && [ -n "$_lebn" ] && [ -f "$_tmp_log" ] && \
        grep -qiE 'Certificate not yet due for renewal|not yet due for renewal; no action taken' "$_tmp_log" 2>/dev/null; then
        _exit_code=0
    fi
    if [ "$_exit_code" -ne 0 ] || [ -z "$_lebn" ]; then
        local _cert_reason _raw_log
        _cert_reason=$(_parse_cert_error "$_tmp_log")
        _raw_log=$(grep -vE '^[[:space:]]*$' "$_tmp_log" 2>/dev/null | tail -35)
        rm -f "$_tmp_log" "$_exit_file"
        echo
        print_error "Не удалось получить сертификат для $dnorm"
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
    # Let's Encrypt и каталог live/ — в нижнем регистре; иначе дубликат и «не найдено».
    local dnorm
    dnorm=$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')

    _ensure_certbot || return 1

    local _tmp_log _exit_file
    _tmp_log=$(mktemp)
    _exit_file="${_tmp_log}.exit"

    # Временно открываем 80 для HTTP-01 (правило с меткой — снимается ниже и в post-hook renew)
    ufw_allow_http01_temp
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    sleep 2

    (
        set +e
        certbot certonly --standalone \
            -d "$dnorm" \
            --email "$email" --agree-tos --non-interactive \
            --http-01-port 80 \
            --key-type ecdsa > "$_tmp_log" 2>&1
        _ec=$?
        if [ "$_ec" -ne 0 ] && [ -f "$_tmp_log" ] && le_live_basename "$dnorm" >/dev/null 2>&1; then
            if grep -qiE 'Certificate not yet due for renewal|not yet due for renewal; no action taken' "$_tmp_log" 2>/dev/null; then
                _ec=0
            fi
        fi
        echo "$_ec" > "$_exit_file"
     ) </dev/null &    show_spinner --step "Получение сертификата для $dnorm"

    ufw_revert_http01_temp
    iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true

    local _exit_code
    _exit_code=$(cat "$_exit_file" 2>/dev/null || echo 1)
    local _lebn
    _lebn=$(le_live_basename "$dnorm" 2>/dev/null) || _lebn=""
    if [ "$_exit_code" -ne 0 ] && [ -n "$_lebn" ] && [ -f "$_tmp_log" ] && \
        grep -qiE 'Certificate not yet due for renewal|not yet due for renewal; no action taken' "$_tmp_log" 2>/dev/null; then
        _exit_code=0
    fi
    if [ "$_exit_code" -ne 0 ] || [ -z "$_lebn" ]; then
        local _cert_reason _raw_log
        _cert_reason=$(_parse_cert_error "$_tmp_log")
        _raw_log=$(grep -vE '^[[:space:]]*$' "$_tmp_log" 2>/dev/null | tail -35)
        rm -f "$_tmp_log" "$_exit_file"
        echo
        print_error "Не удалось получить сертификат для $dnorm"
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
    local _hook_path="${DIR_SCRIPT%/}/lib/extra/ufw_certbot_http01_hook.sh"
    local _pre_hook="bash ${_hook_path} pre"
    local _post_hook="bash ${_hook_path} post"
    local cron_rule="0 3 * * * certbot renew --quiet --pre-hook '${_pre_hook}' --post-hook '${_post_hook}' --deploy-hook '${_deploy_hook}' 2>/dev/null"
    local existing_cron
    existing_cron=$(crontab -l 2>/dev/null)
    if echo "$existing_cron" | grep -q "certbot renew"; then
        if echo "$existing_cron" | grep -q "ufw_certbot_http01_hook.sh"; then
            :
        elif ! echo "$existing_cron" | grep -q "pre-hook"; then
            # Был renew без pre-hook (например Cloudflare) — ставим строку с HTTP-01 hooks
            echo "$existing_cron" | grep -v "certbot renew" | { cat; echo "$cron_rule"; } | crontab -
        else
            # Старый inline pre/post (ufw allow/delete 80) — заменяем на вызов hook-скрипта
            echo "$existing_cron" | grep -v "certbot renew" | { cat; echo "$cron_rule"; } | crontab -
        fi
    else
        (echo "$existing_cron"; echo "$cron_rule") | crontab -
    fi
}

setup_cloudflare_credentials() {
    reading "Введите Cloudflare API Token:" CF_TOKEN || return 1

    # Определяем тип токена:
    # Новый API Token (содержит буквы верхнего регистра — cfut_, cf_, etc.)
    # Старый Global API Key (только hex, строчные буквы и цифры)
    local _is_api_token=false
    if [[ "$CF_TOKEN" =~ [A-Z] ]] || [[ "$CF_TOKEN" =~ _ ]]; then
        _is_api_token=true
    fi

    local _cf_email=""
    if [ "$_is_api_token" = false ]; then
        reading "Введите Cloudflare Email (для Global API Key):" _cf_email || return 1
    fi

    # Шаг 1: проверяем что токен валиден и не отозван
    local _auth_header
    if [ "$_is_api_token" = true ]; then
        _auth_header="Authorization: Bearer $CF_TOKEN"
    else
        _auth_header="X-Auth-Key: $CF_TOKEN"
    fi

    local check
    if [ "$_is_api_token" = true ]; then
        check=$(curl -sS --connect-timeout 10 --max-time 45 -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
            -H "$_auth_header" | jq -r '.success' 2>/dev/null)
        if [ "$check" != "true" ]; then
            print_error "Cloudflare API Token невалиден или отозван"
            echo
            show_continue_prompt
            return 1
        fi
    fi

    # Шаг 2: проверяем доступ к зонам (Zone:Read)
    local zones_resp zones_ok zone_id
    if [ "$_is_api_token" = true ]; then
        zones_resp=$(curl -sS --connect-timeout 10 --max-time 45 -X GET "https://api.cloudflare.com/client/v4/zones?per_page=1" \
            -H "$_auth_header" -H "Content-Type: application/json" 2>/dev/null)
    else
        zones_resp=$(curl -sS --connect-timeout 10 --max-time 45 -X GET "https://api.cloudflare.com/client/v4/zones?per_page=1" \
            -H "X-Auth-Email: $_cf_email" -H "$_auth_header" -H "Content-Type: application/json" 2>/dev/null)
    fi
    zones_ok=$(echo "$zones_resp" | jq -r '.success' 2>/dev/null)
    zone_id=$(echo "$zones_resp" | jq -r '.result[0].id // empty' 2>/dev/null)

    if [ "$zones_ok" != "true" ]; then
        local _zones_err
        _zones_err=$(echo "$zones_resp" | jq -r '.errors[0].code // empty' 2>/dev/null)
        print_error "Токен не имеет доступа к зонам (код ошибки: ${_zones_err:-10000})"
        echo -e "   ${DARKGRAY}Убедитесь что токен имеет разрешение: Zone → Read${NC}"
        echo
        show_continue_prompt
        return 1
    fi

    # Шаг 3: проверяем Zone:DNS:Edit — пробуем создать тестовую TXT-запись и сразу удалить
    # GET /dns_records проверяет только Read, а certbot нужен Edit (POST)
    if [ -n "$zone_id" ]; then
        local create_resp create_ok record_id _dns_write_err
        if [ "$_is_api_token" = true ]; then
            create_resp=$(curl -sS --connect-timeout 10 --max-time 45 -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
                -H "$_auth_header" -H "Content-Type: application/json" \
                --data '{"type":"TXT","name":"_dfc-acme-test","content":"dfc-write-test","ttl":60}' 2>/dev/null)
        else
            create_resp=$(curl -sS --connect-timeout 10 --max-time 45 -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
                -H "X-Auth-Email: $_cf_email" -H "$_auth_header" -H "Content-Type: application/json" \
                --data '{"type":"TXT","name":"_dfc-acme-test","content":"dfc-write-test","ttl":60}' 2>/dev/null)
        fi
        create_ok=$(echo "$create_resp" | jq -r '.success' 2>/dev/null)

        if [ "$create_ok" = "true" ]; then
            # Удаляем тестовую запись
            record_id=$(echo "$create_resp" | jq -r '.result.id // empty' 2>/dev/null)
            if [ -n "$record_id" ]; then
                if [ "$_is_api_token" = true ]; then
                    curl -sS --connect-timeout 10 --max-time 45 -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
                        -H "$_auth_header" >/dev/null 2>&1
                else
                    curl -sS --connect-timeout 10 --max-time 45 -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
                        -H "X-Auth-Email: $_cf_email" -H "$_auth_header" >/dev/null 2>&1
                fi
            fi
        else
            _dns_write_err=$(echo "$create_resp" | jq -r '.errors[0].code // empty' 2>/dev/null)
            print_error "Токен не имеет прав на создание DNS-записей (код: ${_dns_write_err:-10000})"
            echo -e "   ${DARKGRAY}Токен имеет Zone:Read, но НЕТ Zone:DNS:Edit — именно оно нужно certbot${NC}"
            echo -e "   ${DARKGRAY}Создайте новый токен: dash.cloudflare.com/profile/api-tokens${NC}"
            echo -e "   ${DARKGRAY}Шаблон: Edit zone DNS → выберите нужную зону${NC}"
            echo
            show_continue_prompt
            return 1
        fi
    fi

    print_success "Cloudflare API Token подтверждён"

    mkdir -p /etc/letsencrypt
    if [ "$_is_api_token" = true ]; then
        cat > /etc/letsencrypt/cloudflare.ini <<EOF
dns_cloudflare_api_token = $CF_TOKEN
EOF
    else
        cat > /etc/letsencrypt/cloudflare.ini <<EOF
dns_cloudflare_email = $_cf_email
dns_cloudflare_api_key = $CF_TOKEN
EOF
    fi
    chmod 600 /etc/letsencrypt/cloudflare.ini
}

setup_gcore_credentials() {
    reading "Введите Gcore API Token:" GC_TOKEN || return 1

    # Проверяем что токен валиден через Gcore API
    local check_resp check_ok
    check_resp=$(curl -sS --connect-timeout 10 --max-time 30 \
        -X GET "https://api.gcore.com/dns/v2/zones?limit=1" \
        -H "Authorization: APIKey $GC_TOKEN" \
        -H "Content-Type: application/json" 2>/dev/null)
    check_ok=$(echo "$check_resp" | grep -c '"id"' 2>/dev/null || true)

    # Gcore возвращает JSON со списком зон — успех если нет "error"
    if echo "$check_resp" | grep -qiE '"error"|"status":4[0-9]{2}|Unauthorized|Forbidden'; then
        print_error "Gcore API Token невалиден или нет прав доступа к DNS зонам"
        echo -e "   ${DARKGRAY}Убедитесь что токен имеет доступ к DNS в личном кабинете Gcore${NC}"
        echo
        show_continue_prompt
        return 1
    fi

    print_success "Gcore API Token подтверждён"

    mkdir -p /etc/letsencrypt
    cat > /etc/letsencrypt/gcore.ini <<EOF
dns_gcore_apitoken = $GC_TOKEN
EOF
    chmod 600 /etc/letsencrypt/gcore.ini
}

get_cert_gcore() {
    local domain="$1"
    local email="$2"
    local dnorm
    dnorm=$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')

    _ensure_certbot || return 1
    _ensure_gcore_plugin || return 1

    if [ ! -f "/etc/letsencrypt/gcore.ini" ]; then
        print_error "Файл /etc/letsencrypt/gcore.ini не найден"
        return 1
    fi

    local _tmp_log _exit_file
    _tmp_log=$(mktemp)
    _exit_file="${_tmp_log}.exit"

    (
        set +e
        certbot certonly --authenticator dns-gcore \
            --dns-gcore-credentials /etc/letsencrypt/gcore.ini \
            --dns-gcore-propagation-seconds 80 \
            -d "$dnorm" -d "*.$dnorm" \
            --email "$email" --agree-tos --non-interactive \
            --key-type ecdsa > "$_tmp_log" 2>&1
        _ec=$?
        if [ "$_ec" -ne 0 ] && [ -f "$_tmp_log" ] && le_live_basename "$dnorm" >/dev/null 2>&1; then
            if grep -qiE 'Certificate not yet due for renewal|not yet due for renewal; no action taken' "$_tmp_log" 2>/dev/null; then
                _ec=0
            fi
        fi
        echo "$_ec" > "$_exit_file"
     ) </dev/null &    show_spinner --step "Получение wildcard сертификата для *.$dnorm (Gcore)"
    echo

    local _exit_code
    _exit_code=$(cat "$_exit_file" 2>/dev/null || echo 1)
    local _lebn
    _lebn=$(le_live_basename "$dnorm" 2>/dev/null) || _lebn=""
    if [ "$_exit_code" -ne 0 ] && [ -n "$_lebn" ] && [ -f "$_tmp_log" ] && \
        grep -qiE 'Certificate not yet due for renewal|not yet due for renewal; no action taken' "$_tmp_log" 2>/dev/null; then
        _exit_code=0
    fi
    if [ "$_exit_code" -ne 0 ] || [ -z "$_lebn" ]; then
        local _cert_reason _raw_log
        _cert_reason=$(_parse_cert_error "$_tmp_log")
        _raw_log=$(grep -vE '^[[:space:]]*$' "$_tmp_log" 2>/dev/null | tail -35)
        rm -f "$_tmp_log" "$_exit_file"
        echo
        print_error "Не удалось получить сертификат для $dnorm"
        echo -e "   ${DARKGRAY}Причина: ${_cert_reason}${NC}"
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

    # Добавляем cron для обновления (Gcore DNS-01 не требует открытия портов)
    local _deploy_hook='for d in /opt/nginx/ssl/*/; do dn=$(basename "$d"); src="/etc/letsencrypt/live/$dn"; [ -f "$src/fullchain.pem" ] && cp -fL "$src/fullchain.pem" "$d/fullchain.pem" && cp -fL "$src/privkey.pem" "$d/privkey.pem"; done; cd /opt/nginx 2>/dev/null && docker compose restart nginx 2>/dev/null'
    local cron_rule="0 3 * * * certbot renew --quiet --deploy-hook '${_deploy_hook}' 2>/dev/null"
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$cron_rule") | crontab -
    fi
}
