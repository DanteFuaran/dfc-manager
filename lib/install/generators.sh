# ═══════════════════════════════════════════════
# ГЕНЕРАТОРЫ
# ═══════════════════════════════════════════════

generate_password() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%' 2>/dev/null | head -c 24
}

generate_username() {
    openssl rand -base64 12 | tr -dc 'a-zA-Z' 2>/dev/null | head -c 8
}

generate_secret() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' 2>/dev/null | head -c 64
}

generate_webhook_secret() {
    openssl rand -hex 32
}

generate_admin_password() {
    # Генерация пароля: классы A-Z, a-z, 0-9; tr|head даёт SIGPIPE — stderr tr глушим (без «Broken pipe» в UI)
    local upper lower digits shufpart tail
    upper=$(LC_ALL=C tr -dc 'A-Z' </dev/urandom 2>/dev/null | head -c 8)
    lower=$(LC_ALL=C tr -dc 'a-z' </dev/urandom 2>/dev/null | head -c 8)
    digits=$(LC_ALL=C tr -dc '0-9' </dev/urandom 2>/dev/null | head -c 8)
    shufpart=$(echo "${upper}${lower}${digits}" | fold -w1 | shuf | tr -d '\n')
    tail=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c 8)
    printf '%s%s\n' "$shufpart" "$tail"
}

generate_admin_username() {
    # Генерация логина из случайного слова + цифр
    echo "admin$(openssl rand -hex 4)"
}

generate_cookie_key() {
    # Генерация случайного ключа для cookie-защиты панели (16 символов, буквы + цифры)
    local key
    key=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' 2>/dev/null | head -c 16)
    echo "$key"
}

get_cookie_from_nginx() {
    # Извлекаем COOKIE_NAME и COOKIE_VALUE из nginx.conf
    local nginx_conf="${DIR_NGINX}nginx.conf"
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
