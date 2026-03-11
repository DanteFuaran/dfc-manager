# ═══════════════════════════════════════════════════
# FIREWALL (UFW)
# ═══════════════════════════════════════════════════
manage_ufw() {
    while true; do
        # Проверяем установлен ли ufw
        local ufw_installed=0
        command -v ufw >/dev/null 2>&1 && ufw_installed=1

        if [ "$ufw_installed" -eq 0 ]; then
            show_arrow_menu "🔥  Firewall (UFW)" \
                "🛡️   Установить Firewall (UFW)" \
                "──────────────────────────────────────" \
                "❌  Назад"
            local choice=$?
            [[ $choice -eq 255 ]] && return 0

            # Индекс 0 — установить ufw
            if [ "$choice" -eq 0 ]; then
                local _ufw_log
                _ufw_log=$(mktemp /tmp/ufw_install.XXXXXX)
                (apt-get install -y ufw 2>&1) > "$_ufw_log" &
                show_spinner "Установка UFW"
                if command -v ufw >/dev/null 2>&1; then
                    rm -f "$_ufw_log"
                    print_success "UFW успешно установлен"
                    echo
                    show_continue_prompt || return 1
                else
                    show_install_error "Не удалось установить UFW" "$_ufw_log"
                    rm -f "$_ufw_log"
                    return $?
                fi
                continue
            fi
            # Разделитель (index 1) или Назад (index 2)
            [ "$choice" -ge 1 ] && return 0
        else
            # Статус UFW
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}        🔥 FIREWALL (UFW)${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo

            local ufw_status
            ufw_status=$(ufw status 2>/dev/null | head -1)
            if echo "$ufw_status" | grep -q "active"; then
                print_success "UFW активен"
            else
                print_warning "UFW не активен"
            fi
            echo

            show_arrow_menu "🔥  Firewall (UFW)" \
                "📋  Показать открытые порты" \
                "➕  Открыть порт" \
                "➖  Удалить правило" \
                "🧹  Удалить все правила" \
                "──────────────────────────────────────" \
                "🗑️   Удалить Firewall (ufw)" \
                "──────────────────────────────────────" \
                "❌  Назад"
            local choice=$?
            [[ $choice -eq 255 ]] && return 0
        fi

        case $choice in
            0)
                # Показать открытые порты
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}     📋 ОТКРЫТЫЕ ПОРТЫ (UFW)${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                ufw status numbered 2>/dev/null | tail -n +4
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || return 1
                ;;
            1)
                # Открыть порт
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}        ➕ ОТКРЫТЬ ПОРТ${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo

                local ufw_port ufw_proto ufw_comment ufw_ip

                reading_inline "Порт (обязательно):" ufw_port
                if [ -z "$ufw_port" ] || ! [[ "$ufw_port" =~ ^[0-9]+$ ]]; then
                    print_error "Порт не указан или некорректен"
                    echo
                    show_continue_prompt || return 1
                    continue
                fi

                reading_inline "Протокол (tcp/пусто для any):" ufw_proto
                reading_inline "Комментарий (Enter для пропуска):" ufw_comment
                reading_inline "IP-адрес (Enter для всех):" ufw_ip

                echo

                # Формируем правило через массив аргументов (без eval, без проблем с пробелами)
                local cmd_args=("ufw" "allow")
                if [ -n "$ufw_ip" ]; then
                    cmd_args+=("from" "$ufw_ip")
                fi
                cmd_args+=("to" "any" "port" "$ufw_port")
                if [ -n "$ufw_proto" ]; then
                    cmd_args+=("proto" "$ufw_proto")
                fi
                if [ -n "$ufw_comment" ]; then
                    cmd_args+=("comment" "$ufw_comment")
                fi

                (
                    "${cmd_args[@]}" >/dev/null 2>&1
                ) &
                show_spinner "Открытие порта $ufw_port"

                print_success "Порт $ufw_port открыт"
                [ -n "$ufw_proto" ] && echo -e "  ${DARKGRAY}Протокол: ${WHITE}${ufw_proto}${NC}"
                [ -n "$ufw_ip" ] && echo -e "  ${DARKGRAY}Для IP: ${WHITE}${ufw_ip}${NC}"
                [ -n "$ufw_comment" ] && echo -e "  ${DARKGRAY}Комментарий: ${WHITE}${ufw_comment}${NC}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || return 1
                ;;
            2)
                # Удалить правило — остаёмся в этом меню после удаления или отмены
                while true; do
                    # Актуализируем список правил на каждой итерации
                    local rules=()
                    while IFS= read -r line; do
                        local rule_text
                        rule_text=$(echo "$line" | sed 's/^\[\s*[0-9]*\]\s*//')
                        [ -n "$rule_text" ] && rules+=("$rule_text")
                    done < <(ufw status numbered 2>/dev/null | grep '^\[')

                    if [ ${#rules[@]} -eq 0 ]; then
                        clear
                        echo -e "${BLUE}══════════════════════════════════════${NC}"
                        echo -e "${GREEN}       ➖ УДАЛИТЬ ПРАВИЛО${NC}"
                        echo -e "${BLUE}══════════════════════════════════════${NC}"
                        echo
                        print_warning "Нет правил для удаления"
                        echo
                        echo -e "${BLUE}══════════════════════════════════════${NC}"
                        show_continue_prompt || return 1
                        break
                    fi

                    # Формируем меню с кнопкой "Назад"
                    local menu_items=()
                    for r in "${rules[@]}"; do
                        menu_items+=("$r")
                    done
                    menu_items+=("──────────────────────────────────────")
                    menu_items+=("❌  Назад")

                    show_arrow_menu "➖  Удалить правило" "${menu_items[@]}"
                    local del_choice=$?

                    local total_rules=${#rules[@]}
                    # Пользователь выбрал разделитель или "Назад" — выходим из подменю
                    if [ "$del_choice" -ge "$total_rules" ]; then
                        break
                    fi

                    # Запрашиваем подтверждение — не покидаем подменю ни при каком ответе
                    echo
                    echo -e "${YELLOW}Удалить правило: ${WHITE}${rules[$del_choice]}${NC}"
                    echo
                    if ! confirm_action; then
                        # Esc — отмена, возвращаемся к списку правил без удаления
                        continue
                    fi

                    # Подтверждено — удаляем правило
                    local rule_num=$((del_choice + 1))
                    echo "y" | ufw delete "$rule_num" >/dev/null 2>&1
                    # Продолжаем цикл — список правил обновится автоматически
                done
                ;;
            3)
                # Удалить все правила
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}     🗑️  УДАЛИТЬ ВСЕ ПРАВИЛА${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                local rule_count
                rule_count=$(ufw status numbered 2>/dev/null | grep -c '^\[' || true)
                if [ "$rule_count" -eq 0 ]; then
                    print_warning "Нет правил для удаления"
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || return 1
                    continue
                fi
                echo -e "${YELLOW}Будет удалено правил: ${WHITE}${rule_count}${NC}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                if ! confirm_action; then
                    continue
                fi
                echo
                (
                    local cnt
                    cnt=$(ufw status numbered 2>/dev/null | grep -c '^\[' || true)
                    local i
                    for ((i=0; i<cnt; i++)); do
                        echo "y" | ufw delete 1 >/dev/null 2>&1
                    done
                ) &
                show_spinner "Удаление всех правил"
                print_success "Все правила удалены"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || return 1
                ;;
            4) continue ;;
            5)
                # Удалить UFW
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}      ❌  Удалить Firewall (UFW)${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                echo -e "${YELLOW}Вы уверены, что хотите удалить UFW?${NC}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                if ! confirm_action; then
                    continue
                fi
                echo
                (
                    ufw disable >/dev/null 2>&1 || true
                    apt-get purge -y ufw >/dev/null 2>&1
                    apt-get autoremove -y >/dev/null 2>&1
                ) &
                show_spinner "Удаление UFW"
                if ! command -v ufw >/dev/null 2>&1; then
                    print_success "UFW успешно удалён"
                else
                    print_error "Не удалось удалить UFW"
                fi
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || return 1
                ;;
            6) continue ;;
            7) return 0 ;;
        esac
    done
}
