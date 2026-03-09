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
        echo -e "${DARKGRAY}⚠️  На этом сервере уже установлена нода.${NC}"
        echo -e "   ${DARKGRAY}Что бы переустановить ноду нажмите ${BLUE}Enter${DARKGRAY}.${NC}"
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
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${RED}   ⚠️  Подтверждение переустановки${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${RED}⚠️  Все данные текущей ноды будут удалены!${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        if ! confirm_action; then
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
        if ! [ -f "/opt/remnawave/nginx.conf" ]; then
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
    if [ -f "/opt/remnawave/docker-compose.yml" ] && [ -f "/opt/remnawave/nginx.conf" ] && \
       grep -q "remnawave:" /opt/remnawave/docker-compose.yml 2>/dev/null && \
       ! grep -q "remnanode" /opt/remnawave/docker-compose.yml 2>/dev/null; then
        is_local_panel=true
    fi

    if [ "$is_local_panel" = true ]; then
        installation_node_local
    else
        installation_node_remote
    fi
}

# ─── Установка ноды на сервер с панелью (автодетект) ───
installation_node_local() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌐 ДОБАВЛЕНИЕ НОДЫ НА СЕРВЕР ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    # Проверяем пакеты
    if [ ! -f "${DIR_REMNAWAVE}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"

    # ─── Сохраняем бэкап конфигов для восстановления при отмене ───
    local backup_compose="" backup_nginx=""
    backup_compose=$(cat /opt/remnawave/docker-compose.yml 2>/dev/null)
    backup_nginx=$(cat /opt/remnawave/nginx.conf 2>/dev/null)

    # Функция восстановления при отмене (до изменения конфигов)
    _restore_panel_config() {
        if [ -n "$backup_compose" ]; then
            echo "$backup_compose" > /opt/remnawave/docker-compose.yml
        fi
        if [ -n "$backup_nginx" ]; then
            echo "$backup_nginx" > /opt/remnawave/nginx.conf
        fi
        # Перезапускаем панель с оригинальными конфигами
        (
            cd /opt/remnawave
            docker compose down >/dev/null 2>&1
            docker compose up -d >/dev/null 2>&1
        ) &
        show_spinner "Восстановление конфигурации панели"
        show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
    }

    # ─── Автоопределение конфигурации из существующей панели ───
    echo
    print_action "Определение конфигурации панели..."

    # Извлекаем домены из nginx.conf
    local panel_domain sub_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | sed -n '1p')
    sub_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | sed -n '2p')

    if [ -z "$panel_domain" ] || [ -z "$sub_domain" ]; then
        print_error "Не удалось определить домены из nginx.conf"
        echo
        show_continue_prompt || return 1
        return
    fi

    # Извлекаем cookie
    local COOKIE_NAME COOKIE_VALUE
    if ! get_cookie_from_nginx; then
        print_error "Не удалось извлечь cookie из nginx.conf"
        echo
        show_continue_prompt || return 1
        return
    fi

    # Извлекаем API токен
    local existing_api_token
    existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)

    # Определяем домены сертификатов
    local panel_cert_domain sub_cert_domain
    panel_cert_domain=$(grep -A5 "server_name ${panel_domain};" /opt/remnawave/nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
    sub_cert_domain=$(grep -A5 "server_name ${sub_domain};" /opt/remnawave/nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
    if [ -z "$panel_cert_domain" ]; then
        panel_cert_domain=$(grep -A5 "server_name ${panel_domain};" /opt/remnawave/nginx.conf | grep -oP 'live/\K[^/]+' | head -1)
    fi
    if [ -z "$sub_cert_domain" ]; then
        sub_cert_domain=$(grep -A5 "server_name ${sub_domain};" /opt/remnawave/nginx.conf | grep -oP 'live/\K[^/]+' | head -1)
    fi
    [ -z "$panel_cert_domain" ] && panel_cert_domain="$panel_domain"
    [ -z "$sub_cert_domain" ] && sub_cert_domain="$sub_domain"

    # Автоопределяем метод сертификации
    local AUTO_CERT_METHOD
    AUTO_CERT_METHOD=$(detect_cert_method "$panel_domain")

    print_success "Панель: $panel_domain"
    print_success "Подписка: $sub_domain"
    print_success "Метод сертификатов: $([ "$AUTO_CERT_METHOD" = "1" ] && echo "Cloudflare DNS-01" || echo "ACME HTTP-01")"
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    # ─── Запрашиваем selfsteal домен ───

    local SELFSTEAL_DOMAIN
    prompt_domain_with_retry "Домен selfsteal ноды (например node.example.com):" SELFSTEAL_DOMAIN true || return

    # ─── Запрашиваем имя ноды ───
    local entity_name
    while true; do
        reading_inline "Введите имя для ноды (например, Germany):" entity_name
        local _rc_en=$?
        if [[ $_rc_en -eq 2 ]]; then
            echo -e "${YELLOW}Установка отменена${NC}"
            return
        fi
        if [[ -z "$entity_name" ]]; then continue; fi
        if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
            if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                break
            else
                print_error "Имя должно содержать от 3 до 20 символов"
            fi
        else
            print_error "Имя должно содержать только английские буквы, цифры и дефис"
        fi
    done

    # ─── Авторизация в панели (до изменения конфигов) ───
    local _gpt_rc
    get_panel_token; _gpt_rc=$?
    if [[ $_gpt_rc -eq 2 ]]; then return; fi
    if [[ $_gpt_rc -ne 0 ]]; then
        echo -e "${YELLOW}Установка отменена${NC}"
        echo
        show_continue_prompt || return 1
        return
    fi
    local token
    token=$(cat "${DIR_REMNAWAVE}/token")

    # ─── Проверка уникальности домена/имени в API (до изменения конфигов) ───
    if ! check_node_domain "$domain_url" "$token" "$SELFSTEAL_DOMAIN"; then
        print_error "Домен $SELFSTEAL_DOMAIN уже используется в панели"
        echo
        show_continue_prompt || return 1
        return
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
        echo

        if [ "$CERT_METHOD" = "1" ]; then
            if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                show_arrow_menu "🔐  Метод получения сертификата" \
                    "☁️   Cloudflare DNS-01 (wildcard)" \
                    "🌐  ACME HTTP-01 (Let's Encrypt)" \
                    "──────────────────────────────────────" \
                    "❌  Назад"
                local cert_choice=$?
                case $cert_choice in
                    0) CERT_METHOD=1 ;;
                    1) CERT_METHOD=2 ;;
                    *) return ;;
                esac
                setup_cloudflare_credentials || return
            fi
        fi

        LETSENCRYPT_EMAIL=$(grep -r "email" /etc/letsencrypt/accounts/ 2>/dev/null | grep -oP '"[^@]+@[^"]+' | head -1 | tr -d '"')
        if [ -z "$LETSENCRYPT_EMAIL" ]; then
            reading "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        else
            echo -e "${GREEN}✅${NC} Email для сертификата: $LETSENCRYPT_EMAIL"
        fi
        echo

        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
            echo
            return
        fi
    else
        echo -e "${BLUE}──────────────────────────────────────${NC}"
        print_success "Сертификат для $SELFSTEAL_DOMAIN уже существует"
        echo
    fi

    local NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" = "1" ]; then
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # ─── Остановка сервисов и обновление конфигов ───
    echo
    print_action "Обновление конфигурации..."

    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка сервисов" || true

    mkdir -p /var/www/html

    # ─── Перегенерация docker-compose.yml (full: с нодой) ───
    (generate_docker_compose_full "$panel_cert_domain" "$sub_cert_domain" "$NODE_CERT_DOMAIN") &
    show_spinner "Обновление docker-compose.yml" || true

    # Определяем gateway и subnet сети (после генерации docker-compose.yml)
    local network_info network_gateway network_subnet
    network_info=$(get_remnawave_network_info)
    network_gateway=$(echo "$network_info" | awk '{print $1}')
    network_subnet=$(echo "$network_info" | awk '{print $2}')

    # Восстанавливаем API токен
    if [ -n "$existing_api_token" ]; then
        sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=$existing_api_token|" /opt/remnawave/.env
    fi

    # ─── Перегенерация nginx.conf (full: с selfsteal) ───
    (generate_nginx_conf_full "$panel_domain" "$sub_domain" "$SELFSTEAL_DOMAIN" \
        "$panel_cert_domain" "$sub_cert_domain" "$NODE_CERT_DOMAIN" \
        "$COOKIE_NAME" "$COOKIE_VALUE") &
    show_spinner "Обновление nginx.conf" || true

    # ─── UFW для ноды ───
    (
        ufw allow from "$network_subnet" to any port 2222 proto tcp >/dev/null 2>&1
    ) &
    show_spinner "Настройка файрвола" || true

    # ─── Запуск сервисов ───
    echo
    print_action "Запуск сервисов..."

    (
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1
    ) &
    if ! show_spinner "Запуск Docker контейнеров"; then
        print_error "Не удалось запустить контейнеры"
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi

    show_spinner_timer 20 "Ожидание запуска Remnawave" "Запуск Remnawave"

    if ! show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности API" 120; then
        print_error "API не отвечает. Восстановление конфигурации..."
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi

    # ─── Публичный ключ → SECRET_KEY ───
    print_action "Получение публичного ключа панели..."
    get_public_key "$domain_url" "$token" "$target_dir"

    # Проверяем, что SECRET_KEY реально обновлён (не остался плейсхолдером)
    if grep -q 'PUBLIC KEY FROM REMNAWAVE-PANEL' "$target_dir/docker-compose.yml" 2>/dev/null; then
        print_error "Не удалось установить публичный ключ. Восстановление конфигурации..."
        _restore_panel_config
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
        print_error "Не удалось сгенерировать ключи. Восстановление конфигурации..."
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi
    print_success "Ключи сгенерированы"

    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result config_profile_uuid inbound_uuid
    if ! config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name"); then
        print_error "Не удалось создать конфигурационный профиль. Восстановление конфигурации..."
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi
    read config_profile_uuid inbound_uuid <<< "$config_result"
    print_success "Конфигурационный профиль: $entity_name"

    print_action "Создание ноды ($entity_name)..."
    if create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$SELFSTEAL_DOMAIN" "$entity_name"; then
        print_success "Нода создана"
    else
        print_error "Не удалось создать ноду. Восстановление конфигурации..."
        _restore_panel_config
        echo
        show_continue_prompt || return 1
        return
    fi

    print_action "Создание хоста ($SELFSTEAL_DOMAIN)..."
    create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$entity_name" "$SELFSTEAL_DOMAIN"
    print_success "Хост зарегистрирован"

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

    # ─── Финальный перезапуск (с обновлённым SECRET_KEY) ───
    print_action "Перезапуск сервисов..."
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск контейнеров" || true

    randomhtml

    # Ожидаем готовность панели после перезапуска
    show_spinner_timer 15 "Ожидание запуска сервисов" "Запуск сервисов"

    if ! show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности панели" 120; then
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
            # Перезапускаем subscription-page с новым токеном
            (cd /opt/remnawave && docker compose up -d remnawave-subscription-page >/dev/null 2>&1) &
            show_spinner "Перезапуск subscription-page"
        else
            print_error "Не удалось создать API токен"
            echo -e "${YELLOW}⚠️  Subscription-page может не работать. Создайте токен вручную:${NC}"
            echo -e "   ${WHITE}Remnawave Dashboard → Settings → API Tokens${NC}"
        fi
    fi

    # ─── Верификация: ждём пока remnanode запустит xray на порту 443 ───
    print_action "Ожидание подключения ноды (xray → порт 443)..."
    local verify_ok=false
    local verify_elapsed=0
    local verify_timeout=60
    while [ $verify_elapsed -lt $verify_timeout ]; do
        if ss -tuln 2>/dev/null | grep -q ':443 '; then
            verify_ok=true
            break
        fi
        sleep 2
        ((verify_elapsed+=2))
    done

    if [ "$verify_ok" = true ]; then
        print_success "Порт 443 активен — xray (remnanode) работает"
    else
        echo -e "${YELLOW}⚠️  Порт 443 не активен через ${verify_timeout} сек. Диагностика:${NC}"
        echo

        # Проверяем контейнер remnanode
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnanode$'; then
            echo -e "${GREEN}  ✓${NC} Контейнер remnanode запущен"
            echo -e "${DARKGRAY}  Логи remnanode (последние 10 строк):${NC}"
            docker logs --tail 10 remnanode 2>&1 | while IFS= read -r line; do
                echo -e "${DARKGRAY}    $line${NC}"
            done
        else
            echo -e "${RED}  ✗${NC} Контейнер remnanode НЕ запущен"
        fi

        echo
        echo -e "${YELLOW}  Возможные причины:${NC}"
        echo -e "${WHITE}  1. Нода ещё подключается к панели (подождите 1-2 мин)${NC}"
        echo -e "${WHITE}  2. Панель не смогла передать конфиг ноде${NC}"
        echo -e "${WHITE}  3. Проверьте: ${GREEN}docker logs remnanode${NC}"
        echo -e "${WHITE}  4. Проверьте: ${GREEN}docker logs remnawave${NC}"
        echo
        echo -e "${YELLOW}  Конфигурация НЕ откачена — нода создана в панели.${NC}"
        echo -e "${YELLOW}  Попробуйте: ${GREEN}cd /opt/remnawave && docker compose restart${NC}"
        echo
    fi

    # Автоматически включаем доступ по 8443 (нода занимает 443)
    local local_cookie_name="$COOKIE_NAME"
    local local_cookie_value="$COOKIE_VALUE"
    if [ -z "$local_cookie_name" ] || [ -z "$local_cookie_value" ]; then
        get_cookie_from_nginx
        local_cookie_name="$COOKIE_NAME"
        local_cookie_value="$COOKIE_VALUE"
    fi
    auto_enable_panel_access_8443 "$panel_domain" "$local_cookie_name" "$local_cookie_value"

    # ─── Итог ───
    clear
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${GREEN}🎉 Нода добавлена на сервер панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Панель:${NC}       https://$panel_domain:8443"
    echo -e "${WHITE}Подписка:${NC}     https://$sub_domain"
    echo -e "${WHITE}SelfSteal:${NC}    https://$SELFSTEAL_DOMAIN"
    echo
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    echo
    echo -e "${GREEN}✅ Нода зарегистрирована в панели${NC}"
    echo -e "${GREEN}✅ Docker Compose обновлён (nginx + remnanode)${NC}"
    echo -e "${GREEN}✅ Nginx перенастроен (unix socket + proxy_protocol)${NC}"
    echo -e "${GREEN}✅ Доступ к панели по порту 8443 автоматически включён${NC}"
    if [ "$verify_ok" = true ]; then
        echo -e "${GREEN}✅ Порт 443 активен — xray (remnanode) работает${NC}"
    else
        echo -e "${YELLOW}⚠️  Порт 443 пока не активен — проверьте логи ноды${NC}"
    fi
    echo
    echo -e "${DARKGRAY}Архитектура: Xray (порт 443) → unix socket → Nginx → панель${NC}"
    echo -e "${DARKGRAY}Панель доступна по порту 8443 (XRAY занимает 443)${NC}"
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
    echo -e "${GREEN}   📦 УСТАНОВКА ТОЛЬКО НОДЫ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    mkdir -p "${NODE_INSTALL_DIR}" && cd "${NODE_INSTALL_DIR}"

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap 'echo; echo -e "${RED}Установка прервана пользователем${NC}"; echo; rm -rf "'"${NODE_INSTALL_DIR}"'" 2>/dev/null; exit 1' INT TERM
    fi

    prompt_domain_with_retry "Домен selfsteal/ноды (например node.example.com):" SELFSTEAL_DOMAIN || { [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null; return; }

    local PANEL_IP
    prompt_ip_with_retry "IP адрес сервера панели:" PANEL_IP || { [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null; return; }

    echo
    echo -e "${BLUE}➜${NC}  ${YELLOW}Вставьте сертификат (SECRET_KEY) из панели и нажмите Enter дважды:${NC}"
    local CERTIFICATE=""
    while IFS= read -r line; do
        if [ -z "$line" ] && [ -n "$CERTIFICATE" ]; then
            break
        fi
        CERTIFICATE="$CERTIFICATE$line\n"
    done

    declare -A domains_to_check
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then
        echo
        show_arrow_menu "🔐  Метод получения сертификатов" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return

        case $cert_choice in
            0) CERT_METHOD=1 ;;
            1) CERT_METHOD=2 ;;
            2) : ;;
            3) return ;;
        esac

        reading "Email для Let's Encrypt:" LETSENCRYPT_EMAIL

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi

        if ! handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"; then
            echo
            [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" 2>/dev/null
            read -s -n 1 -p "$(echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Назад${NC}")"
            echo
            return
        fi
    else
        CERT_METHOD=$(detect_cert_method "$SELFSTEAL_DOMAIN")
        echo
        print_success "Сертификат для $SELFSTEAL_DOMAIN уже существует"
        echo
    fi

    local NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # Docker-compose для ноды
    (
        cat > "${NODE_INSTALL_DIR}/docker-compose.yml" <<EOL
services:
  remnawave-nginx:
    image: nginx:1.28
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt/live/$NODE_CERT_DOMAIN/fullchain.pem:/etc/nginx/ssl/$NODE_CERT_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$NODE_CERT_DOMAIN/privkey.pem:/etc/nginx/ssl/$NODE_CERT_DOMAIN/privkey.pem:ro
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: sh -c 'rm -f /dev/shm/nginx.sock && exec nginx -g "daemon off;"'
    network_mode: host
    depends_on:
      - remnanode
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

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
      - NODE_PORT=2222
      - SECRET_KEY=$(echo -e "$CERTIFICATE")
    volumes:
      - /dev/shm:/dev/shm:rw
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL
    ) &
    show_spinner "Создание docker-compose.yml" || true

    (generate_nginx_conf_node "$SELFSTEAL_DOMAIN" "$NODE_CERT_DOMAIN" "$NODE_INSTALL_DIR") &
    show_spinner "Создание nginx.conf" || true

    (
        ufw allow from "$PANEL_IP" to any port 2222 >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    ) &
    show_spinner "Настройка файрвола" || true

    (
        cd "${NODE_INSTALL_DIR}"
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск Docker контейнеров" || true

    show_spinner_timer 5 "Ожидание запуска ноды" "Запуск ноды"

    randomhtml

    # Удаляем trap при успешном завершении
    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🎉 НОДА УСТАНОВЛЕНА!${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Директория:${NC}   ${NODE_INSTALL_DIR}"
    echo -e "${WHITE}SelfSteal:${NC}    https://$SELFSTEAL_DOMAIN"
    echo -e "${WHITE}IP панели:${NC}    $PANEL_IP"
    echo
    echo -e "${YELLOW}Проверьте подключение ноды в панели Remnawave${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}
