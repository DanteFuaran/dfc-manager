# ═══════════════════════════════════════════════
# УПРАВЛЕНИЕ ШАБЛОНОМ САЙТА-ЗАГЛУШКИ
# ═══════════════════════════════════════════════

manage_random_template() {
    while true; do
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🎨 СМЕНА ШАБЛОНА САЙТА-ЗАГЛУШКИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Показываем текущий шаблон
    if [ -f /var/www/.current_template ]; then
        local current_template
        current_template=$(cat /var/www/.current_template)
        echo -e "${WHITE}Текущий шаблон:${NC} ${YELLOW}${current_template}${NC}"
        if [ -f /var/www/.template_changed ]; then
            local changed_date
            changed_date=$(cat /var/www/.template_changed)
            echo -e "${DARKGRAY}Установлен: ${changed_date}${NC}"
        fi
        echo
    else
        echo -e "${YELLOW}Шаблон ещё не установлен${NC}"
        echo
    fi
    
    # Спрашиваем как применить шаблон
    show_arrow_menu "🎨 Выберите способ" \
        "🎲  Случайный шаблон" \
        "📋  Выбрать из списка" \
        "⬅️   Назад"
    local choice=$?
    [[ $choice -eq 255 ]] && return

    case $choice in
        0)
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}   🎲 СЛУЧАЙНЫЙ ШАБЛОН${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo
            randomhtml
            ;;
        1)
            show_arrow_menu "🎨 Выберите шаблон" \
                "🏢  NexCore - Корпоративный портал" \
                "💻  DevForge - Технологический хаб" \
                "☁️   Nimbus - Облачные сервисы" \
                "💳  PayVault - Финтех платформа" \
                "📚  LearnHub - Образовательная платформа" \
                "🎬  StreamBox - Медиа портал" \
                "🛒  ShopWave - E-commerce" \
                "🎮  NeonArena - Игровой портал" \
                "👥  ConnectMe - Социальная сеть" \
                "📊  DataPulse - Аналитический центр" \
                "₿  CryptoNex - Крипто биржа" \
                "✈️   WanderWorld - Туристическое агентство" \
                "💪  IronPulse - Фитнес платформа" \
                "📰  ВестникПРО - Новостной портал" \
                "🎵  SoundWave - Музыкальный сервис" \
                "🏠  HomeNest - Недвижимость" \
                "🍕  FastBite - Доставка еды" \
                "🚗  AutoElite - Автомобильный портал" \
                "🎨  Prisma Studio - Дизайн студия" \
                "💼  Vertex Advisory - Консалтинг центр" \
                "──────────────────────────────────────" \
                "⬅️   Назад"
            local template_choice=$?
            [[ $template_choice -eq 255 ]] && return

            if [ $template_choice -eq 21 ]; then
                return
            fi
            
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}   🎨 ПРИМЕНЕНИЕ ШАБЛОНА${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo
            
            apply_template $((template_choice + 1))
            ;;
        2)
            return
            ;;
    esac
    
    echo

    if docker ps --filter "name=remnawave-nginx" --format "{{.Names}}" 2>/dev/null | grep -q "remnawave-nginx"; then
        (
            cd "${DIR_NGINX}" 2>/dev/null
            docker compose restart nginx >/dev/null 2>&1
        ) &
        show_spinner "Применение изменений"
    fi

    print_success "Шаблон успешно изменён"
    echo
    show_continue_prompt || break
    done
}
