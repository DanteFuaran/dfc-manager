# ═══════════════════════════════════════════════
# РАБОТА С ДОМЕНАМИ
# ═══════════════════════════════════════════════

extract_domain() {
    local full_domain="$1"
    local parts
    parts=$(echo "$full_domain" | tr '.' '\n' | wc -l)
    if [ "$parts" -gt 2 ]; then
        echo "$full_domain" | cut -d'.' -f2-
    else
        echo "$full_domain"
    fi
}

get_server_ip() {
    local ip=""
    
    # Пробуем несколько сервисов для получения IP адреса
    ip=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null)
    if [ -n "$ip" ] && [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    
    ip=$(curl -s4 --max-time 5 icanhazip.com 2>/dev/null)
    if [ -n "$ip" ] && [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    
    ip=$(curl -s4 --max-time 5 ident.me 2>/dev/null)
    if [ -n "$ip" ] && [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    
    # Фоллбек на локальный IP если нет доступа в интернет
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -n "$ip" ] && [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    
    echo "unknown"
}

resolve_domain_ip() {
    local domain="$1"
    local ip=""

    # 1. dig (bind-utils)
    if command -v dig &>/dev/null; then
        ip=$(dig +short +time=3 +tries=1 "$domain" A 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -1)
        [ -n "$ip" ] && echo "$ip" && return 0
    fi

    # 2. nslookup
    if command -v nslookup &>/dev/null; then
        ip=$(timeout 3 nslookup "$domain" 2>/dev/null | awk '/^Address:/{print $2}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -1)
        [ -n "$ip" ] && echo "$ip" && return 0
    fi

    # 3. host
    if command -v host &>/dev/null; then
        ip=$(timeout 3 host -t A "$domain" 2>/dev/null | awk '/has address/{print $NF}' | head -1)
        [ -n "$ip" ] && echo "$ip" && return 0
    fi

    # 4. getent (всегда доступен на Linux)
    if command -v getent &>/dev/null; then
        ip=$(getent hosts "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -1)
        [ -n "$ip" ] && echo "$ip" && return 0
    fi

    echo ""
}

check_domain() {
    local domain="$1"
    local check_ip="${2:-true}"
    
    # Получаем IP домена
    local domain_ip
    domain_ip=$(resolve_domain_ip "$domain")

    # Получаем IP сервера для сообщений об ошибках
    local server_ip
    server_ip=$(get_server_ip)

    if [ -z "$domain_ip" ]; then
        echo
        echo -e "${RED}✖  Домена ${YELLOW}$domain${RED} не существует${NC}"
        echo -e "${RED}Проверьте запись домена или пропустите проверку.${NC}"
        return 1
    fi

    if [ "$check_ip" = false ]; then
        return 0
    fi

    # ═══════════════════════════════════════════════════════════
    # УЛУЧШЕННАЯ ПРОВЕРКА IP С ПОДДЕРЖКОЙ NAT/DOCKER/ПРОКСИ
    # ═══════════════════════════════════════════════════════════
    
    local ip_match=false
    
    # 1. Проверяем прямое совпадение с внешним IP
    if [ "$domain_ip" = "$server_ip" ]; then
        ip_match=true
    else
        # 2. Проверяем локальные IP интерфейсов (для Docker/NAT)
        local local_ips
        local_ips=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')
        
        if [ -n "$local_ips" ]; then
            while IFS= read -r local_ip; do
                if [ "$domain_ip" = "$local_ip" ]; then
                    ip_match=true
                    break
                fi
            done <<< "$local_ips"
        fi
    fi
    
    # 3. HTTP fallback проверка (если IP не совпал)
    if [ "$ip_match" = false ]; then
        # Создаём временный токен для проверки
        local test_token
        test_token=$(openssl rand -hex 16)
        mkdir -p /var/www/html
        echo "$test_token" > "/var/www/html/.test_${test_token}.txt" 2>/dev/null
        
        # Пытаемся получить файл через домен
        local test_response
        test_response=$(curl -s -m 5 "http://${domain}/.test_${test_token}.txt" 2>/dev/null || echo "")
        
        # Удаляем тестовый файл
        rm -f "/var/www/html/.test_${test_token}.txt" 2>/dev/null
        
        # Если получили правильный ответ - домен указывает на этот сервер
        if [ "$test_response" = "$test_token" ]; then
            ip_match=true
        fi
    fi
    
    # ═══════════════════════════════════════════════════════════
    # ФИНАЛЬНАЯ ПРОВЕРКА
    # ═══════════════════════════════════════════════════════════
    
    if [ "$ip_match" = false ]; then
        echo
        echo -e "${RED}✖ Домен ${YELLOW}$domain${RED} указывает на ${YELLOW}${domain_ip}${RED}, а не на IP сервера ${YELLOW}${server_ip}${NC}"
        echo -e "${RED}Проверьте запись домена или пропустите проверку.${NC}"
        return 1
    fi
    
    return 0
}

prompt_ip_with_retry() {
    local prompt_text="$1"
    local var_name="$2"

    while true; do
        reading_inline "$prompt_text" "$var_name"
        local _rc=$?
        [ $_rc -eq 2 ] && return 1

        if echo "${!var_name}" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            return 0
        fi

        print_error "Некорректный IP адрес"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить     ${BLUE}Esc${DARKGRAY}: Назад${NC}"

        tput civis 2>/dev/null || true
        local key
        while true; do
            read -s -n 1 key
            if [[ "$key" == $'\x1b' ]]; then
                tput cnorm 2>/dev/null || true
                echo
                return 1
            elif [[ "$key" == "" ]]; then
                tput cnorm 2>/dev/null || true
                local lines_up=5
                for ((l=0; l<lines_up; l++)); do
                    tput cuu1 2>/dev/null
                    tput el 2>/dev/null
                done
                break
            fi
        done
    done
}

prompt_domain_with_retry() {
    local prompt_text="$1"
    local var_name="$2"
    local use_inline="${3:-false}"
    local skip_ip_check="${4:-false}"

    local first=true
    while true; do
        if [ "$first" = true ]; then
            if [ "$use_inline" = true ]; then
                reading_inline "$prompt_text" "$var_name"
                local _rc=$?
                [ $_rc -eq 2 ] && return 1
            else
                reading "$prompt_text" "$var_name"
                local _rc=$?
                [ $_rc -ne 0 ] && return 1
            fi
            first=false
        else
            reading_inline "$prompt_text" "$var_name"
            local _rc=$?
            [ $_rc -eq 2 ] && return 1
        fi

        local check_ip_flag=true
        [ "$skip_ip_check" = true ] && check_ip_flag=false

        # Показываем спиннер пока идёт проверка домена
        local _check_out _check_rc
        local _check_out_file _check_rc_file
        _check_out_file=$(mktemp)
        _check_rc_file=$(mktemp)
        (
            check_domain "${!var_name}" "$check_ip_flag" > "$_check_out_file" 2>&1
            echo $? > "$_check_rc_file"
        ) &
        local _check_pid=$!
        local _spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local _si=0
        tput civis 2>/dev/null || true
        echo
        while kill -0 $_check_pid 2>/dev/null; do
            printf "\r\033[K${GREEN}%s${NC}  Проверка домена" "${_spin[$_si]}"
            _si=$(( (_si+1) % 10 ))
            sleep 0.08
        done
        printf "\r\033[K"
        wait $_check_pid 2>/dev/null
        tput cnorm 2>/dev/null || true
        _check_rc=$(cat "$_check_rc_file" 2>/dev/null)
        _check_out=$(cat "$_check_out_file" 2>/dev/null)
        rm -f "$_check_out_file" "$_check_rc_file"

        # Выводим сообщение об ошибке (если есть) после очистки строки спиннера
        [ -n "$_check_out" ] && printf "%s\n" "$_check_out"

        if [ "$_check_rc" = "0" ]; then
            return 0
        fi

        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${BLUE}Enter${DARKGRAY}: Повторить   ${BLUE}S${DARKGRAY}: Пропустить   ${BLUE}Esc${DARKGRAY}: Назад${NC}"

        tput civis 2>/dev/null || true
        local key
        while true; do
            read -s -n 1 key
            if [[ "$key" == $'\x1b' ]]; then
                tput cnorm 2>/dev/null || true
                echo
                return 1
            elif [[ "$key" == "s" || "$key" == "S" ]]; then
                tput cnorm 2>/dev/null || true
                echo
                local skip_lines=7
                for ((l=0; l<skip_lines; l++)); do
                    tput cuu1 2>/dev/null
                    tput el 2>/dev/null
                done
                return 0
            elif [[ "$key" == "" ]]; then
                tput cnorm 2>/dev/null || true
                local lines_up=7
                for ((l=0; l<lines_up; l++)); do
                    tput cuu1 2>/dev/null
                    tput el 2>/dev/null
                done
                break
            fi
        done
    done
}

check_node_domain() {
    local domain_url="$1"
    local token="$2"
    local domain="$3"

    local response
    response=$(make_api_request "GET" "$domain_url/api/nodes" "$token")

    if [ -z "$response" ]; then
        print_error "Ошибка при проверке домена"
        return 1
    fi

    if echo "$response" | jq -e '.response' >/dev/null 2>&1; then
        local existing_domain
        existing_domain=$(echo "$response" | jq -r --arg addr "$domain" \
            '.response[] | select(.address == $addr) | .address' 2>/dev/null)
        if [ -n "$existing_domain" ]; then
            print_error "Домен уже используется: $domain"
            return 1
        fi
        return 0
    else
        local error_message
        error_message=$(echo "$response" | jq -r '.message // "Unknown error"')
        print_error "Ошибка при проверке домена: $error_message"
        return 1
    fi
}
