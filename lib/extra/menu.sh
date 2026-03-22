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
            "�️   Fail2ban" \
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
            5) install_mtproto || break ;;
            6) continue ;;
            7) return ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# УСТАНОВКА MTPROTO
# ═══════════════════════════════════════════════════
install_mtproto() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📡 MTProto (Телеграм прокси)${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    cd /opt && bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-mtproto/refs/heads/main/mtproto-install.sh)
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
        _tn=$(echo "$_ts" | cut -d: -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/ (.*$//')
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
            # Убираем хэш/ID в скобках в конце имени: "Name (HASH)" → "Name"
            svc_name=$(echo "$svc_line" | cut -d: -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/ (.*$//')
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
    echo -e "${GREEN}   🔒 Региональные ограничения${NC}"
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
    echo -e "${GREEN}   📍 Геолокация IP${NC}"
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
            echo -e " ${DARKGRAY}$(_mpad "${svc_name}:" $col_w)${NC} ${vc}${svc_val}${NC}"
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
