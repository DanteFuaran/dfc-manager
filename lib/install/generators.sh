# ═══════════════════════════════════════════════
# ГЕНЕРАТОРЫ
# ═══════════════════════════════════════════════

generate_password() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%' | head -c 24
}

generate_db_password() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32
}

generate_username() {
    openssl rand -base64 12 | tr -dc 'a-zA-Z' | head -c 8
}

generate_secret() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64
}

generate_webhook_secret() {
    openssl rand -hex 32
}

generate_admin_password() {
    # Генерация пароля минимум 24 символа с заглавными, строчными буквами и цифрами
    local upper=$(tr -dc 'A-Z' < /dev/urandom | head -c 8)
    local lower=$(tr -dc 'a-z' < /dev/urandom | head -c 8)
    local digits=$(tr -dc '0-9' < /dev/urandom | head -c 8)
    # Перемешиваем и добавляем ещё символов для длины
    echo "${upper}${lower}${digits}" | fold -w1 | shuf | tr -d '\n' && tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8
}

generate_admin_username() {
    # Генерация логина из случайного слова + цифр
    echo "admin$(openssl rand -hex 4)"
}

generate_cookie_key() {
    # Генерация случайного ключа для cookie-защиты панели (32 символа, буквы + цифры)
    local key
    key=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32)
    echo "$key"
}

get_cookie_from_nginx() {
    # Извлекаем COOKIE_NAME и COOKIE_VALUE из nginx.conf
    local nginx_conf="/opt/remnawave/nginx.conf"
    if [ ! -f "$nginx_conf" ]; then
        return 1
    fi
    COOKIE_NAME=$(grep -oP '~\*\K[^=]+(?==[^"]+"\s+1)' "$nginx_conf" | head -1)
    COOKIE_VALUE=$(grep -oP '~\*[^=]+=\K[^"]+(?="\s+1)' "$nginx_conf" | head -1)
    if [ -z "$COOKIE_NAME" ] || [ -z "$COOKIE_VALUE" ]; then
        return 1
    fi
    return 0
}
