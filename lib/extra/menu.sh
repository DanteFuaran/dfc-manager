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


# MTProto — вынесено в lib/extra/mtproto.sh
source "${SCRIPT_DIR}/lib/extra/mtproto.sh"


# ═══════════════════════════════════════════════════
# ТЕСТИРОВАНИЕ СЕРВЕРА
# ═══════════════════════════════════════════════════
manage_server_testing() {
    while true; do
        tput civis 2>/dev/null || true
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${BLUE}   🧪  ТЕСТИРОВАНИЕ СЕРВЕРА${NC}"
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
    echo -e "${BLUE}        ⚡ Тест скорости сети${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local _arch _pkg
    _arch=$(uname -m)
    case "$_arch" in
        x86_64)          _pkg="ookla-speedtest-1.2.0-linux-x86_64.tgz" ;;
        aarch64|arm64) _pkg="ookla-speedtest-1.2.0-linux-aarch64.tgz" ;;
        *)
            echo -e "${RED}Тест Speedtest CLI поддерживается только на x86_64 и aarch64.${NC}"
            echo -e "${DARKGRAY}Текущая архитектура: ${_arch}${NC}"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt "Выход"
            return $?
            ;;
    esac

    local tmpfile
    tmpfile=$(mktemp /tmp/speedtest_result.XXXXXX)
    (
        cd /tmp && \
        curl -fsSL --connect-timeout 15 --max-time 180 \
            "https://install.speedtest.net/app/cli/${_pkg}" -o speedtest.tgz && \
        tar -xzf speedtest.tgz
     ) </dev/null &    if ! show_spinner --step --chain "Подготовка инструмента тестирования"; then
        rm -f "$tmpfile"
        echo
        echo -e "${RED}Не удалось скачать или распаковать Speedtest CLI.${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt "Выход"
        return $?
    fi

    (
        cd /tmp && \
        ./speedtest --accept-license --accept-gdpr 2>/dev/null > "$tmpfile" && \
        rm -rf speedtest.tgz speedtest
     ) </dev/null &    if ! show_spinner --step --chain "Запущен тест скорости сети"; then
        rm -f "$tmpfile"
        echo
        echo -e "${RED}Не удалось выполнить тест скорости${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt "Выход"
        return $?
    fi

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    # Парсим результат (Idle Latency — полная строка с jitter/low/high при наличии)
    local server isp latency download dl_ping upload ul_ping loss
    server=$(echo "$output" | grep -oP 'Server:\s*\K.*?(?=\s*\(id)' | sed 's/\s*$//')
    isp=$(echo "$output" | grep -oP 'ISP:\s*\K.*' | sed 's/\s*$//')
    latency=$(echo "$output" | grep -oP 'Idle Latency:\s*\K.*' | head -1 | sed 's/\s*$//')
    [ -z "$latency" ] && latency=$(echo "$output" | grep -oP 'Latency:\s*\K.*' | head -1 | sed 's/\s*$//')
    download=$(echo "$output" | grep -oP 'Download:\s*\K[\d.]+\s*\S+' | sed 's/\s*$//')
    dl_ping=$(echo "$output" | sed -n '/Download:/{n;s/^\s*//;p;}' | grep -oP '^[\d.]+\s*ms' | sed 's/\s*$//')
    upload=$(echo "$output" | grep -oP 'Upload:\s*\K[\d.]+\s*\S+' | sed 's/\s*$//')
    ul_ping=$(echo "$output" | sed -n '/Upload:/{n;s/^\s*//;p;}' | grep -oP '^[\d.]+\s*ms' | sed 's/\s*$//')
    loss=$(echo "$output" | grep -oP 'Packet Loss:\s*\K.*' | sed 's/\s*$//')

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}        ⚡ Тест скорости сети${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if [ -n "$server" ]; then
        echo -e "${GREEN}✅ Диагностика сети завершёна!${NC}"
        echo
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
    show_continue_prompt "Выход"
    return $?
}

run_services_check() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE} 🌍 Доступность популярных сервисов${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (
        _chk=$(mktemp /tmp/dfc_checker_all.XXXXXX.sh)
        curl -fsSL --connect-timeout 10 --max-time 180 "https://storage.umager.ru/checker_all_ru.sh" -o "$_chk" 2>/dev/null \
            && bash "$_chk" </dev/null > "$tmpfile" 2>&1
        rm -f "$_chk"
     ) </dev/null &    show_spinner "Проверка доступности сервисов" "Диагностика доступности сервисов завершена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    _print_ipv4_info "$output"
    _print_checker_sections "$output"
    _print_ipv6_section "$output"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt "Выход"
    return $?
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

# Фолбэк без IPRegion: только базовая геолокация (ip-api / ipwho.is).
_dfc_geolocation_fallback() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 <<'PY'
import json, sys, urllib.request

def emit(q, asn, country, cc, city, isp, org):
    print(f"IPv4: {q}")
    print(f"ASN: {asn}")
    print()
    print("Details")
    print()
    print("Service  IPv4")
    print(f"Страна   {country} ({cc})")
    print(f"Город   {city}")
    print(f"Провайдер   {isp}")
    print(f"Организация   {org}")

def main():
    try:
        req = urllib.request.Request(
            "http://ip-api.com/json/?fields=status,message,query,country,countryCode,city,isp,org,as,asname&lang=ru",
            headers={"User-Agent": "dfc-manager/1.0"},
        )
        with urllib.request.urlopen(req, timeout=20) as r:
            d = json.load(r)
        if d.get("status") == "success":
            q = d.get("query") or ""
            asn = d.get("as") or d.get("asname") or ""
            emit(
                q,
                asn,
                d.get("country") or "",
                d.get("countryCode") or "",
                d.get("city") or "",
                d.get("isp") or "",
                d.get("org") or "",
            )
            return
    except Exception:
        pass
    try:
        req = urllib.request.Request("https://ipwho.is/", headers={"User-Agent": "dfc-manager/1.0"})
        with urllib.request.urlopen(req, timeout=20) as r:
            d = json.load(r)
        if d.get("success"):
            conn = d.get("connection") or {}
            asn_n = conn.get("asn")
            org = conn.get("org") or ""
            asn_s = f"AS{asn_n} {org}" if asn_n else org
            emit(
                d.get("ip") or "",
                asn_s,
                d.get("country") or "",
                d.get("country_code") or "",
                d.get("city") or "",
                conn.get("isp") or "",
                org,
            )
            return
    except Exception:
        pass
    sys.exit(1)

if __name__ == "__main__":
    main()
PY
}

# Одна секции таблицы (Popular / CDN / GeoIP) в формате run_geolocation.
_dfc_emit_ipregion_section() {
    local title="$1" json="$2" key="$3"
    local cnt
    cnt=$(echo "$json" | jq -r --arg k "$key" '(.results[$k] // []) | length') || return 0
    [ "${cnt:-0}" -eq 0 ] && return 0

    echo "$title"
    echo ""
    echo "Service  IPv4"
    echo "$json" | jq -r --arg k "$key" \
        '.results[$k][] | "\(.service)  \(.ipv4 // .ipv6 // "N/A" | tostring)"'
    echo ""
}

# JSON из ipregion.sh -j → текст для парсера геолокации (ASN — ip-api по IPv4).
_dfc_emit_geo_report_from_ipregion_json() {
    local json="$1"
    local ip asn
    ip=$(echo "$json" | jq -r '.ipv4 // empty')
    [ -n "$ip" ] || return 1

    asn=$(curl -fsS --connect-timeout 8 --max-time 22 \
        "http://ip-api.com/json/${ip}?fields=status,as,asname&lang=ru" 2>/dev/null \
        | jq -r 'if .status == "success" then (.as // .asname // "") else "" end' 2>/dev/null)
    [ -z "$asn" ] && asn="—"

    printf 'IPv4: %s\n' "$ip"
    printf 'ASN: %s\n' "$asn"
    echo ""

    _dfc_emit_ipregion_section "Popular services" "$json" "custom"
    _dfc_emit_ipregion_section "CDN services" "$json" "cdn"
    _dfc_emit_ipregion_section "GeoIP services" "$json" "primary"
}

# Полный отчёт: локальный lib/extra/ipregion.sh в режиме -j (JSON в stdout, без спиннера).
_dfc_geolocation_text() {
    if ! command -v jq >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y -qq \
            -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
            jq util-linux >/dev/null 2>&1 || { _dfc_geolocation_fallback; return; }
    fi

    local _menu_dir _scr _json
    _menu_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _scr="$_menu_dir/ipregion.sh"
    if [ ! -f "$_scr" ]; then
        _dfc_geolocation_fallback
        return
    fi

    # -j: только JSON; -4: IPv4; -t: таймаут curl на сервис внутри ipregion.sh
    _json=$(bash "$_scr" -j -t 12 -4 2>/dev/null) || true

    if [ -z "$_json" ] || ! echo "$_json" | jq -e '.ipv4 != null and .ipv4 != ""' >/dev/null 2>&1; then
        _dfc_geolocation_fallback
        return
    fi

    _dfc_emit_geo_report_from_ipregion_json "$_json" || _dfc_geolocation_fallback
}

run_regional_check() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}     🔒 Региональные ограничения${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (
        _chk=$(mktemp /tmp/dfc_checker_inst.XXXXXX.sh)
        curl -fsSL --connect-timeout 10 --max-time 180 "https://storage.umager.ru/checker_inst_ru.sh" -o "$_chk" 2>/dev/null \
            && bash "$_chk" </dev/null > "$tmpfile" 2>&1
        rm -f "$_chk"
     ) </dev/null &    show_spinner "Проверка региональных ограничений" "Диагностика региональных ограничений завершена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    _print_ipv4_info "$output"
    _print_checker_sections "$output"
    _print_ipv6_section "$output"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt "Выход"
    return $?
}

run_geolocation() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}        📍 Геолокация IP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (
        _dfc_geolocation_text
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
        show_continue_prompt "Выход"
        return $?
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
            local _vnorm
            _vnorm=$(printf '%s' "$svc_val" | tr '[:upper:]' '[:lower:]')
            if [[ "$_vnorm" == 'n/a' || "$_vnorm" == 'null' || "$_vnorm" == '-' || "$_vnorm" == 'none' || "$_vnorm" == 'undefined' || "$svc_val" == '—' ]]; then
                vc="${DARKGRAY}"
            fi
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
    show_continue_prompt "Выход"
    return $?
}

# ═══════════════════════════════════════════════════
# ОПТИМИЗАЦИЯ СЕРВЕРА
# ═══════════════════════════════════════════════════
manage_server_optimization() {
    while true; do
        tput civis 2>/dev/null || true
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${BLUE}   ⚙️  ОПТИМИЗАЦИЯ СЕРВЕРА${NC}"
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
