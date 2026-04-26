# ═══════════════════════════════════════════════════
# BESZEL — МОНИТОРИНГ СЕРВЕРА
# ═══════════════════════════════════════════════════

DIR_BESZEL="/opt/beszel/"
DIR_BESZEL_AGENT="/opt/beszel-agent/"

# После спиннера: clear, тот же заголовок что в confirm_nav --delete (красный, по центру в 38),
# центрированное зелёное сообщение, подсказка Enter/Esc.
# $1 — заголовок (как в confirm), $2 — строка успеха (с эмодзи ✅).
_beszel_post_delete_success_screen() {
    local _title="$1" _msg="$2"
    local _tc _p _pad
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    _tc=$(printf '%b' "$_title" | sed 's/\x1b\[[0-9;]*m//g')
    _p=$(( (38 - ${#_tc}) / 2 ))
    [ "$_p" -lt 0 ] && _p=0
    _pad=$(printf "%${_p}s" "")
    printf "%s" "$_pad"
    echo -e "${RED}${_title}${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "$(center "$_msg" "$GREEN")"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

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

# UFW: при необходимости установить; как setup_firewall — deny incoming, SSH из sshd_config,
# опционально 80/443 (только хаб с nginx), плюс дополнительные TCP-порты (порт агента и т.п.).
# Вызов: _beszel_setup_firewall 45876 — хаб (80/443 + порты).
#         _beszel_setup_firewall --agent-node 45876 — только нода агента (без 80/443; HTTP-01 для LE — в certificates.sh).
_beszel_setup_firewall() {
    local _with_http=true
    if [ "${1:-}" = "--agent-node" ]; then
        _with_http=false
        shift
    fi
    local -a _extra_ports=("$@")

    if ! command -v ufw >/dev/null 2>&1; then
        (
            export DEBIAN_FRONTEND=noninteractive
            local DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'
            systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
            local _lw=0
            while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock \
                  /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend \
                  >/dev/null 2>&1; do
                sleep 2; _lw=$(( _lw + 2 )); [ "$_lw" -ge 120 ] && break
            done
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y -qq $DPKG_OPTS ufw >/dev/null 2>&1
         ) </dev/null &        show_spinner --step "Установка Firewall (ufw)" || true
    fi
    command -v ufw >/dev/null 2>&1 || return 0

    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    ufw_ensure_ssh_allow_with_comment >/dev/null 2>&1 || true
    if [ "$_with_http" = true ]; then
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
    fi

    local _p
    for _p in "${_extra_ports[@]}"; do
        [ -z "$_p" ] && continue
        [[ "$_p" =~ ^[0-9]+$ ]] || continue
        [ "$_p" -ge 1 ] && [ "$_p" -le 65535 ] || continue
        ufw allow "${_p}/tcp" >/dev/null 2>&1 || true
    done

    echo "y" | ufw enable >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true
}

# Авто-установка агента на локальной машине после запуска хаба.
_beszel_auto_install_agent() {
    local AGENT_PORT="45876"
    local HUB_URL="http://127.0.0.1:8090"

    # 1. Генерируем временные учётные данные
    local ADMIN_EMAIL ADMIN_PASS
    ADMIN_EMAIL="admin@beszel.local"
    ADMIN_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 20)

    # 2. Создаём первого пользователя через first-run API
    local CREATE_BODY
    CREATE_BODY=$(_EMAIL="$ADMIN_EMAIL" _PASS="$ADMIN_PASS" \
        python3 -c "import json,os; print(json.dumps({'email':os.environ['_EMAIL'],'password':os.environ['_PASS']}))" 2>/dev/null)
    _beszel_http POST "${HUB_URL}/api/beszel/create-user" "$CREATE_BODY" >/dev/null 2>&1

    # 3. Авторизуемся как пользователь
    local AUTH_BODY AUTH_RESP AUTH_TOKEN
    AUTH_BODY=$(_EMAIL="$ADMIN_EMAIL" _PASS="$ADMIN_PASS" \
        python3 -c "import json,os; print(json.dumps({'identity':os.environ['_EMAIL'],'password':os.environ['_PASS']}))" 2>/dev/null)
    AUTH_RESP=$(_beszel_http POST "${HUB_URL}/api/collections/users/auth-with-password" "$AUTH_BODY")
    AUTH_TOKEN=$(echo "$AUTH_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null)
    [ -z "$AUTH_TOKEN" ] && return 1

    # 4. Получаем публичный ключ через /api/beszel/getkey
    # Примечание: /api/beszel/info не работает в Beszel 0.18+ (возвращает HTML вместо JSON).
    # /api/beszel/getkey — deprecated alias, но работает корректно.
    local KEY_RESP BESZEL_KEY
    KEY_RESP=$(_beszel_http GET "${HUB_URL}/api/beszel/getkey" "" "$AUTH_TOKEN")
    BESZEL_KEY=$(echo "$KEY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('key',''))" 2>/dev/null)
    [ -z "$BESZEL_KEY" ] && return 1

    # 5. Создаём постоянный universal token
    local TOKEN_RESP UNIVERSAL_TOKEN
    TOKEN_RESP=$(_beszel_http GET "${HUB_URL}/api/beszel/universal-token?enable=1&permanent=1" "" "$AUTH_TOKEN")
    UNIVERSAL_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null)
    [ -z "$UNIVERSAL_TOKEN" ] && return 1

    # 6. Запускаем агент (порт агента в UFW открывает install_beszel через _beszel_setup_firewall; 80/443 только у хаба).
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

    # 7. Ждём регистрации агента в хабе (до 120 сек).
    local i
    for i in $(seq 1 60); do
        local cnt
        cnt=$(_beszel_http GET "${HUB_URL}/api/collections/systems/records?perPage=1" "" "$AUTH_TOKEN" \
            | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('totalItems',0))" 2>/dev/null)
        [ "${cnt:-0}" -gt 0 ] && break
        sleep 2
    done

    # 8. Записываем daemon-скрипт переподключения агента.
    # Проблема: systems.users имеет cascadeDelete=true — удаление временного пользователя
    # каскадно удаляет systems + fingerprints + universal_tokens. Агент теряет регистрацию.
    # Решение: daemon ждёт создания реального аккаунта (firstRun→false), затем напрямую
    # через SQLite создаёт новый universal token для нового администратора и перезапускает
    # агент, который автоматически перерегистрируется под новым владельцем.
    local _PROJ _DB_DIR _DAEMON
    _PROJ=$(basename "${DIR_BESZEL%/}")
    _DB_DIR=$(docker volume inspect "${_PROJ}_beszel-data" \
        --format '{{.Mountpoint}}' 2>/dev/null || echo "/var/lib/docker/volumes/${_PROJ}_beszel-data/_data")
    _DAEMON="${DIR_BESZEL}.agent-daemon.py"
    cat > "$_DAEMON" <<PYEOF
#!/usr/bin/env python3
"""Beszel agent reconnect daemon.

После _beszel_restore_firstrun (удаления временного пользователя) ждёт,
пока реальный администратор создаст аккаунт через firstRun UI.
Затем создаёт universal token в SQLite и перезапускает агент.
Beszel проверяет universal_tokens по базе данных при каждом подключении агента,
поэтому прямая запись в SQLite работает без перезапуска хаба.
"""
import os, re, random, sqlite3, string, subprocess, sys, time, uuid

DB      = "${_DB_DIR}/data.db"
COMPOSE = "${DIR_BESZEL_AGENT}docker-compose.yml"

def rand_id(n=15):
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=n))

# Ждём до 24 часов пока в таблице users не появится реальный пользователь
uid = None
for _ in range(17280):
    try:
        with sqlite3.connect(DB, timeout=5) as cx:
            row = cx.execute("SELECT id FROM users LIMIT 1").fetchone()
            if row:
                uid = row[0]
                break
    except Exception:
        pass
    time.sleep(5)

if uid is None:
    sys.exit(0)

time.sleep(2)  # даём PocketBase завершить транзакцию

# Создаём universal token для нового администратора напрямую в SQLite
new_token = str(uuid.uuid4())
try:
    with sqlite3.connect(DB, timeout=10) as cx:
        cx.execute(
            "INSERT INTO universal_tokens (id, created, user, token) "
            "VALUES (?, datetime('now'), ?, ?)",
            (rand_id(), uid, new_token),
        )
except Exception:
    sys.exit(1)

# Обновляем TOKEN в docker-compose агента (KEY остаётся тем же)
try:
    with open(COMPOSE) as f:
        content = f.read()
    content = re.sub(r'TOKEN:.*', 'TOKEN: "' + new_token + '"', content)
    with open(COMPOSE, 'w') as f:
        f.write(content)
except Exception:
    sys.exit(1)

# Перезапускаем агент — он подключится с новым токеном и автоматически
# создаст запись systems под реальным администратором
subprocess.run(
    ["docker", "compose", "-f", COMPOSE, "up", "-d"],
    capture_output=True,
)

# Удаляем этот скрипт
try:
    os.unlink(os.path.abspath(__file__))
except Exception:
    pass
PYEOF
    chmod 600 "$_DAEMON"

    # 9. Восстанавливаем first-run состояние (каскадно удаляет systems/tokens временного пользователя).
    _beszel_restore_firstrun "$HUB_URL" "$ADMIN_EMAIL" "$ADMIN_PASS" || true

    # 10. Запускаем daemon в фоне, отвязанным от текущего подпроцесса.
    nohup python3 "$_DAEMON" >/dev/null 2>&1 &
    disown $! 2>/dev/null || true
}

is_beszel_installed() {
    [ -f "${DIR_BESZEL}docker-compose.yml" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "beszel"
}

is_beszel_agent_installed() {
    [ -f "${DIR_BESZEL_AGENT}docker-compose.yml" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "beszel-agent"
}

manage_beszel() {
    while true; do
        local -a items=()
        local -a actions=()

        if ! is_beszel_installed; then
            items+=("📊  Установить панель Beszel"); actions+=("install_hub")
        else
            items+=("🌐  Изменить домен для панели Beszel"); actions+=("change_domain")
        fi

        if ! is_beszel_agent_installed; then
            items+=("🖥️   Подключить ноду"); actions+=("install_agent")
        elif ! is_beszel_installed; then
            # Агент есть, хаба нет — меняем адрес хаба у агента
            items+=("🔗  Изменить адрес хаба агента"); actions+=("change_agent_hub")
        fi

        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("⬅️   Назад");                             actions+=("back")

        show_arrow_menu "📊 Мониторинг Beszel" "${items[@]}"
        local choice=$?
        local action="${actions[$choice]:-back}"

        case "$action" in
            install_hub)       install_beszel ;;
            change_domain)     change_domain_beszel ;;
            install_agent)     install_beszel_agent ;;
            change_agent_hub)  change_agent_hub_url ;;
            *) return 0 ;;
        esac
    done
}

install_beszel() {
    # Между спиннерами курсор не показываем; перед вводом reading_inline сам делает cnorm.
    KEEP_CURSOR_HIDDEN=1
    trap 'KEEP_CURSOR_HIDDEN=; tput civis 2>/dev/null || true; stty sane 2>/dev/null || true; trap - RETURN' RETURN

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "$(center "📊 Установка панели Beszel" "$BLUE")"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if is_beszel_installed; then
        KEEP_CURSOR_HIDDEN=
        trap - RETURN
        echo
        print_success "Панель Beszel уже установлена"
        echo
        show_continue_prompt || return 0
        return 0
    fi

    # ─── Домен или IP (Enter — внешний IP сервера) ───
    local BESZEL_DOMAIN
    local _server_ip
    _server_ip=$(get_server_ip 2>/dev/null)
    local _is_ip_mode=false

    while true; do
        reading_inline --no-eol "${YELLOW}Домен/IP для Beszel ${DARKGRAY}[Enter для ${_server_ip}]:${NC}" BESZEL_DOMAIN
        local _domain_rc=$?

        if [ "$_domain_rc" -eq 2 ]; then
            KEEP_CURSOR_HIDDEN=
            trap - RETURN
            return 0
        fi

        if [ -z "$BESZEL_DOMAIN" ]; then
            BESZEL_DOMAIN="$_server_ip"
            _is_ip_mode=true
            break
        fi

        if [[ "$BESZEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            _is_ip_mode=true
            break
        fi

        local _chk_out_f _chk_rc_f
        _chk_out_f=$(mktemp)
        _chk_rc_f=$(mktemp)
        (
            check_domain "$BESZEL_DOMAIN" > "$_chk_out_f" 2>&1
            echo $? > "$_chk_rc_f"
         ) </dev/null &        local _chk_pid=$!
        dfc_domain_check_wait_inline "$_chk_pid"
        local _chk_rc _chk_out
        _chk_rc=$(cat "$_chk_rc_f" 2>/dev/null)
        _chk_out=$(cat "$_chk_out_f" 2>/dev/null)
        rm -f "$_chk_out_f" "$_chk_rc_f"

        if [ "$_chk_rc" = "0" ]; then
            break
        fi

        echo
        local _out_lines=0
        if [ -n "$_chk_out" ]; then
            printf "%s\n" "$_chk_out"
            _out_lines=$(echo "$_chk_out" | wc -l)
        fi

        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${BLUE}Enter${DARKGRAY}: Повторить   ${BLUE}S${DARKGRAY}: Пропустить   ${BLUE}Esc${DARKGRAY}: Назад${NC}"

        local _total_lines=$((_out_lines + 5))
        tput civis 2>/dev/null || true
        local _nav_key
        while true; do
            read -s -n 1 _nav_key
            if [[ "$_nav_key" == $'\x1b' ]]; then
                if _dfc_after_esc_is_bare; then
                    tput civis 2>/dev/null || true
                    echo
                    KEEP_CURSOR_HIDDEN=
                    trap - RETURN
                    return 0
                fi
                continue
            elif [[ "$_nav_key" == "s" || "$_nav_key" == "S" ]]; then
                tput civis 2>/dev/null || true
                echo
                local _skip_lines=$((_total_lines))
                for (( _l=0; _l<_skip_lines; _l++ )); do
                    tput cuu1 2>/dev/null; tput el 2>/dev/null
                done
                break 2
            elif [[ "$_nav_key" == "" ]]; then
                tput civis 2>/dev/null || true
                for (( _l=0; _l<_total_lines; _l++ )); do
                    tput cuu1 2>/dev/null; tput el 2>/dev/null
                done
                break
            fi
        done
    done
    if [ -n "${KEEP_CURSOR_HIDDEN:-}" ]; then
        tput civis 2>/dev/null || true
    fi
    echo
    echo

    if [[ ! "$BESZEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        BESZEL_DOMAIN=$(printf '%s' "$BESZEL_DOMAIN" | tr '[:upper:]' '[:lower:]')
    fi

    # ─── Сертификат ───
    local BESZEL_PORT="8090"
    local SSL_CERT SSL_KEY CERT_DOMAIN CERT_HOST_FULLCHAIN CERT_HOST_KEY
    local base_domain
    if [ "$_is_ip_mode" = true ]; then
        base_domain="$BESZEL_DOMAIN"
    else
        base_domain=$(extract_domain "$BESZEL_DOMAIN")
    fi

    local _le_found
    _le_found=$(le_live_basename "$BESZEL_DOMAIN" 2>/dev/null) || _le_found=""
    if [ -n "$_le_found" ]; then
        print_cert_exists "${BESZEL_DOMAIN}"
        CERT_DOMAIN="$_le_found"
        CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
        CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
    elif _le_found=$(le_live_basename "$base_domain" 2>/dev/null) && [ -n "$_le_found" ]; then
        print_cert_exists "${base_domain}"
        CERT_DOMAIN="$_le_found"
        CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
        CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
    elif [ "$_is_ip_mode" = true ]; then
        local SELF_SIGNED_DIR
        SELF_SIGNED_DIR=$(mktemp -d)
        (
            local _ss_cfg
            _ss_cfg=$(mktemp)
            {
                echo "[req]"
                echo "distinguished_name = req_dn"
                echo "x509_extensions = v3_req"
                echo "prompt = no"
                echo
                echo "[req_dn]"
                echo "CN = ${BESZEL_DOMAIN}"
                echo
                echo "[v3_req]"
                echo "subjectAltName = IP:${BESZEL_DOMAIN}"
            } > "$_ss_cfg"
            openssl req -x509 -nodes -days 3650 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
                -keyout "${SELF_SIGNED_DIR}/privkey.pem" \
                -out "${SELF_SIGNED_DIR}/fullchain.pem" \
                -config "$_ss_cfg" >/dev/null 2>&1
            rm -f "$_ss_cfg"
         ) </dev/null &        show_spinner --step "Генерация самоподписанного сертификата"
        CERT_DOMAIN="$BESZEL_DOMAIN"
        CERT_HOST_FULLCHAIN="${SELF_SIGNED_DIR}/fullchain.pem"
        CERT_HOST_KEY="${SELF_SIGNED_DIR}/privkey.pem"
    else
        show_arrow_menu "${BLUE}🔒  Получение SSL сертификата${NC}" \
            "🌐  ACME (Let's Encrypt HTTP-01)" \
            "☁️   Cloudflare (DNS-01 Wildcard)" \
            "🔷  Gcore (DNS-01 Wildcard)" \
            "──────────────────────────────────────" \
            "❌  Отмена"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return 0

        case $cert_choice in
            0) # ACME
                reading_inline "Email для Let's Encrypt:" BESZEL_EMAIL
                [[ $? -eq 2 ]] && return 1
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    echo
                    show_continue_prompt || return 0
                    return 0
                fi
                echo
                if ! get_cert_acme "$BESZEL_DOMAIN" "$BESZEL_EMAIL"; then
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || return 0
                    return 0
                fi
                _le_found=$(le_live_basename "$BESZEL_DOMAIN" 2>/dev/null) || _le_found=""
                if [ -n "$_le_found" ]; then
                    CERT_DOMAIN="$_le_found"
                else
                    CERT_DOMAIN=$(printf '%s' "$BESZEL_DOMAIN" | tr '[:upper:]' '[:lower:]')
                fi
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
                ;;
            1) # Cloudflare
                reading_inline "Email для Let's Encrypt:" BESZEL_EMAIL
                [[ $? -eq 2 ]] && return 1
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    echo
                    show_continue_prompt || return 0
                    return 0
                fi
                if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                    setup_cloudflare_credentials || return 1
                fi
                echo
                if ! get_cert_cloudflare "$base_domain" "$BESZEL_EMAIL"; then
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || return 0
                    return 0
                fi
                echo
                _le_found=$(le_live_basename "$base_domain" 2>/dev/null) || _le_found=""
                if [ -n "$_le_found" ]; then
                    CERT_DOMAIN="$_le_found"
                else
                    CERT_DOMAIN=$(printf '%s' "$base_domain" | tr '[:upper:]' '[:lower:]')
                fi
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
                ;;
            2) # Gcore
                reading_inline "Email для Let's Encrypt:" BESZEL_EMAIL
                [[ $? -eq 2 ]] && return 1
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    echo
                    show_continue_prompt || return 0
                    return 0
                fi
                if [ ! -f "/etc/letsencrypt/gcore.ini" ]; then
                    setup_gcore_credentials || return 1
                fi
                echo
                if ! get_cert_gcore "$base_domain" "$BESZEL_EMAIL"; then
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || return 0
                    return 0
                fi
                echo
                _le_found=$(le_live_basename "$base_domain" 2>/dev/null) || _le_found=""
                if [ -n "$_le_found" ]; then
                    CERT_DOMAIN="$_le_found"
                else
                    CERT_DOMAIN=$(printf '%s' "$base_domain" | tr '[:upper:]' '[:lower:]')
                fi
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
                ;;
            *) return 0 ;;
        esac
    fi
    echo

    # Сразу после сообщения о сертификате показываем спиннер «Подготовка файлов»,
    # пока идут копирование сертификата в ssl/, firewall, при необходимости Docker и запись compose.
    local _BZ_ABORT=false
    local _bz_block_tmp _bz_prep_err
    _bz_block_tmp=$(mktemp)
    _bz_prep_err=$(mktemp)
    trap 'kill $(jobs -p) 2>/dev/null || true; _BZ_ABORT=true' INT

    (
        # ─── SSL-пути для nginx ───
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

        # IP-режим при unix+443: отдельный server на 80 с server_name = IP, иначе http://IP попадает в чужой vhost.
        local LISTEN_BLOCK REAL_IP_BLOCK
        if [ -f "${DIR_NGINX}nginx.conf" ] && grep -q 'listen unix:/dev/shm/nginx.sock' "${DIR_NGINX}nginx.conf"; then
            REAL_IP_BLOCK="    real_ip_header proxy_protocol;\n    set_real_ip_from unix:;"
            LISTEN_BLOCK="    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;\n    listen 443 ssl;"
        else
            LISTEN_BLOCK="    listen 443 ssl;\n    listen [::]:443 ssl;"
            REAL_IP_BLOCK=""
        fi

        local BESZEL_HTTP_BLOCK=""
        if [[ "$LISTEN_BLOCK" != *"unix:"* ]] || [ "$_is_ip_mode" = true ]; then
            BESZEL_HTTP_BLOCK=$(cat <<NGINX
server {
    server_name ${BESZEL_DOMAIN};
    listen 80;
    listen [::]:80;
    return 301 https://\$host\$request_uri;
}
NGINX
)
        fi

        local BESZEL_BLOCK
        BESZEL_BLOCK=$(cat <<NGINX
${BESZEL_HTTP_BLOCK}
server {
    server_name ${BESZEL_DOMAIN};
$(echo -e "$LISTEN_BLOCK")
    http2 on;
$(echo -e "$REAL_IP_BLOCK")

    ssl_certificate     ${NGINX_SSL_CERT};
    ssl_certificate_key ${NGINX_SSL_KEY};
    ssl_trusted_certificate ${NGINX_SSL_CERT};

    access_log /dev/stdout combined;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
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

        _beszel_setup_firewall 45876

        if ! { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }; then
            export DEBIAN_FRONTEND=noninteractive
            local DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'
            systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
            local _lw=0
            while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock \
                  /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend \
                  >/dev/null 2>&1; do
                sleep 2; _lw=$(( _lw + 2 )); [ "$_lw" -ge 120 ] && break
            done
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y -qq $DPKG_OPTS ca-certificates curl >/dev/null 2>&1
            dfc_install_docker_engine_official >/dev/null 2>&1 || true
            if ! { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }; then
                printf 'docker' > "$_bz_prep_err"
                exit 1
            fi
        fi

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

        printf '%s' "$BESZEL_BLOCK" > "$_bz_block_tmp"
     ) </dev/null &    if ! show_spinner "Подготовка файлов"; then
        local _prep_fail
        _prep_fail=$(cat "$_bz_prep_err" 2>/dev/null || true)
        rm -f "$_bz_prep_err" "$_bz_block_tmp"
        if [ "$_BZ_ABORT" = true ]; then
            echo
            echo -e "${YELLOW}⚠  Установка прервана — откат изменений...${NC}"
            nginx_remove_server_block "BESZEL" >/dev/null 2>&1 || true
            rm -rf "${DIR_BESZEL}" 2>/dev/null || true
            rm -rf "${DIR_NGINX}ssl/${CERT_DOMAIN:-}" 2>/dev/null || true
            (cd "${DIR_NGINX}" 2>/dev/null && docker compose restart nginx >/dev/null 2>&1) || true
            dfc_restore_interrupt_traps
            return 0
        fi
        dfc_restore_interrupt_traps
        if [ "$_prep_fail" = "docker" ]; then
            print_error "Docker не удалось установить"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || return 0
            return 0
        fi
        print_error "Не удалось подготовить файлы установки"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 0
        return 0
    fi
    rm -f "$_bz_prep_err"

    local BESZEL_BLOCK
    BESZEL_BLOCK=$(cat "$_bz_block_tmp" 2>/dev/null || true)
    rm -f "$_bz_block_tmp"
    if [ -z "$BESZEL_BLOCK" ]; then
        dfc_restore_interrupt_traps
        print_error "Не удалось подготовить конфигурацию Beszel"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 0
        return 0
    fi

    # Важно: не в подпроцессе — иначе _NGINX_EXTERNAL_BLOCKS не обновится в текущем шелле,
    # а nginx_reload опирается на актуальный nginx.conf + кэш блоков.
    nginx_add_server_block "BESZEL" "$BESZEL_BLOCK"

    if [ "$_BZ_ABORT" = true ]; then
        echo
        echo -e "${YELLOW}⚠  Установка прервана — откат изменений...${NC}"
        nginx_remove_server_block "BESZEL" >/dev/null 2>&1 || true
        rm -rf "${DIR_BESZEL}" 2>/dev/null || true
        rm -rf "${DIR_NGINX}ssl/${CERT_DOMAIN:-}" 2>/dev/null || true
        (cd "${DIR_NGINX}" 2>/dev/null && docker compose restart nginx >/dev/null 2>&1) || true
        dfc_restore_interrupt_traps
        return 0
    fi

    # ─── Запускаем Beszel ───
    local _bz_install_log
    _bz_install_log=$(mktemp)
    (
        cd "${DIR_BESZEL}" && docker compose up -d > "$_bz_install_log" 2>&1
     ) </dev/null &    if ! show_spinner "Установка панели Beszel"; then
        if [ "$_BZ_ABORT" = true ]; then
            echo
            echo -e "${YELLOW}⚠  Установка прервана — откат изменений...${NC}"
            docker compose -f "${DIR_BESZEL}docker-compose.yml" down --volumes >/dev/null 2>&1 || true
            rm -rf "${DIR_BESZEL}" 2>/dev/null || true
            nginx_remove_server_block "BESZEL" >/dev/null 2>&1 || true
            rm -rf "${DIR_NGINX}ssl/${CERT_DOMAIN:-}" 2>/dev/null || true
            (cd "${DIR_NGINX}" 2>/dev/null && docker compose restart nginx >/dev/null 2>&1) || true
            dfc_restore_interrupt_traps
            return 0
        fi
        echo
        local _bz_err_detail
        _bz_err_detail=$(tail -40 "$_bz_install_log" 2>/dev/null)
        if [ -z "$_bz_err_detail" ] && [ -f "${DIR_BESZEL}docker-compose.yml" ]; then
            _bz_err_detail=$(cd "${DIR_BESZEL}" && docker compose logs --no-log-prefix 2>&1 | tail -40) || true
        fi
        rm -f "$_bz_install_log"
        if [ -n "$_bz_err_detail" ]; then
            echo -e "${DARKGRAY}── Подробности ──────────────────────────${NC}"
            echo "$_bz_err_detail"
            echo -e "${DARKGRAY}────────────────────────────────────────${NC}"
        fi
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 0
        return 0
    fi
    rm -f "$_bz_install_log"

    # ─── Авто-установка агента на этом же сервере ───
    (
        _beszel_wait_api && _beszel_auto_install_agent
     ) </dev/null &    show_spinner "Подключение агента мониторинга" || true
    kill $(jobs -p) 2>/dev/null || true

    if [ "$_BZ_ABORT" = true ]; then
        echo
        echo -e "${YELLOW}⚠  Установка прервана — откат изменений...${NC}"
        docker compose -f "${DIR_BESZEL}docker-compose.yml" down --volumes >/dev/null 2>&1 || true
        rm -rf "${DIR_BESZEL}" 2>/dev/null || true
        nginx_remove_server_block "BESZEL" >/dev/null 2>&1 || true
        rm -rf "${DIR_NGINX}ssl/${CERT_DOMAIN:-}" 2>/dev/null || true
        (cd "${DIR_NGINX}" 2>/dev/null && docker compose restart nginx >/dev/null 2>&1) || true
        dfc_restore_interrupt_traps
        return 0
    fi

    # Запускаем/перезапускаем nginx
    (nginx_reload ) </dev/null &    show_spinner "Запуск Nginx"

    KEEP_CURSOR_HIDDEN=
    trap - RETURN

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "$(center "📊 Панель Beszel успешно установлена!" "$GREEN")"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}🔗 Панель мониторинга: ${WHITE}https://${BESZEL_DOMAIN}${NC}"
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${DARKGRAY}При первом входе создайте свою учётную запись администратора.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    dfc_restore_interrupt_traps
    show_continue_prompt || return 0
}

# ─── Изменение домена Beszel ───
change_domain_beszel() {
    if ! is_beszel_installed; then
        print_error "Beszel не установлен"
        return 1
    fi

    KEEP_CURSOR_HIDDEN=1
    trap 'KEEP_CURSOR_HIDDEN=; tput civis 2>/dev/null || true; stty sane 2>/dev/null || true; trap - RETURN' RETURN

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "$(center "🌐 Изменить домен для панели Beszel" "$BLUE")"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local NEW_DOMAIN
    prompt_domain_with_retry \
        "${YELLOW}Новый домен или IP для Beszel ${DARKGRAY}[например beszel.com]:${NC}" \
        NEW_DOMAIN true false false true || return 1
    if [ -n "${KEEP_CURSOR_HIDDEN:-}" ]; then
        tput civis 2>/dev/null || true
    fi
    local _cd_ip=false
    if [[ "$NEW_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        _cd_ip=true
    else
        NEW_DOMAIN=$(printf '%s' "$NEW_DOMAIN" | tr '[:upper:]' '[:lower:]')
    fi
    echo
    echo

    # Получаем сертификат
    local CERT_DOMAIN CERT_HOST_FULLCHAIN CERT_HOST_KEY
    local base_domain
    if [ "$_cd_ip" = true ]; then
        base_domain="$NEW_DOMAIN"
    else
        base_domain=$(extract_domain "$NEW_DOMAIN")
    fi

    if [ "$_cd_ip" = true ]; then
        local SELF_SIGNED_DIR
        SELF_SIGNED_DIR=$(mktemp -d)
        (
            local _ss_cfg
            _ss_cfg=$(mktemp)
            {
                echo "[req]"
                echo "distinguished_name = req_dn"
                echo "x509_extensions = v3_req"
                echo "prompt = no"
                echo
                echo "[req_dn]"
                echo "CN = ${NEW_DOMAIN}"
                echo
                echo "[v3_req]"
                echo "subjectAltName = IP:${NEW_DOMAIN}"
            } > "$_ss_cfg"
            openssl req -x509 -nodes -days 3650 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
                -keyout "${SELF_SIGNED_DIR}/privkey.pem" \
                -out "${SELF_SIGNED_DIR}/fullchain.pem" \
                -config "$_ss_cfg" >/dev/null 2>&1
            rm -f "$_ss_cfg"
         ) </dev/null &        show_spinner --step "Генерация самоподписанного сертификата"
        CERT_DOMAIN="$NEW_DOMAIN"
        CERT_HOST_FULLCHAIN="${SELF_SIGNED_DIR}/fullchain.pem"
        CERT_HOST_KEY="${SELF_SIGNED_DIR}/privkey.pem"
    else
        local _le_found
        _le_found=$(le_live_basename "$NEW_DOMAIN" 2>/dev/null) || _le_found=""
        if [ -n "$_le_found" ]; then
            print_cert_exists "${NEW_DOMAIN}"
            CERT_DOMAIN="$_le_found"
            CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
            CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
        elif _le_found=$(le_live_basename "$base_domain" 2>/dev/null) && [ -n "$_le_found" ]; then
            print_cert_exists "${base_domain}"
            CERT_DOMAIN="$_le_found"
            CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
            CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
        else
            show_arrow_menu "${BLUE}🔒  Получение SSL сертификата${NC}" \
            "🌐  ACME (Let's Encrypt HTTP-01)" \
            "☁️   Cloudflare (DNS-01 Wildcard)" \
            "🔷  Gcore (DNS-01 Wildcard)" \
            "──────────────────────────────────────" \
            "❌  Отмена"
        local cert_choice=$?
        [[ $cert_choice -eq 255 ]] && return 0

        case $cert_choice in
            0)
                reading_inline "Email для Let's Encrypt:" BESZEL_EMAIL
                [[ $? -eq 2 ]] && return 1
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    echo
                    show_continue_prompt || return 0
                    return 0
                fi
                if ! get_cert_acme "$NEW_DOMAIN" "$BESZEL_EMAIL"; then
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || return 0
                    return 0
                fi
                _le_found=$(le_live_basename "$NEW_DOMAIN" 2>/dev/null) || _le_found=""
                if [ -n "$_le_found" ]; then
                    CERT_DOMAIN="$_le_found"
                else
                    CERT_DOMAIN=$(printf '%s' "$NEW_DOMAIN" | tr '[:upper:]' '[:lower:]')
                fi
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
                ;;
            1)
                reading_inline "Email для Let's Encrypt:" BESZEL_EMAIL
                [[ $? -eq 2 ]] && return 1
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    echo
                    show_continue_prompt || return 0
                    return 0
                fi
                if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                    setup_cloudflare_credentials || return 1
                fi
                if ! get_cert_cloudflare "$base_domain" "$BESZEL_EMAIL"; then
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || return 0
                    return 0
                fi
                echo
                _le_found=$(le_live_basename "$base_domain" 2>/dev/null) || _le_found=""
                if [ -n "$_le_found" ]; then
                    CERT_DOMAIN="$_le_found"
                else
                    CERT_DOMAIN=$(printf '%s' "$base_domain" | tr '[:upper:]' '[:lower:]')
                fi
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
                ;;
            2)
                reading_inline "Email для Let's Encrypt:" BESZEL_EMAIL
                [[ $? -eq 2 ]] && return 1
                if [ -z "$BESZEL_EMAIL" ]; then
                    print_error "Email не может быть пустым"
                    echo
                    show_continue_prompt || return 0
                    return 0
                fi
                if [ ! -f "/etc/letsencrypt/gcore.ini" ]; then
                    setup_gcore_credentials || return 1
                fi
                if ! get_cert_gcore "$base_domain" "$BESZEL_EMAIL"; then
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    show_continue_prompt || return 0
                    return 0
                fi
                echo
                _le_found=$(le_live_basename "$base_domain" 2>/dev/null) || _le_found=""
                if [ -n "$_le_found" ]; then
                    CERT_DOMAIN="$_le_found"
                else
                    CERT_DOMAIN=$(printf '%s' "$base_domain" | tr '[:upper:]' '[:lower:]')
                fi
                CERT_HOST_FULLCHAIN="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
                CERT_HOST_KEY="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
                ;;
            *) return 0 ;;
        esac
        fi
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
        REAL_IP_BLOCK="    real_ip_header proxy_protocol;\n    set_real_ip_from unix:;"
        LISTEN_BLOCK="    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;\n    listen 443 ssl;"
    else
        LISTEN_BLOCK="    listen 443 ssl;\n    listen [::]:443 ssl;"
        REAL_IP_BLOCK=""
    fi

    local BESZEL_HTTP_BLOCK=""
    if [[ "$LISTEN_BLOCK" != *"unix:"* ]] || [ "$_cd_ip" = true ]; then
        BESZEL_HTTP_BLOCK=$(cat <<NGINX
server {
    server_name ${NEW_DOMAIN};
    listen 80;
    listen [::]:80;
    return 301 https://\$host\$request_uri;
}
NGINX
)
    fi

    local BESZEL_BLOCK
    BESZEL_BLOCK=$(cat <<NGINX
${BESZEL_HTTP_BLOCK}
server {
    server_name ${NEW_DOMAIN};
$(echo -e "$LISTEN_BLOCK")
    http2 on;
$(echo -e "$REAL_IP_BLOCK")

    ssl_certificate     ${NGINX_SSL_CERT};
    ssl_certificate_key ${NGINX_SSL_KEY};
    ssl_trusted_certificate ${NGINX_SSL_CERT};

    access_log /dev/stdout combined;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
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

    nginx_add_server_block "BESZEL" "$BESZEL_BLOCK"
    nginx_cleanup_unused_certs

    (nginx_reload ) </dev/null &    show_spinner "Перезапуск Nginx"

    # Если агент использует публичный домен (не localhost) — обновляем его HUB_URL
    if is_beszel_agent_installed; then
        local _AGENT_HUB
        _AGENT_HUB=$(grep 'HUB_URL:' "${DIR_BESZEL_AGENT}docker-compose.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')
        if [[ "$_AGENT_HUB" != "http://127.0.0.1"* ]] && [ -n "$_AGENT_HUB" ]; then
            (
                sed -i "s|HUB_URL: \"[^\"]*\"|HUB_URL: \"https://${NEW_DOMAIN}\"|" "${DIR_BESZEL_AGENT}docker-compose.yml"
                cd "${DIR_BESZEL_AGENT}" && docker compose up -d --force-recreate >/dev/null 2>&1
             ) </dev/null &            show_spinner "Обновление агента"
        fi
    fi
    KEEP_CURSOR_HIDDEN=
    trap - RETURN

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
    reading_inline "Новый домен/ip хаба ${DARKGRAY}(например example.com)${YELLOW}:" NEW_HUB_URL
    [[ $? -eq 2 ]] && return 1
    if [ -z "$NEW_HUB_URL" ]; then
        print_error "Адрес не может быть пустым"
        echo; show_continue_prompt || return 1; return 1
    fi

    # Нормализуем URL
    if [[ "$NEW_HUB_URL" != http://* ]] && [[ "$NEW_HUB_URL" != https://* ]]; then
        NEW_HUB_URL="https://${NEW_HUB_URL}"
    fi

    echo

    local CURRENT_KEY CURRENT_TOKEN
    CURRENT_KEY=$(grep 'KEY:' "${DIR_BESZEL_AGENT}docker-compose.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')
    CURRENT_TOKEN=$(grep 'TOKEN:' "${DIR_BESZEL_AGENT}docker-compose.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')

    # ─── Новый ключ ───
    local NEW_KEY
    reading_inline "Новый публичный ключ (Enter оставить без изменений):" NEW_KEY
    [[ $? -eq 2 ]] && return 1
    [ -z "$NEW_KEY" ] && NEW_KEY="$CURRENT_KEY"

    echo

    # ─── Новый токен ───
    local NEW_TOKEN
    reading_inline "Новый токен (Enter оставить без изменений):" NEW_TOKEN
    [[ $? -eq 2 ]] && return 1
    [ -z "$NEW_TOKEN" ] && NEW_TOKEN="$CURRENT_TOKEN"

    echo
    echo

    (
        sed -i "s|HUB_URL: \"[^\"]*\"|HUB_URL: \"${NEW_HUB_URL}\"|" "${DIR_BESZEL_AGENT}docker-compose.yml"
        sed -i "s|KEY: \"[^\"]*\"|KEY: \"${NEW_KEY}\"|" "${DIR_BESZEL_AGENT}docker-compose.yml"
        sed -i "s|TOKEN: \"[^\"]*\"|TOKEN: \"${NEW_TOKEN}\"|" "${DIR_BESZEL_AGENT}docker-compose.yml"
        cd "${DIR_BESZEL_AGENT}" && docker compose up -d --force-recreate >/dev/null 2>&1
     ) </dev/null &    show_spinner "Настройки агента обновлены"

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
        if ! confirm_nav --delete "🗑️  Удаление панели Beszel"; then
            return
        fi
    fi

    KEEP_CURSOR_HIDDEN=1
    trap 'KEEP_CURSOR_HIDDEN=; tput cnorm 2>/dev/null || true; trap - RETURN' RETURN

    (
        cd "${DIR_BESZEL}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
     ) </dev/null &    show_spinner "Удаление контейнеров панели Beszel"

    # Удаляем server-блок beszel из nginx.conf.
    # Если Beszel был на IPv4 или со старым default_server — восстанавливаем catch-all, если его нет
    # (старые установки могли удалить блок ssl_reject).
    local _beszel_restore_catchall=false
    local _beszel_blk
    if [ -f "${DIR_NGINX}nginx.conf" ]; then
        _beszel_blk=$(sed -n '/# BEGIN_BESZEL_BLOCK/,/# END_BESZEL_BLOCK/p' "${DIR_NGINX}nginx.conf" 2>/dev/null || true)
        if echo "$_beszel_blk" | grep -qE 'server_name[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
            _beszel_restore_catchall=true
        fi
        if echo "$_beszel_blk" | grep -q 'default_server'; then
            _beszel_restore_catchall=true
        fi
    fi

    nginx_remove_server_block "BESZEL"

    if [ "$_beszel_restore_catchall" = true ] && [ -f "${DIR_NGINX}nginx.conf" ]; then
        if ! grep -q 'ssl_reject_handshake' "${DIR_NGINX}nginx.conf" 2>/dev/null; then
            sed -i 's|} # ─── end http ───|server {\n    listen 443 ssl default_server;\n    server_name _;\n    ssl_reject_handshake on;\n}\n} # ─── end http ───|' "${DIR_NGINX}nginx.conf"
        fi
    fi

    # Удаляем неиспользуемые сертификаты из /opt/nginx/ssl/
    nginx_cleanup_unused_certs

    # Перезапускаем или удаляем nginx
    if nginx_has_users; then
        (nginx_reload ) </dev/null &        show_spinner "Перезапуск Nginx"
    else
        (nginx_teardown ) </dev/null &        show_spinner "Удаление Nginx"
    fi

    rm -rf "${DIR_BESZEL}"

    [ "$_force" = true ] && return 0

    KEEP_CURSOR_HIDDEN=
    trap - RETURN

    _beszel_post_delete_success_screen "🗑️  Удаление панели Beszel" "✅ Панель Beszel была успешно удалёна!"
}

install_beszel_agent() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "$(center "🖥️  Подключение агента Beszel" "$BLUE")"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    if is_beszel_agent_installed; then
        echo
        print_success "Агент Beszel уже установлен"
        echo
        show_continue_prompt || return 0
        return 0
    fi

    echo
    echo -e "${DARKGRAY}В панели управления Beszel нажмите Добавить систему → скопируйте Ключ и Токен.${NC}"
    echo

    local BESZEL_HUB_URL BESZEL_AGENT_PORT BESZEL_KEY BESZEL_TOKEN
    BESZEL_AGENT_PORT="45876"
    local _step=1

    # Стереть предыдущую строку (answered line) при возврате назад
    _bza_erase() { printf "\033[A\033[K"; }

    while true; do
        case $_step in
            1) # URL
                _mt_read_input BESZEL_HUB_URL "Домен панели Beszel ${DARKGRAY}(например monitor.example.com):" ""
                if [ $? -eq 0 ]; then
                    if [ -z "$BESZEL_HUB_URL" ]; then
                        _bza_erase   # стереть пустую строку, повторить
                    else
                        (( _step++ ))
                    fi
                else
                    return 1   # Esc на 1-м шаге — выход
                fi ;;
            2) # Порт
                _mt_read_input BESZEL_AGENT_PORT "Порт агента ${DARKGRAY}(по умолчанию 45876):" "45876"
                if [ $? -eq 0 ]; then
                    [ -z "$BESZEL_AGENT_PORT" ] && BESZEL_AGENT_PORT="45876"
                    (( _step++ ))
                else
                    _bza_erase; (( _step-- ))
                fi ;;
            3) # Ключ
                _mt_read_input BESZEL_KEY "Ключ ${DARKGRAY}(публичный ключ из панели):" ""
                if [ $? -eq 0 ]; then
                    if [ -z "$BESZEL_KEY" ]; then
                        _bza_erase
                    else
                        (( _step++ ))
                    fi
                else
                    _bza_erase; (( _step-- ))
                fi ;;
            4) # Токен
                _mt_read_input BESZEL_TOKEN "Токен ${DARKGRAY}(токен из панели):" ""
                if [ $? -eq 0 ]; then
                    if [ -z "$BESZEL_TOKEN" ]; then
                        _bza_erase
                    else
                        break
                    fi
                else
                    _bza_erase; (( _step-- ))
                fi ;;
        esac
    done

    # Нормализуем URL (добавляем https:// если не указан протокол)
    if [[ "$BESZEL_HUB_URL" != http://* ]] && [[ "$BESZEL_HUB_URL" != https://* ]]; then
        BESZEL_HUB_URL="https://${BESZEL_HUB_URL}"
    fi

    echo
    echo

    KEEP_CURSOR_HIDDEN=1
    trap 'KEEP_CURSOR_HIDDEN=; tput cnorm 2>/dev/null || true; stty sane 2>/dev/null || true; trap - RETURN' RETURN

    # ─── Шаг 1: Обновление системы и установка пакетов ───
    (
        export DEBIAN_FRONTEND=noninteractive
        local DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

        apt-get update -qq >/dev/null 2>&1
        apt-get upgrade -y -qq $DPKG_OPTS >/dev/null 2>&1
        apt-get install -y -qq $DPKG_OPTS ca-certificates curl wget >/dev/null 2>&1
        if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
            dfc_install_docker_engine_official >/dev/null 2>&1 || true
        fi
     ) </dev/null &    show_spinner --step "Обновление пакетов системы"
    echo

    # ─── UFW: SSH и порт агента (без постоянного 80/443 — нода ходит к хабу исходящим) ───
    _beszel_setup_firewall --agent-node "${BESZEL_AGENT_PORT}"

    # ─── Шаг 2: Создаём файлы ───
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
     ) </dev/null &    show_spinner --step "Подготовка файлов"

    (
        cd "${DIR_BESZEL_AGENT}" && docker compose up -d >/dev/null 2>&1
     ) </dev/null &    if ! show_spinner --step "Добавление агента Beszel"; then
        KEEP_CURSOR_HIDDEN=
        trap - RETURN
        echo
        print_error "Не удалось запустить агент. Проверьте логи: cd ${DIR_BESZEL_AGENT} && docker compose logs"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 0
        return 0
    fi

    KEEP_CURSOR_HIDDEN=
    trap - RETURN

    echo
    echo -e "${GREEN}✅ Агент Beszel успешно установлен!${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || return 0
}

uninstall_beszel_agent() {
    local _force=false
    [[ "${1:-}" == "--force" ]] && _force=true

    if [ "$_force" = false ]; then
        if ! confirm_nav --delete "🗑️  Удаление агента Beszel"; then
            return
        fi
    fi

    KEEP_CURSOR_HIDDEN=1
    trap 'KEEP_CURSOR_HIDDEN=; tput cnorm 2>/dev/null || true; trap - RETURN' RETURN

    local AGENT_PORT_STORED
    AGENT_PORT_STORED=$(grep 'LISTEN:' "${DIR_BESZEL_AGENT}docker-compose.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')

    (
        cd "${DIR_BESZEL_AGENT}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
     ) </dev/null &    show_spinner --step "Удаление агента Beszel"

    if [ -n "$AGENT_PORT_STORED" ]; then
        ufw delete allow "${AGENT_PORT_STORED}/tcp" >/dev/null 2>&1 || true
    fi

    rm -rf "${DIR_BESZEL_AGENT}"

    [ "$_force" = true ] && return 0

    KEEP_CURSOR_HIDDEN=
    trap - RETURN

    _beszel_post_delete_success_screen "🗑️  Удаление агента Beszel" "✅ Агент Beszel был успешно удалён!"
}
