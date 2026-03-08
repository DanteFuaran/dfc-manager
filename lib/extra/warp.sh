# ═══════════════════════════════════════════════════
# WARP NATIVE
# ═══════════════════════════════════════════════════
manage_warp() {
    local has_panel=false
    local has_node=false
    is_panel_installed && has_panel=true
    is_node_installed  && has_node=true

    local warp_installed=false
    ip link show warp 2>/dev/null | grep -q "warp" && warp_installed=true

    local -a items=()
    local -a actions=()

    # Ничего не установлено
    if [ "$has_panel" = false ] && [ "$has_node" = false ]; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   🌐 WARP${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}На сервере нет приложений требующих WARP${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 0
    fi

    # Только панель (без ноды) — только пункты конфигурации
    if [ "$has_panel" = true ] && [ "$has_node" = false ]; then
        items+=("➕  Добавить WARP в конфигурацию ноды");  actions+=("add_config")
        items+=("➖  Удалить WARP из конфигурации ноды");  actions+=("del_config")
        items+=("──────────────────────────────────────");  actions+=("sep")
        items+=("❌  Назад");                               actions+=("back")

    # Только нода (без панели) — только установка/удаление WARP
    elif [ "$has_node" = true ] && [ "$has_panel" = false ]; then
        if [ "$warp_installed" = false ]; then
            items+=("📥  Установить WARP");  actions+=("install")
        else
            items+=("🗑️   Удалить WARP");    actions+=("uninstall")
        fi
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("❌  Назад");                              actions+=("back")

    # Оба компонента — все пункты
    else
        if [ "$warp_installed" = false ]; then
            items+=("📥  Установить WARP");  actions+=("install")
        else
            items+=("🗑️   Удалить WARP");    actions+=("uninstall")
        fi
        items+=("──────────────────────────────────────");  actions+=("sep")
        items+=("➕  Добавить WARP в конфигурацию ноды");  actions+=("add_config")
        items+=("➖  Удалить WARP из конфигурации ноды");  actions+=("del_config")
        items+=("──────────────────────────────────────");  actions+=("sep")
        items+=("❌  Назад");                               actions+=("back")
    fi

    show_arrow_menu "🌐  WARP" "${items[@]}"
    local choice=$?
    local action="${actions[$choice]:-back}"

    case "$action" in
        install)   install_warp_native ;;
        uninstall) uninstall_warp_native ;;
        add_config) add_warp_to_config ;;
        del_config) remove_warp_from_config ;;
        *) return 0 ;;
    esac
}


install_warp_native() {
    # Проверяем, есть ли нода на сервере
    local node_found=false
    if grep -q "remnanode:" /opt/remnawave/docker-compose.yml 2>/dev/null; then
        node_found=true
    fi
    if grep -q "remnanode:" /opt/remnanode/docker-compose.yml 2>/dev/null; then
        node_found=true
    fi
    if [ "$node_found" = false ]; then
        echo -e "${YELLOW}⚠️  Нода не найдена на этом сервере${NC}"
        echo -e "${DARKGRAY}WARP работает только с установленной нодой.${NC}"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}           📥 УСТАНОВКА WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Проверяем, установлен ли уже WARP
    if ip link show warp 2>/dev/null | grep -q "warp"; then
        print_success "WARP уже установлен"
        echo
        show_continue_prompt || return 1
        return 0
    fi

    # Спрашиваем WARP+ ключ
    echo -e "${YELLOW}Если у вас есть ключ для WARP, вы можете ввести его ниже.${NC}"
    echo -e "${DARKGRAY}Оставьте пустым для бесплатной версии.${NC}"
    echo
    reading_inline "WARP+ ключ (Enter для пропуска):" warp_key
    local _rc_wk=$?
    echo
    if [[ $_rc_wk -eq 2 ]]; then return 0; fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}           📥 УСТАНОВКА WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local _warp_log
    _warp_log=$(mktemp /tmp/warp_install.XXXXXX)

    (
        # 1. Установка WireGuard
        echo "=== apt-get update ==="
        apt-get update -qq 2>&1
        echo "=== apt-get install wireguard ==="
        apt-get install -y wireguard 2>&1

        # 2. Определяем архитектуру и скачиваем wgcf
        local arch
        case $(uname -m) in
            x86_64)          arch="amd64" ;;
            aarch64|arm64)   arch="arm64" ;;
            armv7l)          arch="armv7" ;;
            *)               arch="amd64" ;;
        esac
        local wgcf_version
        wgcf_version=$(curl -sL --max-time 10 "https://api.github.com/repos/ViRb3/wgcf/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
        if [ -z "$wgcf_version" ]; then
            echo "ERROR: не удалось получить версию wgcf с GitHub API"
            exit 1
        fi
        echo "=== wgcf version: $wgcf_version ==="
        local wgcf_bin="wgcf_${wgcf_version#v}_linux_${arch}"
        wget -q "https://github.com/ViRb3/wgcf/releases/download/${wgcf_version}/${wgcf_bin}" -O /tmp/wgcf 2>&1
        chmod +x /tmp/wgcf
        mv /tmp/wgcf /usr/local/bin/wgcf

        # 3. Регистрация
        cd /tmp
        rm -f wgcf-account.toml wgcf-profile.conf 2>/dev/null
        echo "=== wgcf register ==="
        timeout 60 bash -c 'yes | wgcf register' 2>&1 || \
            { echo | wgcf register 2>&1; sleep 2; }

        # 4. Применяем WARP+ ключ если задан
        if [ -n "${warp_key:-}" ]; then
            echo "=== wgcf update key ==="
            wgcf update --license-key "${warp_key}" 2>&1 || true
        fi

        # 5. Генерация конфигурации
        echo "=== wgcf generate ==="
        wgcf generate 2>&1

        # 6. Редактирование конфигурации
        local conf="/tmp/wgcf-profile.conf"
        if [ ! -f "$conf" ]; then
            echo "ERROR: wgcf-profile.conf не создан — регистрация или генерация не удалась"
            exit 1
        fi

        sed -i '/^DNS =/d' "$conf" 2>&1
        grep -q 'Table = off' "$conf"          || sed -i '/^MTU =/aTable = off' "$conf" 2>&1
        grep -q 'PersistentKeepalive' "$conf" || sed -i '/^Endpoint =/aPersistentKeepalive = 25' "$conf" 2>&1

        # 7. IPv6
        local ipv6_ok=false
        sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q ' = 0' && \
        sysctl net.ipv6.conf.default.disable_ipv6 2>/dev/null | grep -q ' = 0' && \
        ip -6 addr show scope global 2>/dev/null | grep -qv 'fe80::' && ipv6_ok=true
        if [ "$ipv6_ok" = false ]; then
            sed -i 's/,\s*[0-9a-fA-F:]*\/128//' "$conf" 2>&1
            sed -i '/Address = [0-9a-fA-F:]*\/128/d' "$conf" 2>&1
        fi

        # 8. Перемещаем конфигурацию
        mkdir -p /etc/wireguard
        mv "$conf" /etc/wireguard/warp.conf 2>&1

        # 9. Запускаем и включаем автозапуск
        echo "=== systemctl start wg-quick@warp ==="
        systemctl start wg-quick@warp 2>&1
        systemctl enable wg-quick@warp 2>&1
    ) > "$_warp_log" 2>&1 &
    show_spinner "Установка WARP"
    echo

    # Проверяем результат
    if ip link show warp 2>/dev/null | grep -q "warp"; then
        rm -f "$_warp_log"
        print_success "Настройка WARP"
        print_success "Создание WARP интерфейса"
        print_success "WARP успешно установлен"
        echo

        # Автоматически открываем порт 8443 для WARP-инбаунда
        if command -v ufw >/dev/null 2>&1; then
            ufw allow 8443/tcp >/dev/null 2>&1
            print_success "Порт 8443 открыт (ufw)"
        fi

        echo -e "${YELLOW}⚠️  Добавьте WARP в конфигурацию ноды через соответствующий пункт меню.${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
    else
        journalctl -u wg-quick@warp --no-pager -n 10 >> "$_warp_log" 2>/dev/null

        # Диагностика: определяем причину по ключевым словам в логе
        local _diag="Не удалось установить WARP"
        if grep -q "TLS handshake timeout" "$_warp_log" 2>/dev/null; then
            _diag="Нет доступа к серверам Cloudflare — TLS timeout"
        elif grep -q "connection refused\|connect: connection refused" "$_warp_log" 2>/dev/null; then
            _diag="Соединение отклонено при регистрации WARP"
        elif grep -q "no account detected" "$_warp_log" 2>/dev/null; then
            _diag="Регистрация аккаунта WARP не удалась"
        elif grep -q "ERROR: wgcf-profile.conf" "$_warp_log" 2>/dev/null; then
            _diag="Генерация конфигурации WARP не удалась"
        fi

        # Фильтруем лог: убираем Go стектрейсы, оставляем суть
        local _filtered
        _filtered=$(mktemp /tmp/warp_filtered.XXXXXX)
        grep -v '^\s*|' "$_warp_log" \
            | grep -v 'github\.com/' \
            | grep -v '^\s*Wraps:' \
            | grep -v 'runtime/' \
            | grep -v '^Error types:' \
            | grep -v '^\s*-- stack trace:' \
            | grep -v '\[\.\.\.' \
            | sed '/^$/d' \
            > "$_filtered"

        # Добавляем подсказку в начало лога при известных ошибках
        if grep -q "TLS handshake timeout" "$_warp_log" 2>/dev/null; then
            local _hint_file
            _hint_file=$(mktemp /tmp/warp_hint.XXXXXX)
            echo "💡 Сервер не может подключиться к api.cloudflareclient.com" > "$_hint_file"
            echo "   Проверьте, не заблокирован ли исходящий HTTPS-трафик" >> "$_hint_file"
            echo "   или попробуйте повторить установку позже." >> "$_hint_file"
            echo "" >> "$_hint_file"
            cat "$_filtered" >> "$_hint_file"
            mv "$_hint_file" "$_filtered"
        fi

        show_install_error "$_diag" "$_filtered"
        rm -f "$_warp_log" "$_filtered"
        return $?
    fi
}

uninstall_warp_native() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}          🗑️  УДАЛЕНИЕ WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    # Проверяем, установлен ли WARP
    if ! ip link show warp 2>/dev/null | grep -q "warp"; then
        echo
        print_error "WARP не установлен"
        echo
        echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
        show_continue_prompt || return 1
        return 0
    fi

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 0
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}          🗑️  УДАЛЕНИЕ WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    (
        # Останавливаем интерфейс
        wg-quick down warp >/dev/null 2>&1 || true
        systemctl disable wg-quick@warp >/dev/null 2>&1 || true
        # Удаляем файлы
        rm -f /etc/wireguard/warp.conf 2>/dev/null || true
        rm -f /usr/local/bin/wgcf 2>/dev/null || true
        rm -f /tmp/wgcf-account.toml /tmp/wgcf-profile.conf 2>/dev/null || true
    ) &
    show_spinner "Удаление WARP"
    echo

    # Проверяем результат
    if ! ip link show warp 2>/dev/null | grep -q "warp"; then
        print_success "Удаление WARP"
        print_success "WARP успешно удалён"
    else
        print_error "Не удалось удалить WARP — интерфейс всё ещё активен"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

add_warp_to_config() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ➕ ДОБАВЛЕНИЕ WARP В КОНФИГУРАЦИЮ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Предупреждение — операция должна выполняться на сервере с панелью
    echo -e "${RED}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${YELLOW}Вы уверены, что находитесь на сервере с установленной панелью?${NC}"
    echo -e "${DARKGRAY}Добавление WARP создаст второй инбаунд (порт 8443),${NC}"
    echo -e "${DARKGRAY}хост и маршрутизацию трафика через WARP.${NC}"
    echo
    echo -en "${GREEN}[?]${NC} ${YELLOW}Продолжить? (Enter/Esc):${NC} "
    read -rsn 1 -t 10 key 2>/dev/null || true
    echo

    if [ "$key" = $'\x1b' ]; then
        return 0
    fi

    # Получаем токен
    if ! get_panel_token; then
        return 1
    fi
    local token
    token=$(cat "${DIR_REMNAWAVE}/token")
    local domain_url="127.0.0.1:3000"

    # Получаем список конфигураций
    local config_response
    config_response=$(make_api_request "GET" "${domain_url}/api/config-profiles" "$token")

    if [ -z "$config_response" ] || ! echo "$config_response" | jq -e '.response.configProfiles' >/dev/null 2>&1; then
        print_error "Не удалось получить список конфигураций"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    local configs
    configs=$(echo "$config_response" | jq -r '.response.configProfiles[] | select(.uuid and .name) | "\(.name) \(.uuid)"' 2>/dev/null)

    if [ -z "$configs" ]; then
        print_error "Конфигурации не найдены"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    echo -e "${YELLOW}Выберите конфигурацию для добавления WARP:${NC}"
    echo

    local i=1
    declare -A config_map
    declare -A config_name_map
    local menu_items=()
    while IFS=' ' read -r name uuid; do
        [ -z "$name" ] && continue
        menu_items+=("📄  $name")
        config_map[$i]="$uuid"
        config_name_map[$i]="$name"
        ((i++))
    done <<< "$configs"

    menu_items+=("──────────────────────────────────────")
    menu_items+=("❌  Назад")

    show_arrow_menu "📄  Выберите конфигурацию" "${menu_items[@]}"
    local choice=$?

    # Проверка - выбран ли разделитель или "Назад"
    if [ $choice -ge $((i-1)) ]; then
        return 0
    fi

    local selected_uuid=${config_map[$((choice+1))]}
    local selected_name=${config_name_map[$((choice+1))]}
    [ -z "$selected_uuid" ] && return 1

    # Получаем данные конфигурации
    local config_data
    config_data=$(make_api_request "GET" "${domain_url}/api/config-profiles/$selected_uuid" "$token")

    if [ -z "$config_data" ]; then
        print_error "Не удалось получить данные конфигурации"
        return 1
    fi

    local config_json
    config_json=$(echo "$config_data" | jq -r '.response.config // .config // empty')

    if [ -z "$config_json" ] || [ "$config_json" = "null" ]; then
        print_error "Конфигурация пуста"
        return 1
    fi

    # Проверяем, есть ли уже warp-out
    if echo "$config_json" | jq -e '.outbounds[] | select(.tag == "warp-out")' >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  WARP уже добавлен в эту конфигурацию${NC}"
        echo
        show_continue_prompt || return 1
        return 0
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ➕ ДОБАВЛЕНИЕ WARP В КОНФИГУРАЦИЮ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Получаем данные из первого (основного) инбаунда
    local main_inbound_tag main_domain
    main_inbound_tag=$(echo "$config_json" | jq -r '.inbounds[0].tag // empty' 2>/dev/null)
    main_domain=$(echo "$config_json" | jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' 2>/dev/null)

    if [ -z "$main_inbound_tag" ] || [ -z "$main_domain" ]; then
        print_error "Не удалось определить параметры основного инбаунда"
        echo
        show_continue_prompt || return 1
        return 1
    fi

    # Генерируем новые ключи для WARP-инбаунда
    print_action "Генерация REALITY ключей для WARP-инбаунда..."
    local warp_private_key
    warp_private_key=$(generate_xray_keys "$domain_url" "$token")
    if [ -z "$warp_private_key" ]; then
        print_error "Не удалось сгенерировать ключи"
        echo
        show_continue_prompt || return 1
        return 1
    fi
    print_success "Ключи сгенерированы"

    local warp_short_id
    warp_short_id=$(openssl rand -hex 8)

    # Формируем тег для WARP-инбаунда
    local warp_inbound_tag="${selected_name} - Warp"

    # Добавляем второй инбаунд (порт 8443)
    local warp_inbound
    warp_inbound=$(jq -n --arg tag "$warp_inbound_tag" --arg domain "$main_domain" \
        --arg private_key "$warp_private_key" --arg short_id "$warp_short_id" '{
        tag: $tag,
        port: 8443,
        protocol: "vless",
        settings: { clients: [], decryption: "none" },
        sniffing: { enabled: true, destOverride: ["http", "tls", "quic"] },
        streamSettings: {
            network: "tcp",
            security: "reality",
            realitySettings: {
                show: false,
                xver: 1,
                dest: "/dev/shm/nginx.sock",
                spiderX: "",
                shortIds: [$short_id],
                privateKey: $private_key,
                fingerprint: "chrome",
                serverNames: [$domain]
            }
        }
    }')

    config_json=$(echo "$config_json" | jq --argjson warp_inbound "$warp_inbound" '.inbounds += [$warp_inbound]')

    # Добавляем warp-out outbound
    local warp_outbound='{
        "tag": "warp-out",
        "protocol": "freedom",
        "settings": { "domainStrategy": "UseIP" },
        "streamSettings": { "sockopt": { "interface": "warp", "tcpFastOpen": true } }
    }'
    config_json=$(echo "$config_json" | jq --argjson wo "$warp_outbound" '.outbounds += [$wo]')

    # Добавляем правила маршрутизации:
    # 1. Основной инбаунд → DIRECT
    # 2. WARP-инбаунд → warp-out
    local rule_direct rule_warp
    rule_direct=$(jq -n --arg tag "$main_inbound_tag" '{
        type: "field",
        inboundTag: [$tag],
        outboundTag: "DIRECT"
    }')
    rule_warp=$(jq -n --arg tag "$warp_inbound_tag" '{
        type: "field",
        inboundTag: [$tag],
        outboundTag: "warp-out"
    }')

    config_json=$(echo "$config_json" | jq --argjson rd "$rule_direct" --argjson rw "$rule_warp" \
        '.routing.rules += [$rd, $rw]')

    # Обновляем конфигурацию через API
    print_action "Обновление конфигурации..."
    local update_body
    update_body=$(jq -n --arg uuid "$selected_uuid" --argjson config "$config_json" '{
        uuid: $uuid,
        config: $config
    }')
    local update_response
    update_response=$(make_api_request "PATCH" "${domain_url}/api/config-profiles" "$token" "$update_body")

    if [ -z "$update_response" ] || ! echo "$update_response" | jq -e '.' >/dev/null 2>&1; then
        print_error "Не удалось обновить конфигурацию"
        echo
        show_continue_prompt || return 1
        return 1
    fi
    print_success "Конфигурация обновлена"

    # Получаем UUID нового инбаунда из обновлённой конфигурации
    local updated_config
    updated_config=$(make_api_request "GET" "${domain_url}/api/config-profiles/$selected_uuid" "$token")
    local warp_inbound_uuid
    warp_inbound_uuid=$(echo "$updated_config" | jq -r --arg tag "$warp_inbound_tag" \
        '.response.inbounds[] | select(.tag == $tag) | .uuid // empty' 2>/dev/null)

    if [ -n "$warp_inbound_uuid" ] && [ "$warp_inbound_uuid" != "null" ]; then
        # Создаём хост для WARP-инбаунда (порт 8443)
        print_action "Создание хоста для WARP-инбаунда..."
        create_host "$domain_url" "$token" "$selected_uuid" "$warp_inbound_uuid" \
            "${selected_name} - Warp" "$main_domain" 8443
        print_success "Хост создан ($main_domain:8443)"

        # Добавляем WARP-инбаунд в сквады
        print_action "Обновление сквадов..."
        local squad_uuids
        squad_uuids=$(get_default_squad "$domain_url" "$token")
        if [ -n "$squad_uuids" ]; then
            while IFS= read -r squad_uuid; do
                [ -z "$squad_uuid" ] && continue
                update_squad "$domain_url" "$token" "$squad_uuid" "$warp_inbound_uuid"
            done <<< "$squad_uuids"
            print_success "Сквады обновлены"
        fi

        # Обновляем ноду — добавляем WARP-инбаунд в activeInbounds
        print_action "Обновление ноды..."
        local nodes_response
        nodes_response=$(make_api_request "GET" "${domain_url}/api/nodes" "$token")
        local node_uuid
        node_uuid=$(echo "$nodes_response" | jq -r --arg cp "$selected_uuid" \
            '.response[] | select(.configProfile.activeConfigProfileUuid == $cp) | .uuid // empty' 2>/dev/null | head -1)

        if [ -n "$node_uuid" ] && [ "$node_uuid" != "null" ]; then
            # Получаем текущие activeInbounds ноды
            local current_inbounds
            current_inbounds=$(echo "$nodes_response" | jq -r --arg uuid "$node_uuid" \
                '[.response[] | select(.uuid == $uuid) | .configProfile.activeInbounds[]] // []' 2>/dev/null)

            # Добавляем WARP-инбаунд
            local new_inbounds
            new_inbounds=$(echo "$current_inbounds" | jq --arg inbound "$warp_inbound_uuid" '. + [$inbound] | unique' 2>/dev/null)

            local node_update_body
            node_update_body=$(jq -n --arg uuid "$node_uuid" --argjson inbounds "$new_inbounds" \
                --arg cp_uuid "$selected_uuid" '{
                uuid: $uuid,
                configProfile: {
                    activeConfigProfileUuid: $cp_uuid,
                    activeInbounds: $inbounds
                }
            }')

            make_api_request "PATCH" "${domain_url}/api/nodes" "$token" "$node_update_body" >/dev/null 2>&1
            print_success "Нода обновлена"
        fi
    else
        echo -e "${YELLOW}⚠️  Не удалось получить UUID WARP-инбаунда (хост и сквады не обновлены)${NC}"
    fi

    echo
    echo -e "${GREEN}✅ WARP добавлен в конфигурацию${NC}"
    echo
    echo -e "${DARKGRAY}Основной инбаунд (порт 443) → DIRECT${NC}"
    echo -e "${DARKGRAY}WARP-инбаунд (порт 8443) → warp-out${NC}"
    echo -e "${DARKGRAY}Не забудьте установить WARP на сервере ноды${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}

remove_warp_from_config() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   ➖ УДАЛЕНИЕ WARP ИЗ КОНФИГУРАЦИИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Предупреждение — операция должна выполняться на сервере с панелью
    echo -e "${RED}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${YELLOW}Вы уверены, что находитесь на сервере с установленной панелью?${NC}"
    echo -e "${DARKGRAY}Будет удалён WARP-инбаунд (порт 8443), хост и маршрутизация.${NC}"
    echo
    echo -en "${GREEN}[?]${NC} ${YELLOW}Продолжить? (Enter/Esc):${NC} "
    read -rsn 1 -t 10 key 2>/dev/null || true
    echo

    if [ "$key" = $'\x1b' ]; then
        return 0
    fi

    # Получаем токен
    if ! get_panel_token; then
        return 1
    fi
    local token
    token=$(cat "${DIR_REMNAWAVE}/token")
    local domain_url="127.0.0.1:3000"

    # Получаем список конфигураций
    local config_response
    config_response=$(make_api_request "GET" "${domain_url}/api/config-profiles" "$token")

    if [ -z "$config_response" ]; then
        print_error "Не удалось получить список конфигураций"
        return 1
    fi

    local configs
    configs=$(echo "$config_response" | jq -r '.response.configProfiles[] | select(.uuid and .name) | "\(.name) \(.uuid)"' 2>/dev/null)

    if [ -z "$configs" ]; then
        print_error "Конфигурации не найдены"
        return 1
    fi

    echo -e "${YELLOW}Выберите конфигурацию для удаления WARP:${NC}"
    echo

    local i=1
    declare -A config_map
    local menu_items=()
    while IFS=' ' read -r name uuid; do
        [ -z "$name" ] && continue
        menu_items+=("📄  $name")
        config_map[$i]="$uuid"
        ((i++))
    done <<< "$configs"

    menu_items+=("──────────────────────────────────────")
    menu_items+=("❌  Назад")

    show_arrow_menu "📄  Выберите конфигурацию" "${menu_items[@]}"
    local choice=$?

    # Проверка - выбран ли разделитель или "Назад"
    if [ $choice -ge $((i-1)) ]; then
        return 0
    fi

    local selected_uuid=${config_map[$((choice+1))]}
    [ -z "$selected_uuid" ] && return 1

    # Получаем данные конфигурации
    local config_data
    config_data=$(make_api_request "GET" "${domain_url}/api/config-profiles/$selected_uuid" "$token")

    local config_json
    config_json=$(echo "$config_data" | jq -r '.response.config // .config // empty')

    if [ -z "$config_json" ] || [ "$config_json" = "null" ]; then
        print_error "Конфигурация пуста"
        return 1
    fi

    local removed=false

    # Удаляем WARP-инбаунд (порт 8443)
    if echo "$config_json" | jq -e '.inbounds[] | select(.port == 8443)' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.inbounds[] | select(.port == 8443))' 2>/dev/null)
        echo -e "${GREEN}✓${NC} Удалён WARP-инбаунд (порт 8443)"
        removed=true
    fi

    # Удаляем warp-out из outbounds
    if echo "$config_json" | jq -e '.outbounds[] | select(.tag == "warp-out")' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.outbounds[] | select(.tag == "warp-out"))' 2>/dev/null)
        echo -e "${GREEN}✓${NC} Удалён warp-out из outbounds"
        removed=true
    fi

    # Удаляем правила маршрутизации связанные с WARP
    if echo "$config_json" | jq -e '.routing.rules[] | select(.outboundTag == "warp-out")' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.routing.rules[] | select(.outboundTag == "warp-out"))' 2>/dev/null)
        echo -e "${GREEN}✓${NC} Удалено правило маршрутизации WARP"
        removed=true
    fi

    # Удаляем правило DIRECT для основного инбаунда (добавленное при WARP)
    # Оставляем только если есть inboundTag в правиле
    if echo "$config_json" | jq -e '.routing.rules[] | select(.outboundTag == "DIRECT" and .inboundTag)' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.routing.rules[] | select(.outboundTag == "DIRECT" and .inboundTag))' 2>/dev/null)
        echo -e "${GREEN}✓${NC} Удалено правило маршрутизации DIRECT по инбаунду"
        removed=true
    fi

    if [ "$removed" = false ]; then
        echo
        echo -e "${YELLOW}WARP не был настроен в этой конфигурации${NC}"
        echo
        show_continue_prompt || return 1
        return 0
    fi

    # Обновляем конфигурацию
    local update_body
    update_body=$(jq -n --arg uuid "$selected_uuid" --argjson config "$config_json" '{
        uuid: $uuid,
        config: $config
    }')
    local update_response
    update_response=$(make_api_request "PATCH" "${domain_url}/api/config-profiles" "$token" "$update_body")

    if [ -n "$update_response" ] && echo "$update_response" | jq -e '.' >/dev/null 2>&1; then
        echo
        print_success "WARP удалён из конфигурации"
        echo
        echo -e "${DARKGRAY}Хосты связанные с WARP-инбаундом будут удалены автоматически.${NC}"
    else
        echo
        print_error "Не удалось обновить конфигурацию"
    fi

    echo
    show_continue_prompt || return 1
}
