# ═══════════════════════════════════════════════
# РЕДАКТИРОВАНИЕ ДОМЕНОВ
# ═══════════════════════════════════════════════

obtain_cert_for_domain() {
    local new_domain="$1"
    local panel_dir="$2"
    local current_domain="$3"
    local -n __cert_result_ref=$4

    # Определяем cert domain для нового домена
    local _cert_dom _base_dom
    _base_dom=$(extract_domain "$new_domain")
    local parts
    parts=$(echo "$new_domain" | tr '.' '\n' | wc -l)
    if [ "$parts" -gt 2 ]; then
        _cert_dom="$_base_dom"
    else
        _cert_dom="$new_domain"
    fi

    # Определяем метод получения сертификата по текущему домену
    local cert_method
    cert_method=$(detect_cert_method "$current_domain")

    # Проверяем наличие сертификата для нового домена
    if [ -d "/etc/letsencrypt/live/${_cert_dom}" ] || [ -d "/etc/letsencrypt/live/${new_domain}" ]; then
        print_success "SSL-сертификат для ${new_domain} уже существует"
        if [ -d "/etc/letsencrypt/live/${new_domain}" ]; then
            __cert_result_ref="$new_domain"
        else
            __cert_result_ref="$_cert_dom"
        fi
        return 0
    fi

    # Получаем email из существующей регистрации certbot
    local _cert_email
    _cert_email=$(grep -r '"email"' /etc/letsencrypt/accounts/ 2>/dev/null | grep -oP '"[^@]+@[^"]+' | head -1 | tr -d '"')
    local _email_flag
    if [ -n "$_cert_email" ]; then
        _email_flag="--email $_cert_email"
    else
        _email_flag="--register-unsafely-without-email"
    fi

    # Нужно получить новый сертификат
    if [ "$cert_method" = "1" ] && [ -f "/etc/letsencrypt/cloudflare.ini" ]; then
        (
            certbot certonly --dns-cloudflare \
                --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
                --dns-cloudflare-propagation-seconds 30 \
                -d "$_cert_dom" -d "*.$_cert_dom" \
                --agree-tos $_email_flag --non-interactive \
                --key-type ecdsa >/dev/null 2>&1
        ) &
        show_spinner "Получение wildcard сертификата для *.$_cert_dom"
    else
        (
            cd "$panel_dir"
            cd "${DIR_NGINX}" && docker compose stop nginx >/dev/null 2>&1
        ) &
        show_spinner "Остановка nginx"

        ufw_allow_http01_temp
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        sleep 2

        (
            certbot certonly --standalone \
                -d "$new_domain" \
                --agree-tos $_email_flag --non-interactive \
                --http-01-port 80 \
                --key-type ecdsa >/dev/null 2>&1
        ) &
        show_spinner "Получение SSL-сертификата для $new_domain"

        ufw_revert_http01_temp
        iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true

        _cert_dom="$new_domain"
    fi

    # Проверяем, получен ли сертификат
    if [ ! -d "/etc/letsencrypt/live/${_cert_dom}" ]; then
        print_error "Не удалось получить сертификат для ${new_domain}"
        echo -e "${WHITE}Убедитесь что DNS-записи для ${YELLOW}${new_domain}${WHITE} настроены правильно.${NC}"
        echo
        (
            cd "$panel_dir"
            cd "${DIR_NGINX}" && docker compose start nginx >/dev/null 2>&1
        ) &
        show_spinner "Запуск nginx"
        echo
        return 1
    fi

    print_success "SSL-сертификат получен"

    local _deploy_hook='cd /opt/nginx 2>/dev/null && docker compose restart nginx 2>/dev/null'
    local cron_rule
    if [ "$cert_method" != "1" ]; then
        local _hook_path="${DIR_SCRIPT%/}/lib/extra/ufw_certbot_http01_hook.sh"
        local _pre_hook="bash ${_hook_path} pre"
        local _post_hook="bash ${_hook_path} post"
        cron_rule="0 3 * * * certbot renew --quiet --pre-hook '${_pre_hook}' --post-hook '${_post_hook}' --deploy-hook '${_deploy_hook}' 2>/dev/null"
    else
        # Cloudflare DNS-01 — порт 80 не нужен
        cron_rule="0 3 * * * certbot renew --quiet --deploy-hook '${_deploy_hook}' 2>/dev/null"
    fi
    # Заменяем существующий cron или добавляем новый
    if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null | grep -v "certbot renew"; echo "$cron_rule") | crontab -
    else
        (crontab -l 2>/dev/null; echo "$cron_rule") | crontab -
    fi

    __cert_result_ref="$_cert_dom"
    return 0
}

change_panel_domain() {
    # Если панель не установлена — предлагаем обновить адрес панели на удалённом сервере
    if ! is_panel_installed; then
        _change_panel_url_remote
        return $?
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}      🌐 Смена домена панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    local current_domain
    current_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" | head -1)

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен панели:" new_domain; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')

    CONFIRM_WARN_LINE="$(echo -e "${WHITE}Текущий домен:${NC} ${YELLOW}${current_domain}${NC}\n${WHITE}Новый домен:${NC}   ${GREEN}${new_domain}${NC}")"
    if ! confirm_nav "🌐 Смена домена панели" "Подтвердить" "Отменить"; then
        unset CONFIRM_WARN_LINE
        return 0
    fi
    unset CONFIRM_WARN_LINE

    # ─── Прогресс ───
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}      🌐 Смена домена панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_domain" new_cert_domain; then
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    # Копируем новый сертификат в /opt/nginx/ssl/
    nginx_copy_cert "$new_cert_domain" 2>/dev/null || true

    local old_cert_domain
    old_cert_domain=$(grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' "${DIR_NGINX}nginx.conf" | head -1)

    local boundary
    boundary=$(grep -nP '^\s*server_name\s' "${DIR_NGINX}nginx.conf" | sed -n '2p' | cut -d: -f1)
    echo

    # Остановка панели
    (
        cd "$panel_dir"
        docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка работы панели"

    # Обновление конфигов
    (
        if [ -n "$old_cert_domain" ] && [ "$old_cert_domain" != "$new_cert_domain" ]; then
            if [ -n "$boundary" ]; then
                sed -i "1,${boundary}s|/etc/nginx/ssl/${old_cert_domain}/|/etc/nginx/ssl/${new_cert_domain}/|g" "${DIR_NGINX}nginx.conf"
            else
                sed -i "s|/etc/nginx/ssl/${old_cert_domain}/|/etc/nginx/ssl/${new_cert_domain}/|g" "${DIR_NGINX}nginx.conf"
            fi
        fi
        sed -i "s|server_name ${current_domain}|server_name ${new_domain}|g" "${DIR_NGINX}nginx.conf"
        if [ -f "${panel_dir}/.env" ]; then
            sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=${new_domain}|" "${panel_dir}/.env"
        fi
    ) &
    show_spinner "Обновление конфигов"

    # Обновление cookie доступа
    local OLD_COOKIE_NAME OLD_COOKIE_VALUE NEW_COOKIE_NAME NEW_COOKIE_VALUE
    if get_cookie_from_nginx; then
        OLD_COOKIE_NAME="$COOKIE_NAME"
        OLD_COOKIE_VALUE="$COOKIE_VALUE"
        NEW_COOKIE_NAME=$(generate_cookie_key)
        NEW_COOKIE_VALUE=$(generate_cookie_key)
        (
            sed -i "s|~\*${OLD_COOKIE_NAME}=${OLD_COOKIE_VALUE}|~*${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}|g" "${DIR_NGINX}nginx.conf"
            sed -i "s|\$arg_${OLD_COOKIE_NAME}|\$arg_${NEW_COOKIE_NAME}|g" "${DIR_NGINX}nginx.conf"
            sed -i "s|    \"[^\"]*\" \"${OLD_COOKIE_NAME}=${OLD_COOKIE_VALUE}; Path=|    \"${NEW_COOKIE_VALUE}\" \"${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}; Path=|g" "${DIR_NGINX}nginx.conf"
            sed -i "s|\"${OLD_COOKIE_VALUE}\" 1|\"${NEW_COOKIE_VALUE}\" 1|g" "${DIR_NGINX}nginx.conf"
        ) &
        show_spinner "Обновление доступов"
    fi

    # Перезапуск сервисов и ожидание доступности
    (
        cd "$panel_dir"
        docker compose up -d >/dev/null 2>&1
        cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1
        # Ждём доступности сайта
        local _w=0
        while [ $_w -lt 60 ]; do
            curl -s -f -o /dev/null --max-time 5 "https://${new_domain}" 2>/dev/null && break
            sleep 2
            _w=$((_w + 2))
        done
    ) &
    show_spinner "Перезапуск сервисов"

    nginx_cleanup_unused_certs

    echo
    print_success "Домен панели изменён на ${new_domain}"

    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${GREEN}🔗 Ссылка для первого входа в панель:${NC}"
    if [ -n "$NEW_COOKIE_NAME" ] && [ -n "$NEW_COOKIE_VALUE" ]; then
        echo -e "${WHITE}https://${new_domain}/auth/login?${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}${NC}"
    else
        get_cookie_from_nginx
        echo -e "${WHITE}https://${new_domain}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ─── Обновление адреса панели на удалённом сервере (subpage/node) ───
_change_panel_url_remote() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Смена адреса панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    # Находим все docker-compose файлы с REMNAWAVE_PANEL_URL
    local -a compose_files=()
    local -a compose_dirs=()
    local f
    for f in /opt/subscribe-page/docker-compose.yml \
             /opt/remnasubpage/docker-compose.yml \
             /opt/remnanode/docker-compose.yml; do
        if [ -f "$f" ] && grep -q 'REMNAWAVE_PANEL_URL=' "$f" 2>/dev/null; then
            compose_files+=("$f")
            compose_dirs+=("$(dirname "$f")")
        fi
    done

    if [ ${#compose_files[@]} -eq 0 ]; then
        print_error "Не найдены компоненты с подключением к панели"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    # Извлекаем текущий адрес панели
    local current_url
    current_url=$(grep -oP 'REMNAWAVE_PANEL_URL=\K\S+' "${compose_files[0]}" 2>/dev/null | head -1)

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен панели:" new_domain false true; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')
    local new_url="https://${new_domain}"

    CONFIRM_WARN_LINE="$(echo -e "${WHITE}Текущий адрес:${NC} ${YELLOW}${current_url}${NC}\n${WHITE}Новый адрес:${NC}   ${GREEN}${new_url}${NC}")"
    if ! confirm_nav "🌐 Смена адреса панели" "Подтвердить" "Отменить"; then
        unset CONFIRM_WARN_LINE
        return 0
    fi
    unset CONFIRM_WARN_LINE

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Смена адреса панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Обновляем REMNAWAVE_PANEL_URL
    local i
    for i in "${!compose_files[@]}"; do
        sed -i "s|REMNAWAVE_PANEL_URL=.*|REMNAWAVE_PANEL_URL=${new_url}|g" "${compose_files[$i]}"
    done
    (sleep 0.3) &
    show_spinner "Обновление конфигов"

    # Перезапускаем контейнеры и ждём доступности
    (
        for i in "${!compose_dirs[@]}"; do
            cd "${compose_dirs[$i]}" && docker compose down >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1
        done
        cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1
        # Ждём доступности сайта
        local _w=0
        while [ $_w -lt 60 ]; do
            curl -s -f -o /dev/null --max-time 5 "${new_url}" 2>/dev/null && break
            sleep 2
            _w=$((_w + 2))
        done
    ) &
    show_spinner "Перезапуск сервисов"

    echo
    print_success "Адрес панели обновлён на ${new_url}"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

change_sub_domain() {
    # Автоопределение: sub-page в составе панели
    if grep -q 'remnawave-subscription-page' /opt/remnawave/docker-compose.yml 2>/dev/null; then
        _change_sub_domain_local_existing
        return
    fi

    # Sub-page как standalone
    local _sp_dir=""
    local _d
    for _d in "/opt/subscribe-page" "/opt/remnasubpage"; do
        if [ -f "$_d/docker-compose.yml" ] && grep -q 'remnawave-subscription-page' "$_d/docker-compose.yml" 2>/dev/null; then
            _sp_dir="$_d"
            break
        fi
    done

    if [ -n "$_sp_dir" ]; then
        _change_sub_domain_standalone "$_sp_dir"
        return
    fi

    # Панель есть, sub-page нет — sub-page на удалённом сервере
    if is_panel_installed; then
        _change_sub_domain_remote
        return
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Смена домена подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    print_error "Страница подписки не найдена на этом сервере"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ─── Смена домена standalone страницы подписки ───
_change_sub_domain_standalone() {
    local subpage_dir="$1"

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Смена домена подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Извлекаем текущий домен из секции SUB_BLOCK в nginx.conf, или первый server_name
    local current_sub_domain
    if grep -q '# BEGIN_SUB_BLOCK' "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        current_sub_domain=$(sed -n '/^# BEGIN_SUB_BLOCK$/,/^# END_SUB_BLOCK$/p' "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -oP 'server_name\s+\K\S+(?=;)' | head -1)
    fi
    if [ -z "$current_sub_domain" ]; then
        current_sub_domain=$(grep -oP 'server_name\s+\K\S+(?=;)' "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -v '^_$' | head -1)
    fi

    # Извлекаем panel_url и api_token из docker-compose
    local panel_url api_token new_api_token
    panel_url=$(grep -oP 'REMNAWAVE_PANEL_URL=\K\S+' "${subpage_dir}/docker-compose.yml" 2>/dev/null | head -1)
    api_token=$(grep -oP 'REMNAWAVE_API_TOKEN=\K\S+' "${subpage_dir}/docker-compose.yml" 2>/dev/null | head -1)

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен страницы подписки:" new_domain; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')

    reading_inline "API токен (Enter оставить без изменений):" new_api_token
    echo

    CONFIRM_WARN_LINE="$(echo -e "${WHITE}Текущий домен:${NC} ${YELLOW}${current_sub_domain:-не определён}${NC}\n${WHITE}Новый домен:${NC}   ${GREEN}${new_domain}${NC}")"
    [ -n "$new_api_token" ] && CONFIRM_WARN_LINE+=$'\n'"$(echo -e "${WHITE}API токен:${NC}     ${GREEN}обновить${NC}")"
    if ! confirm_nav "🌐 Смена домена подписки" "Подтвердить" "Отменить"; then
        unset CONFIRM_WARN_LINE
        return 0
    fi
    unset CONFIRM_WARN_LINE

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Смена домена подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$subpage_dir" "$current_sub_domain" new_cert_domain; then
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    nginx_copy_cert "$new_cert_domain" 2>/dev/null || true

    # Используем новый токен если указан
    local _use_token="${new_api_token:-$api_token}"

    (
        generate_docker_compose_subpage "$new_cert_domain" "$panel_url" "$_use_token" "$subpage_dir"
        generate_nginx_conf_subpage "$new_domain" "$new_cert_domain" "$subpage_dir"
    ) &
    show_spinner "Подготовка файлов"

    (
        cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1
    ) &
    show_spinner "Обновление конфигурации"

    (
        cd "$subpage_dir"
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    nginx_cleanup_unused_certs

    echo
    print_success "Домен страницы подписки изменён на ${new_domain}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ─── Смена домена локальной страницы подписки ───
_change_sub_domain_local_existing() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Смена домена подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    local current_sub_domain
    current_sub_domain=$(grep -oP '^SUB_PUBLIC_DOMAIN=\K.*' "${panel_dir}/.env" 2>/dev/null)
    if [ -z "$current_sub_domain" ]; then
        # Находим домен подписки по маркеру upstream json
        current_sub_domain=$(
            awk '/^\s*server_name\s/ && !/server_name\s+_/ {
                sn = $2; gsub(/;/, "", sn)
            }
            /proxy_pass http:\/\/json/ && sn != "" { print sn; exit }' "${DIR_NGINX}nginx.conf"
        )
    fi

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен страницы подписки:" new_domain; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')

    local new_api_token
    reading_inline "API токен (Enter оставить без изменений):" new_api_token
    echo

    CONFIRM_WARN_LINE="$(echo -e "${WHITE}Текущий домен:${NC} ${YELLOW}${current_sub_domain}${NC}\n${WHITE}Новый домен:${NC}   ${GREEN}${new_domain}${NC}")"
    [ -n "$new_api_token" ] && CONFIRM_WARN_LINE+=$'\n'"$(echo -e "${WHITE}API токен:${NC}     ${GREEN}обновить${NC}")"
    if ! confirm_nav "🌐 Смена домена подписки" "Подтвердить" "Отменить"; then
        unset CONFIRM_WARN_LINE
        print_error "Операция отменена"
        sleep 2
        return 0
    fi
    unset CONFIRM_WARN_LINE

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Смена домена подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_sub_domain" new_cert_domain; then
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    # Копируем новый сертификат в /opt/nginx/ssl/
    nginx_copy_cert "$new_cert_domain" 2>/dev/null || true

    local old_sub_cert_domain
    old_sub_cert_domain=$(grep -A5 "server_name.*${current_sub_domain}" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -oP '/etc/nginx/ssl/\K[^/]+' | head -1)

    local start_line end_line
    start_line=$(grep -n "server_name ${current_sub_domain}" "${DIR_NGINX}nginx.conf" | head -1 | cut -d: -f1)
    end_line=$(awk -v s="$start_line" 'NR > s && /^\s*server_name\s/ { print NR; exit }' "${DIR_NGINX}nginx.conf")

    (
        if [ -n "$old_sub_cert_domain" ] && [ "$old_sub_cert_domain" != "$new_cert_domain" ]; then
            if [ -n "$start_line" ] && [ -n "$end_line" ]; then
                sed -i "${start_line},${end_line}s|/etc/nginx/ssl/${old_sub_cert_domain}/|/etc/nginx/ssl/${new_cert_domain}/|g" "${DIR_NGINX}nginx.conf"
            elif [ -n "$start_line" ]; then
                sed -i "${start_line},\$s|/etc/nginx/ssl/${old_sub_cert_domain}/|/etc/nginx/ssl/${new_cert_domain}/|g" "${DIR_NGINX}nginx.conf"
            fi
        fi
        sed -i "s|server_name ${current_sub_domain}|server_name ${new_domain}|g" "${DIR_NGINX}nginx.conf"
        if [ -f "${panel_dir}/.env" ]; then
            sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=${new_domain}|" "${panel_dir}/.env"
            if [ -n "$new_api_token" ]; then
                sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=${new_api_token}|" "${panel_dir}/.env"
            fi
        fi
    ) &
    show_spinner "Подготовка файлов"

    (
        cd "${DIR_NGINX}" && docker compose restart nginx >/dev/null 2>&1
    ) &
    show_spinner "Обновление конфигурации"

    (
        cd "$panel_dir"
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    nginx_cleanup_unused_certs

    echo
    print_success "Домен страницы подписки изменён на ${new_domain}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ─── Страница подписки на удалённом сервере ───
_change_sub_domain_remote() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Подписка на удалённом сервере${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi

    local new_domain
    if ! prompt_domain_with_retry "Домен страницы подписки на удалённом сервере:" new_domain false true; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')

    CONFIRM_WARN_LINE="$(echo -e "${WHITE}Домен подписки:${NC} ${GREEN}${new_domain}${NC}")"
    if ! confirm_nav "🌐 Подписка на удалённом сервере" "Подтвердить" "Отменить"; then
        unset CONFIRM_WARN_LINE
        print_error "Операция отменена"
        sleep 2
        return 0
    fi
    unset CONFIRM_WARN_LINE

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Подписка на удалённом сервере${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Авторизуемся в панели ДО спиннеров (чтобы ввод логина/пароля не перемешивался)
    local domain_url="127.0.0.1:3000"
    local _gpt_rc
    get_panel_token; _gpt_rc=$?
    if [[ $_gpt_rc -ne 0 ]]; then
        print_error "Не удалось авторизоваться в панели"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 1
    fi
    local token
    token=$(cat "${DIR_SCRIPT}/token")

    # Обновляем SUB_PUBLIC_DOMAIN
    (
        if grep -q "^SUB_PUBLIC_DOMAIN=" "${panel_dir}/.env" 2>/dev/null; then
            sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=${new_domain}|" "${panel_dir}/.env"
        else
            echo "SUB_PUBLIC_DOMAIN=${new_domain}" >> "${panel_dir}/.env"
        fi
    ) &
    show_spinner "Обновление конфигурации"

    # Проверяем, есть ли уже API токен subscription-page
    local existing_api_token
    existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "${panel_dir}/.env" 2>/dev/null | head -1)

    if [ -z "$existing_api_token" ] || [ "$existing_api_token" = "\$api_token" ]; then
        # Переименовываем старый токен если есть
        docker exec remnawave-db psql -U postgres -d postgres -c \
            "UPDATE api_tokens SET token_name = token_name || '_old' WHERE token_name = 'subscription-page';" >/dev/null 2>&1 || true
        if create_api_token "$domain_url" "$token" "$panel_dir" 2>/dev/null; then
            existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "${panel_dir}/.env" 2>/dev/null | head -1)
        else
            print_error "Не удалось создать API токен"
            echo -e "${YELLOW}Создайте токен вручную: Dashboard → Settings → API Tokens${NC}"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || return 1
            return 1
        fi
    fi

    # Перезапускаем панель с новым SUB_PUBLIC_DOMAIN
    (
        cd "$panel_dir"
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск панели"

    echo
    print_success "Домен страницы подписки изменён на ${new_domain}"
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${WHITE}API токен для страницы подписки:${NC}"
    echo
    echo -e "${GREEN}${existing_api_token}${NC}"
    echo
    echo -e "${DARKGRAY}Используйте этот токен при установке${NC}"
    echo -e "${DARKGRAY}страницы подписки на удалённом сервере.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

change_node_domain() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   🌐 Смена домена ноды${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
        return 1
    fi

    local current_node_domain
    # Определяем домен ноды по маркеру selfsteal (try_files /index.html)
    current_node_domain=$(
        awk '/^\s*server_name\s/ && !/server_name\s+_/ {
            sn = $2; gsub(/;/, "", sn)
        }
        /try_files \/index\.html/ && sn != "" { print sn; exit }' "${DIR_NGINX}nginx.conf"
    )

    if [ -z "$current_node_domain" ]; then
        print_warning "Нода не обнаружена в конфигурации nginx."
        echo -e "${WHITE}Смена домена ноды доступна только при установке${NC}"
        echo -e "${WHITE}типа \"Панель + Нода\" на одном сервере.${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
        return 1
    fi

    echo -e "${WHITE}Текущий домен ноды:${NC} ${YELLOW}${current_node_domain}${NC}"
    echo

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен ноды:" new_domain; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')

    CONFIRM_WARN_LINE="$(echo -e "${WHITE}Текущий домен:${NC} ${YELLOW}${current_node_domain}${NC}\n${WHITE}Новый домен:${NC}   ${GREEN}${new_domain}${NC}")"
    if ! confirm_nav "🌐 Смена домена ноды" "Подтвердить" "Отменить"; then
        unset CONFIRM_WARN_LINE
        print_error "Операция отменена"
        sleep 2
        return 0
    fi
    unset CONFIRM_WARN_LINE

    echo

    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_node_domain" new_cert_domain; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
        echo
        return 1
    fi

    local old_node_cert_domain
    # Копируем новый сертификат в /opt/nginx/ssl/
    nginx_copy_cert "$new_cert_domain" 2>/dev/null || true

    local old_node_cert_domain
    old_node_cert_domain=$(grep -A5 "server_name.*${current_node_domain}" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -oP '/etc/nginx/ssl/\K[^/]+' | head -1)

    local start_line
    start_line=$(grep -n "server_name ${current_node_domain}" "${DIR_NGINX}nginx.conf" | head -1 | cut -d: -f1)

    if [ -n "$old_node_cert_domain" ] && [ "$old_node_cert_domain" != "$new_cert_domain" ]; then
        if [ -n "$start_line" ]; then
            sed -i "${start_line},\$s|/etc/nginx/ssl/${old_node_cert_domain}/|/etc/nginx/ssl/${new_cert_domain}/|g" "${DIR_NGINX}nginx.conf"
        fi
    fi
    sed -i "s|server_name ${current_node_domain}|server_name ${new_domain}|g" "${DIR_NGINX}nginx.conf"
    
    (sleep 0.3) &
    show_spinner "Обновление nginx.conf"

    (
        if [ -f "${panel_dir}/docker-compose.yml" ] && grep -q "${current_node_domain}" "${panel_dir}/docker-compose.yml" 2>/dev/null; then
            sed -i "s|${current_node_domain}|${new_domain}|g" "${panel_dir}/docker-compose.yml"
        fi
    ) &
    show_spinner "Обновление docker-compose.yml"

    (
        cd "$panel_dir"
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    nginx_cleanup_unused_certs

    echo
    print_success "Домен ноды изменён на ${new_domain}"
    echo
    print_warning "Не забудьте обновить домен ноды в панели Remnawave"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
    echo
}

manage_domains() {
    show_arrow_menu "🌐 Редактирование доменов" \
        "🌐  Сменить домен панели" \
        "🌐  Сменить домен страницы подписки" \
        "🌐  Сменить домен ноды" \
        "──────────────────────────────────────" \
        "⬅️   Назад"
    local choice=$?
    [[ $choice -eq 255 ]] && return

    case $choice in
        0) change_panel_domain ;;
        1) change_sub_domain ;;
        2) change_node_domain ;;
        3) : ;;
        4) return ;;
    esac
}
