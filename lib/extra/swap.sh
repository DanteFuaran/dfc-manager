# ═══════════════════════════════════════════════════
# SWAP
# ═══════════════════════════════════════════════════
manage_swap() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BLUE}   💾 Управление SWAP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Определяем текущий объём RAM
    local ram_kb
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_mb=$((ram_kb / 1024))
    local ram_gb=$((ram_mb / 1024))

    # Определяем оптимальный размер SWAP
    local swap_size_gb
    if [ "$ram_mb" -le 2048 ]; then
        swap_size_gb=2
    elif [ "$ram_mb" -le 4096 ]; then
        swap_size_gb=2
    elif [ "$ram_mb" -le 8192 ]; then
        swap_size_gb=4
    else
        swap_size_gb=8
    fi

    echo -e "${DARKGRAY}RAM на сервере: ${WHITE}${ram_mb} MB (~${ram_gb} GB)${NC}"
    echo -e "${DARKGRAY}Рекомендуемый размер SWAP: ${WHITE}${swap_size_gb} GB${NC}"
    echo

    # Проверяем текущий SWAP
    local current_swap
    current_swap=$(swapon --show --noheadings 2>/dev/null)
    if [ -n "$current_swap" ]; then
        local swap_total
        swap_total=$(free -h | awk '/Swap:/ {print $2}')
        print_success "SWAP уже активен (${swap_total})"
        echo
        echo -e "${DARKGRAY}Текущие SWAP-устройства:${NC}"
        swapon --show 2>/dev/null
        echo

        show_arrow_menu "💾  Управление SWAP" \
            "💾  Пересоздать SWAP (${swap_size_gb} GB)" \
            "🗑️   Удалить SWAP" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return 0

        case $choice in
            0)
                # Удаляем текущий swap, потом создаём новый
                echo
                (
                    swapoff -a 2>/dev/null
                    rm -f /swapfile 2>/dev/null
                    sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null
                ) &
                show_spinner "Удаление текущего SWAP"
                ;;
            1)
                # Только удаляем
                echo
                if ! confirm_nav --delete "🗑️  Удаление SWAP"; then
                    print_error "Операция отменена"
                    sleep 2
                    return 0
                fi
                echo
                (
                    swapoff -a 2>/dev/null
                    rm -f /swapfile 2>/dev/null
                    sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null
                    sed -i '/vm.swappiness/d' /etc/sysctl.conf 2>/dev/null
                ) &
                show_spinner "Удаление SWAP"
                echo
                print_success "SWAP удалён"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || return 1
                return 0
                ;;
            2) return 0 ;;
            3) return 0 ;;
        esac
    else
        print_warning "SWAP не настроен на сервере"
        echo

        show_arrow_menu "💾  Управление SWAP" \
            "💾  Создать SWAP (${swap_size_gb} GB)" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return 0

        case $choice in
            0) ;; # продолжаем создание
            1) return 0 ;;
            2) return 0 ;;
        esac
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   💾 СОЗДАНИЕ SWAP (${swap_size_gb} GB)${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Проверяем свободное место
    local free_space_kb
    free_space_kb=$(df / --output=avail | tail -1)
    local needed_kb=$((swap_size_gb * 1024 * 1024))
    if [ "$free_space_kb" -lt "$needed_kb" ]; then
        print_error "Недостаточно места на диске для создания SWAP"
        echo -e "${DARKGRAY}Свободно: $((free_space_kb / 1024)) MB, требуется: $((needed_kb / 1024)) MB${NC}"
        echo
        show_continue_prompt || return 1
        return 0
    fi

    # Создаём swapfile
    (
        fallocate -l "${swap_size_gb}G" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$((swap_size_gb * 1024)) status=none 2>/dev/null
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile 2>/dev/null
    ) &
    show_spinner "Создание SWAP-файла (${swap_size_gb} GB)"

    # Добавляем в fstab если нет
    if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        print_success "Добавлено в /etc/fstab"
    fi

    # Настройка swappiness
    sysctl vm.swappiness=10 >/dev/null 2>&1
    if ! grep -q 'vm.swappiness' /etc/sysctl.conf 2>/dev/null; then
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
    else
        sed -i 's/vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
    fi
    print_success "Swappiness установлен на 10"

    # Проверяем результат
    if swapon --show | grep -q '/swapfile'; then
        echo
        print_success "SWAP (${swap_size_gb} GB) успешно создан и активирован"
    else
        echo
        print_error "Не удалось активировать SWAP"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 1
}
