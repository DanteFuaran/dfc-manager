# ─── Восстановление конфига Nginx до заводского состояния (соло-панель) ───
restore_nginx_config() {
    if [ ! -f "/opt/remnawave/.env" ]; then
        clear
        print_error "Файл /opt/remnawave/.env не найден"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    # ─── Определяем домен панели из .env (надёжнее чем nginx.conf) ───
    local panel_domain=""
    panel_domain=$(grep -oP '^FRONT_END_DOMAIN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)
    if [ -z "$panel_domain" ]; then
        # Fallback: из nginx.conf
        panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -v '^_$' | head -1)
    fi
    if [ -z "$panel_domain" ]; then
        clear
        print_error "Не удалось определить домен панели"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    # ─── Cookie: из nginx.conf или генерируем новые ───
    local COOKIE_NAME="" COOKIE_VALUE=""
    if [ -f "${DIR_NGINX}nginx.conf" ] && get_cookie_from_nginx 2>/dev/null; then
        : # cookie получены
    else
        COOKIE_NAME=$(generate_cookie_key)
        COOKIE_VALUE=$(generate_cookie_key)
    fi

    # ─── Автоопределение сертификата панели ───
    local panel_cert=""
    if [ -f "${DIR_NGINX}nginx.conf" ]; then
        panel_cert=$(grep -A 5 "server_name ${panel_domain};" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | head -1)
    fi
    if [ -z "$panel_cert" ]; then
        # Fallback: ищем сертификат в letsencrypt
        if [ -d "/etc/letsencrypt/live/${panel_domain}" ]; then
            panel_cert="$panel_domain"
        else
            # Wildcard — ищем по базовому домену
            local _base_domain
            _base_domain=$(echo "$panel_domain" | sed 's/^[^.]*\.//')
            if [ -d "/etc/letsencrypt/live/${_base_domain}" ]; then
                panel_cert="$_base_domain"
            else
                panel_cert="$panel_domain"
            fi
        fi
    fi

    if ! confirm_nav --delete "⚠️  Экстренное восстановление Nginx"; then
        return
    fi

    # ─── Генерируем заводской конфиг: только панель ───
    # (_nginx_http_header сохраняет внешние блоки (Beszel и др.) и восстанавливает их)
    generate_nginx_conf_panel_only "$panel_domain" "$panel_cert" "$COOKIE_NAME" "$COOKIE_VALUE"

    # Убираем IPv6 если отключён
    nginx_strip_ipv6_if_disabled

    # Перезапускаем nginx
    (cd "${DIR_NGINX}" && docker compose down >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1) &
    if ! show_spinner "Перезапуск Nginx"; then
        print_error "Nginx не запустился. Проверьте: docker logs remnawave-nginx"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    echo
    echo -e "${GREEN}✅ Nginx восстановлен к заводским настройкам${NC}"
    echo
    echo -e "${GREEN}🔗 Cookie-ссылка для входа в панель:${NC}"
    echo -e "${WHITE}https://${panel_domain}/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ═══════════════════════════════════════════════════
# СМЕНА ДОМЕНА ТЕЛЕГРАМ БОТА (WEBHOOK_URL в .env панели)
# ═══════════════════════════════════════════════════

manage_change_bot_domain() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🤖  Сменить домен телеграм бота${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local rw_env="${DIR_PANEL}.env"
    if [ ! -f "$rw_env" ]; then
        print_error "Файл ${rw_env} не найден"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    # Текущий WEBHOOK_URL
    local current_domain=""
    local current_url
    current_url=$(grep -oP '^WEBHOOK_URL=\K\S+' "$rw_env" 2>/dev/null)
    if [ -n "$current_url" ]; then
        current_domain=$(echo "$current_url" | sed 's|^https\?://||;s|/.*||')
        echo -e "${DARKGRAY}  Текущий домен бота: ${WHITE}${current_domain}${NC}"
        echo
    fi
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    echo

    local new_domain=""
    prompt_domain_with_retry "Новый домен бота (без http):" new_domain true
    local rc=$?
    [ $rc -ne 0 ] && return

    if [ -z "$new_domain" ]; then
        echo -e "${YELLOW}  Отменено${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi

    new_domain=$(echo "$new_domain" | sed 's|^https\?://||;s|/$||')
    local new_url="https://${new_domain}/api/v1/remnawave"

    echo
    sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=${new_url}|" "$rw_env"
    echo -e "${GREEN}✅ Обновление домена телеграм бота${NC}"

    (cd "${DIR_PANEL}" && docker compose down >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1) &
    if show_spinner "Перезапуск панели Remnawave"; then
        echo -e "${GREEN}✅ Готово${NC}"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ═══════════════════════════════════════════════════
# УПРАВЛЕНИЕ ДОСТУПОМ К ПАНЕЛИ
# ═══════════════════════════════════════════════════

manage_panel_access() {
    while true; do
        # Определяем текущий активный порт прямого доступа
        local _current_port=""
        if grep -q "# ─── 8443 Fallback" ${DIR_NGINX}nginx.conf 2>/dev/null; then
            _current_port="8443"
        elif grep -q "# ─── 443 Direct" ${DIR_NGINX}nginx.conf 2>/dev/null; then
            _current_port="443"
        fi

        # Формируем лейбл для переключателя
        local _toggle_label
        if [ "$_current_port" = "8443" ]; then
            _toggle_label="🔒  Переключить панель на 443"
        elif [ "$_current_port" = "443" ]; then
            _toggle_label="🔓  Переключить панель на 8443"
        else
            _toggle_label="🔓  Переключить панель на 8443"
        fi

        # Показываем cookie-ссылку
        local COOKIE_NAME COOKIE_VALUE _panel_domain
        get_cookie_from_nginx 2>/dev/null
        _panel_domain=$(grep -oP 'server_name\s+\K[^;]+' ${DIR_NGINX}nginx.conf 2>/dev/null | head -1)

        show_arrow_menu "🔓  Доступ к панели" \
            "🔐  Сбросить суперадмина" \
            "🌐  Сменить домены" \
            "🍪  Сменить cookie доступа" \
            "🎨  Сменить сайт-заглушку" \
            "🤖  Сменить домен телеграм бота" \
            "──────────────────────────────────────" \
            "🔗  Показать данные панели" \
            "──────────────────────────────────────" \
            "$_toggle_label" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) change_credentials || break ;;
            1) manage_domains ;;
            2) regenerate_cookies || break ;;
            3) manage_random_template ;;
            4) manage_change_bot_domain ;;
            5) ;;
            6)
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "   ${GREEN}🔗  Данные панели${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                local COOKIE_NAME COOKIE_VALUE
                if get_cookie_from_nginx; then
                    local pd
                    pd=$(grep -oP 'server_name\s+\K[^;]+' ${DIR_NGINX}nginx.conf | head -1)
                    echo
                    echo -e "${GREEN}🔗 Cookie-ссылка для входа в панель:${NC}"
                    echo -e "${WHITE}https://${pd}/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
                    if [ -n "$_current_port" ]; then
                        echo
                        echo -e "${GREEN}🔗 Прямой доступ (порт ${_current_port}):${NC}"
                        echo -e "${WHITE}https://${pd}:${_current_port}/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
                    fi
                else
                    echo
                    print_error "Не удалось извлечь cookie из nginx.conf"
                fi

                # Домен панели
                local _fe_domain
                _fe_domain=$(grep -oP '^FRONT_END_DOMAIN=\K\S+' /opt/remnawave/.env 2>/dev/null)
                if [ -n "$_fe_domain" ]; then
                    echo
                    echo -e "${GREEN}🌐 Домен панели:${NC}"
                    echo -e "${WHITE}${_fe_domain}${NC}"
                fi

                # Домен подписки
                local _sub_domain
                _sub_domain=$(grep -oP '^SUB_PUBLIC_DOMAIN=\K\S+' /opt/remnawave/.env 2>/dev/null)
                if [ -n "$_sub_domain" ]; then
                    echo
                    echo -e "${GREEN}📄 Домен страницы подписки:${NC}"
                    echo -e "${WHITE}${_sub_domain}${NC}"
                fi

                # Webhook secret
                local _wh_secret
                _wh_secret=$(grep -oP '^WEBHOOK_SECRET_HEADER=\K\S+' /opt/remnawave/.env 2>/dev/null)
                if [ -n "$_wh_secret" ]; then
                    echo
                    echo -e "${GREEN}🔑 Вебхук секрет (WEBHOOK_SECRET_HEADER):${NC}"
                    echo -e "${WHITE}${_wh_secret}${NC}"
                fi

                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt
                ;;
            7) ;;
            8)
                if [ "$_current_port" = "8443" ]; then
                    switch_panel_port 443 || break
                else
                    switch_panel_port 8443 || break
                fi
                ;;
            9) ;;
            10) return ;;
        esac
    done
}

open_panel_access() {
    switch_panel_port 8443
}


close_panel_access() {
    switch_panel_port 443
}


_update_hosts_port() {
    local dir="${1:-/opt/remnawave}"
    local target_port="$2"
    local inbound_port="${3:-}"   # опционально: уже полученный xray inbound port
    local domain_url="127.0.0.1:3000"

    # Получаем токен
    local token
    token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "$dir/.env" 2>/dev/null)
    [ -z "$token" ] && [ -f "${DIR_SCRIPT}/token" ] && token=$(cat "${DIR_SCRIPT}/token" 2>/dev/null)
    [ -z "$token" ] && return 0

    # Получаем xray inbound port из config profile (если не передан)
    if [ -z "$inbound_port" ]; then
        local profiles_response
        profiles_response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token" 2>/dev/null)
        [ -z "$profiles_response" ] && return 0
        inbound_port=$(echo "$profiles_response" | jq -r '[.response.configProfiles[].config.inbounds[].port] | first // empty' 2>/dev/null)
        [ -z "$inbound_port" ] && return 0
    fi

    # Получаем все хосты
    local hosts_response
    hosts_response=$(make_api_request "GET" "$domain_url/api/hosts" "$token" 2>/dev/null)
    [ -z "$hosts_response" ] && return 0

    # Обновляем порт у хостов, у которых он не совпадает с inbound port
    local host_uuids
    host_uuids=$(echo "$hosts_response" | jq -r --argjson port "$inbound_port" \
        '[.response[] | select(.port != $port) | .uuid] | .[]' 2>/dev/null)

    for uuid in $host_uuids; do
        make_api_request "PATCH" "$domain_url/api/hosts" "$token" \
            "{\"uuid\":\"${uuid}\",\"port\":${inbound_port}}" >/dev/null 2>&1
    done
}

switch_panel_port() {
    local target_port="$1"
    local dir="/opt/remnawave"

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     🔒 Переключение порта панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if [ ! -f "${DIR_NGINX}nginx.conf" ]; then
        print_error "Файл nginx.conf не найден"
        sleep 2
        return 1
    fi

    local COOKIE_NAME COOKIE_VALUE
    if ! get_cookie_from_nginx; then
        print_error "Не удалось извлечь cookie из nginx.conf"
        sleep 2
        return 1
    fi

    local panel_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" | head -1)

    local panel_cert
    panel_cert=$(grep -A 5 "server_name ${panel_domain};" "${DIR_NGINX}nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | head -1)

    # Определяем sub_domain (домен подписки → upstream json)
    local sub_domain="" sub_cert="" json_line=""
    json_line=$(grep -n 'proxy_pass http://json' "${DIR_NGINX}nginx.conf" | head -1 | cut -d: -f1)
    if [ -n "$json_line" ]; then
        sub_domain=$(head -n "$json_line" "${DIR_NGINX}nginx.conf" | grep -oP 'server_name\s+\K[^;]+' | tail -1)
        sub_cert=$(head -n "$json_line" "${DIR_NGINX}nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | tail -1)
        [ -z "$sub_cert" ] && sub_cert="$sub_domain"
    fi

    # Определяем selfsteal_domain (из области вне внешних блоков)
    local selfsteal_domain="" selfsteal_cert=""
    selfsteal_domain=$(sed '/^# BEGIN_.*_BLOCK$/,/^# END_.*_BLOCK$/d' "${DIR_NGINX}nginx.conf" \
        | grep -oP 'server_name\s+\K[^;]+' | sort -u | grep -v '^_$' \
        | grep -vF "$panel_domain" | grep -vF "${sub_domain:-__NONE__}" | head -1)
    if [ -n "$selfsteal_domain" ]; then
        selfsteal_cert=$(grep -A 5 "server_name ${selfsteal_domain};" "${DIR_NGINX}nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | head -1)
        [ -z "$selfsteal_cert" ] && selfsteal_cert="$selfsteal_domain"
    fi

    # Удаляем любые существующие блоки прямого доступа
    sed -i '/# ─── 8443 Fallback/,/^}$/d' "${DIR_NGINX}nginx.conf"
    sed -i '/# ─── 443 Direct/,/^}$/d' "${DIR_NGINX}nginx.conf"
    sed -i '/# ─── Sub Direct/,/^}$/d' "${DIR_NGINX}nginx.conf"
    sed -i '/# ─── Selfsteal Direct/,/^}$/d' "${DIR_NGINX}nginx.conf"
    sed -i '/# ─── Default Direct/,/^}$/d' "${DIR_NGINX}nginx.conf"

    # Удаляем неразмеченные default_server блоки на порту 443 (совместимость со старыми конфигами)
    awk '
    /^server \{/ { buf=$0; ds=0; next }
    buf != "" { buf = buf "\n" $0; if ($0 ~ /listen 443 ssl default_server/) ds=1; if (/^\}$/) { if (!ds) print buf; buf = ""; ds = 0 }; next }
    { print }
    ' "${DIR_NGINX}nginx.conf" > "${DIR_NGINX}nginx.conf.tmp" && mv "${DIR_NGINX}nginx.conf.tmp" "${DIR_NGINX}nginx.conf"

    # Вставляем после последнего серверного блока
    local insert_after_line
    insert_after_line=$(grep -n "^}$" "${DIR_NGINX}nginx.conf" | tail -1 | cut -d: -f1)

    local temp_file="/tmp/remnawave_port_switch_$$.conf"
    if [ "$target_port" = "443" ]; then
        cat > "$temp_file" << 'SERVERBLOCK_443'

# ─── 443 Direct
server {
    server_name PANEL_DOMAIN_PH;
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/PANEL_CERT_PH/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/PANEL_CERT_PH/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/PANEL_CERT_PH/fullchain.pem";

    add_header Set-Cookie $set_cookie_header;

    location ^~ /api/auth/ {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_busy_buffers_size 24k;
        proxy_buffers 8 16k;
        proxy_buffer_size 16k;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 443;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        error_page 418 = @unauthorized;
        recursive_error_pages on;
        if ($authorized = 0) {
            return 418;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_busy_buffers_size 24k;
        proxy_buffers 8 16k;
        proxy_buffer_size 16k;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 443;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location @unauthorized {
        root /var/www/html;
        index index.html;
    }
}
SERVERBLOCK_443

        # Добавляем блок подписки если sub_domain определён
        if [ -n "$sub_domain" ]; then
            cat >> "$temp_file" << 'SUBBLOCK_443'

# ─── Sub Direct
server {
    server_name SUB_DOMAIN_PH;
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/SUB_CERT_PH/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/SUB_CERT_PH/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/SUB_CERT_PH/fullchain.pem";

    location / {
        proxy_http_version 1.1;
        proxy_pass http://json;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_intercept_errors on;
        error_page 400 404 500 502 @redirect;
    }

    location @redirect {
        return 444;
    }
}
SUBBLOCK_443
            sed -i "s/SUB_DOMAIN_PH/${sub_domain}/g" "$temp_file"
            sed -i "s/SUB_CERT_PH/${sub_cert}/g" "$temp_file"
        fi

        # Добавляем блок selfsteal если selfsteal_domain определён
        if [ -n "$selfsteal_domain" ]; then
            cat >> "$temp_file" << 'SELFSTEALBLOCK_443'

# ─── Selfsteal Direct
server {
    server_name SELFSTEAL_DOMAIN_PH;
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/SELFSTEAL_CERT_PH/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/SELFSTEAL_CERT_PH/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/SELFSTEAL_CERT_PH/fullchain.pem";

    root /var/www/html;
    index index.html;

    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;

    if ($request_method !~ ^(GET|HEAD)$) {
        return 444;
    }

    location ~ /\. {
        return 444;
    }

    location ~* \.(php|asp|aspx|jsp|cgi)$ {
        return 444;
    }

    location = /robots.txt {
        default_type text/plain;
        return 200 "User-agent: *\nDisallow: /\n";
    }

    location = / {
        try_files /index.html =444;
    }

    location / {
        return 444;
    }
}
SELFSTEALBLOCK_443
            sed -i "s/SELFSTEAL_DOMAIN_PH/${selfsteal_domain}/g" "$temp_file"
            sed -i "s/SELFSTEAL_CERT_PH/${selfsteal_cert}/g" "$temp_file"
        fi

        # Default server — отклоняем неизвестные домены
        cat >> "$temp_file" << 'DEFAULTBLOCK_443'

# ─── Default Direct
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
    return 444;
}
DEFAULTBLOCK_443
    else
        cat > "$temp_file" << 'SERVERBLOCK_8443'

# ─── 8443 Fallback (direct access) ───
server {
    server_name PANEL_DOMAIN_PH;
    listen 8443 ssl;
    listen [::]:8443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/PANEL_CERT_PH/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/PANEL_CERT_PH/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/PANEL_CERT_PH/fullchain.pem";

    add_header Set-Cookie $set_cookie_header;

    location ^~ /api/auth/ {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_busy_buffers_size 24k;
        proxy_buffers 8 16k;
        proxy_buffer_size 16k;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 8443;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        error_page 418 = @unauthorized;
        recursive_error_pages on;
        if ($authorized = 0) {
            return 418;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_busy_buffers_size 24k;
        proxy_buffers 8 16k;
        proxy_buffer_size 16k;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 8443;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location @unauthorized {
        root /var/www/html;
        index index.html;
    }
}
SERVERBLOCK_8443
    fi

    sed -i "s/PANEL_DOMAIN_PH/${panel_domain}/g" "$temp_file"
    sed -i "s/PANEL_CERT_PH/${panel_cert}/g" "$temp_file"

    if [ -n "$insert_after_line" ]; then
        sed -i "${insert_after_line}r ${temp_file}" "${DIR_NGINX}nginx.conf"
    else
        cat "$temp_file" >> "${DIR_NGINX}nginx.conf"
    fi
    rm -f "$temp_file"

    # Убираем IPv6 из сгенерированных блоков если IPv6 отключён
    nginx_strip_ipv6_if_disabled

    (
        cd "${DIR_NGINX}"
        docker compose down nginx >/dev/null 2>&1
        docker compose up -d nginx >/dev/null 2>&1
        _i=0
        _nginx_ok=0
        while [ $_i -lt 20 ]; do
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
                _nginx_ok=1
                break
            fi
            sleep 0.5
            _i=$((_i + 1))
        done
        [ "$_nginx_ok" -eq 0 ] && exit 1

        # UFW: при переключении на 8443 порт 443 не трогаем
        if [ "$target_port" = "443" ]; then
            ufw delete allow 8443/tcp >/dev/null 2>&1 || true
        fi
        ufw allow "${target_port}"/tcp >/dev/null 2>&1

        # Получаем xray inbound port и обновляем хосты
        _api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "$dir/.env" 2>/dev/null)
        [ -z "$_api_token" ] && [ -f "${DIR_SCRIPT}/token" ] && _api_token=$(cat "${DIR_SCRIPT}/token" 2>/dev/null)
        _xray_port=""
        if [ -n "$_api_token" ]; then
            _profiles_resp=$(make_api_request "GET" "127.0.0.1:3000/api/config-profiles" "$_api_token" 2>/dev/null)
            _xray_port=$(echo "$_profiles_resp" | jq -r '[.response.configProfiles[].config.inbounds[].port] | first // empty' 2>/dev/null)
        fi
        if [ "$target_port" = "443" ] && [ -n "$_xray_port" ] && [ "$_xray_port" != "443" ]; then
            ufw allow "${_xray_port}"/tcp >/dev/null 2>&1
        fi
        ufw reload >/dev/null 2>&1 || true
        _update_hosts_port "$dir" "$target_port" "$_xray_port"
        exit 0
    ) &
    if ! show_spinner "Перезапуск nginx" "Порт доступа к панели изменён на ${target_port}"; then
        print_error "Nginx не запустился. Проверьте: docker logs remnawave-nginx"
        echo
        show_continue_prompt || return 1
        return 1
    fi
    echo
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    echo
    echo -e "${GREEN}🔗 Ссылка на панель:${NC}"
    echo -e "${WHITE}https://${panel_domain}:${target_port}/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

auto_enable_panel_access_8443() {
    local panel_domain="${1:-}"
    local cookie_name="${2:-}"
    local cookie_value="${3:-}"
    local dir="/opt/remnawave"

    [ ! -f "${DIR_NGINX}nginx.conf" ] && return 1

    if [ -z "$panel_domain" ]; then
        panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" | head -1)
    fi

    local panel_cert
    panel_cert=$(grep -A 5 "server_name ${panel_domain};" "${DIR_NGINX}nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | head -1)

    if grep -q "# ─── 8443 Fallback" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        ufw allow 8443/tcp >/dev/null 2>&1
        return 0
    fi

    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":8443" && return 1
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":8443" && return 1
    fi

    local insert_after_line
    # Вставляем перед закрывающей скобкой http{} (новый формат) или после последнего server{} (старый формат)
    insert_after_line=$(grep -n "^}$" "${DIR_NGINX}nginx.conf" | tail -1 | cut -d: -f1)

    local temp_file="/tmp/remnawave_8443_auto_$$.conf"
    cat > "$temp_file" << 'EOF'

# ─── 8443 Fallback (direct access) ───
server {
    server_name PANEL_DOMAIN;
    listen 8443 ssl;
    listen [::]:8443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/PANEL_CERT/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/PANEL_CERT/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/PANEL_CERT/fullchain.pem";

    add_header Set-Cookie $set_cookie_header;

    # API endpoints - no auth required for auth status
    location ^~ /api/auth/ {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_busy_buffers_size 24k;
        proxy_buffers 8 16k;
        proxy_buffer_size 16k;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 8443;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        error_page 418 = @unauthorized;
        recursive_error_pages on;
        if ($authorized = 0) {
            return 418;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_busy_buffers_size 24k;
        proxy_buffers 8 16k;
        proxy_buffer_size 16k;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 8443;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location @unauthorized {
        root /var/www/html;
        index index.html;
    }
}
EOF

    sed -i "s/PANEL_DOMAIN/${panel_domain}/g" "$temp_file"
    sed -i "s/PANEL_CERT/${panel_cert}/g" "$temp_file"

    if [ -n "$insert_after_line" ]; then
        sed -i "${insert_after_line}r ${temp_file}" "${DIR_NGINX}nginx.conf"
    else
        cat "$temp_file" >> "${DIR_NGINX}nginx.conf"
    fi

    rm -f "$temp_file"

    (
        cd "${DIR_NGINX}"
        docker compose restart nginx >/dev/null 2>&1
    ) &
    show_spinner "Активация доступа по 8443"

    ufw allow 8443/tcp >/dev/null 2>&1

    return 0
}

change_credentials() {
    if ! confirm_nav --delete "🔐 Сброс суперадмина"; then
        print_error "Операция отменена"
        sleep 2
        return
    fi

    echo
    echo

    (
        cd /opt/remnawave
        docker compose stop remnawave >/dev/null 2>&1
    ) &
    show_spinner "Остановка панели"

    if docker exec -i remnawave-db psql -U postgres -d postgres <<'EOSQL' >/dev/null 2>&1
DELETE FROM admin;
EOSQL
    then
        echo -e "✅ Обновление данных суперадмина"
    else
        print_error "Не удалось обновить данные суперадмина"
        (
            cd /opt/remnawave
            docker compose start remnawave >/dev/null 2>&1
        ) &
        show_spinner "Запуск панели"
        sleep 2
        return
    fi

    # Запускаем панель и ждём готовности по Docker healthcheck
    (
        cd /opt/remnawave
        docker compose start remnawave >/dev/null 2>&1

        # Ждём healthy-статуса от Docker healthcheck (интервал 3s, до 60s)
        _w=0
        while [ $_w -lt 60 ]; do
            _status=$(docker inspect --format='{{.State.Health.Status}}' remnawave 2>/dev/null)
            [ "$_status" = "healthy" ] && break
            sleep 3
            _w=$((_w + 3))
        done

        # Ждём пока NGINX запущен (обычно уже работает, до 20s)
        _w=0
        while [ $_w -lt 20 ]; do
            _running=$(docker inspect --format='{{.State.Running}}' nginx 2>/dev/null || echo "false")
            [ "$_running" = "true" ] && break
            sleep 2
            _w=$((_w + 2))
        done
    ) &
    show_spinner "Запуск панели"

    tput cnorm 2>/dev/null || true

    echo
    echo -e "${GREEN}✅ Сброс выполнен успешно!${NC}"
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${WHITE}При следующем входе в панель будет создан суперадмин${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return
}

regenerate_cookies() {
    tput civis 2>/dev/null

    if [ ! -f ${DIR_NGINX}nginx.conf ]; then
        print_error "Файл nginx.conf не найден"
        sleep 2
        tput cnorm 2>/dev/null
        return
    fi

    local COOKIE_NAME COOKIE_VALUE
    if ! get_cookie_from_nginx; then
        print_error "Не удалось извлечь cookie из nginx.conf"
        sleep 2
        tput cnorm 2>/dev/null
        return
    fi
    local OLD_NAME="$COOKIE_NAME"
    local OLD_VALUE="$COOKIE_VALUE"

    CONFIRM_WARN_LINE="${YELLOW}⚠️  Текущие cookie будут заменены на новые.${NC}"
    if ! confirm_nav "🍪 Смена cookie доступа" "Подтвердить" "Отменить"; then
        unset CONFIRM_WARN_LINE
        print_error "Операция отменена"
        sleep 2
        tput cnorm 2>/dev/null
        return
    fi
    unset CONFIRM_WARN_LINE

    local NEW_NAME NEW_VALUE
    NEW_NAME=$(generate_cookie_key)
    NEW_VALUE=$(generate_cookie_key)

    echo
    print_action "Обновление cookie..."

    sed -i "s|~\*${OLD_NAME}=${OLD_VALUE}|~*${NEW_NAME}=${NEW_VALUE}|g" ${DIR_NGINX}nginx.conf
    sed -i "s|\$arg_${OLD_NAME}|\$arg_${NEW_NAME}|g" ${DIR_NGINX}nginx.conf
    sed -i "s|    \"[^\"]*\" \"${OLD_NAME}=${OLD_VALUE}; Path=|    \"${NEW_VALUE}\" \"${NEW_NAME}=${NEW_VALUE}; Path=|g" ${DIR_NGINX}nginx.conf
    sed -i "s|\"${OLD_VALUE}\" 1|\"${NEW_VALUE}\" 1|g" ${DIR_NGINX}nginx.conf

    print_success "Cookie успешно обновлены!"

    (cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1) &
    show_spinner "Перезапуск Nginx"

    local panel_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' ${DIR_NGINX}nginx.conf | head -1)

    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}🔐 НОВАЯ ССЫЛКА ДОСТУПА К ПАНЕЛИ:${NC}"
    echo -e "${WHITE}https://${panel_domain}/auth/login?${NEW_NAME}=${NEW_VALUE}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
    tput cnorm 2>/dev/null
}
