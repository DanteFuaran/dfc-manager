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
            "⚡  Speed Test (Тест соединения)" \
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
    echo -e "${GREEN}   ⚡ Speed Test (Тест соединения)${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    (
        cd /tmp && \
        curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz" -o speedtest.tgz && \
        tar -xzf speedtest.tgz && \
        ./speedtest --accept-license --accept-gdpr && \
        rm -rf speedtest.tgz speedtest
    )
    echo
    echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}"
    read -r
}

run_services_check() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌍 Доступность популярных сервисов${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    bash <(curl -s storage.umager.ru/checker_all_ru.sh)
    echo
    echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}"
    read -r
}

run_regional_check() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔒 Региональные ограничения${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    bash <(curl -s storage.umager.ru/checker_inst_ru.sh)
    echo
    echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}"
    read -r
}

run_geolocation() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📍 Геолокация IP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    bash <(curl -s storage.umager.ru/ipregion.sh)
    echo
    echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}"
    read -r
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
