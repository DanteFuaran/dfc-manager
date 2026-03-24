# ═══════════════════════════════════════════════
# API ФУНКЦИИ (Remnawave Panel)
# ═══════════════════════════════════════════════

make_api_request() {
    local method=$1
    local url=$2
    local token=$3
    local data="${4:-}"

    local headers=(
        -H "Authorization: Bearer $token"
        -H "Content-Type: application/json"
        -H "X-Forwarded-For: 127.0.0.1"
        -H "X-Forwarded-Proto: https"
        -H "X-Remnawave-Client-Type: browser"
    )

    if [ -n "$data" ]; then
        curl -s --max-time 10 -X "$method" "http://$url" "${headers[@]}" -d "$data"
    else
        curl -s --max-time 10 -X "$method" "http://$url" "${headers[@]}"
    fi
}

get_panel_token() {
    local TOKEN_FILE="${DIR_SCRIPT}/token"
    local domain_url="127.0.0.1:3000"
    local token=""

    # Проверяем сохранённый токен
    if [ -f "$TOKEN_FILE" ]; then
        token=$(cat "$TOKEN_FILE")
        local test_response
        test_response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")

        if [ -z "$test_response" ] || ! echo "$test_response" | jq -e '.response.configProfiles' >/dev/null 2>&1; then
            echo -e "${RED}Сохранённый токен недействителен. Запрашиваем новый...${NC}"
            token=""
        fi
    fi

    if [ -z "$token" ]; then
        # Проверяем наличие OAuth
        local auth_status
        auth_status=$(make_api_request "GET" "$domain_url/api/auth/status" "")
        local oauth_enabled=false

        if [ -n "$auth_status" ]; then
            local github_enabled yandex_enabled pocketid_enabled telegram_enabled
            github_enabled=$(echo "$auth_status" | jq -r '.response.authentication.oauth2.providers.github // false' 2>/dev/null)
            yandex_enabled=$(echo "$auth_status" | jq -r '.response.authentication.oauth2.providers.yandex // false' 2>/dev/null)
            pocketid_enabled=$(echo "$auth_status" | jq -r '.response.authentication.oauth2.providers.pocketid // false' 2>/dev/null)
            telegram_enabled=$(echo "$auth_status" | jq -r '.response.authentication.tgAuth.enabled // false' 2>/dev/null)

            if [ "$github_enabled" = "true" ] || [ "$yandex_enabled" = "true" ] || \
               [ "$pocketid_enabled" = "true" ] || [ "$telegram_enabled" = "true" ]; then
                oauth_enabled=true
            fi
        fi

        if [ "$oauth_enabled" = true ]; then
            echo -e "${YELLOW}═════════════════════════════════════════════════${NC}"
            echo -e "${RED}ВНИМАНИЕ:${NC}"
            echo -e "${YELLOW}Включена авторизация через OAuth/Telegram.${NC}"
            echo -e "${YELLOW}Зайдите в панель, перейдите в 'API токены' -> 'Создать новый токен'${NC}"
            echo -e "${YELLOW}Скопируйте созданный токен и введите его ниже.${NC}"

            while true; do
                reading_inline "Введите API-токен: " token
                local _rc_token=$?
                if [[ $_rc_token -eq 2 ]]; then return 2; fi
                if [ -z "$token" ]; then continue; fi

                local test_response
                test_response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
                if [ -z "$test_response" ] || ! echo "$test_response" | jq -e '.response.configProfiles' >/dev/null 2>&1; then
                    print_error "Токен недействителен"
                    echo
                    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
                    echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить     ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
                    local key
                    while true; do
                        read -s -n 1 key
                        if [[ "$key" == $'\x1b' ]]; then
                            local _drain; while IFS= read -r -s -n1 -t 0.05 _drain; do :; done
                            echo; return 2
                        fi
                        [[ "$key" == "" ]] && break
                    done
                    continue
                fi

                break
            done
        else
            local _login_step=1
            local username="" password=""
            while true; do
                if [[ $_login_step -eq 1 ]]; then
                    reading_inline "Введите логин панели:" username
                    local _rc_u=$?
                    if [[ $_rc_u -eq 2 ]]; then return 2; fi
                    if [[ -z "$username" ]]; then
                        echo
                        print_error "Логин не может быть пустым"
                        echo
                        echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
                        echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить     ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
                        local _key
                        while true; do
                            read -s -n 1 _key
                            if [[ "$_key" == $'\x1b' ]]; then
                                local _drain; while IFS= read -r -s -n1 -t 0.05 _drain; do :; done
                                echo; return 2
                            fi
                            if [[ "$_key" == "" ]]; then
                                for ((i=0; i<6; i++)); do tput cuu1 2>/dev/null; tput el 2>/dev/null; done
                                break
                            fi
                        done
                        continue
                    fi
                    _login_step=2
                fi

                reading_inline "Введите пароль панели:" password
                local _rc_p=$?
                if [[ $_rc_p -eq 2 ]]; then
                    tput cuu1 2>/dev/null; tput el 2>/dev/null
                    tput cuu1 2>/dev/null; tput el 2>/dev/null
                    _login_step=1
                    username=""
                    continue
                fi
                if [[ -z "$password" ]]; then
                    echo
                    print_error "Пароль не может быть пустым"
                    echo
                    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
                    echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить     ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
                    local _key
                    while true; do
                        read -s -n 1 _key
                        if [[ "$_key" == $'\x1b' ]]; then
                            local _drain; while IFS= read -r -s -n1 -t 0.05 _drain; do :; done
                            echo; return 2
                        fi
                        if [[ "$_key" == "" ]]; then
                            for ((i=0; i<6; i++)); do tput cuu1 2>/dev/null; tput el 2>/dev/null; done
                            break
                        fi
                    done
                    continue
                fi

                local login_response
                login_response=$(make_api_request "POST" "$domain_url/api/auth/login" "" \
                    "$(jq -n --arg u "$username" --arg p "$password" '{username: $u, password: $p}')")
                token=$(echo "$login_response" | jq -r '.response.accessToken // empty')

                if [ -n "$token" ] && [ "$token" != "null" ]; then
                    break
                fi

                echo
                print_error "Неверный логин или пароль"
                echo
                echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
                echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить     ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
                local key
                while true; do
                    read -s -n 1 key
                    if [[ "$key" == $'\x1b' ]]; then
                        local _drain; while IFS= read -r -s -n1 -t 0.05 _drain; do :; done
                        echo; return 2
                    fi
                    if [[ "$key" == "" ]]; then
                        for ((i=0; i<7; i++)); do
                            tput cuu1 2>/dev/null
                            tput el 2>/dev/null
                        done
                        _login_step=1
                        username=""
                        break
                    fi
                done
            done
        fi

        echo "$token" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE" 2>/dev/null
    fi

    # Финальная проверка
    local final_test
    final_test=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
    if [ -z "$final_test" ] || ! echo "$final_test" | jq -e '.response.configProfiles' >/dev/null 2>&1; then
        print_error "Токен не прошёл проверку"
        return 1
    fi

    return 0
}

register_remnawave() {
    local domain_url=$1
    local username=$2
    local password=$3
    local max_attempts=5
    local attempt=1

    local register_data
    register_data=$(jq -n --arg u "$username" --arg p "$password" '{username: $u, password: $p}')
    local token=""

    while [ $attempt -le $max_attempts ] && [ -z "$token" ]; do
        local response
        response=$(curl -s -X POST "http://$domain_url/api/auth/register" \
            -H "Content-Type: application/json" \
            -H "X-Forwarded-For: 127.0.0.1" \
            -H "X-Forwarded-Proto: https" \
            -d "$register_data" 2>/dev/null)

        token=$(echo "$response" | jq -r '.response.accessToken // empty' 2>/dev/null)

        if [ -z "$token" ]; then
            # Попытка логина если уже зарегистрирован
            local login_data='{"username":"'"$username"'","password":"'"$password"'"}'
            response=$(curl -s -X POST "http://$domain_url/api/auth/login" \
                -H "Content-Type: application/json" \
                -H "X-Forwarded-For: 127.0.0.1" \
                -H "X-Forwarded-Proto: https" \
                -d "$login_data" 2>/dev/null)
            token=$(echo "$response" | jq -r '.response.accessToken // empty' 2>/dev/null)
        fi

        if [ -z "$token" ]; then
            sleep 3
            ((attempt++))
        fi
    done

    echo "$token"
}

get_public_key() {
    local domain_url=$1
    local token=$2
    local target_dir=$3
    local max_attempts=8
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        local response
        response=$(make_api_request "GET" "$domain_url/api/keygen" "$token")
        local pubkey
        pubkey=$(echo "$response" | jq -r '.response.pubKey // empty' 2>/dev/null)

        if [ -n "$pubkey" ]; then
            sed -i "s|SECRET_KEY=.*|SECRET_KEY=\"$pubkey\"|" "$target_dir/docker-compose.yml" 2>/dev/null
            return 0
        fi

        sleep 4
        ((attempt++))
    done

    print_error "Не удалось получить публичный ключ из API"
    return 1
}

generate_xray_keys() {
    local domain_url=$1
    local token=$2
    local max_attempts=8
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        local response
        response=$(make_api_request "GET" "$domain_url/api/system/tools/x25519/generate" "$token")
        local private_key
        private_key=$(echo "$response" | jq -r '.response.keypairs[0].privateKey // empty' 2>/dev/null)

        if [ -z "$private_key" ] || [ "$private_key" = "null" ]; then
            # Fallback - возможно другая версия API
            private_key=$(echo "$response" | jq -r '.response.privateKey // empty' 2>/dev/null)
        fi

        if [ -n "$private_key" ] && [ "$private_key" != "null" ]; then
            echo "$private_key"
            return 0
        fi

        sleep 4
        ((attempt++))
    done

    echo ""
}

create_config_profile() {
    local domain_url=$1
    local token=$2
    local name=$3
    local domain=$4
    local private_key=$5
    local inbound_tag="${6:-Steal}"

    local short_id
    short_id=$(openssl rand -hex 8)

    local request_body
    request_body=$(jq -n --arg name "$name" --arg domain "$domain" \
        --arg private_key "$private_key" --arg short_id "$short_id" \
        --arg inbound_tag "$inbound_tag" '{
        name: $name,
        config: {
            log: { loglevel: "warning" },
            dns: {
                queryStrategy: "UseIPv4",
                servers: [
                    { address: "https://dns.google/dns-query", skipFallback: false },
                    { address: "https://1.1.1.1/dns-query", skipFallback: false },
                    { address: "https://dns.quad9.net/dns-query", skipFallback: false }
                ]
            },
            inbounds: [{
                tag: $inbound_tag,
                port: 443,
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
                        serverNames: [$domain]
                    }
                }
            }],
            outbounds: [
                { tag: "DIRECT", protocol: "freedom" },
                { tag: "BLOCK", protocol: "blackhole" }
            ],
            routing: {
                domainStrategy: "AsIs",
                rules: [
                    { ip: ["geoip:private"], type: "field", outboundTag: "BLOCK" },
                    { type: "field", protocol: ["bittorrent"], outboundTag: "BLOCK" }
                ]
            }
        }
    }')

    local response
    response=$(make_api_request "POST" "$domain_url/api/config-profiles" "$token" "$request_body")

    local config_uuid
    config_uuid=$(echo "$response" | jq -r '.response.uuid // empty' 2>/dev/null)
    local inbound_uuid
    inbound_uuid=$(echo "$response" | jq -r '.response.inbounds[0].uuid // empty' 2>/dev/null)

    if [ -z "$config_uuid" ] || [ "$config_uuid" = "null" ] || \
       [ -z "$inbound_uuid" ] || [ "$inbound_uuid" = "null" ]; then
        echo "ERROR" >&2
        return 1
    fi

    echo "$config_uuid $inbound_uuid"
}

delete_config_profile() {
    local domain_url=$1
    local token=$2

    local response
    response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")

    local config_uuids
    config_uuids=$(echo "$response" | jq -r '.response.configProfiles[].uuid // empty' 2>/dev/null)

    if [ -n "$config_uuids" ]; then
        while IFS= read -r uuid; do
            [ -z "$uuid" ] && continue
            make_api_request "DELETE" "$domain_url/api/config-profiles/$uuid" "$token" >/dev/null 2>&1
        done <<< "$config_uuids"
    fi
}

create_node() {
    local domain_url=$1
    local token=$2
    local config_profile_uuid=$3
    local inbound_uuid=$4
    local node_address="${5:-172.30.0.1}"
    local node_name="${6:-Steal}"

    local request_body
    request_body=$(jq -n --arg name "$node_name" --arg address "$node_address" \
        --arg config_uuid "$config_profile_uuid" --arg inbound "$inbound_uuid" '{
        name: $name,
        address: $address,
        port: 2222,
        configProfile: {
            activeConfigProfileUuid: $config_uuid,
            activeInbounds: [$inbound]
        },
        isTrafficTrackingActive: false,
        trafficLimitBytes: 0,
        notifyPercent: 0,
        trafficResetDay: 31,
        excludedInbounds: [],
        countryCode: "XX",
        consumptionMultiplier: 1.0
    }')

    local response
    response=$(make_api_request "POST" "$domain_url/api/nodes" "$token" "$request_body")

    if echo "$response" | jq -e '.response.uuid' >/dev/null 2>&1; then
        return 0
    else
        echo "ERROR: $response" >&2
        return 1
    fi
}

create_host() {
    local domain_url=$1
    local token=$2
    local config_uuid=$3
    local inbound_uuid=$4
    local remark=$5
    local address=$6
    local port="${7:-443}"

    local request_body
    request_body=$(jq -n --arg config_uuid "$config_uuid" --arg inbound_uuid "$inbound_uuid" \
        --arg remark "$remark" --arg address "$address" --argjson port "$port" '{
        inbound: {
            configProfileUuid: $config_uuid,
            configProfileInboundUuid: $inbound_uuid
        },
        remark: $remark,
        address: $address,
        port: $port,
        path: "",
        sni: $address,
        host: "",
        alpn: null,
        fingerprint: "chrome",
        allowInsecure: false,
        isDisabled: false,
        securityLayer: "DEFAULT"
    }')

    make_api_request "POST" "$domain_url/api/hosts" "$token" "$request_body" >/dev/null
}

get_default_squad() {
    local domain_url=$1
    local token=$2

    local response
    response=$(make_api_request "GET" "$domain_url/api/internal-squads" "$token")
    echo "$response" | jq -r '.response.internalSquads[].uuid // empty' 2>/dev/null
}

update_squad() {
    local domain_url=$1
    local token=$2
    local squad_uuid=$3
    local inbound_uuid=$4

    local current
    current=$(make_api_request "GET" "$domain_url/api/internal-squads" "$token")

    # Получаем текущие inbounds сквада
    local current_inbounds
    current_inbounds=$(echo "$current" | jq -r --arg uuid "$squad_uuid" \
        '[.response.internalSquads[] | select(.uuid == $uuid) | .inbounds[].uuid] // []' 2>/dev/null)

    # Добавляем новый inbound к существующим
    local inbounds_array
    inbounds_array=$(echo "$current_inbounds" | jq --arg inbound "$inbound_uuid" \
        '. + [$inbound] | unique | map({uuid: .})' 2>/dev/null)

    local request_body
    request_body=$(jq -n --arg uuid "$squad_uuid" --argjson inbounds "$inbounds_array" '{
        uuid: $uuid,
        inbounds: $inbounds
    }')

    make_api_request "PATCH" "$domain_url/api/internal-squads" "$token" "$request_body" >/dev/null
}

create_api_token() {
    local domain_url=$1
    local token=$2
    local target_dir=${3:-${DIR_PANEL}}

    local request_body='{"tokenName":"subscription-page"}'
    local response
    response=$(make_api_request "POST" "$domain_url/api/tokens" "$token" "$request_body")

    local api_token
    api_token=$(echo "$response" | jq -r '.response.token // empty' 2>/dev/null)

    if [ -z "$api_token" ] || [ "$api_token" = "null" ]; then
        print_error "Не удалось создать API токен: $(echo "$response" | jq -r '.message // "Unknown error"')"
        return 1
    fi

    if grep -q "^REMNAWAVE_API_TOKEN=" "$target_dir/.env" 2>/dev/null; then
        sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=$api_token|" "$target_dir/.env"
    else
        echo "REMNAWAVE_API_TOKEN=$api_token" >> "$target_dir/.env"
    fi
    print_success "Регистрация API токена"
}
