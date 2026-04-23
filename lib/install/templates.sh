# ═══════════════════════════════════════════════
# ШАБЛОНЫ SELFSTEAL
# ═══════════════════════════════════════════════

# Список шаблонов: ID|Название
get_templates_list() {
    echo "1|NexCore - Корпоративный портал"
    echo "2|DevForge - Технологический хаб"
    echo "3|Nimbus - Облачные сервисы"
    echo "4|PayVault - Финтех платформа"
    echo "5|LearnHub - Образовательная платформа"
    echo "6|StreamBox - Медиа портал"
    echo "7|ShopWave - E-commerce"
    echo "8|NeonArena - Игровой портал"
    echo "9|ConnectMe - Социальная сеть"
    echo "10|DataPulse - Аналитический центр"
    echo "11|CryptoNex - Крипто биржа"
    echo "12|WanderWorld - Туристическое агентство"
    echo "13|IronPulse - Фитнес платформа"
    echo "14|ВестникПРО - Новостной портал"
    echo "15|SoundWave - Музыкальный сервис"
    echo "16|HomeNest - Недвижимость"
    echo "17|FastBite - Доставка еды"
    echo "18|AutoElite - Автомобильный портал"
    echo "19|Prisma Studio - Дизайн студия"
    echo "20|Vertex Advisory - Консалтинг центр"
}

# Применить конкретный шаблон (скачивание с GitHub)
apply_template() {
    local template_id=$1
    
    local template_data=$(get_templates_list | grep "^${template_id}|")
    if [ -z "$template_data" ]; then
        echo -e "${RED}✖${NC} Шаблон #${template_id} не найден"
        return 1
    fi
    
    IFS='|' read -r id name <<< "$template_data"
    
    echo ""

    # Создаём директорию если не существует
    mkdir -p /var/www/html/
    
    # Очищаем директорию (кроме метаданных и MT Proto connect-страницы)
    find /var/www/html/ -mindepth 1 -not -name '.current_template' -not -name '.template_changed' -not -name 'mtproto-connect.html' -delete 2>/dev/null
    
    # Скачиваем шаблон с GitHub (Contents API → raw HTML)
    local _api_url="https://api.github.com/repos/DanteFuaran/dfc-manager/contents/templates/${template_id}/index.html?ref=${SCRIPT_BRANCH}"

    if curl -fsSL --connect-timeout 15 --max-time 120 \
        -H "Accept: application/vnd.github.v3.raw" \
        "${_api_url}" -o /var/www/html/index.html; then
        echo "$name" > /var/www/.current_template
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > /var/www/.template_changed
        echo -e "${GREEN}✅${NC}  Установка шаблона: ${WHITE}${name}${NC}"
    else
        echo -e "${RED}✖${NC} Ошибка загрузки шаблона. Проверьте интернет-соединение."
        # Создаём заглушку на случай ошибки
        echo "<html><body><h1>Site under maintenance</h1></body></html>" > /var/www/html/index.html
        return 1
    fi
}

# Случайный шаблон
randomhtml() {
    local random_id=$((RANDOM % 20 + 1))
    apply_template "$random_id"
}
