# ═══════════════════════════════════════════════════
# ДОПОЛНИТЕЛЬНЫЕ ПРОГРАММЫ — ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════════
manage_extra_settings() {
    while true; do
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   🧩  ДОПОЛНИТЕЛЬНЫЕ ПРОГРАММЫ${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        show_arrow_menu "🧩  Дополнительные программы" \
            "🔥  Firewall (UFW)" \
            "🌐  WARP" \
            "🛡️   Fail2ban" \
            "📝  Logrotate" \
            "📊  Beszel (мониторинг)" \
            "📡  MTProto (Телеграм прокси)" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) manage_ufw || break ;;
            1) manage_warp || break ;;
            2) manage_fail2ban || break ;;
            3) manage_logrotate || break ;;
            4) manage_beszel || break ;;
            5) manage_mtproto || break ;;
            6) continue ;;
            7) return ;;
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
    echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}"
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
    stty -icanon -echo min 1 time 0 2>/dev/null || true
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
    local base="${1:-1337}"
    for port in "$base" 8443 8444 8445 9443 10443; do
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

# Записывает run.sh для контейнера
_mt_write_run_sh() {
    cat > "$1" << 'RUNSH'
#!/bin/bash
if [ ! -z "$DEBUG" ]; then set -x; fi
mkdir /data 2>/dev/null >/dev/null
RANDOM=$(printf "%d" "0x$(head -c4 /dev/urandom | od -t x1 -An | tr -d ' ')")
if [ -z "$WORKERS" ]; then WORKERS=2; fi
echo "#### Telegram Proxy"
SECRET_CMD=""
if [ ! -z "$SECRET" ]; then
  echo "[+] Using the explicitly passed secret: '$SECRET'."
elif [ -f /data/secret ]; then
  SECRET="$(cat /data/secret)"
  echo "[+] Using the secret in /data/secret: '$SECRET'."
else
  SECRET_COUNT="${SECRET_COUNT:-1}"
  echo "[+] No secret passed. Will generate $SECRET_COUNT random ones."
  SECRET="$(dd if=/dev/urandom bs=16 count=1 2>&1 | od -tx1 | head -n1 | tail -c +9 | tr -d ' ')"
  for pass in $(seq 2 $SECRET_COUNT); do
    SECRET="$SECRET,$(dd if=/dev/urandom bs=16 count=1 2>&1 | od -tx1 | head -n1 | tail -c +9 | tr -d ' ')"
  done
fi
if echo "$SECRET" | grep -qE '^[0-9a-fA-F]{32}(,[0-9a-fA-F]{32}){,15}$'; then
  SECRET="$(echo "$SECRET" | tr '[:upper:]' '[:lower:]')"
  SECRET_CMD="-S $(echo "$SECRET" | sed 's/,/ -S /g')"
  echo -- "$SECRET_CMD" > /data/secret_cmd
  echo "$SECRET" > /data/secret
else
  echo '[F] Bad secret format.'; exit 1
fi
TAG_CMD=""
if [[ ! -z "$TAG" ]]; then
  if echo "$TAG" | grep -qE '^[0-9a-fA-F]{32}$'; then
    TAG="$(echo "$TAG" | tr '[:upper:]' '[:lower:]')"
    TAG_CMD="-P $TAG"
  fi
fi
curl -s https://core.telegram.org/getProxyConfig -o /etc/telegram/backend.conf || { echo '[F] Cannot download proxy config.'; exit 2; }
CONFIG=/etc/telegram/backend.conf
IP="$(curl -s -4 "https://digitalresistance.dog/myIp")"
INTERNAL_IP="$(ip -4 route get 8.8.8.8 | grep '^8\.8\.8\.8\s' | grep -Po 'src\s+\d+\.\d+\.\d+\.\d+' | awk '{print $2}')"
[ -z "$IP" ] && { echo "[F] Cannot determine external IP."; exit 3; }
[ -z "$INTERNAL_IP" ] && { echo "[F] Cannot determine internal IP."; exit 4; }
echo "[*] External IP: $IP"
sleep 1
exec /usr/local/bin/mtproto-proxy -p 2398 -H 443 -M "$WORKERS" -C 60000 \
  --aes-pwd /etc/telegram/hello-explorers-how-are-you-doing \
  -u root $CONFIG --allow-skip-dh --nat-info "$INTERNAL_IP:$IP" \
  --http-stats $SECRET_CMD $TAG_CMD
RUNSH
    chmod +x "$1"
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
    volumes:
      - ./run.sh:/run.sh:ro
    environment:
      - SECRET=${PROXY_SECRET}
      - TAG=${PROXY_TAG}
COMPOSE
}

# Установка / переустановка MTProto (встроенная реализация)
# Шаги ввода: 1-домен, 2-порт, 3-секрет, 4-IP, 5-tag.  Esc → предыдущий шаг.
_mt_do_install() {
    set +e
    local PROXY_PORT PROXY_SECRET SERVER_IP FAKE_DOMAIN PROXY_TAG
    PROXY_PORT="1337"
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

    local _step=1 _secret_input="" _tag_input=""
    while true; do
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}       📦 Установка MTProto${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo

        case $_step in
            2) # Порт
                local _port_default="${PROXY_PORT:-$(_mt_find_free_port "1337")}"
                _mt_read_input PROXY_PORT "Порт прокси ${DARKGRAY}[${_port_default}]${NC}:" "$_port_default" \
                    && (( _step++ )) || (( _step-- ))
                ;;
            3) # Секрет
                echo -e "  ${DARKGRAY}Секрет — ключ шифрования подключения (передаётся клиентам в ссылке).${NC}"
                _mt_read_input _secret_input "Введите секрет ${DARKGRAY}[Enter для создания нового]${NC}:" "" \
                    && (( _step++ )) || (( _step-- ))
                ;;
            4) # IP/домен
                local _default_host="${SERVER_IP:-$(_mt_get_server_ip)}"
                _mt_read_input SERVER_IP "Домен или IP для ссылки подключения ${DARKGRAY}[${_default_host}]${NC}:" "$_default_host" \
                    && (( _step++ )) || (( _step-- ))
                ;;
            5) # Proxy Tag
                echo -e "  ${DARKGRAY}Proxy Tag — ID прокси для статистики в @MTProxybot.${NC}"
                echo -e "  ${DARKGRAY}Это${NC} ${YELLOW}НЕ секрет${DARKGRAY} выше! Можно оставить пустым.${NC}"
                _mt_read_input _tag_input "Proxy Tag ${DARKGRAY}[Enter для пропуска]${NC}:" "${PROXY_TAG}" \
                    && break || (( _step-- ))
                ;;
        esac
    done

    # Финализация введённых значений
    if [ -n "$_secret_input" ]; then
        PROXY_SECRET="$_secret_input"
    else
        PROXY_SECRET=$(_mt_generate_fake_tls_secret "$FAKE_DOMAIN")
    fi
    if [ "$_tag_input" = "$PROXY_SECRET" ]; then
        echo -e "  ${RED}⚠  Это значение совпадает с секретом — Tag очищен.${NC}"
        _tag_input=""
    fi
    PROXY_TAG="$_tag_input"
    echo

    # Подготавливаем файлы
    _mt_write_compose
    _mt_write_run_sh "${_MT_DIR}/run.sh"
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
    show_spinner "Запуск MTProto..." "MTProto запущен"

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${PROXY_PORT}/tcp" >/dev/null 2>&1 || true
    fi

    if _mt_running; then
        _mt_save_config
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        print_success "MTProto успешно установлен!"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        local _cw=12
        echo -e " ${DARKGRAY}$(_mpad "Домен/IP:" $_cw)${NC} ${WHITE}${SERVER_IP}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Порт:" $_cw)${NC} ${WHITE}${PROXY_PORT}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Секрет:" $_cw)${NC} ${YELLOW}${PROXY_SECRET}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Fake TLS:" $_cw)${NC} ${WHITE}${FAKE_DOMAIN}${NC}"
        [ -n "$PROXY_TAG" ] && echo -e " ${DARKGRAY}$(_mpad "Tag:" $_cw)${NC} ${WHITE}${PROXY_TAG}${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}🔗 Ссылка для Telegram:${NC}"
        echo -e "   ${GREEN}tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${NC}"
    else
        echo
        print_error "Контейнер не запустился. Логи:"
        docker logs "$_MT_CONTAINER" 2>&1 | tail -20 || true
    fi
    _mt_press_enter
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

    local _rs="${RED}● Не запущен${NC}"
    _mt_running && _rs="${GREEN}● Запущен${NC}"

    local _cw=12
    echo -e " ${DARKGRAY}$(_mpad "Статус:" $_cw)${NC} ${_rs}"
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Домен/IP:" $_cw)${NC} ${WHITE}${SERVER_IP:-}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Порт:" $_cw)${NC} ${WHITE}${PROXY_PORT:-}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Секрет:" $_cw)${NC} ${YELLOW}${PROXY_SECRET}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Fake TLS:" $_cw)${NC} ${WHITE}${FAKE_DOMAIN:-}${NC}"
    if [ -n "${PROXY_TAG:-}" ]; then
        echo -e " ${DARKGRAY}$(_mpad "Tag:" $_cw)${NC} ${WHITE}${PROXY_TAG}${NC}"
    else
        echo -e " ${DARKGRAY}$(_mpad "Tag:" $_cw)${NC} ${YELLOW}не задан${NC} ${DARKGRAY}(получить: @MTProxybot)${NC}"
    fi
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}🔗 Ссылка для Telegram:${NC}"
    echo -e "   ${GREEN}tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${NC}"
    _mt_press_enter
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

    tput civis 2>/dev/null || true
    trap 'tput cnorm 2>/dev/null; return 0' INT

    while true; do
        local _raw _active _uptime _dc_conns
        local _pid
        _pid=$(docker inspect --format '{{.State.Pid}}' "$_MT_CONTAINER" 2>/dev/null) || _pid=""
        _raw=""
        [ -n "$_pid" ] && _raw=$(nsenter -t "$_pid" -n curl -s --max-time 2 http://127.0.0.1:2398/stats 2>/dev/null || true)
        _uptime=$(echo "$_raw" | awk '$1=="uptime"{print $2; exit}')
        _uptime="${_uptime:-0}"
        _dc_conns=$(echo "$_raw" | awk '$1=="total_encrypted_connections"{print $2; exit}')
        _dc_conns="${_dc_conns:-0}"

        # Активные клиенты из /proc/net/tcp
        _active=$(docker exec "$_MT_CONTAINER" sh -c \
            'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null' 2>/dev/null \
            | awk 'FNR>1 && $4=="01" && $2~/:01BB$/{split($3,a,":"); ip=a[1]; if(!(ip in ips)){ips[ip]=1}} END{n=0; for(k in ips)n++; print n}' \
            2>/dev/null || echo "0")

        if [ -n "${PROXY_TAG:-}" ] && [ "$_active" -gt "$_max_sim" ] 2>/dev/null; then
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
        local _cv="${GREEN}"
        local _cval="$_active"
        if [ -z "${PROXY_TAG:-}" ]; then _cval="— (нужен Tag)"; _cv="${DARKGRAY}"; fi

        local _cw=22
        echo -e " ${WHITE}$(_mpad "Активных клиентов:" $_cw)${NC} ${_cv}${_cval}${NC}"
        echo -e " ${WHITE}$(_mpad "Макс одновременно:" $_cw)${NC} ${YELLOW}${_max_sim}${NC}"
        echo -e " ${WHITE}$(_mpad "К серверам Telegram:" $_cw)${NC} ${WHITE}${_dc_conns}${NC}"
        echo -e " ${WHITE}$(_mpad "Трафик (вх / исх):" $_cw)${NC} ${WHITE}${_net_io}${NC}"
        echo -e " ${WHITE}$(_mpad "Аптайм:" $_cw)${NC} ${WHITE}${_up_str}${NC}"
        echo
        echo -e "${DARKGRAY}Обновление каждые 5 сек • Ctrl+C для выхода${NC}"
        sleep 5
    done
}

# Сменить конфигурацию — делегируем mtproto (нужен read_input, generate_fake_tls_secret)
_mt_do_change_config() {
    if command -v mtproto >/dev/null 2>&1; then
        mtproto
    else
        echo -e "${RED}✖ MTProto не установлен. Сначала установите прокси.${NC}"
        _mt_press_enter
    fi
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

    echo -e "${YELLOW}Внимание: MTProto будет полностью удалён с сервера.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${DARKGRAY}  Enter: Подтвердить   Esc: Отмена${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; echo -e "${BLUE}ℹ  Удаление отменено${NC}"; _mt_press_enter; return ;;
            "")      break ;;
        esac
    done
    tput cnorm 2>/dev/null || true
    echo

    (if [ -d "$_MT_DIR" ]; then
        cd "$_MT_DIR" && docker compose down --remove-orphans >/dev/null 2>&1 || true
    fi
    docker rm -f "$_MT_CONTAINER" >/dev/null 2>&1 || true) &
    show_spinner "Остановка контейнера..." "Контейнер остановлен"

    (docker rmi "$_MT_IMAGE" >/dev/null 2>&1 || true
    rm -rf "$_MT_DIR" 2>/dev/null || true
    if command -v ufw >/dev/null 2>&1 && [ -n "${PROXY_PORT:-}" ]; then
        ufw delete allow "${PROXY_PORT}/tcp" >/dev/null 2>&1 || true
    fi
    rm -f /usr/local/bin/mtproto /usr/local/bin/mt 2>/dev/null || true
    rm -rf /usr/local/lib/mtproto 2>/dev/null || true) &
    show_spinner "Удаление остаточных файлов..." "Удаление остаточных файлов"

    echo
    echo -e "${GREEN}✅ MTProto полностью удалён${NC}"
    _mt_press_enter
}

manage_mtproto() {
    while true; do
        _mt_load_env
        local _installed=false _running=false
        _mt_installed && _installed=true
        _mt_running   && _running=true

        local _line1="📡 MTProto Proxy"
        local _l1_pad=$(( (38 - ${#_line1}) / 2 ))
        local _l1_prefix; printf -v _l1_prefix "%${_l1_pad}s" ""

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

        local _title="${_l1_prefix}${_line1}\n${_l2_prefix}${DARKGRAY}Статус: ${_stat_color}● ${_stat_word}${NC}"

        local -a _items=() _actions=()

        if [ "$_installed" = false ]; then
            _items+=("📦  Установить MTProto");     _actions+=("install")
        else
            _items+=("📦  Переустановить MTProto"); _actions+=("install")
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
            _items+=("──────────────────────────────────────"); _actions+=("sep")
            _items+=("🗑️   Удалить MTProto");                  _actions+=("uninstall")
        fi

        _items+=("──────────────────────────────────────"); _actions+=("sep")
        _items+=("⬅️   Назад");                             _actions+=("back")

        show_arrow_menu "$_title" "${_items[@]}"
        local _choice=$?
        [[ $_choice -eq 255 ]] && return

        local _action="${_actions[$_choice]:-sep}"
        case "$_action" in
            install)       _mt_do_install ;;
            stats)         _mt_do_stats ;;
            config)        _mt_do_config ;;
            change_config) _mt_do_change_config ;;
            start)         _mt_do_start ;;
            stop)          _mt_do_stop ;;
            restart)       _mt_do_restart ;;
            uninstall)     _mt_do_uninstall ;;
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
            0) run_speed_test ;;
            1) run_services_check ;;
            2) run_regional_check ;;
            3) run_geolocation ;;
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
        tar -xzf speedtest.tgz && \
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
    echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}"
    tput civis 2>/dev/null || true
    read -r
    tput cnorm 2>/dev/null || true
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
    echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}"
    tput civis 2>/dev/null || true
    read -r
    tput cnorm 2>/dev/null || true
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
    echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}"
    tput civis 2>/dev/null || true
    read -r
    tput cnorm 2>/dev/null || true
}

run_geolocation() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}        📍 Геолокация IP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    # Устанавливаем util-linux (нужен ipregion.sh) и запускаем скрипт в фоне
    (
        apt-get install -y util-linux >/dev/null 2>&1
        bash <(curl -s "storage.umager.ru/ipregion.sh") </dev/null
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
        echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}"
        tput civis 2>/dev/null || true
        read -r
        tput cnorm 2>/dev/null || true
        return
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
    echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}"
    tput civis 2>/dev/null || true
    read -r
    tput cnorm 2>/dev/null || true
}

# ═══════════════════════════════════════════════════
# ОПТИМИЗАЦИЯ СЕРВЕРА
# ═══════════════════════════════════════════════════
manage_server_optimization() {
    while true; do
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
