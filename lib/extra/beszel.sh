# ═══════════════════════════════════════════════════
# BESZEL — МОНИТОРИНГ СЕРВЕРА
# ═══════════════════════════════════════════════════

DIR_BESZEL="/opt/beszel/"
DIR_BESZEL_AGENT="/opt/beszel-agent/"

# HTTP-вызов через python3
# Использование: _beszel_http METHOD url [body] [auth_token]
_beszel_http() {
    local method="$1" url="$2" body="${3:-}" token="${4:-}"
    _BZURL="$url" _BZBODY="$body" _BZMETHOD="$method" _BZTOKEN="$token" \
    python3 - <<'PYEOF' 2>/dev/null
import urllib.request, urllib.error, os, sys
url    = os.environ.get('_BZURL','')
body   = os.environ.get('_BZBODY','')
method = os.environ.get('_BZMETHOD','GET')
token  = os.environ.get('_BZTOKEN','')
req = urllib.request.Request(url, method=method)
req.add_header('Content-Type', 'application/json')
if token:
    req.add_header('Authorization', token)
data = body.encode() if body else None
try:
    with urllib.request.urlopen(req, data=data, timeout=15) as r:
        sys.stdout.write(r.read().decode())
        sys.exit(0)
except urllib.error.HTTPError as e:
    sys.stdout.write(e.read().decode())
    sys.exit(e.code)
except Exception as e:
    sys.stderr.write(str(e)+'\n')
    sys.exit(1)
PYEOF
}

# Ждёт, пока Beszel API поднимется (до 60 сек)
_beszel_wait_api() {
    local i
    for i in $(seq 1 30); do
        if _beszel_http GET "http://127.0.0.1:8090/api/beszel/first-run" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

# Восстанавливает first-run состояние Beszel после авто-настройки агента.
# Удаляет временного пользователя и возвращает суперадмина _@b.b.
# Аргументы: <hub_url> <email> <password>
_beszel_restore_firstrun() {
    local HUB_URL="$1" EMAIL="$2" PASS="$3"
    _BZ_HUB="$HUB_URL" _BZ_EMAIL="$EMAIL" _BZ_PASS="$PASS" \
    python3 - <<'PYEOF' 2>/dev/null
import urllib.request, urllib.parse, urllib.error, json, os, secrets
hub   = os.environ['_BZ_HUB']
email = os.environ['_BZ_EMAIL']
pw    = os.environ['_BZ_PASS']

def api(method, path, body=None, token=None):
    req = urllib.request.Request(hub + path, method=method)
    req.add_header('Content-Type', 'application/json')
    if token:
        req.add_header('Authorization', token)
    data = json.dumps(body).encode() if body else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=10) as r:
            return json.loads(r.read().decode() or '{}')
    except Exception:
        return {}

# Авторизуемся как суперпользователь
su = api('POST', '/api/collections/_superusers/auth-with-password',
         {'identity': email, 'password': pw})
su_token = su.get('token', '')
if not su_token:
    raise SystemExit(1)

# Восстанавливаем временного суперадмина _@b.b для first-run UI
tmp_pw = secrets.token_urlsafe(24)
api('POST', '/api/collections/_superusers/records',
    {'email': '_@b.b', 'password': tmp_pw, 'passwordConfirm': tmp_pw}, su_token)

# Удаляем временного обычного пользователя
filt = urllib.parse.urlencode({'filter': f"email='{email}'", 'perPage': '1'})
users = api('GET', f'/api/collections/users/records?{filt}', token=su_token)
for u in users.get('items', []):
    api('DELETE', f'/api/collections/users/records/{u["id"]}', token=su_token)

# Удаляем временного суперпользователя (последним — инвалидирует токен)
sus = api('GET', f'/api/collections/_superusers/records?{filt}', token=su_token)
for s in sus.get('items', []):
    api('DELETE', f'/api/collections/_superusers/records/{s["id"]}', token=su_token)
PYEOF
}

# Авто-установка агента на локальной машине после запуска хаба.
_beszel_auto_install_agent() {
    local AGENT_PORT="45876"
    local HUB_URL="http://127.0.0.1:8090"

    # 1. Получаем публичный ключ из приватного ключа в volume
    local KEY_PATH
    KEY_PATH=$(docker volume inspect beszel_beszel-data --format '{{.Mountpoint}}' 2>/dev/null)/id_ed25519
    local BESZEL_KEY
    BESZEL_KEY=$(ssh-keygen -y -f "$KEY_PATH" 2>/dev/null)
    [ -z "$BESZEL_KEY" ] && return 1

    # 2. Генерируем временные учётные данные
    local TEMP_EMAIL TEMP_PASS
    TEMP_EMAIL="setup@beszel.local"
    TEMP_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 20)

    # 3. Создаём первого пользователя через first-run API
    local CREATE_BODY
    CREATE_BODY=$(_EMAIL="$TEMP_EMAIL" _PASS="$TEMP_PASS" \
        python3 -c "import json,os; print(json.dumps({'email':os.environ['_EMAIL'],'password':os.environ['_PASS']}))" 2>/dev/null)
    _beszel_http POST "${HUB_URL}/api/beszel/create-user" "$CREATE_BODY" >/dev/null 2>&1

    # 4. Авторизуемся как пользователь
    local AUTH_BODY AUTH_RESP AUTH_TOKEN
    AUTH_BODY=$(_EMAIL="$TEMP_EMAIL" _PASS="$TEMP_PASS" \
        python3 -c "import json,os; print(json.dumps({'identity':os.environ['_EMAIL'],'password':os.environ['_PASS']}))" 2>/dev/null)
    AUTH_RESP=$(_beszel_http POST "${HUB_URL}/api/collections/users/auth-with-password" "$AUTH_BODY")
    AUTH_TOKEN=$(echo "$AUTH_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null)
    [ -z "$AUTH_TOKEN" ] && return 1

    # 5. Создаём постоянный universal token
    local TOKEN_RESP UNIVERSAL_TOKEN
    TOKEN_RESP=$(_beszel_http GET "${HUB_URL}/api/beszel/universal-token?enable=1&permanent=1" "" "$AUTH_TOKEN")
    UNIVERSAL_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null)
    [ -z "$UNIVERSAL_TOKEN" ] && return 1

    # 6. Восстанавливаем first-run состояние — удаляем временного пользователя
    _beszel_restore_firstrun "$HUB_URL" "$TEMP_EMAIL" "$TEMP_PASS" || true

    # 7. Поднимаем агент
    ufw allow "${AGENT_PORT}/tcp" >/dev/null 2>&1 || true
    mkdir -p "${DIR_BESZEL_AGENT}"
    cat > "${DIR_BESZEL_AGENT}docker-compose.yml" <<YAML
services:
  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - beszel-agent-data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      LISTEN: "${AGENT_PORT}"
      KEY: "${BESZEL_KEY}"
      TOKEN: "${UNIVERSAL_TOKEN}"
      HUB_URL: "${HUB_URL}"
      SYSTEM_NAME: "Beszel"
    healthcheck:
      test: ["CMD", "/agent", "health"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  beszel-agent-data:
YAML
    cd "${DIR_BESZEL_AGENT}" && docker compose up -d >/dev/null 2>&1
}

is_beszel_installed() {
    [ -f "${DIR_BESZEL}docker-compose.yml" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "beszel"
}

is_beszel_agent_installed() {
    [ -f "${DIR_BESZEL_AGENT}docker-compose.yml" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "beszel-agent"
}

manage_beszel() {
    local -a items=()
    local -a actions=()

    if ! is_beszel_installed; then
        items+=("📊  Установить панель Beszel"); actions+=("install_hub")
    else
        items+=("🌐  Изменить домен Beszel");    actions+=("change_domain")
    fi

    if ! is_beszel_agent_installed; then
        items+=("🖥️   Подключить агент (ноду)"); actions+=("install_agent")
    else
        items+=("🔗  Изменить адрес хаба агента"); actions+=("change_agent_hub")
    fi

    items+=("──────────────────────────────────────"); actions+=("sep")
    items+=("⬅️   Назад");                             actions+=("back")

    show_arrow_menu "📊  Beszel" "${items[@]}"
    local choice=$?
    local action="${actions[$choice]:-back}"

    case "$action" in
        install_hub)       install_beszel ;;
        change_domain)     change_domain_beszel ;;
        install_agent)     install_beszel_agent ;;
        change_agent_hub)  change_agent_hub_url ;;
        *) return 0 ;;
    esac
}

install_beszel() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       📊 Установка Beszel${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if is_beszel_installed; then
        echo
        print_success "Beszel уже установлен"
        echo
        show_continue_prompt || return 0
        return 0
    fi

    # ─── Домен ───
    local BESZEL_DOMAIN
    prompt_domain_with_retry "Домен для Beszel (например monitor.example.com):" BESZEL_DOMAIN true || return 1
    echo
    echo

    # ─── Сертификат ───
    local BESZEL_PORT="8090"
    local SSL_CERT SSL_KEY CERT_DOMAIN CERT_HOST_FULLCHAIN CERT_HOST_KEY
    local base_domain
    base_domain=$(extract_domain "$BESZEL_DOMAIN")

    if [ -f "/etc/letsencrypt/live/${BESZEL_DOMAIN}/fullchain.pem" ]; then
        print_success "Сертификат для ${BESZEL_DOMAIN} уже существует"
        echo
        CERT_DOMAIN="$BESZEL_DOMAIN"
        CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${BESZEL_DOMAIN}/fullchain.pem"
        CERT_HOST_KEY="/etc/letsencrypt/live/${BESZEL_DOMAIN}/privkey.pem"
    elif [ -f "/etc/letsencrypt/live/${base_domain}/fullchain.pem" ]; then
        print_success "Сертификат для ${base_domain} уже существует"
        echo
        CERT_DOMAIN="$base_domain"
        CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${base_domain}/fullchain.pem"
        CERT_HOST_KEY="/etc/letsencrypt/live/${base_domain}/privkey.pem"
    else
        show_arrow_menu "🔒  SSL сертификат" \
            "🌐  ACME (Let's Encrypt HTTP-01)" \
            "☁️   Cloudflare (DNS-01 Wildcard)" \
            "🔐  Самоподписанный сертификат" \
            "──────────────────────────────────────" \
            "❌  Отмена"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return 0

        case $cert_choice in
            0) # ACME
                reading "Email для Let's Encrypt:" BESZEL_EMAIL
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    return 1
                fi
                echo
                echo
                get_cert_acme "$BESZEL_DOMAIN" "$BESZEL_EMAIL" || return 1
                CERT_DOMAIN="$BESZEL_DOMAIN"
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${BESZEL_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${BESZEL_DOMAIN}/privkey.pem"
                ;;
            1) # Cloudflare
                reading "Email для Let's Encrypt:" BESZEL_EMAIL
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    return 1
                fi
                if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                    setup_cloudflare_credentials || return 1
                fi
                echo
                echo
                get_cert_cloudflare "$base_domain" "$BESZEL_EMAIL" || return 1
                CERT_DOMAIN="$base_domain"
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${base_domain}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${base_domain}/privkey.pem"
                ;;
            2) # Самоподписанный
                local SELF_SIGNED_DIR
                SELF_SIGNED_DIR=$(mktemp -d)
                (
                    openssl req -x509 -nodes -days 3650 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
                        -keyout "${SELF_SIGNED_DIR}/privkey.pem" \
                        -out "${SELF_SIGNED_DIR}/fullchain.pem" \
                        -subj "/CN=${BESZEL_DOMAIN}" >/dev/null 2>&1
                ) &
                show_spinner "Генерация самоподписанного сертификата"
                CERT_DOMAIN="$BESZEL_DOMAIN"
                CERT_HOST_FULLCHAIN="${SELF_SIGNED_DIR}/fullchain.pem"
                CERT_HOST_KEY="${SELF_SIGNED_DIR}/privkey.pem"
                ;;
            *) return 0 ;;
        esac
    fi
    # ─── SSL-пути для nginx ───
    local NGINX_SSL_CERT NGINX_SSL_KEY
    if [[ "$CERT_HOST_FULLCHAIN" == /etc/letsencrypt/* ]]; then
        # Let's Encrypt — копируем в /opt/nginx/ssl/
        nginx_copy_cert "$CERT_DOMAIN"
        NGINX_SSL_CERT="/etc/nginx/ssl/${CERT_DOMAIN}/fullchain.pem"
        NGINX_SSL_KEY="/etc/nginx/ssl/${CERT_DOMAIN}/privkey.pem"
    else
        # Самоподписанный — копируем в /opt/nginx/ssl/
        mkdir -p "${DIR_NGINX}ssl/${CERT_DOMAIN}"
        cp -f "$CERT_HOST_FULLCHAIN" "${DIR_NGINX}ssl/${CERT_DOMAIN}/fullchain.pem"
        cp -f "$CERT_HOST_KEY" "${DIR_NGINX}ssl/${CERT_DOMAIN}/privkey.pem"
        NGINX_SSL_CERT="/etc/nginx/ssl/${CERT_DOMAIN}/fullchain.pem"
        NGINX_SSL_KEY="/etc/nginx/ssl/${CERT_DOMAIN}/privkey.pem"
        # Удаляем временную директорию сертификата
        rm -rf "${SELF_SIGNED_DIR:-}" 2>/dev/null || true
    fi

    # ─── Определяем listen-режим до запуска ensure_nginx ───
    local LISTEN_BLOCK REAL_IP_BLOCK
    if [ -f "${DIR_NGINX}nginx.conf" ] && grep -q 'listen unix:/dev/shm/nginx.sock' "${DIR_NGINX}nginx.conf"; then
        LISTEN_BLOCK="    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;"
        REAL_IP_BLOCK=$'\n    real_ip_header proxy_protocol;\n    set_real_ip_from unix:;'
    else
        LISTEN_BLOCK="    listen 443 ssl;\n    listen [::]:443 ssl;"
        REAL_IP_BLOCK=""
    fi

    local BESZEL_BLOCK
    BESZEL_BLOCK=$(cat <<NGINX
server {
    server_name ${BESZEL_DOMAIN};
$(echo -e "$LISTEN_BLOCK")
    http2 on;
${REAL_IP_BLOCK}

    ssl_certificate     ${NGINX_SSL_CERT};
    ssl_certificate_key ${NGINX_SSL_KEY};
    ssl_trusted_certificate ${NGINX_SSL_CERT};

    access_log /dev/stdout combined;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
)

    # ─── Подготовка файлов (директория, docker-compose, nginx conf.d) ───
    (
        mkdir -p "${DIR_BESZEL}"
        cat > "${DIR_BESZEL}docker-compose.yml" <<YAML
services:
  beszel:
    image: henrygd/beszel:latest
    container_name: beszel
    restart: unless-stopped
    ports:
      - "127.0.0.1:8090:8090"
    volumes:
      - beszel-data:/beszel_data
      - beszel-socket:/beszel_socket
    healthcheck:
      test: ["CMD", "/beszel", "health", "--url", "http://127.0.0.1:8090"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  beszel-data:
  beszel-socket:
YAML
        ensure_nginx
        if [ ! -f "${DIR_NGINX}nginx.conf" ]; then
            nginx_generate_minimal_conf
        fi
        nginx_add_server_block "BESZEL" "$BESZEL_BLOCK"
    ) &
    show_spinner "Подготовка файлов"

    # ─── Запускаем Beszel ───
    (
        cd "${DIR_BESZEL}" && docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Установка Beszel"

    # ─── Авто-установка агента на этом же сервере ───
    (
        _beszel_wait_api && _beszel_auto_install_agent
    ) &
    show_spinner "Подключение агента мониторинга"

    # Запускаем/перезапускаем nginx
    (nginx_reload) &
    show_spinner "Запуск Nginx"

    echo
    print_success "Beszel успешно установлен"
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}🔗 Панель мониторинга:${NC}"
    echo -e "${WHITE}https://${BESZEL_DOMAIN}${NC}"
    echo
    echo -e "${DARKGRAY}При первом входе создайте свою учётную запись администратора.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

# ─── Изменение домена Beszel ───
change_domain_beszel() {
    if ! is_beszel_installed; then
        print_error "Beszel не установлен"
        return 1
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     🌐  Изменить домен Beszel${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local NEW_DOMAIN
    prompt_domain_with_retry "Новый домен для Beszel:" NEW_DOMAIN true || return 1
    echo
    echo

    # Получаем сертификат
    local CERT_DOMAIN CERT_HOST_FULLCHAIN CERT_HOST_KEY
    local base_domain
    base_domain=$(extract_domain "$NEW_DOMAIN")

    if [ -f "/etc/letsencrypt/live/${NEW_DOMAIN}/fullchain.pem" ]; then
        print_success "Сертификат для ${NEW_DOMAIN} уже существует"
        echo
        CERT_DOMAIN="$NEW_DOMAIN"
        CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${NEW_DOMAIN}/fullchain.pem"
        CERT_HOST_KEY="/etc/letsencrypt/live/${NEW_DOMAIN}/privkey.pem"
    elif [ -f "/etc/letsencrypt/live/${base_domain}/fullchain.pem" ]; then
        print_success "Сертификат для ${base_domain} уже существует"
        echo
        CERT_DOMAIN="$base_domain"
        CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${base_domain}/fullchain.pem"
        CERT_HOST_KEY="/etc/letsencrypt/live/${base_domain}/privkey.pem"
    else
        show_arrow_menu "🔒  SSL сертификат" \
            "🌐  ACME (Let's Encrypt HTTP-01)" \
            "☁️   Cloudflare (DNS-01 Wildcard)" \
            "🔐  Самоподписанный сертификат" \
            "──────────────────────────────────────" \
            "❌  Отмена"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return 0

        case $cert_choice in
            0)
                reading "Email для Let's Encrypt:" BESZEL_EMAIL
                if [ -z "$BESZEL_EMAIL" ]; then print_error "Email не может быть пустым"; return 1; fi
                echo
                get_cert_acme "$NEW_DOMAIN" "$BESZEL_EMAIL" || return 1
                CERT_DOMAIN="$NEW_DOMAIN"
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${NEW_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${NEW_DOMAIN}/privkey.pem"
                ;;
            1)
                reading "Email для Let's Encrypt:" BESZEL_EMAIL
                if [ -z "$BESZEL_EMAIL" ]; then print_error "Email не может быть пустым"; return 1; fi
                if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                    setup_cloudflare_credentials || return 1
                fi
                echo
                get_cert_cloudflare "$base_domain" "$BESZEL_EMAIL" || return 1
                CERT_DOMAIN="$base_domain"
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${base_domain}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${base_domain}/privkey.pem"
                ;;
            2)
                local SELF_SIGNED_DIR
                SELF_SIGNED_DIR=$(mktemp -d)
                (
                    openssl req -x509 -nodes -days 3650 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
                        -keyout "${SELF_SIGNED_DIR}/privkey.pem" \
                        -out "${SELF_SIGNED_DIR}/fullchain.pem" \
                        -subj "/CN=${NEW_DOMAIN}" >/dev/null 2>&1
                ) &
                show_spinner "Генерация самоподписанного сертификата"
                CERT_DOMAIN="$NEW_DOMAIN"
                CERT_HOST_FULLCHAIN="${SELF_SIGNED_DIR}/fullchain.pem"
                CERT_HOST_KEY="${SELF_SIGNED_DIR}/privkey.pem"
                ;;
            *) return 0 ;;
        esac
    fi

    local NGINX_SSL_CERT NGINX_SSL_KEY
    if [[ "$CERT_HOST_FULLCHAIN" == /etc/letsencrypt/* ]]; then
        nginx_copy_cert "$CERT_DOMAIN"
        NGINX_SSL_CERT="/etc/nginx/ssl/${CERT_DOMAIN}/fullchain.pem"
        NGINX_SSL_KEY="/etc/nginx/ssl/${CERT_DOMAIN}/privkey.pem"
    else
        mkdir -p "${DIR_NGINX}ssl/${CERT_DOMAIN}"
        cp -f "$CERT_HOST_FULLCHAIN" "${DIR_NGINX}ssl/${CERT_DOMAIN}/fullchain.pem"
        cp -f "$CERT_HOST_KEY" "${DIR_NGINX}ssl/${CERT_DOMAIN}/privkey.pem"
        NGINX_SSL_CERT="/etc/nginx/ssl/${CERT_DOMAIN}/fullchain.pem"
        NGINX_SSL_KEY="/etc/nginx/ssl/${CERT_DOMAIN}/privkey.pem"
        rm -rf "${SELF_SIGNED_DIR:-}" 2>/dev/null || true
    fi

    local LISTEN_BLOCK REAL_IP_BLOCK
    if [ -f "${DIR_NGINX}nginx.conf" ] && grep -q 'listen unix:/dev/shm/nginx.sock' "${DIR_NGINX}nginx.conf"; then
        LISTEN_BLOCK="    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;"
        REAL_IP_BLOCK=$'\n    real_ip_header proxy_protocol;\n    set_real_ip_from unix:;'
    else
        LISTEN_BLOCK="    listen 443 ssl;\n    listen [::]:443 ssl;"
        REAL_IP_BLOCK=""
    fi

    local BESZEL_BLOCK
    BESZEL_BLOCK=$(cat <<NGINX
server {
    server_name ${NEW_DOMAIN};
$(echo -e "$LISTEN_BLOCK")
    http2 on;
${REAL_IP_BLOCK}

    ssl_certificate     ${NGINX_SSL_CERT};
    ssl_certificate_key ${NGINX_SSL_KEY};
    ssl_trusted_certificate ${NGINX_SSL_CERT};

    access_log /dev/stdout combined;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
)

    (
        nginx_add_server_block "BESZEL" "$BESZEL_BLOCK"
        nginx_cleanup_unused_certs
    ) &
    show_spinner "Обновление конфигурации Nginx"

    (nginx_reload) &
    show_spinner "Перезапуск Nginx"

    # Если агент использует публичный домен (не localhost) — обновляем его HUB_URL
    if is_beszel_agent_installed; then
        local _AGENT_HUB
        _AGENT_HUB=$(grep 'HUB_URL:' "${DIR_BESZEL_AGENT}docker-compose.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')
        if [[ "$_AGENT_HUB" != "http://127.0.0.1"* ]] && [ -n "$_AGENT_HUB" ]; then
            (
                sed -i "s|HUB_URL: \"[^\"]*\"|HUB_URL: \"https://${NEW_DOMAIN}\"|" "${DIR_BESZEL_AGENT}docker-compose.yml"
                cd "${DIR_BESZEL_AGENT}" && docker compose up -d --force-recreate >/dev/null 2>&1
            ) &
            show_spinner "Обновление агента"
        fi
    fi
    echo
    print_success "Домен Beszel изменён"
    echo
    echo -e "${YELLOW}🔗 Новый адрес панели:${NC}"
    echo -e "${WHITE}https://${NEW_DOMAIN}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

# ─── Изменение адреса хаба для локального агента ───
change_agent_hub_url() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    🔗  Изменить адрес хаба агента${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if ! is_beszel_agent_installed; then
        print_error "Агент Beszel не установлен"
        return 1
    fi

    local CURRENT_HUB_URL
    CURRENT_HUB_URL=$(grep 'HUB_URL:' "${DIR_BESZEL_AGENT}docker-compose.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')

    echo -e "${DARKGRAY}Текущий адрес хаба: ${WHITE}${CURRENT_HUB_URL:-не указан}${NC}"
    echo

    local NEW_HUB_URL
    reading_inline "Новый адрес хаба (например https://monitor.example.com):" NEW_HUB_URL
    [[ $? -eq 2 ]] && return 1
    if [ -z "$NEW_HUB_URL" ]; then
        print_error "Адрес не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    (
        sed -i "s|HUB_URL: \"[^\"]*\"|HUB_URL: \"${NEW_HUB_URL}\"|" "${DIR_BESZEL_AGENT}docker-compose.yml"
        cd "${DIR_BESZEL_AGENT}" && docker compose up -d --force-recreate >/dev/null 2>&1
    ) &
    show_spinner "Обновление адреса хаба"

    echo
    print_success "Адрес хаба обновлён"
    echo
    echo -e "${YELLOW}🔗 Новый адрес хаба:${NC}"
    echo -e "${WHITE}${NEW_HUB_URL}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

uninstall_beszel() {
    local _force=false
    [[ "${1:-}" == "--force" ]] && _force=true

    if [ "$_force" = false ]; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${RED}       🗑️  УДАЛЕНИЕ BESZEL${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}⚠️  Панель мониторинга Beszel будет удалена.${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        if ! confirm_action; then return; fi
        echo
        echo
    fi

    (
        cd "${DIR_BESZEL}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление контейнеров Beszel"

    # Удаляем server-блок beszel из nginx.conf
    nginx_remove_server_block "BESZEL"

    # Удаляем неиспользуемые сертификаты из /opt/nginx/ssl/
    nginx_cleanup_unused_certs

    # Перезапускаем или удаляем nginx
    if nginx_has_users; then
        (nginx_reload) &
        show_spinner "Перезапуск nginx"
    else
        (nginx_teardown) &
        show_spinner "Удаление nginx"
    fi

    rm -rf "${DIR_BESZEL}"

    [ "$_force" = true ] && return 0

    echo
    print_success "Beszel удалён"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

install_beszel_agent() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}    🖥️  Подключение агента Beszel${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if is_beszel_agent_installed; then
        echo
        print_success "Агент Beszel уже установлен"
        echo
        show_continue_prompt || return 0
        return 0
    fi

    echo
    echo -e "${DARKGRAY}Агент собирает метрики и отправляет их на панель Beszel.${NC}"
    echo -e "${DARKGRAY}В панели управления Beszel нажмите Добавить систему → скопируйте Ключ и Токен.${NC}"
    echo

    # ─── URL панели ───
    local BESZEL_HUB_URL
    reading_inline "URL панели Beszel (например https://monitor.example.com):" BESZEL_HUB_URL
    [[ $? -eq 2 ]] && return 1
    if [ -z "$BESZEL_HUB_URL" ]; then
        print_error "URL не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    # ─── Порт агента ───
    local BESZEL_AGENT_PORT
    reading_inline "Порт агента (по умолчанию 45876):" BESZEL_AGENT_PORT
    [[ $? -eq 2 ]] && return 1
    [ -z "$BESZEL_AGENT_PORT" ] && BESZEL_AGENT_PORT="45876"

    # ─── Публичный ключ (KEY) ───
    local BESZEL_KEY
    reading_inline "Ключ (публичный ключ из панели):" BESZEL_KEY
    [[ $? -eq 2 ]] && return 1
    if [ -z "$BESZEL_KEY" ]; then
        print_error "Ключ не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    # ─── TOKEN ───
    local BESZEL_TOKEN
    reading_inline "Токен (токен из панели):" BESZEL_TOKEN
    [[ $? -eq 2 ]] && return 1
    if [ -z "$BESZEL_TOKEN" ]; then
        print_error "Токен не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    # ─── Создаём файлы и запускаем агент ───
    ufw allow "${BESZEL_AGENT_PORT}/tcp" >/dev/null 2>&1 || true

    echo
    echo
    (
        mkdir -p "${DIR_BESZEL_AGENT}"
        cat > "${DIR_BESZEL_AGENT}docker-compose.yml" <<YAML
services:
  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - beszel-agent-data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      LISTEN: "${BESZEL_AGENT_PORT}"
      KEY: "${BESZEL_KEY}"
      TOKEN: "${BESZEL_TOKEN}"
      HUB_URL: "${BESZEL_HUB_URL}"
    healthcheck:
      test: ["CMD", "/agent", "health"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  beszel-agent-data:
YAML
    ) &
    show_spinner "Подготовка файлов"

    (
        cd "${DIR_BESZEL_AGENT}" && docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Добавление агента Beszel"

    echo
    print_success "Агент Beszel добавлен"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

uninstall_beszel_agent() {
    local _force=false
    [[ "${1:-}" == "--force" ]] && _force=true

    if [ "$_force" = false ]; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${RED}    🗑️  УДАЛЕНИЕ АГЕНТА BESZEL${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}⚠️  Агент Beszel будет остановлен и удалён.${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        if ! confirm_action; then return; fi
        echo
    fi

    local AGENT_PORT_STORED
    AGENT_PORT_STORED=$(grep 'LISTEN:' "${DIR_BESZEL_AGENT}docker-compose.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')

    (
        cd "${DIR_BESZEL_AGENT}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление агента Beszel"

    if [ -n "$AGENT_PORT_STORED" ]; then
        ufw delete allow "${AGENT_PORT_STORED}/tcp" >/dev/null 2>&1 || true
    fi

    rm -rf "${DIR_BESZEL_AGENT}"

    [ "$_force" = true ] && return 0

    print_success "Агент Beszel удалён"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}
