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

# Установка / переустановка — делегируем внешнему скрипту
_mt_do_install() {
    if command -v mtproto >/dev/null 2>&1; then
        mtproto
    else
        cd /opt && bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-mtproto/refs/heads/main/mtproto-install.sh)
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
    show_spinner "Остановка и удаление контейнера..." "Контейнер удалён"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "         ${YELLOW}Удалить образ Docker?${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${DARKGRAY}  Enter: Удалить   Esc: Оставить${NC}"
    tput civis 2>/dev/null || true
    local _del_image=false
    while true; do
        local _k2=""
        IFS= read -rsn1 _k2
        case "$_k2" in
            $'\x1b') break ;;
            "")      _del_image=true; break ;;
        esac
    done
    tput cnorm 2>/dev/null || true
    if $_del_image; then
        (docker rmi "$_MT_IMAGE" >/dev/null 2>&1 || true) &
        show_spinner "Удаление образа..." "Образ удалён"
    fi

    rm -rf "$_MT_DIR" 2>/dev/null || true
    if command -v ufw >/dev/null 2>&1 && [ -n "${PROXY_PORT:-}" ]; then
        ufw delete allow "${PROXY_PORT}/tcp" >/dev/null 2>&1 || true
    fi
    # Удаляем симлинки и скрипт mtproto
    rm -f /usr/local/bin/mtproto /usr/local/bin/mt 2>/dev/null || true
    rm -rf /usr/local/lib/mtproto 2>/dev/null || true
    echo -e "${GREEN}✅ MTProto полностью удалён${NC}"
    _mt_press_enter
}

manage_mtproto() {
    while true; do
        _mt_load_env
        local _installed=false _running=false
        _mt_installed && _installed=true
        _mt_running   && _running=true

        local _status_line=""
        if   [ "$_running"   = true ]; then
            _status_line="\n${DARKGRAY}    Статус: ${GREEN}● Запущен${NC}"
        elif [ "$_installed" = true ]; then
            _status_line="\n${DARKGRAY}    Статус: ${YELLOW}● Остановлен${NC}"
        else
            _status_line="\n${DARKGRAY}    Статус: ${DARKGRAY}● Не установлен${NC}"
        fi

        local _title="  📡 MTProto Proxy${_status_line}"

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
