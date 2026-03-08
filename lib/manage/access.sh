# ═══════════════════════════════════════════════════
# УПРАВЛЕНИЕ ДОСТУПОМ К ПАНЕЛИ
# ═══════════════════════════════════════════════════

manage_panel_access() {
    while true; do
        # Показываем текущий статус доступа по 8443
        local _8443_status
        if grep -q "# ─── 8443 Fallback" /opt/remnawave/nginx.conf 2>/dev/null; then
            _8443_status="${GREEN}открыт${NC}"
        else
            _8443_status="${RED}закрыт${NC}"
        fi

        # Показываем cookie-ссылку
        local COOKIE_NAME COOKIE_VALUE _panel_domain
        get_cookie_from_nginx 2>/dev/null
        _panel_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf 2>/dev/null | head -1)

        show_arrow_menu "🔓  Доступ к панели" \
            "🔓  Открыть доступ по 8443" \
            "🔒  Закрыть доступ по 8443" \
            "🔗  Показать cookie-ссылку" \
            "──────────────────────────────────────" \
            "🔐  Сбросить суперадмина" \
            "🍪  Сменить cookie доступа" \
            "🌐  Редактировать домены" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) open_panel_access || break ;;
            1) close_panel_access || break ;;
            2)
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}          🔗  Показать cookie-ссылку${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                local COOKIE_NAME COOKIE_VALUE
                if get_cookie_from_nginx; then
                    local pd
                    pd=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | head -1)
                    echo
                    echo -e "${GREEN}🔗 Cookie-ссылка на панель (основной порт):${NC}"
                    echo -e "${WHITE}https://${pd}/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
                    echo
                    if grep -q "# ─── 8443 Fallback" /opt/remnawave/nginx.conf 2>/dev/null; then
                        echo -e "${GREEN}🔗 Cookie-ссылка на панель (доступ по 8443):${NC}"
                        echo -e "${WHITE}https://${pd}:8443/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
                    fi
                else
                    echo
                    print_error "Не удалось извлечь cookie из nginx.conf"
                fi
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt
                ;; # Всегда возвращаемся в меню "Доступ к панели"
            3) ;;
            4) change_credentials || break ;;
            5) regenerate_cookies || break ;;
            6) manage_domains ;;
            7) ;;
            8) return ;;
        esac
    done
}

open_panel_access() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔓 ОТКРЫТИЕ ДОСТУПА К ПАНЕЛИ (8443)${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local dir="/opt/remnawave"

    if [ ! -f "$dir/nginx.conf" ]; then
        print_error "Файл nginx.conf не найден"
        sleep 2
        return
    fi

    local COOKIE_NAME COOKIE_VALUE
    if ! get_cookie_from_nginx; then
        print_error "Не удалось извлечь cookie из nginx.conf"
        sleep 2
        return
    fi

    local panel_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "$dir/nginx.conf" | head -1)

    local panel_cert
    panel_cert=$(grep -A 5 "server_name ${panel_domain};" "$dir/nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | head -1)

    if grep -q "# ─── 8443 Fallback" "$dir/nginx.conf" 2>/dev/null; then
        if ufw status 2>/dev/null | grep -q "8443/tcp.*ALLOW"; then
            print_success "Доступ по 8443 уже открыт"
        else
            ufw allow 8443/tcp >/dev/null 2>&1
            print_success "Порт 8443 открыт в файрволе"
        fi
        echo
        echo -e "${GREEN}🔗 Ссылка на панель:${NC}"
        echo -e "${WHITE}https://${panel_domain}:8443/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
        echo
        echo -e "${RED}⚠️  Не забудьте закрыть доступ после использования!${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi

    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":8443"; then
            print_error "Порт 8443 уже занят другим процессом"
            sleep 2
            return
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":8443"; then
            print_error "Порт 8443 уже занят другим процессом"
            sleep 2
            return
        fi
    fi

    local insert_after_line
    insert_after_line=$(awk '/^server \{/ {start=NR; brace=1} 
        brace {if (/\{/) brace++; if (/\}/) brace--} 
        brace==0 && start {print NR; exit}' "$dir/nginx.conf")
    
    if [ -z "$insert_after_line" ]; then
        insert_after_line=$(grep -n "^}$" "$dir/nginx.conf" | tail -1 | cut -d: -f1)
    fi

    local temp_file="/tmp/remnawave_8443_block_$$.conf"
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
        sed -i "${insert_after_line}r ${temp_file}" "$dir/nginx.conf"
    else
        cat "$temp_file" >> "$dir/nginx.conf"
    fi

    rm -f "$temp_file"

    (
        cd "$dir"
        docker compose down remnawave-nginx >/dev/null 2>&1
        docker compose up -d remnawave-nginx >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск nginx"

    sleep 2
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
        print_error "Nginx не запустился. Проверьте: docker logs remnawave-nginx"
        echo
        show_continue_prompt || return 1
        return
    fi

    ufw allow 8443/tcp >/dev/null 2>&1

    echo
    print_success "Доступ по 8443 открыт"
    echo
    echo -e "${GREEN}🔗 Ссылка на панель:${NC}"
    echo -e "${WHITE}https://${panel_domain}:8443/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${RED}⚠️  Не забудьте закрыть доступ после использования!${NC}"
    echo
    show_continue_prompt || return 1
}

close_panel_access() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🔒 ЗАКРЫТИЕ ДОСТУПА К ПАНЕЛИ (8443)${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local dir="/opt/remnawave"

    if [ ! -f "$dir/nginx.conf" ]; then
        print_error "Файл nginx.conf не найден"
        sleep 2
        return
    fi

    if ! grep -q "# ─── 8443 Fallback" "$dir/nginx.conf" 2>/dev/null; then
        print_warning "Доступ по 8443 уже закрыт"
        sleep 2
        return
    fi

    sed -i '/# ─── 8443 Fallback/,/^}$/d' "$dir/nginx.conf"

    (
        cd "$dir"
        docker compose down remnawave-nginx >/dev/null 2>&1
        docker compose up -d remnawave-nginx >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск nginx"

    sleep 2
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
        print_error "Nginx не запустился. Проверьте: docker logs remnawave-nginx"
        echo
        show_continue_prompt || return 1
        return
    fi

    if ufw status 2>/dev/null | grep -q "8443.*ALLOW"; then
        ufw delete allow 8443/tcp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    fi

    echo
    print_success "Доступ по 8443 закрыт"
    echo
    show_continue_prompt || return 1
}

auto_enable_panel_access_8443() {
    local panel_domain="${1:-}"
    local cookie_name="${2:-}"
    local cookie_value="${3:-}"
    local dir="/opt/remnawave"

    [ ! -f "$dir/nginx.conf" ] && return 1

    if [ -z "$panel_domain" ]; then
        panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "$dir/nginx.conf" | head -1)
    fi

    local panel_cert
    panel_cert=$(grep -A 5 "server_name ${panel_domain};" "$dir/nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | head -1)

    if grep -q "# ─── 8443 Fallback" "$dir/nginx.conf" 2>/dev/null; then
        ufw allow 8443/tcp >/dev/null 2>&1
        return 0
    fi

    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":8443" && return 1
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":8443" && return 1
    fi

    local insert_after_line
    insert_after_line=$(awk '/^server \{/ {start=NR; brace=1} 
        brace {if (/\{/) brace++; if (/\}/) brace--} 
        brace==0 && start {print NR; exit}' "$dir/nginx.conf")
    
    if [ -z "$insert_after_line" ]; then
        insert_after_line=$(grep -n "^}$" "$dir/nginx.conf" | tail -1 | cut -d: -f1)
    fi

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
        sed -i "${insert_after_line}r ${temp_file}" "$dir/nginx.conf"
    else
        cat "$temp_file" >> "$dir/nginx.conf"
    fi

    rm -f "$temp_file"

    (
        cd "$dir"
        docker compose restart remnawave-nginx >/dev/null 2>&1
    ) &
    show_spinner "Активация доступа по 8443"

    ufw allow 8443/tcp >/dev/null 2>&1

    return 0
}

change_credentials() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔐 СБРОС СУПЕРАДМИНА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${WHITE}Эта операция удалит текущего суперадмина из базы данных.${NC}"
    echo -e "${WHITE}При следующем входе в панель вам будет предложено${NC}"
    echo -e "${WHITE}создать нового суперадмина.${NC}"

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return
    fi

    echo
    print_action "Сброс суперадмина..."

    (
        cd /opt/remnawave
        docker compose stop remnawave >/dev/null 2>&1
    ) &
    show_spinner "Остановка панели"

    if docker exec -i remnawave-db psql -U postgres -d postgres <<'EOSQL' >/dev/null 2>&1
DELETE FROM admin;
EOSQL
    then
        print_success "Суперадмин удалён из базы данных"
    else
        print_error "Не удалось удалить суперадмина"
        (
            cd /opt/remnawave
            docker compose start remnawave >/dev/null 2>&1
        ) &
        show_spinner "Запуск панели"
        sleep 2
        return
    fi

    (
        cd /opt/remnawave
        docker compose start remnawave >/dev/null 2>&1
    ) &
    show_spinner "Запуск панели"

    show_spinner_timer 10 "Ожидание запуска панели" "Запуск панели"

    echo
    echo -e "${GREEN}✅ Сброс выполнен успешно!${NC}"
    echo
    echo -e "${WHITE}При следующем входе в панель вы сможете создать${NC}"
    echo -e "${WHITE}нового суперадмина с любым логином и паролем.${NC}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
}

regenerate_cookies() {
    clear
    tput civis 2>/dev/null
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🍪 СМЕНА COOKIE ДОСТУПА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if [ ! -f /opt/remnawave/nginx.conf ]; then
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

    echo -e "${YELLOW}⚠️  Текущие cookie будут заменены на новые.${NC}"
    echo

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        tput cnorm 2>/dev/null
        return
    fi

    local NEW_NAME NEW_VALUE
    NEW_NAME=$(generate_cookie_key)
    NEW_VALUE=$(generate_cookie_key)

    echo
    print_action "Обновление cookie..."

    sed -i "s|~\*${OLD_NAME}=${OLD_VALUE}|~*${NEW_NAME}=${NEW_VALUE}|g" /opt/remnawave/nginx.conf
    sed -i "s|\$arg_${OLD_NAME}|\$arg_${NEW_NAME}|g" /opt/remnawave/nginx.conf
    sed -i "s|    \"[^\"]*\" \"${OLD_NAME}=${OLD_VALUE}; Path=|    \"${NEW_VALUE}\" \"${NEW_NAME}=${NEW_VALUE}; Path=|g" /opt/remnawave/nginx.conf
    sed -i "s|\"${OLD_VALUE}\" 1|\"${NEW_VALUE}\" 1|g" /opt/remnawave/nginx.conf

    print_success "Cookie успешно обновлены!"

    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск nginx"

    local panel_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | head -1)

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
