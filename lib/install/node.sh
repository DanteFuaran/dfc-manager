# ═══════════════════════════════════════════════
# УСТАНОВКА: ТОЛЬКО НОДА
# ═══════════════════════════════════════════════

installation_node() {
    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Проверяем, не установлена ли уже нода
    if [ -f "/opt/remnawave/docker-compose.yml" ] && grep -q "remnanode" /opt/remnawave/docker-compose.yml; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${RED}      ⚠️  Нода уже установлена${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        print_warning "На этом сервере уже установлена нода."
        echo -e "   ${DARKGRAY}Чтобы переустановить ноду, нажмите ${BLUE}Enter${DARKGRAY}.${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"

        # Промпт: Enter = переустановить, Esc = назад
        tput civis 2>/dev/null
        local _choice=0
        while true; do
            printf "${DARKGRAY} ${BLUE}Enter${DARKGRAY}: Переустановить    ${BLUE}Esc${DARKGRAY}: Назад${NC}"
            local _nk
            IFS= read -rsn1 _nk 2>/dev/null
            if [[ "$_nk" == "" ]] || [[ "$_nk" == $'\n' ]] || [[ "$_nk" == $'\r' ]]; then
                _choice=1; break
            elif [[ "$_nk" == $'\x1b' ]]; then
                IFS= read -rsn1 -t 0.1 _ns 2>/dev/null || true
                [[ -z "$_ns" ]] && { _choice=0; break; }
            fi
        done
        tput cnorm 2>/dev/null; echo

        # Esc — выход в главное меню
        [[ $_choice -eq 0 ]] && return 1

        # Enter — подтверждение переустановки
        if ! confirm_nav --delete "⚠️ Переустановка ноды"; then
            return 0
        fi

        # Останавливаем и удаляем контейнер ноды с томами
        (
            cd /opt/remnawave 2>/dev/null
            docker compose stop remnanode 2>/dev/null || true
            docker compose rm -f -v remnanode 2>/dev/null || true
        ) &
        show_spinner "Удаление контейнера ноды"

        # Если нода стоит отдельно (не на сервере панели) — чистим .env и compose
        if ! [ -f "${DIR_NGINX}nginx.conf" ]; then
            (
                cd /opt/remnawave 2>/dev/null
                docker compose down -v 2>/dev/null || true
                rm -f /opt/remnawave/docker-compose.yml
                rm -f /opt/remnawave/.env
            ) &
            show_spinner "Очистка конфигурации ноды"
        fi
        # Продолжаем — is_local_panel будет пересчитан ниже
    fi

    # ─── Определяем режим: локальная панель или удалённая ───
    local is_local_panel=false
    if [ -f "/opt/remnawave/docker-compose.yml" ] && [ -f "${DIR_NGINX}nginx.conf" ] && \
       grep -q "remnawave:" /opt/remnawave/docker-compose.yml 2>/dev/null && \
       ! grep -q "remnanode" /opt/remnawave/docker-compose.yml 2>/dev/null; then
        is_local_panel=true
    fi

    if [ "$is_local_panel" = true ]; then
        installation_node_local
    elif [ -f "/opt/remnasubpage/docker-compose.yml" ] || [ -f "/opt/subscribe-page/docker-compose.yml" ]; then
        installation_node_with_existing_subpage
    else
        installation_node_remote
    fi
}

# ─── Подключение удалённой ноды к панели (только API регистрация) ───
installation_node_connect() {
    local domain_url="127.0.0.1:3000"

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}     ➕ Подключение ноды в панель${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # ─── Авторизуемся, затем запрашиваем домен и имя ───
    local SELFSTEAL_DOMAIN entity_name
    local _input_step=1
    local _overwrite_domain=false
    while true; do
        if [[ $_input_step -eq 1 ]]; then
            # ─── Авторизация в панели ───
            local _gpt_rc
            get_panel_token; _gpt_rc=$?
            if [[ $_gpt_rc -ne 0 ]]; then
                echo -e "${YELLOW}Авторизация отменена${NC}"
                echo
                show_continue_prompt || return 1
                return
            fi
            tput sc 2>/dev/null || true
            _input_step=2
        fi
        if [[ $_input_step -eq 2 ]]; then
            prompt_domain_with_retry "Введите домен ноды ${DARKGRAY}(например node.example.com)${DARKGRAY}:" SELFSTEAL_DOMAIN true true || return
            # ─── Проверка домена в панели ───
            local _chk_token
            _chk_token=$(cat "${DIR_SCRIPT}/token")
            check_node_domain "$domain_url" "$_chk_token" "$SELFSTEAL_DOMAIN"
            local _cnd_rc=$?
            if [[ $_cnd_rc -eq 2 ]]; then
                echo
                show_continue_prompt || return 1
                return
            elif [[ $_cnd_rc -eq 1 ]]; then
                local _existing_name _owk _ows
                _existing_name=$(make_api_request "GET" "$domain_url/api/nodes" "$_chk_token" | \
                    jq -r --arg addr "$SELFSTEAL_DOMAIN" '.response[] | select(.address == $addr) | .name' 2>/dev/null)
                echo
                print_warning "Домен $SELFSTEAL_DOMAIN уже используется в панели"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                _flush_stdin
                tput civis 2>/dev/null
                printf "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Перезаписать    ${BLUE}Esc${DARKGRAY}: Назад${NC}"
                while true; do
                    IFS= read -rsn1 _owk 2>/dev/null
                    if [[ "$_owk" == "" ]] || [[ "$_owk" == $'\n' ]] || [[ "$_owk" == $'\r' ]]; then
                        tput cnorm 2>/dev/null; echo
                        _overwrite_domain=true
                        entity_name="$_existing_name"
                        _input_step=4
                        break
                    elif [[ "$_owk" == $'\x1b' ]]; then
                        IFS= read -rsn1 -t 0.1 _ows 2>/dev/null || true
                        if [[ -z "$_ows" ]]; then
                            tput cnorm 2>/dev/null; echo
                            tput rc 2>/dev/null || true
                            printf "\033[J" 2>/dev/null || true
                            SELFSTEAL_DOMAIN=""
                            break
                        fi
                        IFS= read -rsn1 -t 0.1 2>/dev/null || true
                    fi
                done
                [[ $_input_step -eq 4 ]] || continue
            else
                _input_step=3
            fi
        fi
        if [[ $_input_step -eq 3 ]]; then
            while true; do
                reading_inline "Введите имя для ноды ${DARKGRAY}(например, Germany)${DARKGRAY}:" entity_name
                local _rc_en=$?
                if [[ $_rc_en -eq 2 ]]; then
                    tput rc 2>/dev/null || true
                    printf "\033[J" 2>/dev/null || true
                    SELFSTEAL_DOMAIN=""
                    _input_step=2
                    break
                fi
                if [[ -z "$entity_name" ]]; then continue; fi
                if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
                    if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                        _input_step=4
                        break
                    else
                        print_error "Название должно быть от 3 до 20 символов"
                    fi
                else
                    print_error "Допустимы только символы: a-zA-Z0-9 и дефис"
                fi
            done
            [[ $_input_step -eq 4 ]] || continue
        fi
        break
    done
    local token
    token=$(cat "${DIR_SCRIPT}/token")

    # ─── Удаляем существующую ноду при перезаписи ───
    if [[ "$_overwrite_domain" == true ]]; then
        if ! delete_node_by_domain "$domain_url" "$token" "$SELFSTEAL_DOMAIN"; then
            echo
            print_error "Не удалось удалить существующую ноду"
            echo
            show_continue_prompt || return 1
            return
        fi
    fi

    local _cp_resp
    _cp_resp=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
    if echo "$_cp_resp" | jq -e ".response.configProfiles[] | select(.name == \"$entity_name\")" >/dev/null 2>&1; then
        print_error "Имя конфигурационного профиля '$entity_name' уже используется"
        echo
        show_continue_prompt || return 1
        return
    fi

    # ─── API: регистрация ноды ───
    echo
    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")
    if [ -z "$private_key" ]; then
        print_error "Не удалось сгенерировать ключи"
        echo
        show_continue_prompt || return 1
        return
    fi
    print_success "Ключи сгенерированы"

    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result config_profile_uuid inbound_uuid
    if ! config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name"); then
        print_error "Не удалось создать конфигурационный профиль"
        echo
        show_continue_prompt || return 1
        return
    fi
    read config_profile_uuid inbound_uuid <<< "$config_result"
    print_success "Конфигурационный профиль: $entity_name"

    # Порт ноды всегда 2222
    local NODE_LISTEN_PORT=2222

    print_action "Создание ноды ($entity_name)..."
    if create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$SELFSTEAL_DOMAIN" "$entity_name" "$NODE_LISTEN_PORT"; then
        print_success "Нода создана"
    else
        print_error "Не удалось создать ноду"
        echo
        show_continue_prompt || return 1
        return
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
        print_warning "Сквады не найдены"
    fi

    # ─── Получаем SECRET_KEY для удалённого сервера ───
    print_action "Получение публичного ключа панели..."
    local pubkey
    pubkey=$(make_api_request "GET" "$domain_url/api/keygen" "$token" | jq -r '.response.pubKey // empty' 2>/dev/null)

    # ─── Итог ───
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "  ${GREEN}🎉 Нода зарегистрирована в панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    local _is_local_node=false
    if [ -f "${DIR_NGINX}nginx.conf" ] && grep -q "$SELFSTEAL_DOMAIN" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        _is_local_node=true
    fi
    print_warning "Сертификат (Секретный ключ) для установки ноды"
    echo
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    echo
    if [ "$_is_local_node" = true ]; then
        echo -e "${GREEN}Нода успешно подключена!${NC}"
    elif [ -n "$pubkey" ]; then
        echo -e "${WHITE}${pubkey}${NC}"
        echo
        echo -e "${DARKGRAY}Используйте сертификат для установки ноды на удалённом сервере${NC}"
    fi
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ─── Установка ноды на сервер с панелью (автодетект) ───
installation_node_local() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}     🌐 Установка ноды на сервер${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    # Проверяем пакеты
    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"
    local node_dir="/opt/remnanode"

    # ─── Сохраняем бэкап конфигов для восстановления при отмене ───
    local backup_compose="" backup_nginx="" backup_node_compose=""
    backup_compose=$(cat /opt/remnawave/docker-compose.yml 2>/dev/null)
    backup_nginx=$(cat ${DIR_NGINX}nginx.conf 2>/dev/null)
    backup_node_compose=$(cat /opt/remnanode/docker-compose.yml 2>/dev/null)

    # Функция восстановления при отмене (до изменения конфигов)
    _restore_panel_config() {
        if [ -n "$backup_compose" ]; then
            echo "$backup_compose" > /opt/remnawave/docker-compose.yml
        fi
        if [ -n "$backup_nginx" ]; then
            echo "$backup_nginx" > ${DIR_NGINX}nginx.conf
        fi
        if [ -n "$backup_node_compose" ]; then
            echo "$backup_node_compose" > /opt/remnanode/docker-compose.yml
        else
            rm -f /opt/remnanode/docker-compose.yml 2>/dev/null
        fi
        # Останавливаем ноду и перезапускаем панель с оригинальными конфигами
        (cd /opt/remnanode && docker compose down >/dev/null 2>&1) 2>/dev/null || true
        (
            cd /opt/remnawave
            docker compose down >/dev/null 2>&1
            docker compose up -d >/dev/null 2>&1
        ) &
        show_spinner "Восстановление конфигурации панели"
        show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
        tput cnorm 2>/dev/null || true
    }

    # ─── Автоопределение конфигурации из существующей панели ───
    echo
    print_action "Определение конфигурации панели..."

    # Определяем, есть ли локальная страница подписки
    local has_local_sub=false
    if [ -f "${DIR_SUB}docker-compose.yml" ]; then
        has_local_sub=true
    fi

    # Извлекаем домены из nginx.conf
    local panel_domain sub_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' ${DIR_NGINX}nginx.conf | sed -n '1p')

    if [ "$has_local_sub" = true ]; then
        # Определяем домен подписки по маркеру upstream json
        sub_domain=$(
            awk '/^\s*server_name\s/ && !/server_name\s+_/ {
                sn = $2; gsub(/;/, "", sn)
            }
            /proxy_pass http:\/\/json/ && sn != "" { print sn; exit }' "${DIR_NGINX}nginx.conf"
        )
    else
        # Страница подписки на удалённом сервере — берём домен из .env
        sub_domain=$(grep -oP '^SUB_PUBLIC_DOMAIN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)
    fi

    if [ -z "$panel_domain" ]; then
        print_error "Не удалось определить домен панели из nginx.conf"
        echo
        show_continue_prompt || return 1
        return
    fi

    # Извлекаем cookie
    local COOKIE_NAME COOKIE_VALUE
    if ! get_cookie_from_nginx; then
        print_error "Не удалось получить cookie"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return
    fi

    # Извлекаем API токен
    local existing_api_token
    existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)

    # Определяем домены сертификатов
    local panel_cert_domain sub_cert_domain
    panel_cert_domain=$(grep -A5 "server_name ${panel_domain};" ${DIR_NGINX}nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
    [ -z "$panel_cert_domain" ] && panel_cert_domain="$panel_domain"

    if [ "$has_local_sub" = true ]; then
        sub_cert_domain=$(grep -A5 "server_name ${sub_domain};" ${DIR_NGINX}nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
        [ -z "$sub_cert_domain" ] && sub_cert_domain="$sub_domain"
    fi

    # Автоопределяем метод сертификации
    local AUTO_CERT_METHOD
    AUTO_CERT_METHOD=$(detect_cert_method "$panel_domain")

    # ─── Запрашиваем selfsteal домен, авторизуемся, проверяем и вводим имя ───
    local SELFSTEAL_DOMAIN entity_name
    local _input_step=1
    local _overwrite_domain=false
    while true; do
        if [[ $_input_step -eq 1 ]]; then
            tput sc 2>/dev/null || true
            prompt_domain_with_retry "Введите домен ноды ${DARKGRAY}(например node.example.com)${DARKGRAY}:" SELFSTEAL_DOMAIN true true || return
            _input_step=2
        fi
        if [[ $_input_step -eq 2 ]]; then
            # ─── Авторизация в панели (до изменения конфигов) ───
            local _gpt_rc
            get_panel_token; _gpt_rc=$?
            if [[ $_gpt_rc -eq 2 ]]; then
                tput rc 2>/dev/null || true
                printf "\033[J" 2>/dev/null || true
                SELFSTEAL_DOMAIN=""
                _input_step=1
                continue
            fi
            if [[ $_gpt_rc -ne 0 ]]; then
                echo -e "${YELLOW}Установка отменена${NC}"
                echo
                show_continue_prompt || return 1
                return
            fi
            # ─── Проверка домена в панели (до изменения конфигов) ───
            local _chk_token
            _chk_token=$(cat "${DIR_SCRIPT}/token")
            check_node_domain "$domain_url" "$_chk_token" "$SELFSTEAL_DOMAIN"
            local _cnd_rc=$?
            if [[ $_cnd_rc -eq 2 ]]; then
                echo
                show_continue_prompt || return 1
                return
            elif [[ $_cnd_rc -eq 1 ]]; then
                local _existing_name _owk _ows
                _existing_name=$(make_api_request "GET" "$domain_url/api/nodes" "$_chk_token" | \
                    jq -r --arg addr "$SELFSTEAL_DOMAIN" '.response[] | select(.address == $addr) | .name' 2>/dev/null)
                echo
                print_warning "Домен $SELFSTEAL_DOMAIN уже используется в панели"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                _flush_stdin
                tput civis 2>/dev/null
                printf "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Перезаписать    ${BLUE}Esc${DARKGRAY}: Назад${NC}"
                while true; do
                    IFS= read -rsn1 _owk 2>/dev/null
                    if [[ "$_owk" == "" ]] || [[ "$_owk" == $'\n' ]] || [[ "$_owk" == $'\r' ]]; then
                        tput cnorm 2>/dev/null; echo
                        _overwrite_domain=true
                        entity_name="$_existing_name"
                        _input_step=4
                        break
                    elif [[ "$_owk" == $'\x1b' ]]; then
                        IFS= read -rsn1 -t 0.1 _ows 2>/dev/null || true
                        if [[ -z "$_ows" ]]; then
                            tput cnorm 2>/dev/null; echo
                            tput rc 2>/dev/null || true
                            printf "\033[J" 2>/dev/null || true
                            SELFSTEAL_DOMAIN=""
                            _input_step=1
                            break
                        fi
                        IFS= read -rsn1 -t 0.1 2>/dev/null || true
                    fi
                done
                [[ $_input_step -eq 1 ]] && continue
            else
                _input_step=3
            fi
        fi
        if [[ $_input_step -eq 3 ]]; then
            while true; do
                reading_inline "Введите имя для ноды ${DARKGRAY}(например, Germany)${DARKGRAY}:" entity_name
                local _rc_en=$?
                if [[ $_rc_en -eq 2 ]]; then
                    tput rc 2>/dev/null || true
                    printf "\033[J" 2>/dev/null || true
                    SELFSTEAL_DOMAIN=""
                    _input_step=1
                    break
                fi
                if [[ -z "$entity_name" ]]; then continue; fi
                if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
                    if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                        _input_step=4
                        break
                    else
                        print_error "Название должно быть от 3 до 20 символов"
                    fi
                else
                    print_error "Допустимы только символы: a-zA-Z0-9 и дефис"
                fi
            done
            [[ $_input_step -eq 4 ]] || continue
        fi
        break
    done
    local token
    token=$(cat "${DIR_SCRIPT}/token")

    # ─── Удаляем существующую ноду при перезаписи ───
    if [[ "$_overwrite_domain" == true ]]; then
        if ! delete_node_by_domain "$domain_url" "$token" "$SELFSTEAL_DOMAIN"; then
            echo
            print_error "Не удалось удалить существующую ноду"
            echo
            show_continue_prompt || return 1
            return
        fi
    fi

    local response
    response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
    if echo "$response" | jq -e ".response.configProfiles[] | select(.name == \"$entity_name\")" >/dev/null 2>&1; then
        print_error "Имя конфигурационного профиля '$entity_name' уже используется"
        echo
        show_continue_prompt || return 1
        return
    fi

    # ─── Получаем сертификат для selfsteal домена ───
    local CERT_METHOD="$AUTO_CERT_METHOD"
    local LETSENCRYPT_EMAIL=""

    declare -A domains_to_check
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then

        if [ "$CERT_METHOD" = "1" ]; then
            if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                show_arrow_menu "🔐 Метод получения сертификата" \
                    "🌐  ACME HTTP-01 (Let's Encrypt)" \
                    "☁️   Cloudflare DNS-01 (wildcard)" \
                    "──────────────────────────────────────" \
                    "⬅️   Назад"
                local cert_choice=$?
                case $cert_choice in
                    0) CERT_METHOD=2 ;;
                    1) CERT_METHOD=1 ;;
                    *) return ;;
                esac
                setup_cloudflare_credentials || return
            fi
        fi

        LETSENCRYPT_EMAIL=$(grep -r "email" /etc/letsencrypt/accounts/ 2>/dev/null | grep -oP '"[^@]+@[^"]+' | head -1 | tr -d '"')
        if [ -z "$LETSENCRYPT_EMAIL" ]; then
            reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
            [[ $? -eq 2 ]] && return
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
        print_cert_exists "$SELFSTEAL_DOMAIN"
    fi

    local NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" = "1" ]; then
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # Копируем сертификат ноды в /opt/nginx/ssl/
    nginx_copy_cert "$NODE_CERT_DOMAIN" 2>/dev/null || true

    # TCP-порт API ноды (2222) — спрашиваем ДО остановки, чтобы видеть реальную картину занятых портов
    local NODE_LISTEN_PORT=2222
    if ! prompt_remnanode_listen_port NODE_LISTEN_PORT 2222; then
        return 1
    fi

    # TCP-порт входящего VLESS REALITY (8443) — проверяем ДО остановки сервисов,
    # чтобы обнаружить сторонние процессы (MTProto и др.), которые не остановятся вместе с панелью
    local NODE_INBOUND_PORT=8443
    if ! prompt_host_inbound_port NODE_INBOUND_PORT 8443; then
        return 1
    fi
    echo

    # ─── Остановка и подготовка файлов ───
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка сервисов" || true

    (
        exec >/dev/null 2>&1
        mkdir -p /var/www/html

        if [ "$has_local_sub" = true ]; then
            generate_docker_compose_full "$panel_cert_domain" "$sub_cert_domain" "$NODE_CERT_DOMAIN" "$NODE_LISTEN_PORT"
        else
            generate_docker_compose_panel_with_node "$panel_cert_domain" "$NODE_CERT_DOMAIN" "$NODE_LISTEN_PORT"
        fi

        if [ -n "$existing_api_token" ]; then
            sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=$existing_api_token|" /opt/remnawave/.env
        fi

        if [ "$has_local_sub" = true ]; then
            generate_nginx_conf_full "$panel_domain" "$sub_domain" "$SELFSTEAL_DOMAIN" \
                "$panel_cert_domain" "$sub_cert_domain" "$NODE_CERT_DOMAIN" \
                "$COOKIE_NAME" "$COOKIE_VALUE"
        else
            generate_nginx_conf_panel_with_node "$panel_domain" "$SELFSTEAL_DOMAIN" \
                "$panel_cert_domain" "$NODE_CERT_DOMAIN" \
                "$COOKIE_NAME" "$COOKIE_VALUE"
        fi

        _ni=$(get_remnawave_network_info 2>/dev/null) || true
        _nw_subnet=$(echo "$_ni" | awk '{print $2}')
        _node_server_ip=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || \
                          curl -s4 --max-time 5 api.ipify.org 2>/dev/null || \
                          hostname -I | awk '{print $1}')
        # Подсеть remnawave-network покрывает панель в Docker; отдельно gateway не нужен.
        # Публичный IP — hairpin/SNAT, если панель ходит к ноде по внешнему адресу.
        [ -n "$_nw_subnet" ] && ufw allow from "$_nw_subnet" to any port "$NODE_LISTEN_PORT" >/dev/null 2>&1 || true
        [ -n "$_node_server_ip" ] && ufw allow from "$_node_server_ip" to any port "$NODE_LISTEN_PORT" >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        ufw allow "${NODE_INBOUND_PORT}/tcp" >/dev/null 2>&1 || true
    ) &
    show_spinner "Подготовка файлов" || true

    echo

    # ─── Запуск сервисов ───
    (
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1
        cd "$node_dir"
        docker compose up -d >/dev/null 2>&1 || true
        cd "${DIR_NGINX}"
        docker compose up -d --force-recreate >/dev/null 2>&1 || true
    ) &
    if ! show_spinner "Настройка сервисов"; then
        print_error "Не удалось запустить контейнеры"
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi

    if ! show_spinner_until_ready "http://127.0.0.1:3001/health" "Проверка доступности API" 120; then
        print_error "API не отвечает. Восстановление конфигурации..."
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi

    echo

    # ─── Регистрация ноды ───
    local _tmp_pk="/tmp/_nd_pk_$$"
    local _tmp_cr="/tmp/_nd_cr_$$"

    (
        exec >/dev/null 2>&1
        get_public_key "$domain_url" "$token" "$node_dir" || exit 1
        if grep -q 'PUBLIC KEY FROM REMNAWAVE-PANEL' "$node_dir/docker-compose.yml" 2>/dev/null; then
            exit 1
        fi
        pk=$(generate_xray_keys "$domain_url" "$token") || exit 1
        [ -z "$pk" ] && exit 1
        echo "$pk" > "$_tmp_pk"
        cr=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$pk" "$entity_name" "$NODE_INBOUND_PORT") || exit 1
        echo "$cr" > "$_tmp_cr"
        read cpu_u ci_u <<< "$cr"
        create_node "$domain_url" "$token" "$cpu_u" "$ci_u" "$SELFSTEAL_DOMAIN" "$entity_name" "$NODE_LISTEN_PORT" || exit 1
    ) &
    if ! show_spinner "Создание Ноды"; then
        print_error "Не удалось зарегистрировать ноду. Восстановление..."
        _restore_panel_config
        rm -f "$_tmp_pk" "$_tmp_cr"
        echo
        show_continue_prompt || return 1
        return
    fi

    local config_result config_profile_uuid inbound_uuid
    config_result=$(cat "$_tmp_cr" 2>/dev/null)
    rm -f "$_tmp_pk" "$_tmp_cr"
    read config_profile_uuid inbound_uuid <<< "$config_result"

    if [ -z "$config_profile_uuid" ] || [ -z "$inbound_uuid" ]; then
        print_error "Не удалось получить данные ноды. Восстановление..."
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi

    (
        exec >/dev/null 2>&1
        create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$entity_name" "$SELFSTEAL_DOMAIN" "$NODE_INBOUND_PORT" || true
        squad_uuids=$(get_default_squad "$domain_url" "$token") || true
        if [ -n "$squad_uuids" ]; then
            while IFS= read -r squad_uuid; do
                [ -z "$squad_uuid" ] && continue
                update_squad "$domain_url" "$token" "$squad_uuid" "$inbound_uuid" || true
            done <<< "$squad_uuids"
        fi
    ) &
    show_spinner "Регистрация хоста" || true

    # ─── Финальный перезапуск (с обновлённым SECRET_KEY) ───
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1 || true
        docker compose up -d >/dev/null 2>&1 || true
        cd "$node_dir"
        docker compose down >/dev/null 2>&1 || true
        docker compose up -d >/dev/null 2>&1 || true
        cd "${DIR_NGINX}"
        docker compose restart nginx >/dev/null 2>&1 || true
    ) &
    show_spinner "Подготовка панели" || true

    randomhtml
    echo

    show_spinner_timer 15 "Запуск сервисов" "Запуск сервисов"

    if ! show_spinner_until_ready "http://127.0.0.1:3001/health" "Подключение к панели" 120; then
        print_error "Панель не отвечает после перезапуска. Восстановление..."
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi

    # ─── API: создание токена для subscription-page (если не было) ───
    if [ -z "$existing_api_token" ] || [ "$existing_api_token" = "\$api_token" ]; then
        print_action "Создание API токена для подписок..."
        if create_api_token "$domain_url" "$token" "/opt/remnawave"; then
            print_success "API токен создан"
            if [ "$has_local_sub" = true ]; then
                # Перезапускаем subscription-page с новым токеном
                (cd /opt/remnawave && docker compose up -d remnawave-subscription-page >/dev/null 2>&1) &
                show_spinner "Перезапуск subscription-page"
            fi
        else
            print_error "Не удалось создать API токен"
            print_warning "Subscription-page может не работать. Создайте токен вручную:"
            echo -e "   ${WHITE}Remnawave Dashboard → Settings → API Tokens${NC}"
        fi
    fi

    # ─── Итог ───
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "  ${GREEN}🎉 Нода добавлена на сервер панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "$(center "✅ Нода успешно добавлена!" "$WHITE")"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ─── Установка ноды на отдельный сервер (удалённая панель) ───
installation_node_remote() {
    # Узнаём куда устанавливать: /opt/remnanode (отдельная нода)
    local NODE_INSTALL_DIR="/opt/remnanode"

    # Проверяем, это первичная установка?
    local is_fresh_install=false
    if [ ! -d "${NODE_INSTALL_DIR}" ] || [ -z "$(ls -A "${NODE_INSTALL_DIR}" 2>/dev/null)" ]; then
        is_fresh_install=true
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       📦 Установка только ноды${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    mkdir -p "${NODE_INSTALL_DIR}" && cd "${NODE_INSTALL_DIR}"

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap 'rm -rf "'"${NODE_INSTALL_DIR}"'" 2>/dev/null; handle_interrupt' INT TERM
    fi

    prompt_domain_with_retry "Домен ноды ${DARKGRAY}(например node.example.com)${DARKGRAY}:" SELFSTEAL_DOMAIN || { [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null; return; }

    local PANEL_IP
    prompt_ip_with_retry "IP адрес сервера панели:" PANEL_IP || { [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null; return; }

    echo
    echo -e "${BLUE}➜${NC}  ${YELLOW}Вставьте сертификат (Секретный ключ) из панели и нажмите Enter дважды:${NC}"
    local CERTIFICATE=""
    while IFS= read -r line; do
        if [ -z "$line" ] && [ -n "$CERTIFICATE" ]; then
            break
        fi
        CERTIFICATE="$CERTIFICATE$line\n"
    done

    declare -A domains_to_check
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    local needs_certs=false
    if check_if_certificates_needed domains_to_check; then
        needs_certs=true
        echo
        show_arrow_menu "🔐 Метод получения сертификатов" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return

        case $cert_choice in
            0) CERT_METHOD=2 ;;
            1) CERT_METHOD=1 ;;
            2|3) return ;;
        esac

        reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        [[ $? -eq 2 ]] && return
        echo

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi

    else
        CERT_METHOD=$(detect_cert_method "$SELFSTEAL_DOMAIN")
        echo
        print_cert_exists "$SELFSTEAL_DOMAIN"
    fi

    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    if [ "$needs_certs" = true ]; then
        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null
            show_continue_prompt || true
            return
        fi
    fi

    local NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # Проверяем сертификаты перед запуском Docker
    local cert_path="/etc/letsencrypt/live/$NODE_CERT_DOMAIN"
    if [ ! -f "$cert_path/fullchain.pem" ] || [ ! -f "$cert_path/privkey.pem" ]; then
        # Пробуем найти с суффиксом (-0001, -0002 и т.д.)
        local _alt_path
        _alt_path=$(ls -d /etc/letsencrypt/live/${NODE_CERT_DOMAIN}-* 2>/dev/null | head -1)
        if [ -n "$_alt_path" ] && [ -f "$_alt_path/fullchain.pem" ] && [ -f "$_alt_path/privkey.pem" ]; then
            cert_path="$_alt_path"
            NODE_CERT_DOMAIN=$(basename "$_alt_path")
        else
            print_error "Сертификаты не найдены в $cert_path"
            echo -e "${DARKGRAY}Содержимое /etc/letsencrypt/live/:${NC}"
            ls -la /etc/letsencrypt/live/ 2>/dev/null || echo "  (директория не существует)"
            [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null
            show_continue_prompt || true
            return
        fi
    fi

    # Копируем сертификат ноды в /opt/nginx/ssl/
    nginx_copy_cert "$NODE_CERT_DOMAIN" 2>/dev/null || true

    # Создаём директорию для selfsteal до запуска Docker (том монтируется в nginx)
    mkdir -p /var/www/html

    local NODE_LISTEN_PORT=2222
    if ! prompt_remnanode_listen_port NODE_LISTEN_PORT 2222; then
        [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null
        return 1
    fi

    local NODE_INBOUND_PORT=8443
    if ! prompt_host_inbound_port NODE_INBOUND_PORT 8443; then
        [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null
        return 1
    fi

    # Docker-compose для ноды
    (
        ensure_nginx
        cat > "${NODE_INSTALL_DIR}/docker-compose.yml" <<EOL
services:
  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    network_mode: host
    environment:
      - NODE_PORT=${NODE_LISTEN_PORT}
      - SECRET_KEY=$(echo -e "$CERTIFICATE")
    volumes:
      - /dev/shm:/dev/shm:rw
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 ${NODE_LISTEN_PORT}']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 15s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL
        generate_nginx_conf_node "$SELFSTEAL_DOMAIN" "$NODE_CERT_DOMAIN"
    ) &
    show_spinner "Подготовка файлов" || true

    (
        ufw allow from "$PANEL_IP" to any port "$NODE_LISTEN_PORT" >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1
        ufw allow "${NODE_INBOUND_PORT}/tcp" >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    ) &
    show_spinner "Настройка файрвола" || true

    randomhtml
    echo

    # ─── Согласование с MTProto: если MT Proto установлен, его nginx /connect блок
    # мог занимать 443 напрямую. Перезапускаем nginx с новым конфигом (где /connect
    # переключён на unix-сокет), чтобы освободить 443 до старта xray на ноде.
    # generate_nginx_conf_node уже записал новый nginx.conf выше (с unix-сокетом),
    # плюс nginx_restore_server_blocks адаптировал MT_CONNECT блоки под сокет.
    (
        _mt_ensure_stream_mode >/dev/null 2>&1 || true
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'remnawave-nginx'; then
            cd "${DIR_NGINX}" && docker compose up -d --force-recreate >/dev/null 2>&1 || true
        fi
    ) &
    show_spinner "Проверка совместимости MTProto" || true

    # Если MTProto stream-блок есть в nginx.conf — запускаем nginx ПЕРВЫМ,
    # чтобы он занял 443 через stream, а Xray использовал только 8443
    local _mt_stream_present=false
    if grep -q "# BEGIN_MTPROTO_STREAM" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        _mt_stream_present=true
        (cd "${DIR_NGINX}" && docker compose up -d --force-recreate >/dev/null 2>&1) &
        show_spinner "Запуск nginx" || true
        sleep 1
    fi

    (
        cd "${NODE_INSTALL_DIR}"
        docker compose up -d >/dev/null 2>&1
    ) &
    if ! show_spinner "Запуск контейнеров"; then
        print_error "Не удалось запустить контейнеры"
        show_continue_prompt || true
        return
    fi

    if ! $_mt_stream_present; then
        (cd "${DIR_NGINX}" && docker compose up -d --force-recreate >/dev/null 2>&1) &
        show_spinner "Запуск nginx" || true
    fi

    show_spinner_timer 5 "Ожидание запуска ноды" "Запуск ноды"
    tput cnorm 2>/dev/null || true

    # Проверка здоровья: nginx должен создать unix-сокет
    local health_ok=true
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
        health_ok=false
    elif [ ! -S /dev/shm/nginx.sock ]; then
        health_ok=false
    fi

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnanode$'; then
        health_ok=false
    fi

    # Удаляем trap при успешном завершении
    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

    if [ "$health_ok" = true ]; then
        echo
        print_success "Нода успешно подключена"
    else
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${YELLOW}   ⚠️  НОДА УСТАНОВЛЕНА С ПРЕДУПРЕЖДЕНИЯМИ${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}Диагностика:${NC}"
        echo -e "${WHITE}  docker logs remnawave-nginx${NC}"
        echo -e "${WHITE}  docker logs remnanode${NC}"
        echo -e "${WHITE}  ls -la /dev/shm/nginx.sock${NC}"
        echo -e "${WHITE}  cd ${NODE_INSTALL_DIR} && docker compose restart${NC}"
    fi
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

# ─── Установка ноды на сервер с уже установленной страницей подписки ───
installation_node_with_existing_subpage() {
    local SUBPAGE_DIR="${DIR_SUB%/}"
    local NODE_INSTALL_DIR="/opt/remnanode"

    cd /opt 2>/dev/null || true

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "$(center "📦 Установка ноды" "$BLUE")"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    # Извлекаем данные из существующей установки subpage
    local PANEL_URL API_TOKEN SUB_DOMAIN SUB_CERT_DOMAIN

    PANEL_URL=$(grep -oP 'REMNAWAVE_PANEL_URL=\K\S+' "${SUBPAGE_DIR}/docker-compose.yml" 2>/dev/null | head -1)
    API_TOKEN=$(grep -oP 'REMNAWAVE_API_TOKEN=\K\S+' "${SUBPAGE_DIR}/docker-compose.yml" 2>/dev/null | head -1)
    SUB_DOMAIN=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -v '_' | head -1)
    SUB_CERT_DOMAIN=$(grep -oP '/ssl/\K[^/]+' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
    [ -z "$SUB_CERT_DOMAIN" ] && SUB_CERT_DOMAIN="$SUB_DOMAIN"

    if [ -z "$PANEL_URL" ] || [ -z "$API_TOKEN" ] || [ -z "$SUB_DOMAIN" ]; then
        print_error "Не удалось извлечь данные из существующей установки страницы подписки."
        print_error "Проверьте ${SUBPAGE_DIR}/docker-compose.yml и ${DIR_NGINX}nginx.conf"
        show_continue_prompt || return 1
        return
    fi

    # Запрашиваем параметры ноды
    local SELFSTEAL_DOMAIN PANEL_IP
    while true; do
        echo
        prompt_domain_with_retry "Домен ноды ${DARKGRAY}(например node.example.com)${DARKGRAY}:" SELFSTEAL_DOMAIN true || return
        if prompt_ip_with_retry "IP адрес сервера панели:" PANEL_IP; then
            break
        else
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "$(center "📦 Установка ноды" "$BLUE")"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
        fi
    done

    echo
    echo -e "${BLUE}➜${NC}  ${YELLOW}Вставьте сертификат (Секретный ключ) из панели и нажмите Enter дважды:${NC}"
    local CERTIFICATE=""
    while IFS= read -r line; do
        if [ -z "$line" ] && [ -n "$CERTIFICATE" ]; then
            break
        fi
        CERTIFICATE="$CERTIFICATE$line\n"
    done

    # Сертификат для selfsteal домена
    declare -A domains_to_check
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    local needs_certs=false
    local CERT_METHOD LETSENCRYPT_EMAIL=""

    if check_if_certificates_needed domains_to_check; then
        needs_certs=true
        echo
        show_arrow_menu "🔐 Метод получения сертификатов" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return
        case $cert_choice in
            0) CERT_METHOD=2 ;;
            1) CERT_METHOD=1 ;;
            2|3) return ;;
        esac
        reading_inline "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        [[ $? -eq 2 ]] && return
        echo
        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi
    else
        CERT_METHOD=$(detect_cert_method "$SELFSTEAL_DOMAIN")
        echo
        print_cert_exists "$SELFSTEAL_DOMAIN"
    fi

    if [ ! -f "${DIR_SCRIPT}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    if [ "$needs_certs" = true ]; then
        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            show_continue_prompt || true
            return
        fi
    fi

    local NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # Проверяем сертификаты
    local cert_path="/etc/letsencrypt/live/$NODE_CERT_DOMAIN"
    if [ ! -f "$cert_path/fullchain.pem" ] || [ ! -f "$cert_path/privkey.pem" ]; then
        # Пробуем найти с суффиксом (-0001, -0002 и т.д.)
        local _alt_path
        _alt_path=$(ls -d /etc/letsencrypt/live/${NODE_CERT_DOMAIN}-* 2>/dev/null | head -1)
        if [ -n "$_alt_path" ] && [ -f "$_alt_path/fullchain.pem" ] && [ -f "$_alt_path/privkey.pem" ]; then
            cert_path="$_alt_path"
            NODE_CERT_DOMAIN=$(basename "$_alt_path")
        else
            print_error "Сертификаты не найдены в $cert_path"
            show_continue_prompt || true
            return
        fi
    fi

    # Копируем сертификат ноды в /opt/nginx/ssl/
    nginx_copy_cert "$NODE_CERT_DOMAIN" 2>/dev/null || true

    mkdir -p /var/www/html
    mkdir -p "${NODE_INSTALL_DIR}"

    local NODE_LISTEN_PORT=2222
    if ! prompt_remnanode_listen_port NODE_LISTEN_PORT 2222; then
        return 1
    fi

    # Порт REALITY на хосте — до остановки subpage/nginx, иначе освобождённый 443/8443
    # даст ложное «порт свободен» (MTProto, прокси и т.д.).
    local NODE_INBOUND_PORT=8443
    if ! prompt_host_inbound_port NODE_INBOUND_PORT 8443; then
        return 1
    fi

    # Останавливаем существующую страницу подписки
    (cd "${SUBPAGE_DIR}" && docker compose down --remove-orphans >/dev/null 2>&1) &
    show_spinner "Остановка страницы подписки" || true

    # Генерируем конфиги для ноды + страницы подписки
    (
        generate_docker_compose_node_with_subpage \
            "$NODE_CERT_DOMAIN" "$SUB_CERT_DOMAIN" \
            "$PANEL_URL" "$API_TOKEN" "$CERTIFICATE" \
            "$NODE_INSTALL_DIR" "$NODE_LISTEN_PORT"
        generate_nginx_conf_node_with_subpage \
            "$SELFSTEAL_DOMAIN" "$NODE_CERT_DOMAIN" \
            "$SUB_DOMAIN" "$SUB_CERT_DOMAIN" \
            "$NODE_INSTALL_DIR"
    ) &
    show_spinner "Подготовка файлов" || true

    # Настройка файрвола
    (
        ufw allow from "$PANEL_IP" to any port "$NODE_LISTEN_PORT" >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1
        ufw allow "${NODE_INBOUND_PORT}/tcp" >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    ) &
    show_spinner "Настройка файрвола" || true

    randomhtml
    echo

    # Согласование с MTProto: перезапустим nginx с новым конфигом, чтобы /connect-блок
    # переключился на unix-сокет и 443 освободился для xray.
    (
        _mt_ensure_stream_mode >/dev/null 2>&1 || true
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'remnawave-nginx'; then
            cd "${DIR_NGINX}" && docker compose up -d --force-recreate >/dev/null 2>&1 || true
        fi
    ) &
    show_spinner "Проверка совместимости MTProto" || true

    # Запуск контейнеров
    (cd /opt/subscribe-page && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск страницы подписки" || true

    # Если MTProto stream-блок есть — запускаем nginx первым
    local _mt_stream_present2=false
    if grep -q "# BEGIN_MTPROTO_STREAM" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        _mt_stream_present2=true
        (cd "${DIR_NGINX}" && docker compose up -d --force-recreate >/dev/null 2>&1) &
        show_spinner "Запуск nginx" || true
        sleep 1
    fi

    (cd "${NODE_INSTALL_DIR}" && docker compose up -d >/dev/null 2>&1) &
    if ! show_spinner "Подключение ноды"; then
        print_error "Не удалось запустить контейнеры"
        show_continue_prompt || true
        return
    fi
    echo

    if ! $_mt_stream_present2; then
        (cd "${DIR_NGINX}" && docker compose up -d --force-recreate >/dev/null 2>&1) &
        show_spinner_timer 15 "Ожидание запуска сервисов" "Запуск сервисов"
    else
        show_spinner_timer 15 "Ожидание запуска сервисов" "Запуск сервисов"
    fi
    tput cnorm 2>/dev/null || true

    # Проверка здоровья
    local health_ok=true
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
        health_ok=false
    elif [ ! -S /dev/shm/nginx.sock ]; then
        health_ok=false
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnanode$'; then
        health_ok=false
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "$(center "🎉 Нода и страница подписки установлены" "$GREEN")"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    if [ "$health_ok" = true ]; then
        echo -e "$(center "Нода успешно подключена!")"
    else
        echo -e "$(center "⚠️ Нода установлена, но не подключилась к панели" "$YELLOW")"
    fi
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}
