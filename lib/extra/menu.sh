# ═══════════════════════════════════════════════════
# ДОПОЛНИТЕЛЬНЫЕ ПРОГРАММЫ — ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════════
manage_extra_settings() {
    while true; do
        tput civis 2>/dev/null || true
        clear

        local _ufw_st _warp_st _f2b_st
        command -v ufw >/dev/null 2>&1 && _ufw_st="${GREEN}(установлен)${NC}" || _ufw_st="${DARKGRAY}(не установлен)${NC}"
        ip link show warp 2>/dev/null | grep -q "warp" && _warp_st="${GREEN}(установлен)${NC}" || _warp_st="${DARKGRAY}(не установлен)${NC}"
        command -v fail2ban-client >/dev/null 2>&1 && _f2b_st="${GREEN}(установлен)${NC}" || _f2b_st="${DARKGRAY}(не установлен)${NC}"

        show_arrow_menu "🧩  Дополнительные программы" \
            "🔥  UFW - Firewall      ${_ufw_st}" \
            "🌐  WARP - Cloudflare   ${_warp_st}" \
            "🛡️   Fail2ban - Defence  ${_f2b_st}" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) manage_ufw || break ;;
            1) manage_warp || break ;;
            2) manage_fail2ban || break ;;
            3) continue ;;
            4) return ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MTPROTO — УПРАВЛЕНИЕ
# ═══════════════════════════════════════════════════
_MT_CONTAINER="mtproto-proxy"
_MT_IMAGE="telegrammessenger/proxy:latest"
_MT_DIR="/opt/mtproto"
_MT_ENV="${_MT_DIR}/.env"

_mt_installed() { docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${_MT_CONTAINER}$"; }
_mt_running()   { docker ps    --format '{{.Names}}' 2>/dev/null | grep -q "^${_MT_CONTAINER}$"; }
_mt_load_env()  { [ -f "$_MT_ENV" ] && source "$_MT_ENV" 2>/dev/null || true; }

_mt_press_enter() {
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e " ${BLUE}Enter${DARKGRAY}: Продолжить${NC}"
    tput civis 2>/dev/null || true
    read -r
    tput cnorm 2>/dev/null || true
}

# ── MTProto install helpers ──────────────────────────────────────────────────

# Поглощает CSI/SS3 escape-последовательность из буфера ввода (после \e)
_mt_consume_escape_seq() {
    local _s1="" _s2=""
    read -rsn1 -t 0.1 _s1 2>/dev/null || _s1=""
    if [[ "$_s1" == '[' ]] || [[ "$_s1" == 'O' ]]; then
        while true; do
            read -rsn1 -t 0.1 _s2 2>/dev/null || { _s2=""; break; }
            [[ -z "$_s2" ]] && break
            [[ "$_s2" =~ [a-zA-Z~] ]] && break
        done
    fi
}

# Интерактивный ввод строки (Backspace, зелёный ввод)
# Esc → возвращает 1 ("назад"), Enter → записывает значение и возвращает 0
# Использование: _mt_read_input VARNAME "Промпт" "default" || { на_шаг_назад; }
_mt_read_input() {
    local _var="$1" _prompt="$2" _default="${3:-}"
    local _typed="" _ch _orig_stty _rc=0
    _orig_stty=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo isig min 1 time 0 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf "\033[1;34m\xe2\x9e\x9c\033[0m  \033[1;33m%b\033[0m " "$_prompt"
    while IFS= read -rsn1 -t 0 _ch 2>/dev/null; do :; done
    while true; do
        _ch=""
        IFS= read -rsn1 _ch 2>/dev/null || _ch=""
        if [[ "$_ch" == $'\n' ]] || [[ "$_ch" == $'\r' ]] || [[ "$_ch" == "" ]]; then
            printf "\n"; break
        elif [[ "$_ch" == $'\x7f' ]] || [[ "$_ch" == $'\b' ]]; then
            if [ "${#_typed}" -gt 0 ]; then _typed="${_typed%?}"; printf '\b \b'; fi
        elif [[ "$_ch" == $'\e' ]]; then
            _mt_consume_escape_seq
            printf "\r\033[K"   # стрерть текущую строку без перевода
            _rc=1; break
        elif [[ -n "$_ch" ]] && [[ "$_ch" =~ [[:print:]] ]]; then
            _typed="${_typed}${_ch}"
            printf "${GREEN}%s${NC}" "$_ch"
        fi
    done
    if [ -n "${_orig_stty}" ]; then stty "$_orig_stty" 2>/dev/null || stty sane 2>/dev/null || true
    else stty sane 2>/dev/null || true; fi
    if [ "$_rc" -eq 0 ]; then
        if [ -z "$_typed" ]; then printf -v "$_var" '%s' "$_default"
        else printf -v "$_var" '%s' "$_typed"; fi
    fi
    return $_rc
}

# Получает внешний IP сервера
_mt_get_server_ip() {
    curl -s --max-time 5 ifconfig.me 2>/dev/null ||
    curl -s --max-time 5 icanhazip.com 2>/dev/null ||
    curl -s --max-time 5 api.ipify.org 2>/dev/null ||
    echo "YOUR_IP"
}

# Проверяет/устанавливает Docker
_mt_check_docker() {
    if ! command -v docker &>/dev/null; then
        print_warning "Docker не установлен"
        echo
        echo -e "  ${YELLOW}Установить Docker автоматически? [y/N]${NC}"
        local _ans=""
        read -r _ans
        if [[ "$_ans" =~ ^[Yy]$ ]]; then
            (curl -fsSL https://get.docker.com | sh >/dev/null 2>&1) &
            show_spinner "Установка Docker..." "Docker установлен"
        else
            return 1
        fi
    fi
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker не запущен"; return 1
    fi
}

# Генерирует Fake TLS secret на основе домена
_mt_generate_fake_tls_secret() {
    local domain="${1:-google.com}"
    local domain_hex
    domain_hex=$(printf '%s' "$domain" | xxd -ps | tr -d '\n')
    local domain_len=${#domain_hex}
    local needed=$(( 30 - domain_len ))
    [ "$needed" -lt 0 ] && needed=0
    local random_hex=""
    [ "$needed" -gt 0 ] && random_hex=$(openssl rand -hex 15 2>/dev/null | cut -c1-"$needed")
    printf 'ee%s%s' "$domain_hex" "$random_hex"
}

# Ищет свободный порт начиная с base
_mt_find_free_port() {
    local base="${1:-8443}"
    for port in "$base" 8444 8445 9443 10443 1337; do
        if ! ss -tuln 2>/dev/null | grep -q ":${port} "; then
            echo "$port"; return 0
        fi
    done
    echo "10443"
}

# Сохраняет конфиг в .env
_mt_save_config() {
    mkdir -p "$_MT_DIR"
    cat > "$_MT_ENV" << EOF
PROXY_PORT=${PROXY_PORT}
PROXY_SECRET=${PROXY_SECRET}
SERVER_IP=${SERVER_IP}
FAKE_DOMAIN=${FAKE_DOMAIN}
PROXY_TAG=${PROXY_TAG}
EOF
}

# Записывает docker-compose.yml
_mt_write_compose() {
    mkdir -p "$_MT_DIR"
    cat > "${_MT_DIR}/docker-compose.yml" << 'COMPOSE'
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    restart: unless-stopped
    ports:
      - "${PROXY_PORT}:443"
    environment:
      - SECRET=${PROXY_SECRET}
      - TAG=${PROXY_TAG}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE
}

# Установка / переустановка MTProto (встроенная реализация)
# Шаги ввода: 1-домен, 2-порт, 3-секрет, 4-IP, 5-tag.  Esc → предыдущий шаг.
# При Esc стираем строки текущего шага и повторно выводим предыдущий инпут.
_mt_do_install() {
    set +e
    local PROXY_PORT PROXY_SECRET SERVER_IP FAKE_DOMAIN PROXY_TAG
    PROXY_PORT="8443"
    FAKE_DOMAIN="google.com"
    PROXY_SECRET=""
    SERVER_IP=""
    PROXY_TAG=""
    [ -f "$_MT_ENV" ] && source "$_MT_ENV" 2>/dev/null || true

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       📦 Установка MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    _mt_check_docker || { _mt_press_enter; return; }

    # _mt_erase_lines N — стираем N строк вверх (текущая уже пустая после \r\033[K)
    _mt_erase_lines() {
        local n=$1
        while [ $n -gt 0 ]; do
            printf "\033[A\033[K"
            (( n-- ))
        done
    }

    local _step=1 _secret_input=""

    while true; do
        case $_step in
            1) # IP/домен для ссылки с проверкой
                local _default_host="${SERVER_IP:-$(_mt_get_server_ip)}"
                while true; do
                    _mt_read_input SERVER_IP "Домен или IP для ссылки подключения ${DARKGRAY}[${_default_host}]${NC}:" "$_default_host"
                    if [ $? -eq 1 ]; then
                        return  # Esc на первом шаге — выход
                    fi
                    
                    # Проверяем сопоставление домена/IP с сервером
                    if check_domain "$SERVER_IP" true; then
                        (( _step++ ))
                        break
                    fi
                    
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить   ${BLUE}S${DARKGRAY}: Пропустить   ${BLUE}Esc${DARKGRAY}: Назад${NC}"
                    
                    tput civis 2>/dev/null || true
                    local key
                    while true; do
                        read -s -n 1 key
                        if [[ "$key" == $'\x1b' ]]; then
                            tput cnorm 2>/dev/null || true
                            echo
                            return  # Esc — выход из установки
                        elif [[ "$key" == "s" || "$key" == "S" ]]; then
                            tput cnorm 2>/dev/null || true
                            (( _step++ ))
                            break 2  # Пропустить проверку
                        elif [[ "$key" == "" ]]; then
                            tput cnorm 2>/dev/null || true
                            # Перерисовываем экран с заголовком и повторяем ввод
                            clear
                            echo -e "${BLUE}══════════════════════════════════════${NC}"
                            echo -e "${GREEN}       📦 Установка MTProto${NC}"
                            echo -e "${BLUE}══════════════════════════════════════${NC}"
                            echo
                            break  # Повторить ввод домена
                        fi
                    done
                done
                ;;
            2) # Порт
                local _port_default="${PROXY_PORT:-$(_mt_find_free_port "8443")}"
                _mt_read_input PROXY_PORT "Порт прокси ${DARKGRAY}[${_port_default}]${NC}:" "$_port_default"
                if [ $? -eq 0 ]; then
                    if [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] && (( PROXY_PORT >= 1 && PROXY_PORT <= 65535 )); then
                        (( _step++ ))
                    else
                        echo -e "${RED}✖ Порт должен быть числом от 1 до 65535${NC}"
                    fi
                else
                    _mt_erase_lines 1
                    (( _step-- ))
                fi
                ;;
            3) # Fake TLS домен
                _mt_read_input FAKE_DOMAIN "Fake TLS домен ${DARKGRAY}[${FAKE_DOMAIN}]${NC}:" "$FAKE_DOMAIN"
                if [ $? -eq 0 ]; then
                    (( _step++ ))
                else
                    _mt_erase_lines 1
                    (( _step-- ))
                fi
                ;;
            4) # Секрет
                _mt_read_input _secret_input "Введите секрет ${DARKGRAY}[Enter для создания нового]${NC}:" ""
                if [ $? -eq 0 ]; then
                    (( _step++ ))
                else
                    _mt_erase_lines 1
                    (( _step-- ))
                fi
                ;;
            5) # Показать секрет + Telegram TAG
                local _disp_secret
                if [ -n "$_secret_input" ]; then
                    _disp_secret="$_secret_input"
                else
                    _disp_secret=$(_mt_generate_fake_tls_secret "$FAKE_DOMAIN")
                fi
                echo -e "   ${DARKGRAY}Секрет:${NC} ${YELLOW}${_disp_secret}${NC}"
                echo
                _mt_read_input PROXY_TAG "Telegram TAG ${DARKGRAY}[Enter - пропустить]${NC}:" "${PROXY_TAG:-}"
                if [ $? -eq 0 ]; then
                    break
                else
                    _mt_erase_lines 2
                    (( _step-- ))
                fi
                ;;
        esac
    done

    # Финализация введённых значений
    if [ -n "$_secret_input" ]; then
        PROXY_SECRET="$_secret_input"
    else
        PROXY_SECRET=$(_mt_generate_fake_tls_secret "$FAKE_DOMAIN")
    fi
    echo
    echo

    # Подготавливаем файлы
    _mt_write_compose
    _mt_save_config
    print_success "Подготовка файлов"

    # Чистим старый контейнер если есть
    if _mt_installed; then
        (cd "$_MT_DIR" && docker compose down --remove-orphans >/dev/null 2>&1 || \
         docker rm -f "$_MT_CONTAINER" >/dev/null 2>&1) &
        show_spinner "Очистка старого контейнера..." "Старый контейнер удалён"
    fi

    # Тянем образ и запускаем
    (cd "$_MT_DIR" && docker compose pull >/dev/null 2>&1) &
    show_spinner "Загрузка образа..." "Образ загружен"

    (cd "$_MT_DIR" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск MTProto..." "MTProto запущен!"

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${PROXY_PORT}" >/dev/null 2>&1 || true
    fi

    if _mt_running; then
        _mt_save_config
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        local _ok_line="✅ MTProto успешно установлен!"
        local _ok_pad=$(( (38 - ${#_ok_line}) / 2 ))
        local _ok_prefix; printf -v _ok_prefix "%${_ok_pad}s" ""
        echo -e "${_ok_prefix}${GREEN}${_ok_line}${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        local _cw=12
        echo -e " ${DARKGRAY}$(_mpad "Домен/IP:" $_cw)${NC} ${WHITE}${SERVER_IP}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Порт:" $_cw)${NC} ${WHITE}${PROXY_PORT}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Секрет:" $_cw)${NC} ${YELLOW}${PROXY_SECRET}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Fake TLS:" $_cw)${NC} ${WHITE}${FAKE_DOMAIN}${NC}"
        [ -n "$PROXY_TAG" ] && echo -e " ${DARKGRAY}$(_mpad "Tag:" $_cw)${NC} ${WHITE}${PROXY_TAG}${NC}"
        echo
        echo -e "${BLUE}──────────────────────────────────────${NC}"
        echo
        echo -e "${WHITE}🔗 Ссылка для Telegram:${NC}"
        echo -e "   ${GREEN}tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
        tput civis 2>/dev/null || true
        while true; do
            local _k=""
            IFS= read -rsn1 _k
            case "$_k" in
                $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
                "")      tput cnorm 2>/dev/null || true; return 0 ;;
            esac
        done
    else
        echo
        print_error "Контейнер не запустился. Логи:"
        docker logs "$_MT_CONTAINER" 2>&1 | tail -20 || true
        _mt_press_enter
    fi
}

# Показать конфигурацию и ссылку
_mt_do_config() {
    _mt_load_env
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}      📄 Конфигурация и ссылка${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if [ -z "${PROXY_SECRET:-}" ]; then
        echo -e "${YELLOW}⚠️  Конфигурация не найдена. Сначала установите прокси.${NC}"
        _mt_press_enter; return
    fi

    local _rs="${RED}Не запущен${NC}"
    _mt_running && _rs="${GREEN}Запущен${NC}"

    local _cw=12
    echo -e " ${DARKGRAY}$(_mpad "Статус:" $_cw)${NC} ${_rs}"
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Домен/IP:" $_cw)${NC} ${WHITE}${SERVER_IP:-}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Порт:" $_cw)${NC} ${WHITE}${PROXY_PORT:-}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Секрет:" $_cw)${NC} ${YELLOW}${PROXY_SECRET}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Fake TLS:" $_cw)${NC} ${WHITE}${FAKE_DOMAIN:-}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}🔗 Ссылка для Telegram:${NC}"
    echo -e "   ${GREEN}tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${NC}"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

# Статистика подключений
_mt_do_stats() {
    _mt_load_env

    if ! _mt_running; then
        echo -e "${RED}✖ Прокси не запущен${NC}"
        _mt_press_enter; return
    fi

    local _max_file="${_MT_DIR}/stats_max_connections"
    local _uptime_file="${_MT_DIR}/stats_uptime_ts"
    local _max_sim=0
    [ -f "$_max_file" ] && _max_sim=$(cat "$_max_file" 2>/dev/null || echo "0")

    local _container_started
    _container_started=$(docker inspect --format '{{.State.StartedAt}}' \
        "$_MT_CONTAINER" 2>/dev/null | sed 's/[^0-9]//g' | cut -c1-14)
    local _saved_ts=""
    [ -f "$_uptime_file" ] && _saved_ts=$(cat "$_uptime_file" 2>/dev/null || true)
    if [ "$_container_started" != "$_saved_ts" ]; then
        _max_sim=0
        echo "$_container_started" > "$_uptime_file" 2>/dev/null || true
    fi

    local _st_orig_stty
    _st_orig_stty=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo isig min 0 time 0 2>/dev/null || true

    _mt_stats_restore() {
        if [ -n "${_st_orig_stty}" ]; then stty "$_st_orig_stty" 2>/dev/null || stty sane 2>/dev/null || true
        else stty sane 2>/dev/null || true; fi
        tput cnorm 2>/dev/null || true
    }

    while true; do
        local _active _uptime
        local _started_at _start_ts _now
        _started_at=$(docker inspect --format '{{.State.StartedAt}}' "$_MT_CONTAINER" 2>/dev/null || echo "")
        _now=$(date +%s)
        if [ -n "$_started_at" ]; then
            _start_ts=$(date -d "$_started_at" +%s 2>/dev/null || echo "$_now")
        else
            _start_ts="$_now"
        fi
        _uptime=$(( _now - _start_ts ))

        # Считаем подключения изнутри контейнера — только там видны реальные IP клиентов.
        # На хосте Docker не создаёт сокеты для проброшенных портов (отдельный net namespace).
        # Внутри контейнера порт всегда 443 (PROXY_PORT — это только хостовый маппинг).
        local _ss_out
        _ss_out=$(docker exec "$_MT_CONTAINER" \
            ss -tn state established 2>/dev/null \
            | awk 'NR>1 && $3 ~ /:443$/')

        # Уникальные IP клиентов — $4 (Peer Address:Port), обрезаем порт клиента
        # MTProto открывает несколько TCP-соединений на устройство — считаем по уникальным IP
        local _client_ips
        _client_ips=$(printf '%s\n' "$_ss_out" \
            | awk 'NF{print $4}' \
            | sed 's/:[0-9]*$//; s/^\[//; s/\]$//' \
            | sort -u)
        _active=$(printf '%s\n' "$_client_ips" | awk 'NF{c++} END{print c+0}')

        # Геолокация: кеш /tmp/mtproto_geo — строки вида "IP|Страна, Город"
        # Новые IP запрашиваем батчем через ip-api.com (бесплатно, без ключа)
        local _geo_cache="/tmp/mtproto_geo"
        touch "$_geo_cache" 2>/dev/null || true
        local _new_ips=""
        while IFS= read -r _gip; do
            [ -z "$_gip" ] && continue
            grep -q "^${_gip}|" "$_geo_cache" 2>/dev/null || _new_ips="${_new_ips} ${_gip}"
        done <<< "$_client_ips"
        if [ -n "$_new_ips" ]; then
            # Формируем JSON-массив и делаем батч-запрос в фоне
            (
                local _jarr
                _jarr=$(echo "$_new_ips" | tr ' ' '\n' | grep -v '^$' \
                    | awk '{printf "\"%s\",",$1}' | sed 's/,$//')
                local _resp
                _resp=$(curl -s --max-time 6 -X POST \
                    "http://ip-api.com/batch?fields=query,country,city" \
                    -H "Content-Type: application/json" \
                    -d "[${_jarr}]" 2>/dev/null)
                # Парсим: {"query":"1.2.3.4","country":"Russia","city":"Moscow"}
                echo "$_resp" | grep -oP '\{[^}]+\}' | while read -r _obj; do
                    local _q _co _ci
                    _q=$(echo "$_obj"  | grep -oP '"query"\s*:\s*"\K[^"]+')
                    _co=$(echo "$_obj" | grep -oP '"country"\s*:\s*"\K[^"]+')
                    _ci=$(echo "$_obj" | grep -oP '"city"\s*:\s*"\K[^"]+')
                    [ -z "$_q" ] && continue
                    local _geo_str="—"
                    [ -n "$_co" ] && _geo_str="${_co}"
                    [ -n "$_ci" ] && _geo_str="${_geo_str}, ${_ci}"
                    # Атомарная запись (append): если IP ещё не в кеше — добавляем
                    grep -q "^${_q}|" "$_geo_cache" 2>/dev/null \
                        || echo "${_q}|${_geo_str}" >> "$_geo_cache"
                done
            ) &
        fi

        if [ "$_active" -gt "$_max_sim" ] 2>/dev/null; then
            _max_sim="$_active"
            echo "$_max_sim" > "$_max_file" 2>/dev/null || true
        fi

        local _up_h _up_m _up_s _up_str
        _up_h=$(( _uptime / 3600 )); _up_m=$(( (_uptime % 3600) / 60 )); _up_s=$(( _uptime % 60 ))
        printf -v _up_str "%02d:%02d:%02d" "$_up_h" "$_up_m" "$_up_s"

        local _net_io="—"
        local _stats_out
        _stats_out=$(docker stats --no-stream --format "{{.NetIO}}" "$_MT_CONTAINER" 2>/dev/null || true)
        [ -n "$_stats_out" ] && _net_io="$_stats_out"

        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}       📊 Статистика MTProto${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        local _cw=22
        echo -e " ${DARKGRAY}$(_mpad "Активных клиентов:" $_cw)${NC} ${GREEN}${_active}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Макс одновременно:" $_cw)${NC} ${YELLOW}${_max_sim}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Трафик (вх / исх):" $_cw)${NC} ${WHITE}${_net_io}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Аптайм:" $_cw)${NC} ${WHITE}${_up_str}${NC}"
        if [ -n "$_client_ips" ]; then
            echo
            echo -e "${BLUE}──────────────────────────────────────────────────────${NC}"
            echo -e " ${DARKGRAY}Подключённые IP:${NC}"
            while IFS= read -r _ip; do
                [ -z "$_ip" ] && continue
                local _geo_str
                _geo_str=$(grep "^${_ip}|" "$_geo_cache" 2>/dev/null | head -1 | cut -d'|' -f2)
                [ -z "$_geo_str" ] && _geo_str="..."
                printf "   ${WHITE}%-20s${DARKGRAY}%s${NC}\n" "$_ip" "$_geo_str"
            done <<< "$_client_ips"
        fi
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"

        # Ждём 5 сек с проверкой Enter/Esc каждые 0.1 сек
        local _si=0 _sk _rr
        while [ $_si -lt 50 ]; do
            _sk=""
            IFS= read -rsn1 -t 0.1 _sk 2>/dev/null && _rr=0 || _rr=$?
            if [[ "$_sk" == $'\e' ]]; then
                _mt_consume_escape_seq
                _mt_stats_restore
                return 1   # Esc = выход в главное меню
            elif [[ $_rr -eq 0 && "$_sk" == "" ]]; then
                _mt_stats_restore
                return 0   # Enter = назад в меню MTProto
            fi
            (( _si++ )) || true
        done
    done
    _mt_stats_restore
}

# Сменить конфигурацию — интерактивно
_mt_do_change_config() {
    if ! _mt_installed; then
        echo -e "${RED}✖ MTProto не установлен. Сначала установите прокси.${NC}"
        _mt_press_enter; return
    fi
    _mt_load_env

    local _old_port="${PROXY_PORT:-}"
    local _step=1 _secret_input=""
    local NEW_SERVER_IP="$SERVER_IP"
    local NEW_PROXY_PORT="$PROXY_PORT"
    local NEW_FAKE_DOMAIN="$FAKE_DOMAIN"
    local NEW_PROXY_TAG="${PROXY_TAG:-}"

    _mt_erase_lines() {
        local n=$1
        while [ $n -gt 0 ]; do
            printf "\033[A\033[K"
            (( n-- ))
        done
    }

    while true; do
        case $_step in
            1) # IP/домен
                local _default_host="${NEW_SERVER_IP:-$(_mt_get_server_ip)}"
                while true; do
                    clear
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    echo -e "${GREEN}     🔑 Смена конфигурации MTProto${NC}"
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    echo
                    _mt_read_input NEW_SERVER_IP "Домен или IP для ссылки подключения ${DARKGRAY}[${_default_host}]${NC}:" "$_default_host"
                    if [ $? -eq 1 ]; then return; fi
                    if check_domain "$NEW_SERVER_IP" true; then
                        (( _step++ )); break
                    fi
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить   ${BLUE}S${DARKGRAY}: Пропустить   ${BLUE}Esc${DARKGRAY}: Назад${NC}"
                    tput civis 2>/dev/null || true
                    local key
                    while true; do
                        read -s -n 1 key
                        if [[ "$key" == $'\x1b' ]]; then tput cnorm 2>/dev/null || true; return
                        elif [[ "$key" == "s" || "$key" == "S" ]]; then tput cnorm 2>/dev/null || true; (( _step++ )); break 2
                        elif [[ "$key" == "" ]]; then tput cnorm 2>/dev/null || true; break
                        fi
                    done
                done ;;
            2) # Порт
                local _port_default="${NEW_PROXY_PORT:-$(_mt_find_free_port "8443")}"
                _mt_read_input NEW_PROXY_PORT "Порт прокси ${DARKGRAY}[${_port_default}]${NC}:" "$_port_default"
                if [ $? -eq 0 ]; then
                    if [[ "$NEW_PROXY_PORT" =~ ^[0-9]+$ ]] && (( NEW_PROXY_PORT >= 1 && NEW_PROXY_PORT <= 65535 )); then
                        (( _step++ ))
                    else
                        echo -e "${RED}✖ Порт должен быть числом от 1 до 65535${NC}"
                    fi
                else _mt_erase_lines 1; (( _step-- )); fi ;;
            3) # Fake TLS домен
                _mt_read_input NEW_FAKE_DOMAIN "Fake TLS домен ${DARKGRAY}[${NEW_FAKE_DOMAIN}]${NC}:" "$NEW_FAKE_DOMAIN"
                if [ $? -eq 0 ]; then (( _step++ ))
                else _mt_erase_lines 1; (( _step-- )); fi ;;
            4) # Секрет
                _mt_read_input _secret_input "Введите секрет ${DARKGRAY}[Enter для создания нового]${NC}:" ""
                if [ $? -eq 0 ]; then (( _step++ ))
                else _mt_erase_lines 1; (( _step-- )); fi ;;
            5) # Показать секрет + Telegram TAG
                local _disp_secret
                if [ -n "$_secret_input" ]; then
                    _disp_secret="$_secret_input"
                else
                    _disp_secret=$(_mt_generate_fake_tls_secret "$NEW_FAKE_DOMAIN")
                fi
                echo -e "   ${DARKGRAY}Секрет:${NC} ${YELLOW}${_disp_secret}${NC}"
                echo
                _mt_read_input NEW_PROXY_TAG "Telegram TAG ${DARKGRAY}[Enter - пропустить]${NC}:" "${NEW_PROXY_TAG:-}"
                if [ $? -eq 0 ]; then break
                else _mt_erase_lines 2; (( _step-- )); fi ;;
        esac
    done

    if [ -n "$_secret_input" ]; then
        PROXY_SECRET="$_secret_input"
    else
        PROXY_SECRET=$(_mt_generate_fake_tls_secret "$NEW_FAKE_DOMAIN")
    fi
    SERVER_IP="$NEW_SERVER_IP"
    PROXY_PORT="$NEW_PROXY_PORT"
    FAKE_DOMAIN="$NEW_FAKE_DOMAIN"
    PROXY_TAG="$NEW_PROXY_TAG"
    echo
    echo

    _mt_write_compose
    _mt_save_config
    print_success "Конфигурация сохранена"

    # Перезапуск с новым портом
    (cd "$_MT_DIR" && docker compose down >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Перезапуск MTProto..." "MTProto перезапущен!"

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${PROXY_PORT}" >/dev/null 2>&1 || true
        if [ -n "$_old_port" ] && [ "$_old_port" != "$PROXY_PORT" ]; then
            ufw delete allow "$_old_port" >/dev/null 2>&1 || true
        fi
    fi

    echo
    echo -e " ${DARKGRAY}Ссылка:${NC} ${GREEN}tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${NC}"
    echo
    _mt_press_enter
}

_mt_do_stop() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}        ⏹️  Остановка MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    if ! _mt_running; then
        echo -e "${YELLOW}⚠️  Прокси не запущен${NC}"
        _mt_press_enter; return
    fi
    (cd "$_MT_DIR" && docker compose stop >/dev/null 2>&1) &
    show_spinner "Остановка прокси..." "Прокси остановлен"
    _mt_press_enter
}

_mt_do_start() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}         ▶️  Запуск MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    if _mt_running; then
        echo -e "${YELLOW}⚠️  Прокси уже запущен${NC}"
        _mt_press_enter; return
    fi
    (cd "$_MT_DIR" && docker compose start >/dev/null 2>&1) &
    show_spinner "Запуск прокси..." "Прокси запущен"
    _mt_press_enter
}

_mt_do_restart() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       🔄 Перезапуск MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    (cd "$_MT_DIR" && docker compose restart >/dev/null 2>&1) &
    show_spinner "Перезапуск прокси..." "Прокси перезапущен"
    _mt_press_enter
}

_mt_do_uninstall() {
    _mt_load_env
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}        🗑️  Удаление MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    if ! _mt_installed; then
        echo -e "${YELLOW}⚠️  Прокси не установлен${NC}"
        _mt_press_enter; return
    fi

    echo -e "    ${YELLOW}MTProto будет удалён с сервера${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "  ${BLUE}Enter${DARKGRAY}: Подтвердить   ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return ;;
            "")      break ;;
        esac
    done
    tput cnorm 2>/dev/null || true
    echo
    echo

    (if [ -d "$_MT_DIR" ]; then
        cd "$_MT_DIR" && docker compose down --remove-orphans >/dev/null 2>&1 || true
    fi
    docker rm -f "$_MT_CONTAINER" >/dev/null 2>&1 || true) &
    show_spinner "Остановка контейнера..." "Контейнер остановлен"

    (docker rmi "$_MT_IMAGE" >/dev/null 2>&1 || true
    rm -rf "$_MT_DIR" 2>/dev/null || true
    if command -v ufw >/dev/null 2>&1 && [ -n "${PROXY_PORT:-}" ]; then
        ufw delete allow "${PROXY_PORT}" >/dev/null 2>&1 || true
    fi
    rm -f /usr/local/bin/mtproto /usr/local/bin/mt 2>/dev/null || true
    rm -rf /usr/local/lib/mtproto 2>/dev/null || true) &
    show_spinner "Удаление остаточных файлов..." "Удаление остаточных файлов"

    echo
    echo -e "${GREEN}✅ MTProto полностью удалён${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        tput civis 2>/dev/null || true
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

_mt_do_update() {
    if ! _mt_installed; then
        echo -e "${RED}✖ MTProto не установлен${NC}"
        _mt_press_enter; return
    fi
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     ⬆️  Обновление образа MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    (cd "$_MT_DIR" && docker compose pull >/dev/null 2>&1) &
    show_spinner "Загрузка нового образа..." "Образ обновлён"
    (cd "$_MT_DIR" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Перезапуск MTProto..." "MTProto обновлён!"
    _mt_press_enter
}

manage_mtproto() {
    while true; do
        tput civis 2>/dev/null || true
        _mt_load_env
        local _installed=false _running=false
        _mt_installed && _installed=true
        _mt_running   && _running=true

        local _line1="📡 MTProto Proxy"

        local _stat_word _stat_color
        if   [ "$_running"   = true ]; then
            _stat_word="Запущен";       _stat_color="${GREEN}"
        elif [ "$_installed" = true ]; then
            _stat_word="Остановлен";    _stat_color="${YELLOW}"
        else
            _stat_word="Не установлен"; _stat_color="${DARKGRAY}"
        fi
        local _stat_plain="Статус: ● ${_stat_word}"
        local _l2_pad=$(( (38 - ${#_stat_plain}) / 2 ))
        local _l2_prefix; printf -v _l2_prefix "%${_l2_pad}s" ""

        local _title="${_line1}\n${_l2_prefix}${DARKGRAY}Статус: ${_stat_color}● ${_stat_word}${NC}"

        local -a _items=() _actions=()

        if [ "$_installed" = false ]; then
            _items+=("📦  Установить MTProto");     _actions+=("install")
        else
            _items+=("📦  Переустановить MTProto"); _actions+=("install")
            _items+=("⬆️   Обновить образ");          _actions+=("update")
            _items+=("──────────────────────────────────────"); _actions+=("sep")
            _items+=("📊  Статистика подключений");            _actions+=("stats")
            _items+=("📄  Конфигурация и ссылка");             _actions+=("config")
            _items+=("🔑  Сменить конфигурацию");              _actions+=("change_config")
            _items+=("──────────────────────────────────────"); _actions+=("sep")
            if [ "$_running" = true ]; then
                _items+=("⏹️   Остановить прокси");    _actions+=("stop")
                _items+=("🔄  Перезапустить прокси"); _actions+=("restart")
            else
                _items+=("▶️   Запустить прокси");     _actions+=("start")
            fi
        fi

        _items+=("──────────────────────────────────────"); _actions+=("sep")
        _items+=("⬅️   Назад");                             _actions+=("back")

        show_arrow_menu "$_title" "${_items[@]}"
        local _choice=$?
        [[ $_choice -eq 255 ]] && return

        local _action="${_actions[$_choice]:-sep}"
        case "$_action" in
            install)       _mt_do_install || return ;;
            update)        _mt_do_update ;;
            stats)         _mt_do_stats || return ;;
            config)        _mt_do_config || return ;;
            change_config) _mt_do_change_config ;;
            start)         _mt_do_start ;;
            stop)          _mt_do_stop ;;
            restart)       _mt_do_restart ;;
            back)          return ;;
            *)             continue ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# ТЕСТИРОВАНИЕ СЕРВЕРА
# ═══════════════════════════════════════════════════
manage_server_testing() {
    while true; do
        tput civis 2>/dev/null || true
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   🧪  ТЕСТИРОВАНИЕ СЕРВЕРА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        show_arrow_menu "🧪  Тестирование сервера" \
            "⚡  Тест скорости сети" \
            "🌍  Доступность популярных сервисов" \
            "🔒  Региональные ограничения" \
            "📍  Геолокация IP" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) run_speed_test     || return ;;
            1) run_services_check || return ;;
            2) run_regional_check || return ;;
            3) run_geolocation    || return ;;
            4) continue ;;
            5) return ;;
        esac
    done
}

run_speed_test() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}        ⚡ Тест скорости сети${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/speedtest_result.XXXXXX)
    (
        cd /tmp && \
        curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz" -o speedtest.tgz && \
        tar -xzf speedtest.tgz
    ) &
    show_spinner "Подготовка инструмента тестирования"
    echo
    (
        cd /tmp && \
        ./speedtest --accept-license --accept-gdpr 2>/dev/null > "$tmpfile" && \
        rm -rf speedtest.tgz speedtest
    ) &
    show_spinner "Запущен тест скорости сети" "Диагностика скорости сети завершёна"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    # Парсим результат
    local server isp latency download dl_ping upload ul_ping loss
    server=$(echo "$output" | grep -oP 'Server:\s*\K.*?(?=\s*\(id)' | sed 's/\s*$//')
    isp=$(echo "$output" | grep -oP 'ISP:\s*\K.*' | sed 's/\s*$//')
    latency=$(echo "$output" | grep -oP 'Idle Latency:\s*\K.*' | sed 's/\s*$//')
    download=$(echo "$output" | grep -oP 'Download:\s*\K[\d.]+\s*\S+' | sed 's/\s*$//')
    dl_ping=$(echo "$output" | sed -n '/Download:/{n;s/^\s*//;p;}' | grep -oP '^[\d.]+\s*ms' | sed 's/\s*$//')
    upload=$(echo "$output" | grep -oP 'Upload:\s*\K[\d.]+\s*\S+' | sed 's/\s*$//')
    ul_ping=$(echo "$output" | sed -n '/Upload:/{n;s/^\s*//;p;}' | grep -oP '^[\d.]+\s*ms' | sed 's/\s*$//')
    loss=$(echo "$output" | grep -oP 'Packet Loss:\s*\K.*' | sed 's/\s*$//')

    if [ -n "$server" ]; then
        local _cw=21
        echo -e "${DARKGRAY}──────────────── [ Сервер ] ─────────────────${NC}"
        echo
        echo -e " ${DARKGRAY}$(_mpad "Сервер подключения:" $_cw)${NC} ${WHITE}${server}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Провайдер:" $_cw)${NC} ${WHITE}${isp}${NC}"
        echo
        echo -e "${DARKGRAY}──────────────── [ Результат ] ─────────────────${NC}"
        echo
        echo -e " ${DARKGRAY}$(_mpad "Задержка:" $_cw)${NC} ${YELLOW}${latency}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Скорость загрузки:" $_cw)${NC} ${GREEN}${download}${NC}  ${DARKGRAY}пинг: ${dl_ping}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Скорость отправки:" $_cw)${NC} ${GREEN}${upload}${NC}  ${DARKGRAY}пинг: ${ul_ping}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Потеряно пакетов:" $_cw)${NC} ${WHITE}${loss}${NC}"
    else
        echo -e "${RED}Не удалось выполнить тест скорости${NC}"
        [ -n "$output" ] && echo -e "\n$output"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

run_services_check() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN} 🌍 Доступность популярных сервисов${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (bash <(curl -s "storage.umager.ru/checker_all_ru.sh") </dev/null > "$tmpfile" 2>&1) &
    show_spinner "Проверка доступности сервисов" "Диагностика доступности сервисов завершена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    _print_ipv4_info "$output"
    _print_checker_sections "$output"
    _print_ipv6_section "$output"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# ХЕЛПЕРЫ ДЛЯ ТЕСТОВ
# ═══════════════════════════════════════════════════
_country_name() {
    case "$1" in
        DE) echo "Германия" ;; RU) echo "Россия" ;;    US) echo "США" ;;
        NL) echo "Нидерланды" ;; GB) echo "Великобритания" ;; FR) echo "Франция" ;;
        FI) echo "Финляндия" ;; PL) echo "Польша" ;;   UA) echo "Украина" ;;
        KZ) echo "Казахстан" ;; TR) echo "Турция" ;;   JP) echo "Япония" ;;
        SG) echo "Сингапур" ;;  CN) echo "Китай" ;;    LV) echo "Латвия" ;;
        LT) echo "Литва" ;;     EE) echo "Эстония" ;;  SE) echo "Швеция" ;;
        NO) echo "Норвегия" ;;  DK) echo "Дания" ;;    CH) echo "Швейцария" ;;
        AT) echo "Австрия" ;;   IT) echo "Италия" ;;   ES) echo "Испания" ;;
        CZ) echo "Чехия" ;;     HU) echo "Венгрия" ;;  RO) echo "Румыния" ;;
        BG) echo "Болгария" ;;  HR) echo "Хорватия" ;; SK) echo "Словакия" ;;
        *) echo "$1" ;;
    esac
}

_svc_yn() {
    echo "$1" | sed 's/\bYes\b/Да/g; s/\bNo\b/Нет/g; s/\bRegion:/Регион:/g'
}

# Корректное выравнивание с учётом многобайтовой кириллицы:
# printf "%-Ns" считает байты, а не символы — _mpad компенсирует разницу
_mpad() {
    local s="$1" w="$2"
    local chars bytes
    chars=${#s}
    bytes=$(printf '%s' "$s" | wc -c)
    printf "%-$(( w + bytes - chars ))s" "$s"
}

# Выводит шапку IPv4 + провайдерскую инфо из вывода скрипта-чекера
_print_ipv4_info() {
    local output="$1"
    local raw_provider raw_cc ipv4_provider ipv4_country ipv4_city ipv4_asn
    raw_provider=$(echo "$output" | grep -oP '(?i)хостинг-провайдер:\s*\K.*' | head -1 | sed 's/\s*$//')
    raw_cc=$(echo "$raw_provider" | grep -oP '^[A-Z]{2}')
    if [ -n "$raw_cc" ]; then
        ipv4_provider=$(echo "$raw_provider" | sed "s/^$raw_cc/$(_country_name "$raw_cc")/")
    else
        ipv4_provider="$raw_provider"
    fi
    local raw_country
    raw_country=$(echo "$output" | grep -oP '(?i)Страна:\s*\K[A-Z]+' | head -1)
    ipv4_country=$(_country_name "$raw_country")
    ipv4_city=$(echo "$output" | grep -oP '(?i)Город:\s*\K.*' | head -1 | sed 's/\s*$//')
    ipv4_asn=$(echo "$output"  | grep -oP '(?i)ASN:\s*\K.*'   | head -1 | sed 's/\s*$//')

    local _cw=20
    echo -e "${DARKGRAY}──────────────── [ IPv4 ] ─────────────────${NC}"
    echo
    [ -n "$ipv4_provider" ] && echo -e " ${DARKGRAY}$(_mpad "Хостинг провайдер:" $_cw)${NC} ${WHITE}${ipv4_provider}${NC}"
    [ -n "$ipv4_country"  ] && echo -e " ${DARKGRAY}$(_mpad "Страна:" $_cw)${NC} ${WHITE}${ipv4_country}${NC}"
    [ -n "$ipv4_city"     ] && echo -e " ${DARKGRAY}$(_mpad "Город:" $_cw)${NC} ${WHITE}${ipv4_city}${NC}"
    [ -n "$ipv4_asn"      ] && echo -e " ${DARKGRAY}$(_mpad "ASN:" $_cw)${NC} ${WHITE}${ipv4_asn}${NC}"
    echo
}

# Выводит блоки секций из вывода чекера (строки типа ====[ Title ]====)
_print_checker_sections() {
    local output="$1"
    # Снимаем ANSI-коды; \r-overwrite: оставляем только последний кадр в строке
    local clean
    clean=$(echo "$output" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' | sed 's/.*\r//')

    # Проход 1: ищем максимальную длину имени сервиса для выравнивания колонки
    local max_name_len=0
    local _t _ts _tn
    while IFS= read -r _t; do
        echo "$_t" | grep -qP '=+\[.*\]=+' && continue
        echo "$_t" | grep -qP '^\s*=+\s*$'  && continue
        [[ -z "$(echo "$_t" | tr -d '[:space:]')" ]] && continue
        echo "$_t" | grep -q ':' || continue
        _ts=$(echo "$_t" | sed 's/->[[:space:]]*/  /g')
        _tn=$(echo "$_ts" | cut -d: -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ ${#_tn} -gt $max_name_len ] && max_name_len=${#_tn}
    done <<< "$clean"
    local col_w=$((max_name_len + 3))

    # Проход 2: вывод с выравниванием по колонке
    local in_section=false
    local first_section=true
    while IFS= read -r line; do
        # Заголовок секции: ===[ ... ]===
        if echo "$line" | grep -qP '=+\[.*\]=+'; then
            local title
            title=$(echo "$line" | grep -oP '\[.*?\]' | head -1)
            $first_section || echo
            echo -e "${DARKGRAY}──────────── ${title} ────────────${NC}"
            echo
            in_section=true
            first_section=false
            continue
        fi
        if $in_section; then
            # Конец секции — строка только из =
            if echo "$line" | grep -qP '^\s*=+\s*$'; then
                in_section=false; continue
            fi
            [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
            local svc_line svc_name svc_value
            svc_line=$(echo "$line" | sed 's/->[[:space:]]*/  /g; s/:[[:space:]]\{4,\}/: /g')
            svc_name=$(echo "$svc_line" | cut -d: -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            svc_value=$(echo "$svc_line" | cut -d: -f2- | sed 's/^[[:space:]:]*//' | sed 's/[[:space:]]*$//')
            svc_value=$(_svc_yn "$svc_value")
            # Цвет и форматирование значения
            local dv
            if [[ "$svc_value" =~ ^(Да|Yes)[[:space:]]*\(Регион:[[:space:]]*([A-Z]+)\) ]]; then
                dv="${GREEN}${BASH_REMATCH[1]}${NC} ${DARKGRAY}(Регион: ${GREEN}${BASH_REMATCH[2]}${NC}${DARKGRAY})${NC}"
            elif [[ "$svc_value" =~ ^(Да|Yes)$ ]]; then
                dv="${GREEN}${svc_value}${NC}"
            elif [[ "$svc_value" =~ ^(Нет|No)$ ]] || [[ "$svc_value" == *Failed* ]]; then
                dv="${RED}${svc_value}${NC}"
            elif [[ "$svc_value" =~ ^[A-Z]{2,4}$ ]]; then
                dv="${GREEN}${svc_value}${NC}"
            else
                dv="${WHITE}${svc_value}${NC}"
            fi
            echo -ne " ${DARKGRAY}$(printf "%-${col_w}s" "${svc_name}:")${NC}"
            echo -e "${dv}"
        fi
    done <<< "$clean"
}

# Выводит секцию IPv6 если IPv6 обнаружен в выводе чекера
_print_ipv6_section() {
    local output="$1"
    # Если явно написано что IPv6 не найден — не показываем блок
    if echo "$output" | grep -qi 'ipv6.*не обнаружен\|no.*ipv6\|ipv6.*not\|ipv6.*отсутствует'; then
        return
    fi
    # Если есть строки с IPv6 данными — показываем
    local ipv6_provider ipv6_country ipv6_city ipv6_asn
    ipv6_provider=$(echo "$output" | grep -oP '(?i)\[ipv6\].*хостинг-провайдер:\s*\K.*' | head -1 | sed 's/\s*$//')
    ipv6_country=$(echo "$output" | grep -oP '(?i)\[ipv6\].*страна:\s*\K[A-Z]+' | head -1)
    ipv6_city=$(echo "$output" | grep -oP '(?i)\[ipv6\].*город:\s*\K.*' | head -1 | sed 's/\s*$//')
    ipv6_asn=$(echo "$output" | grep -oP '(?i)\[ipv6\].*asn:\s*\K.*' | head -1 | sed 's/\s*$//')
    if [ -n "$ipv6_provider$ipv6_country$ipv6_city$ipv6_asn" ]; then
        echo
        echo -e "${DARKGRAY}──────────────── [ IPv6 ] ─────────────────${NC}"
        [ -n "$ipv6_provider" ] && echo -e " ${DARKGRAY}Хостинг провайдер:${NC} ${WHITE}${ipv6_provider}${NC}"
        [ -n "$ipv6_country"  ] && echo -e " ${DARKGRAY}Страна:${NC} ${WHITE}$(_country_name "$ipv6_country")${NC}"
        [ -n "$ipv6_city"     ] && echo -e " ${DARKGRAY}Город:${NC} ${WHITE}${ipv6_city}${NC}"
        [ -n "$ipv6_asn"      ] && echo -e " ${DARKGRAY}ASN:${NC} ${WHITE}${ipv6_asn}${NC}"
    fi
}

run_regional_check() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     🔒 Региональные ограничения${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (bash <(curl -s "storage.umager.ru/checker_inst_ru.sh") </dev/null > "$tmpfile" 2>&1) &
    show_spinner "Проверка региональных ограничений" "Диагностика региональных ограничений завершена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    _print_ipv4_info "$output"
    _print_checker_sections "$output"
    _print_ipv6_section "$output"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

run_geolocation() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}        📍 Геолокация IP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    # Запускаем скрипт геолокации в фоне с таймаутом 20 сек
    (
        command -v lscpu >/dev/null 2>&1 || apt-get install -y util-linux >/dev/null 2>&1
        echo "Y" | bash <(curl -fsSL --connect-timeout 8 --max-time 15 "https://storage.umager.ru/ipregion.sh")
    ) > "$tmpfile" 2>&1 &
    show_spinner "Определение геолокации IP" "Диагностика геолокации завершена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    # Очищаем ANSI-коды, \r, и строки от apt/системы
    local clean
    clean=$(echo "$output" \
        | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\r//g' \
        | grep -vP '^\s*(Reading package|Building dependency|Reading state|upgraded|newly installed|util-linux|No VM|Made with)')

    # Извлекаем IP и ASN из заголовка
    local geo_ip geo_asn
    geo_ip=$(echo "$clean" | grep -oP '^IPv4:\s*\K\S+' | head -1)
    geo_asn=$(echo "$clean" | grep -oP '^ASN:\s*\K.*' | head -1 | sed 's/\s*$//')

    if [ -z "$geo_ip" ]; then
        echo -e "${RED}Не удалось получить данные геолокации${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
        tput civis 2>/dev/null || true
        while true; do
            local _k=""
            IFS= read -rsn1 _k
            case "$_k" in
                $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
                "")      tput cnorm 2>/dev/null || true; return 0 ;;
            esac
        done
    fi

    # Проход 1: найти максимальную длину имени сервиса по всем таблицам
    local _max_svc=0 _in_tbl=false
    while IFS= read -r _l; do
        local _lt
        _lt=$(echo "$_l" | sed 's/^[[:space:]]*//')
        if [[ -z "$_lt" ]]; then
            $_in_tbl && _in_tbl=false; continue
        fi
        echo "$_lt" | grep -qP '^Service\s' && { _in_tbl=true; continue; }
        if $_in_tbl; then
            local _sn
            _sn=$(echo "$_l" | sed 's/[[:space:]]\{2,\}.*//' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            [ ${#_sn} -gt $_max_svc ] && _max_svc=${#_sn}
        fi
    done <<< "$clean"
    local col_w=$(( _max_svc + 3 ))

    # Заголовок IPv4/ASN
    echo -e "${DARKGRAY}──────────────── [ IPv4 ] ─────────────────${NC}"
    echo
    echo -e " ${DARKGRAY}$(_mpad "IPv4:" 5)${NC} ${WHITE}${geo_ip}${NC}"
    [ -n "$geo_asn" ] && echo -e " ${DARKGRAY}$(_mpad "ASN:" 5)${NC} ${WHITE}${geo_asn}${NC}"
    echo

    # Проход 2: парсим секции и таблицы
    local _in_tbl=false _first=true
    while IFS= read -r line; do
        local _t
        _t=$(echo "$line" | sed 's/^[[:space:]]*//')
        # Пустая строка: сбрасываем режим таблицы и пропускаем
        if [[ -z "$_t" ]]; then
            $_in_tbl && _in_tbl=false; continue
        fi
        # Пропускаем строки IPv4/ASN (уже показаны)
        echo "$_t" | grep -qP '^(IPv4|ASN):' && continue
        # Заголовок таблицы "Service  IPv4"
        if echo "$_t" | grep -qP '^Service\s'; then
            _in_tbl=true; continue
        fi
        if $_in_tbl; then
            local svc_name svc_val
            svc_name=$(echo "$line" | sed 's/[[:space:]]\{2,\}.*//' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            svc_val=$(echo "$line" | grep -oP '[[:space:]]{2,}\K\S.*' | head -1 | sed 's/[[:space:]]*$//')
            [[ -z "$svc_val" ]] && continue
            local vc="${GREEN}"
            [[ "$svc_val" =~ ^(N/A|null|-)$ ]] && vc="${DARKGRAY}"
            echo -e " ${WHITE}$(_mpad "${svc_name}:" $col_w)${NC} ${vc}${svc_val}${NC}"
            continue
        fi
        # Заголовок секции: Popular services / CDN services / GeoIP services
        if echo "$_t" | grep -qP '^[A-Za-z][A-Za-z0-9 ]+$'; then
            $_first || echo
            echo -e "${DARKGRAY}──────────── [ ${_t} ] ────────────${NC}"
            echo
            _first=false
        fi
    done <<< "$clean"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        tput civis 2>/dev/null || true
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# ОПТИМИЗАЦИЯ СЕРВЕРА
# ═══════════════════════════════════════════════════
manage_server_optimization() {
    while true; do
        tput civis 2>/dev/null || true
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   ⚙️  ОПТИМИЗАЦИЯ СЕРВЕРА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        show_arrow_menu "⚙️  Оптимизация сервера" \
            "💾  SWAP" \
            "🚀  BBR" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) manage_swap || break ;;
            1) manage_bbr || break ;;
            2) continue ;;
            3) return ;;
        esac
    done
}
