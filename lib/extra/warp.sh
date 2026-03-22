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
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return 0
    fi

    # Только панель (без ноды) — только пункты конфигурации
    if [ "$has_panel" = true ] && [ "$has_node" = false ]; then
        items+=("➕  Добавить WARP в конфигурацию ноды");  actions+=("add_config")
        items+=("➖  Удалить WARP из конфигурации ноды");  actions+=("del_config")
        items+=("──────────────────────────────────────");  actions+=("sep")
        items+=("⬅️  Назад");                               actions+=("back")

    # Только нода (без панели) — только установка/удаление WARP
    elif [ "$has_node" = true ] && [ "$has_panel" = false ]; then
        if [ "$warp_installed" = false ]; then
            items+=("📥  Установить WARP");  actions+=("install")
        else
            items+=("🗑️   Удалить WARP");    actions+=("uninstall")
        fi
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("⬅️  Назад");                              actions+=("back")

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
        items+=("⬅️  Назад");                               actions+=("back")
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

    # Спрашиваем порт WARP-инбаунда
    local warp_install_port=""
    while true; do
        reading_inline "Порт для WARP-инбаунда:" warp_install_port
        local _rc_wp=$?
        if [[ $_rc_wp -eq 2 ]]; then return 0; fi
        if [[ "$warp_install_port" =~ ^[0-9]+$ ]] && [ "$warp_install_port" -ge 1024 ] && [ "$warp_install_port" -le 65535 ]; then
            break
        fi
        print_error "Введите корректный порт (1024–65535)"
    done

    # Спрашиваем WARP+ ключ
    reading_inline "WARP+ ключ (Enter для бесплатной версии):" warp_key
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
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>&1
        echo "=== apt-get install wireguard ==="
        DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" wireguard 2>&1

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

    # Проверяем результат
    if ip link show warp 2>/dev/null | grep -q "warp"; then
        rm -f "$_warp_log"
        if command -v ufw >/dev/null 2>&1; then
            ufw allow "${warp_install_port}/tcp" >/dev/null 2>&1 || true
            echo "${warp_install_port}" > /etc/wireguard/.warp_port
        fi
        print_success "Создание WARP интерфейса"
        print_success "WARP успешно установлен"
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

    echo
    echo -e "${YELLOW}⚠️  Вы уверены что хотите удалить WARP ?${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
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
        # Удаляем пакеты
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y wireguard >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление WARP"

    # Проверяем результат
    if ! ip link show warp 2>/dev/null | grep -q "warp"; then
        print_success "WARP успешно удалён"
        # Закрываем порт в UFW если он был сохранён при установке
        if [ -f /etc/wireguard/.warp_port ] && command -v ufw >/dev/null 2>&1; then
            local _saved_port
            _saved_port=$(cat /etc/wireguard/.warp_port 2>/dev/null)
            if [[ "$_saved_port" =~ ^[0-9]+$ ]]; then
                ufw delete allow "${_saved_port}/tcp" >/dev/null 2>&1 || true
            fi
            rm -f /etc/wireguard/.warp_port
        fi
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
    echo -e "${YELLOW}⚠️  Вы уверены, что находитесь на сервере с установленной панелью?${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    printf "     ${BLUE}Enter${DARKGRAY}: Подтвердить     ${BLUE}Esc${DARKGRAY}: Отменить${NC}"
    read -rsn 1 key 2>/dev/null || true
    echo
    echo
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
    menu_items+=("⬅️  Назад")

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

    # Запрашиваем порт для WARP-инбаунда
    local warp_port=""
    while true; do
        reading_inline "Порт для WARP-инбаунда:" warp_port
        local _rc_port=$?
        if [[ $_rc_port -eq 2 ]]; then return; fi
        if [[ "$warp_port" =~ ^[0-9]+$ ]] && [ "$warp_port" -ge 1024 ] && [ "$warp_port" -le 65535 ]; then
            if ss -tuln 2>/dev/null | grep -qE ":${warp_port}[^0-9]"; then
                print_error "Порт ${warp_port} уже занят (например, nginx). Выберите другой порт."
            else
                break
            fi
        else
            print_error "Введите корректный порт (1024–65535)"
        fi
    done

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ➕ ДОБАВЛЕНИЕ WARP В КОНФИГУРАЦИЮ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

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

    # Добавляем второй инбаунд (порт $warp_port)
    local warp_inbound
    warp_inbound=$(jq -n --arg tag "$warp_inbound_tag" --arg domain "$main_domain" \
        --arg private_key "$warp_private_key" --arg short_id "$warp_short_id" \
        --argjson port "$warp_port" '{
        tag: $tag,
        port: $port,
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
    # 1. YouTube → warp-out (домены через WARP с любого инбаунда)
    # 2. Основной инбаунд → DIRECT
    # 3. WARP-инбаунд → warp-out
    local rule_direct rule_warp rule_youtube
    rule_youtube=$(jq -n '{
        type: "field",
        domain: ["geosite:youtube"],
        outboundTag: "warp-out"
    }')
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

    config_json=$(echo "$config_json" | jq --argjson ry "$rule_youtube" --argjson rd "$rule_direct" --argjson rw "$rule_warp" \
        '.routing.rules += [$ry, $rd, $rw]')

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
        # Создаём хост для WARP-инбаунда
        create_host "$domain_url" "$token" "$selected_uuid" "$warp_inbound_uuid" \
            "${selected_name} - Warp" "$main_domain" "$warp_port" >/dev/null 2>&1

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
            '[.response[] | select(
                .configProfile.activeConfigProfileUuid == $cp or
                .activeConfigProfileUuid == $cp
            ) | .uuid][0] // empty' 2>/dev/null)

        if [ -n "$node_uuid" ] && [ "$node_uuid" != "null" ]; then
            # Получаем текущие activeInbounds ноды (обработка как строк, так и объектов)
            local current_inbounds
            current_inbounds=$(echo "$nodes_response" | jq --arg uuid "$node_uuid" \
                '[.response[] | select(.uuid == $uuid) | .configProfile.activeInbounds[] |
                  if type == "object" then .uuid else . end] // []' 2>/dev/null)

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

    # Открываем порт в UFW на этом сервере
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${warp_port}/tcp" >/dev/null 2>&1 || true
        echo "${warp_port}" > /etc/wireguard/.warp_port
    fi

    echo
    echo -e "${YELLOW}⚠️  Теперь установите WARP на сервере ноды${NC}"
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
    echo -e "${DARKGRAY}Из профиля будет удалён WARP-инбаунд и связанные правила маршрутизации.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    printf " ${BLUE}Enter${DARKGRAY}: Подтвердить     ${BLUE}Esc${DARKGRAY}: Отменить${NC}"
    read -rsn 1 key 2>/dev/null || true
    echo
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
    menu_items+=("⬅️  Назад")

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

    # Определяем порты WARP-инбаундов
    local warp_ports
    warp_ports=$(echo "$config_json" | jq -r --argjson tags \
        "$(echo "$config_json" | jq '[.routing.rules[] | select(.outboundTag == "warp-out" and .inboundTag) | .inboundTag[]] | unique')" \
        '.inbounds[] | select(.tag as $t | $tags | index($t)) | .port | tostring' 2>/dev/null)

    # Определяем остаточные порты (после удаления WARP-инбаундов)
    local remaining_ports
    remaining_ports=$(echo "$config_json" | jq -r --argjson tags \
        "$(echo "$config_json" | jq '[.routing.rules[] | select(.outboundTag == "warp-out" and .inboundTag) | .inboundTag[]] | unique')" \
        '.inbounds[] | select(.tag as $t | $tags | index($t) == null) | .port | tostring' 2>/dev/null)

    # Спрашиваем про порт ДО удаления, пока терминал в нормальном состоянии
    local _should_close_port=false
    local _port_to_close=""
    if command -v ufw >/dev/null 2>&1 && [ -n "$warp_ports" ]; then
        while IFS= read -r port; do
            [ -z "$port" ] && continue
            if ! echo "$remaining_ports" | grep -qx "$port"; then
                _port_to_close="$port"
                break
            fi
        done <<< "$warp_ports"
    fi

    if [ -n "$_port_to_close" ]; then
        show_arrow_menu "🛡️  Закрытие порта WARP" \
            "Закрыть порт от WARP (${_port_to_close})" \
            "Не закрывать порт"
        [ $? -eq 0 ] && _should_close_port=true
    fi

    # После show_arrow_menu — сбрасываем состояние терминала
    stty sane 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   ➖ УДАЛЕНИЕ WARP ИЗ КОНФИГУРАЦИИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Определяем теги WARP-инбаундов
    local warp_inbound_tags
    warp_inbound_tags=$(echo "$config_json" | jq -r '[.routing.rules[] | select(.outboundTag == "warp-out" and .inboundTag) | .inboundTag[]] | unique[]' 2>/dev/null)

    local removed=false

    # Удаляем WARP-инбаунд (определяем по правилу маршрутизации → warp-out)
    if [ -n "$warp_inbound_tags" ]; then
        while IFS= read -r tag; do
            [ -z "$tag" ] && continue
            config_json=$(echo "$config_json" | jq --arg tag "$tag" 'del(.inbounds[] | select(.tag == $tag))' 2>/dev/null)
        done <<< "$warp_inbound_tags"
        print_success "Удалён WARP-инбаунд"
        removed=true
    fi

    # Удаляем warp-out из outbounds
    if echo "$config_json" | jq -e '.outbounds[] | select(.tag == "warp-out")' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.outbounds[] | select(.tag == "warp-out"))' 2>/dev/null)
        print_success "Удалён warp-out из outbounds"
        removed=true
    fi

    # Удаляем правила маршрутизации связанные с WARP
    if echo "$config_json" | jq -e '.routing.rules[] | select(.outboundTag == "warp-out")' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.routing.rules[] | select(.outboundTag == "warp-out"))' 2>/dev/null)
        print_success "Удалено правило маршрутизации WARP"
        removed=true
    fi

    # Удаляем правило DIRECT для основного инбаунда (добавленное при WARP)
    if echo "$config_json" | jq -e '.routing.rules[] | select(.outboundTag == "DIRECT" and .inboundTag)' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.routing.rules[] | select(.outboundTag == "DIRECT" and .inboundTag))' 2>/dev/null)
        print_success "Удалено правило маршрутизации DIRECT по инбаунду"
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
    echo
    print_action "Сохранение конфигурации..."
    local update_body
    update_body=$(jq -n --arg uuid "$selected_uuid" --argjson config "$config_json" '{
        uuid: $uuid,
        config: $config
    }')
    local update_response
    update_response=$(make_api_request "PATCH" "${domain_url}/api/config-profiles" "$token" "$update_body")

    if [ -n "$update_response" ] && echo "$update_response" | jq -e '.' >/dev/null 2>&1; then
        print_success "Конфигурация сохранена"

        # Удаляем хосты WARP
        print_action "Удаление хостов WARP..."
        local hosts_response
        hosts_response=$(make_api_request "GET" "${domain_url}/api/hosts" "$token" 2>/dev/null) || true
        if [ -n "$hosts_response" ]; then
            local host_uuids_to_del
            host_uuids_to_del=$(echo "$hosts_response" | jq -r \
                --arg cp "$selected_uuid" \
                '[.response[] | select(
                    (.inbound.configProfileUuid // "") == $cp and
                    ((.remark // "") | test("[Ww]arp"))
                ) | .uuid // empty] | .[]' 2>/dev/null) || true
            if [ -n "$host_uuids_to_del" ]; then
                while IFS= read -r host_uuid; do
                    [ -z "$host_uuid" ] && continue
                    make_api_request "DELETE" "${domain_url}/api/hosts/${host_uuid}" "$token" >/dev/null 2>&1 || true
                done <<< "$host_uuids_to_del"
                print_success "Хосты WARP удалены"
            else
                print_success "Хосты WARP не найдены"
            fi
        else
            echo -e "${YELLOW}⚠️  Не удалось получить список хостов${NC}"
        fi

        # Закрываем порт если пользователь выбрал "Закрыть" до начала операции
        if [ "$_should_close_port" = true ] && [ -n "$_port_to_close" ]; then
            ufw delete allow "${_port_to_close}/tcp" >/dev/null 2>&1 || true
            print_success "Порт ${_port_to_close}/tcp закрыт в UFW"
        fi

        echo
        print_success "WARP удалён из конфигурации"
        echo
    else
        echo
        print_error "Не удалось обновить конфигурацию"
        echo
    fi

    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}
