# ═══════════════════════════════════════════════════
# УДАЛЕНИЕ/ДОБАВЛЕНИЕ НОДЫ
# ═══════════════════════════════════════════════════

remove_node_from_panel() {
    cd /opt 2>/dev/null || cd / 2>/dev/null

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🗑️  УДАЛЕНИЕ НОДЫ С СЕРВЕРА ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if ! is_node_installed; then
        print_error "Нода не найдена на этом сервере"
        echo -e "${YELLOW}На сервере установлена только панель.${NC}"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    echo -e "${YELLOW}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${WHITE}Эта операция удалит ноду с сервера и настроит панель${NC}"
    echo -e "${WHITE}для работы на стандартном порту 443.${NC}"
    echo
    echo -e "${RED}После удаления ноды:${NC}"
    echo -e "  ${GREEN}✓${NC} Панель будет доступна по https (порт 443)"
    echo -e "  ${GREEN}✓${NC} Порт 8443 будет закрыт"
    echo -e "  ${RED}✗${NC} VPN через эту ноду перестанет работать"
    echo

    if ! confirm_action; then
        return
    fi

    local panel_domain="" panel_cert="" COOKIE_NAME="" COOKIE_VALUE=""

    # Определяем домен панели (из .env → fallback nginx.conf)
    panel_domain=$(grep -oP '^FRONT_END_DOMAIN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)
    [ -z "$panel_domain" ] && panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -v '^_$' | head -1)

    if [ -z "$panel_domain" ]; then
        print_error "Не удалось определить домен панели"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    get_cookie_from_nginx

    panel_cert=$(grep -A5 "server_name ${panel_domain};" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -oP '/ssl/\K[^/]+' | head -1)
    [ -z "$panel_cert" ] && panel_cert="$panel_domain"

    # Определяем подписку (по upstream json — надёжнее чем по позиции)
    local sub_domain="" sub_cert=""
    local _json_line=""
    _json_line=$(grep -n 'proxy_pass http://json' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$_json_line" ]; then
        sub_domain=$(head -n "$_json_line" "${DIR_NGINX}nginx.conf" | grep -oP 'server_name\s+\K[^;]+' | tail -1)
        sub_cert=$(head -n "$_json_line" "${DIR_NGINX}nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | tail -1)
        [ -z "$sub_cert" ] && sub_cert="$sub_domain"
    fi

    echo
    # ─── Остановка сервисов ───
    (
        # Останавливаем отдельную ноду
        if [ -f "/opt/remnanode/docker-compose.yml" ]; then
            cd /opt/remnanode && docker compose down >/dev/null 2>&1
        fi
        cd /opt/remnawave && docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка контейнеров"

    # ─── Обновление конфигов ───
    (
        exec >/dev/null 2>&1
        # Бэкап .env
        cp /opt/remnawave/.env /opt/remnawave/.env.bak 2>/dev/null || true

        # Генерируем compose без ноды
        if [ -n "$sub_domain" ]; then
            generate_docker_compose_panel "$panel_cert" "$sub_cert"
        else
            generate_docker_compose_panel_only "$panel_cert"
        fi

        # Восстанавливаем API токен и настройки из бэкапа .env
        local existing_api_token
        existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env.bak 2>/dev/null | head -1)
        if [ -n "$existing_api_token" ]; then
            sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=$existing_api_token|" /opt/remnawave/.env
        fi
        rm -f /opt/remnawave/.env.bak 2>/dev/null || true

        # Генерируем nginx без ноды
        if [ -n "$sub_domain" ]; then
            generate_nginx_conf_panel "$panel_domain" "$sub_domain" "$panel_cert" "$sub_cert" "$COOKIE_NAME" "$COOKIE_VALUE"
        else
            generate_nginx_conf_panel_only "$panel_domain" "$panel_cert" "$COOKIE_NAME" "$COOKIE_VALUE"
        fi

        nginx_strip_ipv6_if_disabled

        # Удаляем compose ноды
        rm -f /opt/remnanode/docker-compose.yml 2>/dev/null || true
        rmdir /opt/remnanode 2>/dev/null || true

        # Удаляем неиспользуемые сертификаты
        nginx_cleanup_unused_certs

        # Закрываем порты
        ufw delete allow 8443/tcp >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление ноды"

    # ─── Запуск сервисов ───
    (
        cd /opt/remnawave && docker compose up -d >/dev/null 2>&1
        nginx_reload
    ) &
    show_spinner "Запуск сервисов"

    show_spinner_timer 15 "Ожидание запуска панели" "Запуск панели"
    tput cnorm 2>/dev/null || true

    clear
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${GREEN}🎉 Нода удалена, панель настроена!${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Панель теперь доступна по:${NC}"
    echo -e "${GREEN}https://${panel_domain}/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${DARKGRAY}Порт 443 активен, порт 8443 закрыт${NC}"
    echo
    show_continue_prompt || return 1
}

add_node_to_panel() {
    if [ ! -f "/opt/remnawave/docker-compose.yml" ] || [ ! -f "${DIR_NGINX}nginx.conf" ]; then
        print_error "Панель Remnawave не найдена на этом сервере"
        echo -e "${YELLOW}Эта функция регистрирует ноду на удалённом сервере в панели.${NC}"
        echo -e "${YELLOW}Панель должна быть установлена на этом сервере.${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi

    local domain_url="127.0.0.1:3000"

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     ➕  Подключение ноды в панель${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${DARKGRAY}⚠️  Добавление ноды в панель предназначена для запуска${NC}"
    echo -e "${DARKGRAY}   на сервере с установленной панелью Remnawave.${NC}"
    echo
    echo -e "${DARKGRAY}   После завершения подключения, запустите установку${NC}"
    echo -e "${DARKGRAY}   ноды (Только нода) на сервере ноды.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    local _gpt_rc
    get_panel_token; _gpt_rc=$?
    if [[ $_gpt_rc -eq 2 ]]; then return; fi
    if [[ $_gpt_rc -ne 0 ]]; then
        print_error "Не удалось получить токен"
        echo
        show_continue_prompt || return 1
        return
    fi
    local token
    token=$(cat "${DIR_SCRIPT}/token")

    local SELFSTEAL_DOMAIN=""
    local entity_name=""
    local _step=1
    local _overwrite_domain=false

    while true; do
        if [[ $_step -eq 1 ]]; then
            _overwrite_domain=false
            reading_inline "Введите selfsteal домен для ноды (например, node.example.com):" SELFSTEAL_DOMAIN
            local _rc_sd=$?
            if [[ $_rc_sd -eq 2 ]]; then
                return
            fi
            if [[ -z "$SELFSTEAL_DOMAIN" ]]; then continue; fi
            check_node_domain "$domain_url" "$token" "$SELFSTEAL_DOMAIN"
            local _cnd_rc=$?
            if [[ $_cnd_rc -eq 0 ]]; then
                _step=2
            elif [[ $_cnd_rc -eq 1 ]]; then
                echo
                echo -e "${YELLOW}⚠️  Домен $SELFSTEAL_DOMAIN уже используется в панели${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                _flush_stdin
                tput civis 2>/dev/null
                printf "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Перезаписать    ${BLUE}Esc${DARKGRAY}: Назад${NC}"
                local _owk
                while true; do
                    IFS= read -rsn1 _owk 2>/dev/null
                    if [[ "$_owk" == "" ]] || [[ "$_owk" == $'\n' ]] || [[ "$_owk" == $'\r' ]]; then
                        tput cnorm 2>/dev/null; echo
                        entity_name=$(make_api_request "GET" "$domain_url/api/nodes" "$token" | \
                            jq -r --arg addr "$SELFSTEAL_DOMAIN" '.response[] | select(.address == $addr) | .name' 2>/dev/null)
                        _overwrite_domain=true
                        _step=2
                        break
                    elif [[ "$_owk" == $'\x1b' ]]; then
                        IFS= read -rsn1 -t 0.1 _ows 2>/dev/null || true
                        if [[ -z "$_ows" ]]; then
                            tput cnorm 2>/dev/null; echo
                            return
                        fi
                        IFS= read -rsn1 -t 0.1 2>/dev/null || true
                    fi
                done
            else
                echo -e "${YELLOW}Пожалуйста, используйте другой домен${NC}"
            fi
        else
            if [[ "$_overwrite_domain" == true ]]; then break; fi
            reading_inline "Введите имя для вашей ноды (например, Germany):" entity_name
            local _rc_en=$?
            if [[ $_rc_en -eq 2 ]]; then
                _step=1
                SELFSTEAL_DOMAIN=""
                continue
            fi
            if [[ -z "$entity_name" ]]; then continue; fi
            if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
                if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                    local response
                    response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
                    if echo "$response" | jq -e ".response.configProfiles[] | select(.name == \"$entity_name\")" >/dev/null 2>&1; then
                        print_error "Имя конфигурационного профиля '$entity_name' уже используется. Выберите другое."
                    else
                        break
                    fi
                else
                    print_error "Имя должно содержать от 3 до 20 символов"
                fi
            else
                print_error "Имя должно содержать только английские буквы, цифры и дефис"
            fi
        fi
    done

    # Если перезаписываем — удаляем существующую ноду
    if [[ "$_overwrite_domain" == true ]]; then
        echo
        print_action "Удаление существующей ноды..."
        if ! delete_node_by_domain "$domain_url" "$token" "$SELFSTEAL_DOMAIN"; then
            print_error "Не удалось удалить существующую ноду"
            show_continue_prompt || true
            return 1
        fi
        print_success "Существующая нода удалена"
    fi

    echo
    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")
    if [ -z "$private_key" ]; then
        print_error "Не удалось сгенерировать ключи"
        show_continue_prompt || true
        return 1
    fi
    print_success "Ключи сгенерированы"

    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result config_profile_uuid inbound_uuid
    if ! config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name"); then
        print_error "Не удалось создать конфигурационный профиль"
        show_continue_prompt || true
        return 1
    fi
    read config_profile_uuid inbound_uuid <<< "$config_result"
    print_success "Конфигурационный профиль: $entity_name"

    print_action "Создание ноды ($entity_name)..."
    if create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$SELFSTEAL_DOMAIN" "$entity_name"; then
        print_success "Нода создана"
    else
        print_error "Не удалось создать ноду"
        show_continue_prompt || true
        return 1
    fi

    print_action "Создание хоста ($SELFSTEAL_DOMAIN)..."
    if create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$entity_name" "$SELFSTEAL_DOMAIN"; then
        print_success "Хост зарегистрирован"
    else
        print_error "Не удалось зарегистрировать хост"
    fi

    print_action "Настройка сквадов..."
    local squad_uuids
    squad_uuids=$(get_default_squad "$domain_url" "$token")
    if [ -n "$squad_uuids" ]; then
        while IFS= read -r squad_uuid; do
            [ -z "$squad_uuid" ] && continue
            update_squad "$domain_url" "$token" "$squad_uuid" "$inbound_uuid"
        done <<< "$squad_uuids"
        print_success "Сквады обновлены"
    else
        echo -e "${YELLOW}⚠️  Сквады не найдены (будут настроены при создании пользователей)${NC}"
    fi

    # Получаем pubkey панели — он нужен пользователю как SECRET_KEY при установке ноды
    local pubkey=""
    local keygen_response
    keygen_response=$(make_api_request "GET" "$domain_url/api/keygen" "$token" 2>/dev/null)
    pubkey=$(echo "$keygen_response" | jq -r '.response.pubKey // empty' 2>/dev/null)

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     ➕  Подключение ноды в панель${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${RED}─────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Для завершения установки ноды:${NC}"
    echo -e "${WHITE}1. Запустите этот скрипт на сервере, где будет установлена нода${NC}"
    echo -e "${WHITE}2. Выберите \"Установить компоненты\" → \"Только нода\"${NC}"
    if [ -n "$pubkey" ]; then
        echo -e "${WHITE}3. Когда скрипт попросит SECRET KEY — вставьте:${NC}"
        echo
        echo -e "   ${GREEN}${pubkey}${NC}"
        echo
    fi
    echo -e "${RED}─────────────────────────────────────────────────${NC}"
    echo
    print_success "Нода успешно зарегистрирована в панели!"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}
