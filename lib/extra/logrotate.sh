# ═══════════════════════════════════════════════════
# LOGROTATE
# ═══════════════════════════════════════════════════
manage_logrotate() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}          📝 LOGROTATE${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Docker log settings
    local docker_max_size docker_max_file
    docker_max_size=$(grep -oP '"max-size"\s*:\s*"\K[^"]+' /etc/docker/daemon.json 2>/dev/null)
    docker_max_file=$(grep -oP '"max-file"\s*:\s*"\K[^"]+' /etc/docker/daemon.json 2>/dev/null)
    docker_max_size=${docker_max_size:-не настроено}
    docker_max_file=${docker_max_file:-не настроено}

    # Текущий cron интервал (если настроен)
    local cur_hours="не настроено"
    if [ -f /etc/cron.d/logrotate-custom ]; then
        local cron_h
        cron_h=$(grep -oP '^\*/\K[0-9]+' /etc/cron.d/logrotate-custom 2>/dev/null)
        if [ -n "$cron_h" ]; then
            cur_hours="${cron_h}ч"
        fi
    fi

    echo -e "${DARKGRAY}Системные логи:${NC}"
    echo -e "  ${WHITE}Ротация каждые${NC}: ${YELLOW}${cur_hours}${NC}"
    echo
    echo -e "${DARKGRAY}Docker логи (daemon.json):${NC}"
    echo -e "  ${WHITE}max-size${NC}: ${YELLOW}${docker_max_size}${NC}"
    echo -e "  ${WHITE}max-file${NC}: ${YELLOW}${docker_max_file}${NC}"
    echo

    show_arrow_menu "📝  Logrotate" \
        "📝  Настроить ротацию системных логов" \
        "🐳  Настроить ротацию Docker логов" \
        "──────────────────────────────────────" \
        "⬅️  Назад"
    local choice=$?
    [[ $choice -eq 255 ]] && return 0

    case $choice in
        0)
            # Ротация системных логов
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}     📝 СИСТЕМНЫЕ ЛОГИ${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo

            echo -e "${DARKGRAY}Как часто делать ротацию логов:${NC}"
            echo

            show_arrow_menu "⏱️  Частота ротации" \
                "  1 час" \
                "  2 часа" \
                "  3 часа" \
                "  6 часов" \
                " 12 часов" \
                " 24 часа"
            local freq_choice=$?

            local rotate_hours
            case $freq_choice in
                0) rotate_hours=1 ;;
                1) rotate_hours=2 ;;
                2) rotate_hours=3 ;;
                3) rotate_hours=6 ;;
                4) rotate_hours=12 ;;
                5) rotate_hours=24 ;;
                *) return 0 ;;
            esac

            echo
            local keep_count
            reading_inline "Сколько ротаций хранить (по умолчанию 7):" keep_count
            if [ -z "$keep_count" ] || ! [[ "$keep_count" =~ ^[0-9]+$ ]]; then
                keep_count=7
            fi

            echo
            (
                # Устанавливаем rotate count в logrotate.conf
                sed -i "s/^\s*rotate\s\+[0-9]*/rotate ${keep_count}/" /etc/logrotate.conf 2>/dev/null
                # Добавляем compress если не стоит
                if ! grep -q '^\s*compress' /etc/logrotate.conf 2>/dev/null; then
                    sed -i '/^\s*rotate/a compress' /etc/logrotate.conf 2>/dev/null
                fi
                # Создаём cron-задачу для ротации каждые N часов
                cat > /etc/cron.d/logrotate-custom <<CRON_EOF
*/${rotate_hours} * * * * root /usr/sbin/logrotate /etc/logrotate.conf >/dev/null 2>&1
CRON_EOF
                chmod 644 /etc/cron.d/logrotate-custom
                # Отключаем стандартный daily cron для logrotate чтобы не дублировать
                [ -f /etc/cron.daily/logrotate ] && chmod -x /etc/cron.daily/logrotate 2>/dev/null
            ) &
            show_spinner "Применение настроек"
            echo
            print_success "Ротация: каждые ${rotate_hours}ч, хранить ${keep_count} ротаций"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || return 1
            ;;
        1)
            # Ротация Docker логов
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}     🐳 DOCKER ЛОГИ${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo

            echo -e "${DARKGRAY}Максимальный размер одного лог-файла:${NC}"
            echo

            show_arrow_menu "📦  Размер лога" \
                " 10m" \
                " 20m" \
                " 50m" \
                "100m" \
                "200m" \
                "500m"
            local size_choice=$?

            local log_size
            case $size_choice in
                0) log_size="10m" ;;
                1) log_size="20m" ;;
                2) log_size="50m" ;;
                3) log_size="100m" ;;
                4) log_size="200m" ;;
                5) log_size="500m" ;;
                *) return 0 ;;
            esac

            echo
            local log_files
            reading_inline "Количество лог-файлов (сейчас ${docker_max_file}):" log_files
            if [ -z "$log_files" ] || ! [[ "$log_files" =~ ^[0-9]+$ ]]; then
                log_files=${docker_max_file:-3}
            fi

            echo
            (
                mkdir -p /etc/docker
                cat > /etc/docker/daemon.json <<DOCKER_EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "${log_size}",
        "max-file": "${log_files}"
    }
}
DOCKER_EOF
                systemctl restart docker >/dev/null 2>&1
            ) &
            show_spinner "Применение настроек Docker"
            echo
            print_success "Docker логи: max-size=${log_size}, max-file=${log_files}"
            echo -e "${YELLOW}⚠️  Docker перезапущен. Контейнеры будут перезапущены автоматически.${NC}"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || return 1
            ;;
        2) return 0 ;;
        3) return 0 ;;
    esac
}
