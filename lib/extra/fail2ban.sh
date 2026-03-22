# ═══════════════════════════════════════════════════
# FAIL2BAN
# ═══════════════════════════════════════════════════
manage_fail2ban() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}         🛡️  FAIL 2 BAN${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local f2b_installed=false
    if command -v fail2ban-client >/dev/null 2>&1; then
        f2b_installed=true
        local f2b_status
        f2b_status=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
        if [ "$f2b_status" = "active" ]; then
            print_success "Fail2ban установлен и активен"
        else
            print_warning "Fail2ban установлен, но не запущен (${f2b_status})"
        fi

        # Показываем статистику
        echo
        echo -e "${DARKGRAY}Статус jail'ов:${NC}"
        fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://;s/,/\n/g' | while read -r jail; do
            jail=$(echo "$jail" | xargs)
            if [ -n "$jail" ]; then
                local banned
                banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
                echo -e "  ${WHITE}${jail}${NC}: ${YELLOW}${banned:-0}${NC} заблокировано"
            fi
        done
        echo

        show_arrow_menu "🛡️  Fail2ban" \
            "⚙️   Настройки" \
            "🔄  Перезапустить Fail2ban" \
            "🗑️   Удалить Fail2ban" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return 0

        case $choice in
            0)
                # Настройки Fail2ban
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}         ⚙️  НАСТРОЙКИ FAIL2BAN${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo

                # Читаем текущие значения из jail.local
                local cur_maxretry cur_bantime_sec cur_findtime_sec
                cur_maxretry=$(grep -m1 '^maxretry' /etc/fail2ban/jail.local 2>/dev/null | awk '{print $3}')
                cur_bantime_sec=$(grep -m1 '^bantime' /etc/fail2ban/jail.local 2>/dev/null | awk '{print $3}')
                cur_findtime_sec=$(grep -m1 '^findtime' /etc/fail2ban/jail.local 2>/dev/null | awk '{print $3}')
                cur_maxretry=${cur_maxretry:-5}
                local cur_bantime_min=$(( ${cur_bantime_sec:-3600} / 60 ))
                local cur_findtime_min=$(( ${cur_findtime_sec:-600} / 60 ))

                echo -e "${DARKGRAY}Текущие настройки SSH jail:${NC}"
                echo -e "  ${WHITE}Количество:${NC}   ${YELLOW}${cur_maxretry}${NC} попыток"
                echo -e "  ${WHITE}Длит. бана:${NC}   ${YELLOW}${cur_bantime_min}${NC} мин"
                echo -e "  ${WHITE}Окно поиска:${NC}  ${YELLOW}${cur_findtime_min}${NC} мин"
                echo

                local new_maxretry new_bantime_min new_findtime_min
                reading_inline "Количество попыток (сейчас ${cur_maxretry}):" new_maxretry
                if [ -z "$new_maxretry" ] || ! [[ "$new_maxretry" =~ ^[0-9]+$ ]]; then
                    new_maxretry=$cur_maxretry
                fi
                reading_inline "Длительность бана в минутах (сейчас ${cur_bantime_min}):" new_bantime_min
                if [ -z "$new_bantime_min" ] || ! [[ "$new_bantime_min" =~ ^[0-9]+$ ]]; then
                    new_bantime_min=$cur_bantime_min
                fi
                reading_inline "Окно поиска в минутах (сейчас ${cur_findtime_min}):" new_findtime_min
                if [ -z "$new_findtime_min" ] || ! [[ "$new_findtime_min" =~ ^[0-9]+$ ]]; then
                    new_findtime_min=$cur_findtime_min
                fi

                local new_bantime_sec=$(( new_bantime_min * 60 ))
                local new_findtime_sec=$(( new_findtime_min * 60 ))

                (
                    cat > /etc/fail2ban/jail.local <<JAIL_EOF
[DEFAULT]
bantime  = ${new_bantime_sec}
findtime = ${new_findtime_sec}
maxretry = ${new_maxretry}
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = ${new_maxretry}
JAIL_EOF
                    systemctl restart fail2ban >/dev/null 2>&1
                ) >/dev/null 2>&1 &
                wait
                
                echo
                echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
                echo
                echo -e "${GREEN}Настройки обновлены:${NC}"
                echo -e "  ${WHITE}Количество:${NC}   ${YELLOW}${new_maxretry}${NC} попыток"
                echo -e "  ${WHITE}Длит. бана:${NC}   ${YELLOW}${new_bantime_min}${NC} мин"
                echo -e "  ${WHITE}Окно поиска:${NC}  ${YELLOW}${new_findtime_min}${NC} мин"
                echo
                echo -e "${BLUE}════════════════════════════════${NC}"
                show_continue_prompt || return 1
                return 0
                ;;
            1)
                echo
                (
                    systemctl restart fail2ban >/dev/null 2>&1
                ) &
                show_spinner "Перезапуск Fail2ban"
                print_success "Fail2ban перезапущен"
                echo
                show_continue_prompt || return 1
                return 0
                ;;
            2)
                echo
                if ! confirm_action; then
                    print_error "Операция отменена"
                    sleep 2
                    return 0
                fi
                echo
                (
                    systemctl stop fail2ban >/dev/null 2>&1
                    systemctl disable fail2ban >/dev/null 2>&1
                    apt-get remove --purge -y fail2ban >/dev/null 2>&1
                    rm -rf /etc/fail2ban 2>/dev/null
                ) &
                show_spinner "Удаление Fail2ban"
                print_success "Fail2ban удалён"
                echo
                show_continue_prompt || return 1
                return 0
                ;;
            3) return 0 ;;
            4) return 0 ;;
        esac
    else
        echo -e "${YELLOW}⚠️  Fail2ban не установлен${NC}"
        echo
        echo -e "${DARKGRAY}Fail2ban защищает сервер от брутфорс-атак,${NC}"
        echo -e "${DARKGRAY}блокируя IP-адреса после нескольких неудачных попыток входа.${NC}"
        echo

        show_arrow_menu "🛡️  Fail2ban" \
            "📥  Установить Fail2ban" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return 0

        case $choice in
            0) ;; # продолжаем установку
            1) return 0 ;;
            2) return 0 ;;
        esac

        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   📥 УСТАНОВКА FAIL2BAN${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        # Установка
        local _f2b_log
        _f2b_log=$(mktemp /tmp/f2b_install.XXXXXX)
        (
            apt-get update -qq 2>&1
            apt-get install -y -qq fail2ban 2>&1
        ) > "$_f2b_log" &
        show_spinner "Установка Fail2ban"

        if ! command -v fail2ban-client >/dev/null 2>&1; then
            show_install_error "Не удалось установить Fail2ban" "$_f2b_log"
            rm -f "$_f2b_log"
            return $?
        fi
        rm -f "$_f2b_log"

        # Создаём jail.local для SSH
        cat > /etc/fail2ban/jail.local <<'JAIL_EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
JAIL_EOF
        print_success "Конфигурация SSH jail создана"

        # Включаем и запускаем
        (
            systemctl enable fail2ban >/dev/null 2>&1
            systemctl restart fail2ban >/dev/null 2>&1
        ) &
        show_spinner "Запуск Fail2ban"

        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            echo
            print_success "Fail2ban успешно установлен и запущен"
            echo
            echo -e "${DARKGRAY}Настройки SSH jail:${NC}"
            echo -e "  ${WHITE}Количество:${NC}   5 попыток"
            echo -e "  ${WHITE}Длит. бана:${NC}   60 мин"
            echo -e "  ${WHITE}Окно поиска:${NC}  10 мин"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || return 1
        else
            local _svc_log
            _svc_log=$(mktemp /tmp/f2b_service.XXXXXX)
            journalctl -u fail2ban --no-pager -n 30 > "$_svc_log" 2>/dev/null
            show_install_error "Fail2ban установлен, но не удалось запустить" "$_svc_log"
            rm -f "$_svc_log"
            return $?
        fi
    fi
}
