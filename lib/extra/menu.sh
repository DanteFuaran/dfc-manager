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
    show_spinner "Запущен тест скорости сети" "Тест скорости сети завершён"
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
        echo -e "      ${DARKGRAY}Сервер подключения:${NC} ${WHITE}${server}${NC}"
        echo -e "      ${DARKGRAY}Провайдер:${NC} ${WHITE}${isp}${NC}"
        echo
        echo -e "      ${DARKGRAY}Задержка:${NC}            ${YELLOW}${latency}${NC}"
        echo -e "      ${DARKGRAY}Скорость Загрузки:${NC}   ${GREEN}${download}${NC} ${DARKGRAY}| Пинг: ${dl_ping}${NC}"
        echo -e "      ${DARKGRAY}Скорость Отправки:${NC}   ${GREEN}${upload}${NC} ${DARKGRAY}| Пинг: ${ul_ping}${NC}"
        echo -e "      ${DARKGRAY}Потеряно пакетов:${NC}    ${WHITE}${loss}${NC}"
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
    echo -e "${GREEN}   🌍 Доступность популярных сервисов${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (bash <(curl -s "storage.umager.ru/checker_all_ru.sh") > "$tmpfile" 2>&1) &
    show_spinner "Проверка доступности сервисов" "Проверка завершена"
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

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

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

    echo -e "${DARKGRAY}──────────────── [ IPv4 ] ─────────────────${NC}"
    [ -n "$ipv4_provider" ] && echo -e " ${DARKGRAY}Хостинг провайдер:${NC} ${WHITE}${ipv4_provider}${NC}"
    [ -n "$ipv4_country"  ] && echo -e " ${DARKGRAY}Страна:${NC} ${WHITE}${ipv4_country}${NC}"
    [ -n "$ipv4_city"     ] && echo -e " ${DARKGRAY}Город:${NC} ${WHITE}${ipv4_city}${NC}"
    [ -n "$ipv4_asn"      ] && echo -e " ${DARKGRAY}ASN:${NC} ${WHITE}${ipv4_asn}${NC}"
}

# Выводит блоки секций из вывода чекера (строки типа ====[ Title ]====)
_print_checker_sections() {
    local output="$1"
    local in_section=false
    while IFS= read -r line; do
        # Заголовок секции: ===[ ... ]===
        if echo "$line" | grep -qP '=+\[.*\]=+'; then
            local title
            title=$(echo "$line" | grep -oP '\[.*?\]' | head -1)
            echo
            echo -e "${DARKGRAY}────────────${title}────────────${NC}"
            in_section=true; continue
        fi
        if $in_section; then
            # Конец секции — строка только из =
            if echo "$line" | grep -qP '^\s*=+\s*$'; then
                echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
                in_section=false; continue
            fi
            [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
            echo -e "${WHITE}$(_svc_yn "$line")${NC}"
        fi
    done <<< "$output"
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
    (bash <(curl -s "storage.umager.ru/checker_inst_ru.sh") > "$tmpfile" 2>&1) &
    show_spinner "Проверка региональных ограничений" "Проверка завершена"
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

    # Автоматически установить util-linux если отсутствует
    if ! dpkg-query -W -f='${Status}' util-linux 2>/dev/null | grep -q "install ok installed"; then
        (apt-get install -y util-linux >/dev/null 2>&1) &
        show_spinner "Установка зависимостей" "Зависимости установлены"
        echo
    fi

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (bash <(curl -s "storage.umager.ru/ipregion.sh") > "$tmpfile" 2>&1) &
    show_spinner "Определение геолокации IP" "Геолокация определена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    # Парсим поля геолокации
    local geo_ip geo_country geo_region geo_city geo_isp geo_asn geo_org geo_tz geo_coord
    geo_ip=$(echo      "$output" | grep -oP '(?i)(ip\s*(address|addr)?:|your\s*ip:|IP:)\s*\K[\d.]+' | head -1)
    [ -z "$geo_ip" ] && geo_ip=$(echo "$output" | grep -oP '\b(\d{1,3}\.){3}\d{1,3}\b' | head -1)
    geo_country=$(echo "$output" | grep -oP '(?i)Страна[:\s]+\K[^\n]+|Country[:\s]+\K[^\n]+' | head -1 | sed 's/\s*$//')
    geo_region=$(echo  "$output" | grep -oP '(?i)Регион[:\s]+\K[^\n]+|Region[:\s]+\K[^\n]+' | head -1 | sed 's/\s*$//')
    geo_city=$(echo    "$output" | grep -oP '(?i)Город[:\s]+\K[^\n]+|City[:\s]+\K[^\n]+' | head -1 | sed 's/\s*$//')
    geo_isp=$(echo     "$output" | grep -oP '(?i)Провайдер[:\s]+\K[^\n]+|ISP[:\s]+\K[^\n]+|Provider[:\s]+\K[^\n]+' | head -1 | sed 's/\s*$//')
    geo_asn=$(echo     "$output" | grep -oP '(?i)ASN[:\s]+\K[^\n]+' | head -1 | sed 's/\s*$//')
    geo_org=$(echo     "$output" | grep -oP '(?i)Организация[:\s]+\K[^\n]+|Org(anization)?[:\s]+\K[^\n]+' | head -1 | sed 's/\s*$//')
    geo_tz=$(echo      "$output" | grep -oP '(?i)Часовой.*пояс[:\s]+\K[^\n]+|Timezone[:\s]+\K[^\n]+|TimeZone[:\s]+\K[^\n]+' | head -1 | sed 's/\s*$//')
    geo_coord=$(echo   "$output" | grep -oP '(?i)Коорд[^:]*:[\s]+\K[^\n]+|Coord[^:]*:[\s]+\K[^\n]+|Lat.*Lon[:\s]+\K[^\n]+' | head -1 | sed 's/\s*$//')

    if [ -n "$geo_ip$geo_country$geo_city$geo_isp" ]; then
        echo -e "${DARKGRAY}───────────────── [ Сервер ] ─────────────────${NC}"
        [ -n "$geo_ip"      ] && echo -e " ${DARKGRAY}IP адрес:${NC}            ${WHITE}${geo_ip}${NC}"
        [ -n "$geo_country" ] && echo -e " ${DARKGRAY}Страна:${NC}             ${WHITE}${geo_country}${NC}"
        [ -n "$geo_region"  ] && echo -e " ${DARKGRAY}Регион:${NC}             ${WHITE}${geo_region}${NC}"
        [ -n "$geo_city"    ] && echo -e " ${DARKGRAY}Город:${NC}              ${WHITE}${geo_city}${NC}"
        [ -n "$geo_isp"     ] && echo -e " ${DARKGRAY}Провайдер:${NC}         ${WHITE}${geo_isp}${NC}"
        [ -n "$geo_asn"     ] && echo -e " ${DARKGRAY}ASN:${NC}               ${WHITE}${geo_asn}${NC}"
        [ -n "$geo_org"     ] && echo -e " ${DARKGRAY}Организация:${NC}        ${WHITE}${geo_org}${NC}"
        [ -n "$geo_tz"      ] && echo -e " ${DARKGRAY}Часовой пояс:${NC}       ${WHITE}${geo_tz}${NC}"
        [ -n "$geo_coord"   ] && echo -e " ${DARKGRAY}Координаты:${NC}         ${WHITE}${geo_coord}${NC}"
    else
        # Фоллбек — показываем сырой вывод без escape-последовательностей
        echo "$output" | sed 's/\x1B\[[0-9;]*[mK]//g'
    fi

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
