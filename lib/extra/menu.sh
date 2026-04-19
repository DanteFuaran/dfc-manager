# ═══════════════════════════════════════════════════
# ДОПОЛНИТЕЛЬНЫЕ ПРОГРАММЫ — ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════════
manage_extra_settings() {
    while true; do
        tput civis 2>/dev/null || true
        clear

        local _ufw_st _warp_st _f2b_st
        command -v ufw >/dev/null 2>&1 && _ufw_st="${GREEN}(установлен)${NC}" || _ufw_st="${DARKGRAY}(не установлен)${NC}"
        ip link show warp 2>/dev/null | grep -q "warp" && _warp_st="${GREEN}(установлен)${NC}" || _warp_st="${DARKGRAY}(не установлен)${NC}"
        command -v fail2ban-client >/dev/null 2>&1 && _f2b_st="${GREEN}(установлен)${NC}" || _f2b_st="${DARKGRAY}(не установлен)${NC}"

        show_arrow_menu "🧩  Дополнительные программы" \
            "🔥  UFW - Firewall      ${_ufw_st}" \
            "🌐  WARP - Cloudflare   ${_warp_st}" \
            "🛡️   Fail2ban - Defence  ${_f2b_st}" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) manage_ufw || break ;;
            1) manage_warp || break ;;
            2) manage_fail2ban || break ;;
            3) continue ;;
            4) return ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MTPROTO — УПРАВЛЕНИЕ
# ═══════════════════════════════════════════════════
_MT_CONTAINER="mtproto-proxy"
_MT_IMAGE="nineseconds/mtg:2"
_MT_DIR="/opt/mtproto"
_MT_ENV="${_MT_DIR}/.env"

_mt_installed() { docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${_MT_CONTAINER}$"; }
_mt_running()   { docker ps    --format '{{.Names}}' 2>/dev/null | grep -q "^${_MT_CONTAINER}$"; }
_mt_load_env()  { [ -f "$_MT_ENV" ] && source "$_MT_ENV" 2>/dev/null || true; }

_mt_press_enter() {
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e " ${BLUE}Enter${DARKGRAY}: Продолжить${NC}"
    tput civis 2>/dev/null || true
    read -r
    tput cnorm 2>/dev/null || true
}

# ── MTProto install helpers ──────────────────────────────────────────────────

# Поглощает CSI/SS3 escape-последовательность из буфера ввода (после \e)
_mt_consume_escape_seq() {
    local _s1="" _s2=""
    read -rsn1 -t 0.1 _s1 2>/dev/null || _s1=""
    if [[ "$_s1" == '[' ]] || [[ "$_s1" == 'O' ]]; then
        while true; do
            read -rsn1 -t 0.1 _s2 2>/dev/null || { _s2=""; break; }
            [[ -z "$_s2" ]] && break
            [[ "$_s2" =~ [a-zA-Z~] ]] && break
        done
    fi
}

# Интерактивный ввод строки (Backspace, зелёный ввод)
# Esc → возвращает 1 ("назад"), Enter → записывает значение и возвращает 0
# Использование: _mt_read_input VARNAME "Промпт" "default" || { на_шаг_назад; }
_mt_read_input() {
    local _var="$1" _prompt="$2" _default="${3:-}"
    local _typed="" _ch _orig_stty _rc=0
    _orig_stty=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo isig min 1 time 0 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf "\033[1;34m\xe2\x9e\x9c\033[0m  \033[1;33m%b\033[0m " "$_prompt"
    while IFS= read -rsn1 -t 0 _ch 2>/dev/null; do :; done
    while true; do
        _ch=""
        IFS= read -rsn1 _ch 2>/dev/null || _ch=""
        if [[ "$_ch" == $'\n' ]] || [[ "$_ch" == $'\r' ]] || [[ "$_ch" == "" ]]; then
            printf "\n"; break
        elif [[ "$_ch" == $'\x7f' ]] || [[ "$_ch" == $'\b' ]]; then
            if [ "${#_typed}" -gt 0 ]; then _typed="${_typed%?}"; printf '\b \b'; fi
        elif [[ "$_ch" == $'\e' ]]; then
            _mt_consume_escape_seq
            printf "\r\033[K"   # стрерть текущую строку без перевода
            _rc=1; break
        elif [[ -n "$_ch" ]] && [[ "$_ch" =~ [[:print:]] ]]; then
            _typed="${_typed}${_ch}"
            printf "${GREEN}%s${NC}" "$_ch"
        fi
    done
    if [ -n "${_orig_stty}" ]; then stty "$_orig_stty" 2>/dev/null || stty sane 2>/dev/null || true
    else stty sane 2>/dev/null || true; fi
    if [ "$_rc" -eq 0 ]; then
        if [ -z "$_typed" ]; then printf -v "$_var" '%s' "$_default"
        else printf -v "$_var" '%s' "$_typed"; fi
    fi
    return $_rc
}

# Получает внешний IP сервера
_mt_get_server_ip() {
    curl -s --max-time 5 ifconfig.me 2>/dev/null ||
    curl -s --max-time 5 icanhazip.com 2>/dev/null ||
    curl -s --max-time 5 api.ipify.org 2>/dev/null ||
    echo "YOUR_IP"
}

# Проверяет/устанавливает Docker
_mt_check_docker() {
    if ! command -v docker &>/dev/null; then
        print_warning "Docker не установлен"
        echo
        echo -e "  ${YELLOW}Установить Docker автоматически? [y/N]${NC}"
        local _ans=""
        read -r _ans
        if [[ "$_ans" =~ ^[Yy]$ ]]; then
            (curl -fsSL https://get.docker.com | sh >/dev/null 2>&1) &
            show_spinner "Установка Docker..." "Docker установлен"
        else
            return 1
        fi
    fi
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker не запущен"; return 1
    fi
    if ! command -v sqlite3 &>/dev/null; then
        (DEBIAN_FRONTEND=noninteractive apt-get install -y -q sqlite3 >/dev/null 2>&1) &
        show_spinner "Установка необходимых компонентов" "Компоненты установлены"
    fi
}

# Генерирует Fake TLS secret (ee-формат: ee + 16 случайных байт + hex(domain))
# Совместим с nineseconds/mtg:2 и другими modern-реализациями
_mt_generate_fake_tls_secret() {
    local domain="${1:-google.com}"
    local domain_hex
    domain_hex=$(printf '%s' "$domain" | xxd -ps | tr -d '\n')
    local random_hex
    random_hex=$(openssl rand -hex 16 2>/dev/null)
    printf 'ee%s%s' "$random_hex" "$domain_hex"
}

# Извлекает «сырой» 32-символьный секрет (16 байт hex) из FakeTLS-обёртки
# ee<32hex><domain_hex> → <32hex>
_mt_extract_raw_secret() {
    local s="${1:-}"
    if [[ "$s" =~ ^[Ee]{2} ]] && [ ${#s} -gt 34 ]; then
        echo "${s:2:32}"
    else
        echo "$s"
    fi
}

# Секрет для Telegram ссылок: ee + 32 hex (без домена)
# ee<32hex><domain_hex> → ee<32hex>
_mt_link_secret() {
    local s="${1:-}"
    local raw; raw=$(_mt_extract_raw_secret "$s")
    echo "ee${raw}"
}

# Ищет свободный порт начиная с base
_mt_find_free_port() {
    local base="${1:-8443}"
    for port in "$base" 8444 8445 9443 10443 1337; do
        if ! ss -tuln 2>/dev/null | grep -q ":${port} "; then
            echo "$port"; return 0
        fi
    done
    echo "10443"
}

# Сохраняет конфиг в .env и config.toml
_mt_save_config() {
    mkdir -p "$_MT_DIR"
    cat > "$_MT_ENV" << EOF
PROXY_PORT=${PROXY_PORT}
PROXY_SECRET=${PROXY_SECRET}
SERVER_IP=${SERVER_IP}
FAKE_DOMAIN=${FAKE_DOMAIN}
PROXY_TAG=${PROXY_TAG}
PROXY_NAME=${PROXY_NAME:-}
EOF
    # config.toml для mtg:2
    local _pp="false"
    # PROXY protocol только при работе через nginx stream (порт 443)
    _mt_nginx_available && [ "${PROXY_PORT:-}" = "443" ] && _pp="true"
    cat > "${_MT_DIR}/config.toml" << TOML
# Конфигурация MTProto прокси (mtg v2) — управляется dfc-manager

secret = "${PROXY_SECRET}"
bind-to = "0.0.0.0:3128"

# PROXY protocol от nginx для получения реальных IP клиентов
proxy-protocol-listener = ${_pp}

# Предпочтение IPv4/IPv6 для связи с Telegram
prefer-ip = "prefer-ipv4"

# Защита от replay-атак
[defense.anti-replay]
enabled = true
max-size = "1mib"
error-rate = 0.001

# Таймауты сети
[network.timeout]
tcp = "5s"
http = "10s"
idle = "5m"

# TCP Keep-Alive (быстрое обнаружение отключённых клиентов)
[network.keep-alive]
disabled = false
idle = "30s"
interval = "10s"
count = 3
TOML
    if [ -n "${PROXY_TAG:-}" ]; then
        printf '\nadvertise-tag = "%s"\n' "${PROXY_TAG}" >> "${_MT_DIR}/config.toml"
    fi
    _mt_write_proxy_page "${SERVER_IP:-}" "${PROXY_SECRET:-}" "${PROXY_PORT:-}" "${PROXY_NAME:-}"
}

# Выпускает SSL-сертификат для домена через certbot standalone (порт 80)
# Возвращает 0 если сертификат готов (новый или уже существующий), 1 при ошибке
_mt_issue_cert() {
    local _domain="${1:-}"
    # Если это IP — сертификат не нужен
    if [[ "$_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi
    [ -z "$_domain" ] && return 1
    local _cert_dir="/etc/letsencrypt/live/${_domain}"
    # Уже есть — ок
    if [ -f "${_cert_dir}/fullchain.pem" ]; then
        return 0
    fi
    # Открываем порт 80, выпускаем, закрываем
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp >/dev/null 2>&1 || true
    fi
    certbot certonly --standalone --non-interactive --agree-tos \
        --register-unsafely-without-email \
        --preferred-challenges http-01 \
        --http-01-port 80 \
        -d "$_domain" >/dev/null 2>&1
    local _rc=$?
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow 80/tcp >/dev/null 2>&1 || true
    fi
    return $_rc
}

# Находит имя nginx-контейнера
_mt_nginx_container() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -i nginx | head -1
}

# Добавляет домен в nginx: stream map + server block с /connect
_mt_nginx_add_domain() {
    local _domain="${1:-}" _secret="${2:-}" _port="${3:-}" _name="${4:-}"
    [ -z "$_domain" ] || [ -z "$_secret" ] || [ -z "$_port" ] && return 1
    [[ "$_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 1

    local _nginx_conf="/opt/nginx/nginx.conf"
    local _ssl_dir="/opt/nginx/ssl/${_domain}"
    local _cert_src="/etc/letsencrypt/live/${_domain}"

    [ -f "${_cert_src}/fullchain.pem" ] || return 1

    # Копируем сертификат в nginx ssl папку
    mkdir -p "$_ssl_dir"
    cp "${_cert_src}/fullchain.pem" "${_ssl_dir}/fullchain.pem"
    cp "${_cert_src}/privkey.pem"   "${_ssl_dir}/privkey.pem"

    # Renewal hook — копирует сертификат и перезагружает nginx
    local _hook_file="/etc/letsencrypt/renewal-hooks/deploy/mtproto-${_domain}.sh"
    cat > "$_hook_file" << HOOK
#!/bin/bash
# Авторенью: копирует сертификат в nginx ssl и перезагружает nginx
D="${_domain}"
mkdir -p /opt/nginx/ssl/\$D
cp /etc/letsencrypt/live/\$D/fullchain.pem /opt/nginx/ssl/\$D/fullchain.pem
cp /etc/letsencrypt/live/\$D/privkey.pem   /opt/nginx/ssl/\$D/privkey.pem
NGINX=\$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i nginx | head -1)
[ -n "\$NGINX" ] && docker exec "\$NGINX" nginx -s reload 2>/dev/null || true
HOOK
    chmod +x "$_hook_file"

    # Добавляем домен в stream map если есть stream-блок и домен не добавлен
    if grep -q "# BEGIN_MTPROTO_STREAM" "$_nginx_conf" 2>/dev/null && ! grep -q "${_domain}.*127.0.0.1:8444" "$_nginx_conf"; then
        sed -i "s|default\s\+127\.0\.0\.1:8445|${_domain}   127.0.0.1:8444;\n        default                 127.0.0.1:8445|" "$_nginx_conf"
    fi

    # Генерируем HTML-страницу /connect
    _mt_write_proxy_page "$_domain" "$_secret" "$_port" "$_name"

    local _html_path="/var/www/html/mtproto-connect.html"
    local _connect_marker="# BEGIN_MT_CONNECT_${_domain}"

    # Добавляем server block если не добавлен
    if ! grep -q "$_connect_marker" "$_nginx_conf"; then
        # Записываем block во временный файл, затем вставляем через awk перед маркером закрытия http
        local _tmpf; _tmpf=$(mktemp)
        cat > "$_tmpf" << NGINX_BLOCK

${_connect_marker}
server {
    server_name ${_domain};
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/${_domain}/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/${_domain}/privkey.pem";

    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;

    location = /connect {
        default_type text/html;
        alias ${_html_path};
    }

    location / {
        return 444;
    }
}
# END_MT_CONNECT_${_domain}
NGINX_BLOCK
        awk '/end http/ { while ((getline line < blockfile) > 0) print line; close(blockfile) } { print }' \
            blockfile="$_tmpf" "$_nginx_conf" > "${_nginx_conf}.tmp" \
            && mv "${_nginx_conf}.tmp" "$_nginx_conf"
        rm -f "$_tmpf"
    else
        # Обновляем только HTML-файл (server block уже есть)
        :
    fi

    # Перезагружаем nginx (полный рестарт чтобы подхватить новые server blocks)
    local _nc; _nc=$(_mt_nginx_container)
    if [ -n "$_nc" ]; then
        docker exec "$_nc" nginx -t 2>/dev/null \
            && docker restart "$_nc" >/dev/null 2>&1 \
            || true
    fi
}

# Генерирует HTML-страницу с лоадером для редиректа в Telegram
_mt_write_proxy_page() {
    local _domain="${1:-${SERVER_IP:-}}"
    local _secret="${2:-${PROXY_SECRET:-}}"
    local _port="${3:-${PROXY_PORT:-}}"
    local _name="${4:-${PROXY_NAME:-}}"
    [ -z "$_secret" ] || [ -z "$_port" ] || [ -z "$_domain" ] && return 0

    local _display_name="${_name:-MTProto Proxy}"
    local _tg_url="tg://proxy?server=${_domain}&port=${_port}&secret=${_secret}"
    local _html_path="/var/www/html/mtproto-connect.html"

    mkdir -p /var/www/html
    cat > "$_html_path" << HTMLEOF
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_display_name}</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#17212b;color:#fff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{text-align:center;padding:2.5rem 2rem;max-width:360px;width:100%}
.loader{width:56px;height:56px;margin:0 auto 1.5rem;position:relative}
.loader::before,.loader::after{content:'';position:absolute;border-radius:50%}
.loader::before{width:100%;height:100%;border:3px solid rgba(255,255,255,.12);top:0;left:0}
.loader::after{width:100%;height:100%;border:3px solid transparent;border-top-color:#5da8d6;top:0;left:0;animation:spin .9s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.plane{font-size:1.8rem;position:absolute;top:50%;left:50%;transform:translate(-50%,-50%)}
h1{font-size:1.4rem;font-weight:700;margin-bottom:.4rem;letter-spacing:-.01em}
.sub{color:#7a9db8;font-size:.95rem;margin-bottom:2rem}
.btn{display:inline-flex;align-items:center;gap:.5rem;padding:.8rem 2rem;background:#2b5278;border-radius:10px;color:#fff;text-decoration:none;font-size:1rem;font-weight:500;transition:background .2s,transform .1s}
.btn:hover{background:#3a6d9e}
.btn:active{transform:scale(.97)}
.btn svg{width:20px;height:20px;fill:none;stroke:#fff;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
</style>
</head>
<body>
<div class="card">
  <div class="loader"><span class="plane">✈️</span></div>
  <h1>${_display_name}</h1>
  <div class="sub">Телеграм прокси</div>
  <a class="btn" id="btn" href="${_tg_url}">
    <svg viewBox="0 0 24 24"><path d="M22 2L11 13"/><path d="M22 2L15 22 11 13 2 9l20-7z"/></svg>
    Подключиться
  </a>
</div>
<script>
var TG="${_tg_url}",done=false;
function go(){
  if(done)return;done=true;
  window.location.href=TG;
}
setTimeout(go,1200);
setTimeout(function(){window.close()},10000);
document.getElementById('btn').addEventListener('click',function(e){e.preventDefault();go();});
</script>
</body>
</html>
HTMLEOF

    # Обновляем старую test-n страницу для совместимости
    [ -f /var/www/html/mtproto.html ] && cp "$_html_path" /var/www/html/mtproto.html 2>/dev/null || true
}

# Записывает docker-compose.yml
_mt_write_compose() {
    mkdir -p "$_MT_DIR"
    local _port_map="127.0.0.1:3128:3128"
    # Если порт ≠ 443 и нет nginx stream — mtg слушает напрямую на PROXY_PORT
    if [ "${PROXY_PORT:-443}" != "443" ]; then
        _port_map="0.0.0.0:${PROXY_PORT}:3128"
    fi
    cat > "${_MT_DIR}/docker-compose.yml" << COMPOSE
services:
  mtproto-proxy:
    image: nineseconds/mtg:2
    container_name: mtproto-proxy
    restart: unless-stopped
    ports:
      - "${_port_map}"
    volumes:
      - ./config.toml:/config.toml:ro
    command: run /config.toml
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE
}

# Установка / переустановка MTProto (встроенная реализация)
# Шаги ввода: 1-домен, 2-порт, 3-секрет, 4-IP, 5-tag.  Esc → предыдущий шаг.
# При Esc стираем строки текущего шага и повторно выводим предыдущий инпут.
_mt_do_install() {
    set +e
    local PROXY_PORT PROXY_SECRET SERVER_IP FAKE_DOMAIN PROXY_TAG PROXY_NAME
    PROXY_PORT="8443"
    FAKE_DOMAIN="google.com"
    PROXY_SECRET=""
    SERVER_IP=""
    PROXY_TAG=""
    PROXY_NAME=""
    [ -f "$_MT_ENV" ] && source "$_MT_ENV" 2>/dev/null || true

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       📦 Установка MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    _mt_check_docker || { _mt_press_enter; return; }

    # _mt_erase_lines N — стираем N строк вверх (текущая уже пустая после \r\033[K)
    _mt_erase_lines() {
        local n=$1
        while [ $n -gt 0 ]; do
            printf "\033[A\033[K"
            (( n-- ))
        done
    }

    local _step=1 _secret_input=""

    while true; do
        case $_step in
            1) # IP/домен для ссылки с проверкой
                local _default_host="${SERVER_IP:-$(_mt_get_server_ip)}"
                while true; do
                    _mt_read_input SERVER_IP "Домен или IP для ссылки подключения ${DARKGRAY}[${_default_host}]${NC}:" "$_default_host"
                    if [ $? -eq 1 ]; then
                        return  # Esc на первом шаге — выход
                    fi
                    
                    # Проверяем сопоставление домена/IP с сервером
                    if check_domain "$SERVER_IP" true; then
                        (( _step++ ))
                        break
                    fi
                    
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить   ${BLUE}S${DARKGRAY}: Пропустить   ${BLUE}Esc${DARKGRAY}: Назад${NC}"
                    
                    tput civis 2>/dev/null || true
                    local key
                    while true; do
                        read -s -n 1 key
                        if [[ "$key" == $'\x1b' ]]; then
                            tput cnorm 2>/dev/null || true
                            echo
                            return  # Esc — выход из установки
                        elif [[ "$key" == "s" || "$key" == "S" ]]; then
                            tput cnorm 2>/dev/null || true
                            (( _step++ ))
                            break 2  # Пропустить проверку
                        elif [[ "$key" == "" ]]; then
                            tput cnorm 2>/dev/null || true
                            # Перерисовываем экран с заголовком и повторяем ввод
                            clear
                            echo -e "${BLUE}══════════════════════════════════════${NC}"
                            echo -e "${GREEN}       📦 Установка MTProto${NC}"
                            echo -e "${BLUE}══════════════════════════════════════${NC}"
                            echo
                            break  # Повторить ввод домена
                        fi
                    done
                done
                ;;
            2) # Порт MTProto
                local _port_default="${PROXY_PORT:-8443}"
                _mt_read_input PROXY_PORT "Порт MTProto ${DARKGRAY}[${_port_default}]${NC}:" "$_port_default"
                if [ $? -eq 0 ]; then
                    if [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] && (( PROXY_PORT >= 1 && PROXY_PORT <= 65535 )); then
                        (( _step++ ))
                    else
                        echo -e "${RED}✖ Порт должен быть числом от 1 до 65535${NC}"
                    fi
                else
                    _mt_erase_lines 1
                    (( _step-- ))
                fi
                ;;
            3) # Fake TLS домен
                _mt_read_input FAKE_DOMAIN "Fake TLS домен ${DARKGRAY}[${FAKE_DOMAIN}]${NC}:" "$FAKE_DOMAIN"
                if [ $? -eq 0 ]; then
                    (( _step++ ))
                else
                    _mt_erase_lines 1
                    # Если шаг 2 (порт) был пропущен из-за nginx — возвращаемся сразу на шаг 1
                    if _mt_nginx_available; then
                        _step=1
                        clear
                        echo -e "${BLUE}══════════════════════════════════════${NC}"
                        echo -e "${GREEN}       📦 Установка MTProto${NC}"
                        echo -e "${BLUE}══════════════════════════════════════${NC}"
                        echo
                    else
                        (( _step-- ))
                    fi
                fi
                ;;
            4) # Секрет
                _mt_read_input _secret_input "Введите секрет ${DARKGRAY}[Enter для создания нового]${NC}:" ""
                if [ $? -eq 0 ]; then
                    if [ -z "$_secret_input" ]; then
                        # Генерируем секрет и показываем сырой (без ee-обёртки)
                        _secret_input=$(openssl rand -hex 16 2>/dev/null)
                        printf "\033[A\r\033[K\033[1;34m\xe2\x9e\x9c\033[0m  \033[1;33mВведите секрет ${DARKGRAY}[Enter для создания нового]${NC}:\033[0m ${YELLOW}${_secret_input}${NC}\n"
                    elif [[ "$_secret_input" =~ ^[Ee]{2} ]] && [ ${#_secret_input} -gt 34 ]; then
                        # Пользователь ввёл полный FakeTLS секрет — извлекаем сырой
                        _secret_input="${_secret_input:2:32}"
                    fi
                    (( _step++ ))
                else
                    _mt_erase_lines 1
                    (( _step-- ))
                fi
                ;;
            5) # Telegram TAG
                echo
                _mt_read_input PROXY_TAG "Telegram TAG ${DARKGRAY}[Enter - пропустить]${NC}:" "${PROXY_TAG:-}"
                if [ $? -eq 0 ]; then
                    (( _step++ ))
                else
                    _mt_erase_lines 2
                    (( _step-- ))
                fi
                ;;
            6) # Название сервиса для страницы подключения
                _mt_read_input PROXY_NAME "Название сервиса ${DARKGRAY}[Enter - пропустить]${NC}:" "${PROXY_NAME:-}"
                if [ $? -eq 0 ]; then
                    break
                else
                    _mt_erase_lines 1
                    (( _step-- ))
                fi
                ;;
        esac
    done

    # Финализация: собираем полный FakeTLS секрет из сырого + домен
    local _domain_hex
    _domain_hex=$(printf '%s' "$FAKE_DOMAIN" | xxd -ps | tr -d '\n')
    PROXY_SECRET="ee${_secret_input}${_domain_hex}"
    echo
    echo

    # Подготавливаем файлы
    _mt_write_compose
    _mt_save_config
    printf "${GREEN}\u2705${NC} Подготовка файлов\n"

    # База данных
    (_mt_db_migrate) &
    show_spinner "Подключение базы" "Подключение базы"

    # Чистим старый контейнер если есть
    if _mt_installed; then
        (cd "$_MT_DIR" && docker compose down --remove-orphans >/dev/null 2>&1 || \
         docker rm -f "$_MT_CONTAINER" >/dev/null 2>&1) &
        show_spinner "Очистка старого контейнера" "Старый контейнер удалён"
    fi

    # Тянем образ и запускаем
    (cd "$_MT_DIR" && docker compose pull >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Запуск MTProto" "Запуск MTProto"
    tput civis 2>/dev/null || true
    _mt_block_apply
    if _mt_nginx_available && [ "${PROXY_PORT:-}" = "443" ]; then
        # Если порт 443 занят не nginx-ом (например rw-core/Xray) — освобождаем
        local _port443_owner
        _port443_owner=$(ss -tlnp 'sport = :443' 2>/dev/null | awk -F'"' '/users:/{print $2}' | head -1)
        local _node_stopped=false
        if [ -n "$_port443_owner" ] && [ "$_port443_owner" != "nginx" ]; then
            if [ -f "/opt/remnanode/docker-compose.yml" ]; then
                (cd /opt/remnanode && docker compose stop >/dev/null 2>&1) || true
                _node_stopped=true
            fi
        fi

        _mt_nginx_stream_write

        # Перезапускаем nginx чтобы подхватить stream-блок
        local _nc; _nc=$(_mt_nginx_container)
        if [ -n "$_nc" ]; then
            docker restart "$_nc" >/dev/null 2>&1 || true
            sleep 2
        fi

        # Возвращаем ноду (Xray не получит 443 — его занял nginx stream, но 8443 будет работать)
        if $_node_stopped; then
            (cd /opt/remnanode && docker compose start >/dev/null 2>&1) || true
        fi
    fi

    # Выпуск сертификата и настройка /connect страницы
    if ! [[ "${SERVER_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        _mt_issue_cert "$SERVER_IP" &
        if show_spinner "Выпуск SSL-сертификата" "SSL-сертификат получен"; then
            _mt_nginx_add_domain "$SERVER_IP" "$PROXY_SECRET" "$PROXY_PORT" "$PROXY_NAME" &
            show_spinner "Настройка страницы подключения" "Страница подключения готова"
        fi
    fi

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${PROXY_PORT}" >/dev/null 2>&1 || true
    fi

    if _mt_running; then
        _mt_save_config
        print_success "Установка завершена!"
        echo
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        local _ok_line="✅ MTProto успешно установлен!"
        local _ok_pad=$(( (38 - ${#_ok_line}) / 2 ))
        local _ok_prefix; printf -v _ok_prefix "%${_ok_pad}s" ""
        echo -e "${_ok_prefix}${GREEN}${_ok_line}${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        local _cw=12
        echo -e " ${DARKGRAY}$(_mpad "Домен/IP:" $_cw)${NC} ${WHITE}${SERVER_IP}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Порт:" $_cw)${NC} ${WHITE}${PROXY_PORT}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Секрет:" $_cw)${NC} ${YELLOW}${PROXY_SECRET}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Fake TLS:" $_cw)${NC} ${WHITE}${FAKE_DOMAIN}${NC}"
        [ -n "$PROXY_TAG" ] && echo -e " ${DARKGRAY}$(_mpad "Tag:" $_cw)${NC} ${WHITE}${PROXY_TAG}${NC}"
        [ -n "$PROXY_NAME" ] && echo -e " ${DARKGRAY}$(_mpad "Название:" $_cw)${NC} ${WHITE}${PROXY_NAME}${NC}"
        echo
        echo -e "${BLUE}──────────────────────────────────────${NC}"
        echo
        echo -e "${WHITE}🔗 Ссылки для Telegram:${NC}"
        echo -e "   ${GREEN}tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${NC}"
        echo
        # Ссылка страницы подключения (браузер → Telegram)
        if ! [[ "${SERVER_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${WHITE}🌐 Страница подключения (для пользователей):${NC}"
            echo -e "   ${CYAN:-\033[0;36m}https://${SERVER_IP}/connect${NC}"
            echo
        fi
        local _raw_s; _raw_s=$(_mt_extract_raw_secret "$PROXY_SECRET")
        echo -e "${WHITE}🔑 Секрет для @MTProxybot:${NC}"
        echo -e "   ${YELLOW}${_raw_s}${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
        tput civis 2>/dev/null || true
        while true; do
            local _k=""
            IFS= read -rsn1 _k
            case "$_k" in
                $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
                "")      tput cnorm 2>/dev/null || true; return 0 ;;
            esac
        done
    else
        echo
        print_error "Контейнер не запустился. Логи:"
        docker logs "$_MT_CONTAINER" 2>&1 | tail -20 || true
        _mt_press_enter
    fi
}

# Показать конфигурацию и ссылку
_mt_do_config() {
    _mt_load_env
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}      📄 Конфигурация и ссылка${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if [ -z "${PROXY_SECRET:-}" ]; then
        echo -e "${YELLOW}⚠️  Конфигурация не найдена. Сначала установите прокси.${NC}"
        _mt_press_enter; return
    fi

    local _rs="${RED}Не запущен${NC}"
    _mt_running && _rs="${GREEN}Запущен${NC}"

    local _cw=12
    echo -e " ${DARKGRAY}$(_mpad "Статус:" $_cw)${NC} ${_rs}"
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Домен/IP:" $_cw)${NC} ${WHITE}${SERVER_IP:-}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Порт:" $_cw)${NC} ${WHITE}${PROXY_PORT:-}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Секрет:" $_cw)${NC} ${YELLOW}${PROXY_SECRET}${NC}"
    echo -e " ${DARKGRAY}$(_mpad "Fake TLS:" $_cw)${NC} ${WHITE}${FAKE_DOMAIN:-}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}🔗 Ссылки для Telegram:${NC}"
    echo -e "   ${GREEN}tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${NC}"
    echo
    if ! [[ "${SERVER_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${WHITE}🌐 Страница подключения (для пользователей):${NC}"
        echo -e "   ${CYAN:-\033[0;36m}https://${SERVER_IP}/connect${NC}"
        echo
    fi
    local _raw_s; _raw_s=$(_mt_extract_raw_secret "$PROXY_SECRET")
    echo -e "${WHITE}🔑 Секрет для @MTProxybot:${NC}"
    echo -e "   ${YELLOW}${_raw_s}${NC}"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

# Статистика подключений
_mt_do_stats() {
    _mt_load_env

    if ! _mt_running; then
        echo -e "${RED}✖ Прокси не запущен${NC}"
        _mt_press_enter; return
    fi

    local _max_sim=0
    _mt_db_ensure
    local _saved_max; _saved_max=$(_mt_db_stat_get "max_connections")
    [ -n "$_saved_max" ] && _max_sim="$_saved_max"

    local _container_started
    _container_started=$(docker inspect --format '{{.State.StartedAt}}' \
        "$_MT_CONTAINER" 2>/dev/null | sed 's/[^0-9]//g' | cut -c1-14)
    local _saved_ts; _saved_ts=$(_mt_db_stat_get "uptime_ts")
    if [ "$_container_started" != "$_saved_ts" ]; then
        _max_sim=0
        _mt_db_stat_set "uptime_ts" "$_container_started"
    fi

    local _st_orig_stty
    _st_orig_stty=$(stty -g 2>/dev/null || echo "")
    stty -icanon -echo isig min 0 time 0 2>/dev/null || true

    _mt_stats_restore() {
        if [ -n "${_st_orig_stty}" ]; then stty "$_st_orig_stty" 2>/dev/null || stty sane 2>/dev/null || true
        else stty sane 2>/dev/null || true; fi
        tput cnorm 2>/dev/null || true
    }

    while true; do
        local _active _uptime
        local _started_at _start_ts _now
        _started_at=$(docker inspect --format '{{.State.StartedAt}}' "$_MT_CONTAINER" 2>/dev/null || echo "")
        _now=$(date +%s)
        if [ -n "$_started_at" ]; then
            _start_ts=$(date -d "$_started_at" +%s 2>/dev/null || echo "$_now")
        else
            _start_ts="$_now"
        fi
        _uptime=$(( _now - _start_ts ))

        # Активные клиенты: только IP с keepalive-таймером < 3 минут (Telegram посылает данные каждые ~60 сек)
        local _client_ips
        _client_ips=$(_mt_get_active_ips)
        _active=$(printf '%s\n' "$_client_ips" | awk 'NF{c++} END{print c+0}')

        # Сохраняем историю виденных IP в БД
        if [ -n "$_client_ips" ]; then
            while IFS= read -r _gip; do
                [ -z "$_gip" ] && continue
                _mt_db_seen_add "$_gip"
            done <<< "$_client_ips"
        fi

        # Геолокация: кеш в seen_ips.geo (geo_ts = timestamp последнего обновления)
        # Новые IP запрашиваем батчем через ip-api.com (бесплатно, без ключа)
        local _new_ips=""
        while IFS= read -r _gip; do
            [ -z "$_gip" ] && continue
            local _ts; _ts=$(_mt_db_geo_ts "$_gip")
            [ -z "$_ts" ] || [ "$_ts" = "0" ] && _new_ips="${_new_ips} ${_gip}"
        done <<< "$_client_ips"
        if [ -n "$_new_ips" ]; then
            # Формируем JSON-массив и делаем батч-запрос в фоне
            (
                local _jarr
                _jarr=$(echo "$_new_ips" | tr ' ' '\n' | grep -v '^$' \
                    | awk '{printf "\"%s\",",$1}' | sed 's/,$//')
                local _resp
                _resp=$(curl -s --max-time 6 -X POST \
                    "http://ip-api.com/batch?fields=query,country,city" \
                    -H "Content-Type: application/json" \
                    -d "[${_jarr}]" 2>/dev/null)
                # Парсим: {"query":"1.2.3.4","country":"Russia","city":"Moscow"}
                echo "$_resp" | grep -oP '\{[^}]+\}' | while read -r _obj; do
                    local _q _co _ci
                    _q=$(echo "$_obj"  | grep -oP '"query"\s*:\s*"\K[^"]+')
                    _co=$(echo "$_obj" | grep -oP '"country"\s*:\s*"\K[^"]+')
                    _ci=$(echo "$_obj" | grep -oP '"city"\s*:\s*"\K[^"]+')
                    [ -z "$_q" ] && continue
                    local _geo_str="—"
                    [ -n "$_co" ] && _geo_str="${_co}"
                    [ -n "$_ci" ] && _geo_str="${_geo_str}, ${_ci}"
                    _mt_db_geo_set "$_q" "$_geo_str"
                done
            ) &
        fi

        if [ "$_active" -gt "$_max_sim" ] 2>/dev/null; then
            _max_sim="$_active"
            _mt_db_stat_set "max_connections" "$_max_sim"
        fi

        local _up_h _up_m _up_s _up_str
        _up_h=$(( _uptime / 3600 )); _up_m=$(( (_uptime % 3600) / 60 )); _up_s=$(( _uptime % 60 ))
        printf -v _up_str "%02d:%02d:%02d" "$_up_h" "$_up_m" "$_up_s"

        # docker stats --no-stream блокирует ~1.5 сек — запускаем в фоне, используем кеш
        local _net_io_file="/tmp/mtproto_netio"
        if [ ! -f "$_net_io_file" ]; then touch "$_net_io_file" 2>/dev/null || true; fi
        local _net_io
        _net_io=$(cat "$_net_io_file" 2>/dev/null || echo "—")
        [ -z "$_net_io" ] && _net_io="—"
        # Обновляем в фоне для следующего цикла
        ( docker stats --no-stream --format "{{.NetIO}}" "$_MT_CONTAINER" 2>/dev/null \
            | head -1 > "$_net_io_file" ) &

        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}       📊 Статистика MTProto${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        local _cw=22
        echo -e " ${DARKGRAY}$(_mpad "Активных клиентов:" $_cw)${NC} ${GREEN}${_active}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Макс одновременно:" $_cw)${NC} ${YELLOW}${_max_sim}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Трафик (вх / исх):" $_cw)${NC} ${WHITE}${_net_io}${NC}"

        # Трафик за сегодня
        local _today; _today=$(date +%Y-%m-%d)
        local _saved_day; _saved_day=$(_mt_db_stat_get "traffic_day")
        # Парсим текущий NetIO в байты
        _mt_parse_netio_bytes() {
            local _s="$1"; local _total=0
            for _part in $(echo "$_s" | tr '/' ' '); do
                _part=$(echo "$_part" | tr -d ' ')
                local _num _unit _bytes
                _num=$(echo "$_part" | grep -oP '[0-9]+(\.[0-9]+)?')
                _unit=$(echo "$_part" | grep -oP '[a-zA-Z]+')
                _bytes=$(awk -v n="$_num" -v u="$_unit" 'BEGIN{
                    if(u=="B")  b=n;
                    else if(u=="kB") b=n*1000;
                    else if(u=="MB") b=n*1000000;
                    else if(u=="GB") b=n*1000000000;
                    else b=n; printf "%d", b}')
                _total=$(( _total + _bytes ))
            done
            echo "$_total"
        }
        local _cur_bytes; _cur_bytes=$(_mt_parse_netio_bytes "$_net_io")
        if [ "$_saved_day" != "$_today" ]; then
            # Новый день — сохраняем baseline
            _mt_db_stat_set "traffic_day" "$_today"
            _mt_db_stat_set "traffic_day_base" "$_cur_bytes"
        fi
        local _base_bytes; _base_bytes=$(_mt_db_stat_get "traffic_day_base")
        _base_bytes=${_base_bytes:-0}
        local _day_bytes=$(( _cur_bytes - _base_bytes ))
        [ $_day_bytes -lt 0 ] && _day_bytes=0
        local _day_str
        if   [ $_day_bytes -ge 1000000000 ]; then _day_str=$(awk "BEGIN{printf \"%.1fGB\", $_day_bytes/1000000000}")
        elif [ $_day_bytes -ge 1000000 ];    then _day_str=$(awk "BEGIN{printf \"%.1fMB\", $_day_bytes/1000000}")
        elif [ $_day_bytes -ge 1000 ];       then _day_str=$(awk "BEGIN{printf \"%.1fkB\", $_day_bytes/1000}")
        else _day_str="${_day_bytes}B"; fi
        echo -e " ${DARKGRAY}$(_mpad "Трафик за сегодня:" $_cw)${NC} ${WHITE}${_day_str}${NC}"

        echo -e " ${DARKGRAY}$(_mpad "Аптайм:" $_cw)${NC} ${WHITE}${_up_str}${NC}"
        # Фильтруем заблокированные IP из статистики
        local _visible_ips=""
        while IFS= read -r _ip; do
            [ -z "$_ip" ] && continue
            _mt_ip_is_blocked "$_ip" && continue
            _visible_ips+="${_ip}"$'\n'
        done <<< "$_client_ips"
        _visible_ips=$(printf '%s' "$_visible_ips" | sed '/^$/d')

        if [ -n "$_visible_ips" ]; then
            echo
            local _sep_stat="──────────────────────────────────────"
            local _hdr_stat="Подключённые IP:"
            local _hdr_pad=$(( (${#_sep_stat} - ${#_hdr_stat}) / 2 ))
            echo -e "${DARKGRAY}${_sep_stat}${NC}"
            printf "${DARKGRAY}%${_hdr_pad}s%s${NC}\n" "" "$_hdr_stat"
            echo -e "${DARKGRAY}${_sep_stat}${NC}"

            # Считаем /24 подсети среди видимых IP
            declare -A _st_subnet_count=()
            while IFS= read -r _ip; do
                [ -z "$_ip" ] && continue
                local _s24
                _s24=$(echo "$_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
                _st_subnet_count["$_s24"]=$(( ${_st_subnet_count["$_s24"]:-0} + 1 ))
            done <<< "$_visible_ips"

            while IFS= read -r _ip; do
                [ -z "$_ip" ] && continue
                local _geo_str
                _geo_str=$(_mt_db_geo_get "$_ip")
                [ -z "$_geo_str" ] && _geo_str="..."
                printf "   ${WHITE}%-20s${DARKGRAY}%s${NC}\n" "$_ip" "$_geo_str"
            done <<< "$_visible_ips"

            # Подсети с 2+ IP
            local -a _st_subnets=()
            for _sn in "${!_st_subnet_count[@]}"; do
                [ "${_st_subnet_count[$_sn]}" -ge 2 ] && _st_subnets+=("$_sn")
            done
            if [ ${#_st_subnets[@]} -gt 0 ]; then
                IFS=$'\n' _st_subnets=($(printf '%s\n' "${_st_subnets[@]}" | sort))
                unset IFS
                local _hdr_sn="Подозрительные подсети:"
                local _hdr_sn_pad=$(( (${#_sep_stat} - ${#_hdr_sn}) / 2 ))
                echo -e "${DARKGRAY}${_sep_stat}${NC}"
                printf "${DARKGRAY}%${_hdr_sn_pad}s%s${NC}\n" "" "$_hdr_sn"
                echo -e "${DARKGRAY}${_sep_stat}${NC}"
                for _sn in "${_st_subnets[@]}"; do
                    printf "   ${YELLOW}%-20s${DARKGRAY}%s IP из подсети${NC}\n" "$_sn" "${_st_subnet_count[$_sn]}"
                done
            fi
        fi
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"

        # Ждём 5 сек с проверкой Enter/Esc каждые 0.1 сек
        local _si=0 _sk _rr
        while [ $_si -lt 50 ]; do
            _sk=""
            IFS= read -rsn1 -t 0.1 _sk 2>/dev/null && _rr=0 || _rr=$?
            if [[ "$_sk" == $'\e' ]]; then
                _mt_consume_escape_seq
                _mt_stats_restore
                return 1   # Esc = выход в главное меню
            elif [[ $_rr -eq 0 && "$_sk" == "" ]]; then
                _mt_stats_restore
                return 0   # Enter = назад в меню MTProto
            fi
            (( _si++ )) || true
        done
    done
    _mt_stats_restore
}

# Сменить конфигурацию — интерактивно
_mt_do_change_config() {
    if ! _mt_installed; then
        echo -e "${RED}✖ MTProto не установлен. Сначала установите прокси.${NC}"
        _mt_press_enter; return
    fi
    _mt_load_env

    local _old_port="${PROXY_PORT:-}"
    local _step=1 _secret_input=""
    local NEW_SERVER_IP="$SERVER_IP"
    local NEW_PROXY_PORT="$PROXY_PORT"
    local NEW_FAKE_DOMAIN="$FAKE_DOMAIN"
    local NEW_PROXY_TAG="${PROXY_TAG:-}"

    _mt_erase_lines() {
        local n=$1
        while [ $n -gt 0 ]; do
            printf "\033[A\033[K"
            (( n-- ))
        done
    }

    while true; do
        case $_step in
            1) # IP/домен
                local _default_host="${NEW_SERVER_IP:-$(_mt_get_server_ip)}"
                while true; do
                    clear
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    echo -e "${GREEN}     🔑 Смена конфигурации MTProto${NC}"
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    echo
                    _mt_read_input NEW_SERVER_IP "Домен или IP для ссылки подключения ${DARKGRAY}[${_default_host}]${NC}:" "$_default_host"
                    if [ $? -eq 1 ]; then return; fi
                    if check_domain "$NEW_SERVER_IP" true; then
                        (( _step++ )); break
                    fi
                    echo
                    echo -e "${BLUE}══════════════════════════════════════${NC}"
                    echo -e "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Повторить   ${BLUE}S${DARKGRAY}: Пропустить   ${BLUE}Esc${DARKGRAY}: Назад${NC}"
                    tput civis 2>/dev/null || true
                    local key
                    while true; do
                        read -s -n 1 key
                        if [[ "$key" == $'\x1b' ]]; then tput cnorm 2>/dev/null || true; return
                        elif [[ "$key" == "s" || "$key" == "S" ]]; then tput cnorm 2>/dev/null || true; (( _step++ )); break 2
                        elif [[ "$key" == "" ]]; then tput cnorm 2>/dev/null || true; break
                        fi
                    done
                done ;;
            2) # Порт
                local _port_default="${NEW_PROXY_PORT:-$(_mt_find_free_port "8443")}"
                _mt_read_input NEW_PROXY_PORT "Порт прокси ${DARKGRAY}[${_port_default}]${NC}:" "$_port_default"
                if [ $? -eq 0 ]; then
                    if [[ "$NEW_PROXY_PORT" =~ ^[0-9]+$ ]] && (( NEW_PROXY_PORT >= 1 && NEW_PROXY_PORT <= 65535 )); then
                        (( _step++ ))
                    else
                        echo -e "${RED}✖ Порт должен быть числом от 1 до 65535${NC}"
                    fi
                else _mt_erase_lines 1; (( _step-- )); fi ;;
            3) # Fake TLS домен
                _mt_read_input NEW_FAKE_DOMAIN "Fake TLS домен ${DARKGRAY}[${NEW_FAKE_DOMAIN}]${NC}:" "$NEW_FAKE_DOMAIN"
                if [ $? -eq 0 ]; then (( _step++ ))
                else _mt_erase_lines 1; (( _step-- )); fi ;;
            4) # Секрет
                _mt_read_input _secret_input "Введите секрет ${DARKGRAY}[Enter для создания нового]${NC}:" ""
                if [ $? -eq 0 ]; then
                    if [ -z "$_secret_input" ]; then
                        _secret_input=$(openssl rand -hex 16 2>/dev/null)
                        printf "\033[A\r\033[K\033[1;34m\xe2\x9e\x9c\033[0m  \033[1;33mВведите секрет ${DARKGRAY}[Enter для создания нового]${NC}:\033[0m ${YELLOW}${_secret_input}${NC}\n"
                    elif [[ "$_secret_input" =~ ^[Ee]{2} ]] && [ ${#_secret_input} -gt 34 ]; then
                        _secret_input="${_secret_input:2:32}"
                    fi
                    (( _step++ ))
                else _mt_erase_lines 1; (( _step-- )); fi ;;
            5) # Telegram TAG
                echo
                _mt_read_input NEW_PROXY_TAG "Telegram TAG ${DARKGRAY}[Enter - пропустить]${NC}:" "${NEW_PROXY_TAG:-}"
                if [ $? -eq 0 ]; then break
                else _mt_erase_lines 2; (( _step-- )); fi ;;
        esac
    done

    local _domain_hex
    _domain_hex=$(printf '%s' "$NEW_FAKE_DOMAIN" | xxd -ps | tr -d '\n')
    PROXY_SECRET="ee${_secret_input}${_domain_hex}"
    SERVER_IP="$NEW_SERVER_IP"
    PROXY_PORT="$NEW_PROXY_PORT"
    FAKE_DOMAIN="$NEW_FAKE_DOMAIN"
    PROXY_TAG="$NEW_PROXY_TAG"
    echo
    echo

    _mt_write_compose
    _mt_save_config
    print_success "Конфигурация сохранена"

    # Перезапуск с новым портом
    (cd "$_MT_DIR" && docker compose down >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Перезапуск MTProto..." "MTProto перезапущен!"
    _mt_block_apply

    # Управление nginx stream: добавляем если 443, удаляем если нет
    if _mt_nginx_available; then
        if [ "${PROXY_PORT}" = "443" ]; then
            _mt_nginx_stream_write
        else
            _mt_nginx_stream_remove
        fi
        local _nc; _nc=$(_mt_nginx_container)
        [ -n "$_nc" ] && docker restart "$_nc" >/dev/null 2>&1 || true
    fi

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${PROXY_PORT}" >/dev/null 2>&1 || true
        if [ -n "$_old_port" ] && [ "$_old_port" != "$PROXY_PORT" ]; then
            ufw delete allow "$_old_port" >/dev/null 2>&1 || true
        fi
    fi

    echo
    echo -e " ${DARKGRAY}tg:${NC}    ${GREEN}tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${NC}"
    local _raw_s; _raw_s=$(_mt_extract_raw_secret "$PROXY_SECRET")
    echo -e " ${DARKGRAY}Секрет для @MTProxybot:${NC} ${YELLOW}${_raw_s}${NC}"
    echo
    _mt_press_enter
}

_mt_do_stop() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}        ⏹️  Остановка MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    if ! _mt_running; then
        echo -e "${YELLOW}⚠️  Прокси не запущен${NC}"
        _mt_press_enter; return
    fi
    (cd "$_MT_DIR" && docker compose stop >/dev/null 2>&1) &
    show_spinner "Остановка прокси..." "Прокси остановлен"
    _mt_press_enter
}

_mt_do_start() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}         ▶️  Запуск MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    if _mt_running; then
        echo -e "${YELLOW}⚠️  Прокси уже запущен${NC}"
        _mt_press_enter; return
    fi
    (cd "$_MT_DIR" && docker compose start >/dev/null 2>&1) &
    show_spinner "Запуск прокси..." "Прокси запущен"
    _mt_block_apply
    _mt_press_enter
}

_mt_do_restart() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}       🔄 Перезапуск MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    (cd "$_MT_DIR" && docker compose restart >/dev/null 2>&1) &
    # Применяем правила блокировки — они не переживают перезапуск контейнера (iptables остаётся)
    show_spinner "Перезапуск прокси..." "Прокси перезапущен"
    _mt_block_apply
    _mt_press_enter
}

_mt_do_uninstall() {
    _mt_load_env

    if ! _mt_installed; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${RED}        🗑️  Удаление MTProto${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}⚠️  Прокси не установлен${NC}"
        _mt_press_enter; return
    fi

    local _del_items=("✅  Да, удалить" "❌  Нет, не удалять")
    local _del_actions=("yes" "no")
    MENU_ESC_LABEL="Отмена"
    show_arrow_menu "🗑️  Удаление MTProto" "${_del_items[@]}"
    local _choice=$?
    unset MENU_ESC_LABEL
    [[ $_choice -eq 255 ]] && return
    local _act="${_del_actions[$_choice]:-no}"
    [[ "$_act" != "yes" ]] && return

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}         🗑️  Удаление MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    (if [ -d "$_MT_DIR" ]; then
        cd "$_MT_DIR" && docker compose down --remove-orphans >/dev/null 2>&1 || true
    fi
    docker rm -f "$_MT_CONTAINER" >/dev/null 2>&1 || true) &
    show_spinner "Остановка контейнера" "Остановка контейнера"

    (docker rmi "$_MT_IMAGE" >/dev/null 2>&1 || true
    rm -rf "$_MT_DIR" 2>/dev/null || true
    if command -v ufw >/dev/null 2>&1 && [ -n "${PROXY_PORT:-}" ]; then
        ufw delete allow "${PROXY_PORT}" >/dev/null 2>&1 || true
    fi
    _mt_block_clear_all 2>/dev/null || true
    if _mt_nginx_available; then _mt_nginx_stream_remove; fi
    rm -f /usr/local/bin/mtproto /usr/local/bin/mt 2>/dev/null || true
    rm -rf /usr/local/lib/mtproto 2>/dev/null || true) &
    show_spinner "Удаление остаточных файлов" "Удаление остаточных файлов"

    echo
    echo -e "${GREEN}✅ MTProto полностью удалён${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        tput civis 2>/dev/null || true
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

_mt_do_update() {
    if ! _mt_installed; then
        echo -e "${RED}✖ MTProto не установлен${NC}"
        _mt_press_enter; return
    fi
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     ⬆️  Обновление образа MTProto${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    (cd "$_MT_DIR" && docker compose pull >/dev/null 2>&1) &
    show_spinner "Загрузка нового образа..." "Образ обновлён"
    (cd "$_MT_DIR" && docker compose up -d >/dev/null 2>&1) &
    show_spinner "Перезапуск MTProto..." "MTProto обновлён!"
    _mt_press_enter
}

# ─── Управление доступом: блокировка IP / подсетей через iptables ────────────
_MT_DB="${_MT_DIR}/mtproto.db"             # SQLite-база всех данных MTProto
_MT_NGINX_CONF="/opt/nginx/nginx.conf"     # nginx конфиг (stream-блок MTProto)
_MT_NGINX_CONTAINER="remnawave-nginx"      # имя nginx-контейнера

# Инициализация схемы БД (вызывать при установке и при первом обращении)
_mt_db_init() {
    sqlite3 "$_MT_DB" <<'SQL' >/dev/null 2>&1
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS seen_ips (
    ip         TEXT PRIMARY KEY,
    geo        TEXT    DEFAULT '',
    geo_ts     INTEGER DEFAULT 0,
    first_seen INTEGER DEFAULT (strftime('%s','now')),
    last_seen  INTEGER DEFAULT (strftime('%s','now'))
);
CREATE TABLE IF NOT EXISTS blocked (
    entry      TEXT PRIMARY KEY,
    blocked_at INTEGER DEFAULT (strftime('%s','now'))
);
CREATE TABLE IF NOT EXISTS stats (
    key   TEXT PRIMARY KEY,
    value TEXT DEFAULT ''
);
SQL
}

# Создаёт БД если ещё не существует
_mt_db_ensure() { [ -f "$_MT_DB" ] || _mt_db_init; }

# ── seen_ips ──────────────────────────────────────────────────────────────
_mt_db_seen_add() {
    local _ip="$1"
    sqlite3 "$_MT_DB" \
        "INSERT INTO seen_ips(ip) VALUES('$_ip')
         ON CONFLICT(ip) DO UPDATE SET last_seen=strftime('%s','now');" 2>/dev/null || true
}
_mt_db_seen_list() { sqlite3 "$_MT_DB" "SELECT ip FROM seen_ips;" 2>/dev/null; }

# ── geo ───────────────────────────────────────────────────────────────────
_mt_db_geo_get() { sqlite3 "$_MT_DB" "SELECT geo FROM seen_ips WHERE ip='$1';" 2>/dev/null; }
_mt_db_geo_ts()  { sqlite3 "$_MT_DB" "SELECT geo_ts FROM seen_ips WHERE ip='$1';" 2>/dev/null; }
_mt_db_geo_set() {
    local _ip="$1" _geo="${2//\'/\'\'}"
    sqlite3 "$_MT_DB" \
        "INSERT INTO seen_ips(ip,geo,geo_ts) VALUES('$_ip','$_geo',strftime('%s','now'))
         ON CONFLICT(ip) DO UPDATE SET geo='$_geo', geo_ts=strftime('%s','now');" 2>/dev/null || true
}

# ── blocked ───────────────────────────────────────────────────────────────
_mt_db_blocked_add()  { sqlite3 "$_MT_DB" "INSERT OR IGNORE INTO blocked(entry) VALUES('$1');" 2>/dev/null || true; }
_mt_db_blocked_rm()   { sqlite3 "$_MT_DB" "DELETE FROM blocked WHERE entry='$1';" 2>/dev/null || true; }
_mt_db_blocked_has()  { [ "$(sqlite3 "$_MT_DB" "SELECT COUNT(*) FROM blocked WHERE entry='$1';" 2>/dev/null)" = "1" ]; }
_mt_db_blocked_list() { sqlite3 "$_MT_DB" "SELECT entry FROM blocked;" 2>/dev/null; }
_mt_db_blocked_count(){ sqlite3 "$_MT_DB" "SELECT COUNT(*) FROM blocked;" 2>/dev/null; }

# ── stats ─────────────────────────────────────────────────────────────────
_mt_db_stat_get() { sqlite3 "$_MT_DB" "SELECT value FROM stats WHERE key='$1';" 2>/dev/null; }
_mt_db_stat_set() { sqlite3 "$_MT_DB" "INSERT OR REPLACE INTO stats(key,value) VALUES('$1','$2');" 2>/dev/null || true; }

# Однократная миграция данных из старых файлов в БД
_mt_db_migrate() {
    _mt_db_init
    local _ip _e _esc _geo _q _co _ci
    # seen_ips
    if [ -f "${_MT_DIR}/seen_ips" ]; then
        while IFS= read -r _ip; do
            [[ "$_ip" =~ ^[0-9] ]] || continue
            sqlite3 "$_MT_DB" "INSERT OR IGNORE INTO seen_ips(ip) VALUES('$_ip');" 2>/dev/null || true
        done < "${_MT_DIR}/seen_ips"
        mv "${_MT_DIR}/seen_ips" "${_MT_DIR}/seen_ips.migrated" 2>/dev/null || true
    fi
    # blocked_ips
    if [ -f "${_MT_DIR}/blocked_ips" ]; then
        while IFS= read -r _e; do
            [[ "$_e" =~ ^[0-9] ]] || continue
            sqlite3 "$_MT_DB" "INSERT OR IGNORE INTO blocked(entry) VALUES('$_e');" 2>/dev/null || true
        done < "${_MT_DIR}/blocked_ips"
        mv "${_MT_DIR}/blocked_ips" "${_MT_DIR}/blocked_ips.migrated" 2>/dev/null || true
    fi
    # geo cache
    if [ -f "/tmp/mtproto_geo" ]; then
        while IFS='|' read -r _ip _geo; do
            [[ "$_ip" =~ ^[0-9] ]] || continue
            _esc="${_geo//\'/\'\'}"
            sqlite3 "$_MT_DB" "UPDATE seen_ips SET geo='$_esc', geo_ts=strftime('%s','now') WHERE ip='$_ip' AND geo='';" 2>/dev/null || true
        done < "/tmp/mtproto_geo"
    fi
    # stats
    if [ -f "${_MT_DIR}/stats_max_connections" ]; then
        local _v; _v=$(cat "${_MT_DIR}/stats_max_connections" 2>/dev/null | tr -dc '0-9')
        [ -n "$_v" ] && sqlite3 "$_MT_DB" "INSERT OR IGNORE INTO stats(key,value) VALUES('max_connections','$_v');" 2>/dev/null || true
        mv "${_MT_DIR}/stats_max_connections" "${_MT_DIR}/stats_max_connections.migrated" 2>/dev/null || true
    fi
    if [ -f "${_MT_DIR}/stats_uptime_ts" ]; then
        local _ts; _ts=$(cat "${_MT_DIR}/stats_uptime_ts" 2>/dev/null)
        [ -n "$_ts" ] && sqlite3 "$_MT_DB" "INSERT OR IGNORE INTO stats(key,value) VALUES('uptime_ts','$_ts');" 2>/dev/null || true
        mv "${_MT_DIR}/stats_uptime_ts" "${_MT_DIR}/stats_uptime_ts.migrated" 2>/dev/null || true
    fi
}

# Возвращает список уникальных IP клиентов с ESTABLISHED-соединениями к MTProto.
# При nginx: смотрим хостовые соединения на порт 443 (реальные клиентские IP).
# Без nginx: смотрим ss на хосте на порт PROXY_PORT.
_mt_get_active_ips() {
    if _mt_nginx_available; then
        # nginx stream: клиенты подключаются на 443, реальные IP видны на этом порту.
        # HTTP-соединения короткие (<1с), MTProto долгие (часы) — в статистике остаются только MTProto.
        ss -tn state established 'sport = :443' 2>/dev/null \
            | awk 'NR>1 { peer=$4; sub(/:[0-9]+$/,"",peer); if (peer != "127.0.0.1") print peer }' \
            | sort -u
    else
        _mt_load_env
        local _port="${PROXY_PORT:-3128}"
        ss -tn state established 2>/dev/null \
            | awk -v p=":${_port}$" 'NR>1 && $3 ~ p { peer=$4; sub(/:[0-9]+$/,"",peer); if (peer != "127.0.0.1") print peer }' \
            | sort -u
    fi
}

# Использует iptables-legacy если Docker работает через него (иначе правила попадают в другую таблицу)
_mt_ipt() {
    if command -v iptables-legacy >/dev/null 2>&1 && \
       iptables-legacy -n -L DOCKER >/dev/null 2>&1; then
        iptables-legacy "$@"
    else
        iptables "$@"
    fi
}

# Сбросить текущие соединения с IP (использует conntrack если доступен)
_mt_kill_src() {
    local _src="$1"
    if command -v conntrack >/dev/null 2>&1; then
        conntrack -D -s "$_src" >/dev/null 2>&1 || true
    fi
}

# Перезагружает nginx контейнер (применяет изменения конфига)
_mt_nginx_reload() {
    local _nc="${_MT_NGINX_CONTAINER:-remnawave-nginx}"
    docker exec "$_nc" nginx -s reload 2>/dev/null || true
}

# Проверяет доступность nginx контейнера
_mt_nginx_available() {
    local _nc="${_MT_NGINX_CONTAINER:-remnawave-nginx}"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${_nc}$"
}

# Пишет stream-блок в nginx.conf и убирает прямые listen 443 из http-блоков
_mt_nginx_stream_write() {
    local _nc="${_MT_NGINX_CONTAINER:-remnawave-nginx}"
    local _conf="${_MT_NGINX_CONF:-/opt/nginx/nginx.conf}"
    _mt_load_env
    [ ! -f "$_conf" ] && return

    # Удаляем старый stream-блок если есть
    python3 - "$_conf" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f: content = f.read()
# Remove old mtproto stream block
content = re.sub(r'\n# BEGIN_MTPROTO_STREAM.*?# END_MTPROTO_STREAM\n', '\n', content, flags=re.DOTALL)
# Restore any commented-out listen 443
content = content.replace('    #mt# listen 443 ssl;', '    listen 443 ssl;')
content = content.replace('    #mt# listen 443 ssl default_server;', '    listen 443 ssl default_server;')
# Collect all HTTP server_names (exclude _ and empty)
http_domains = re.findall(r'server_name\s+([^;]+);', content)
domain_set = set()
for entry in http_domains:
    for d in entry.split():
        if d != '_' and '.' in d:
            domain_set.add(d)
map_entries = '\n'.join(f'        {d}   127.0.0.1:8444;' for d in sorted(domain_set))
# Build stream block
stream_block = f"""\n# BEGIN_MTPROTO_STREAM
stream {{
    map $ssl_preread_server_name $mt_upstream {{
{map_entries}
        default                 127.0.0.1:8445;
    }}

    server {{
        listen 443;
        ssl_preread on;
        proxy_pass $mt_upstream;
    }}

    # HTTP gate: proxy_protocol для сохранения реального IP → nginx http
    server {{
        listen 127.0.0.1:8444;
        proxy_pass unix:/dev/shm/nginx.sock;
        proxy_protocol on;
    }}

    # MTG gate: proxy_protocol для передачи реального IP → mtg:2
    server {{
        listen 127.0.0.1:8445;
        proxy_pass 127.0.0.1:3128;
        proxy_protocol on;
    }}
}}
# END_MTPROTO_STREAM"""
# Comment out direct 443 listen in http blocks
content = content.replace('    listen 443 ssl;', '    #mt# listen 443 ssl;')
content = content.replace('    listen 443 ssl default_server;', '    #mt# listen 443 ssl default_server;')
# Insert stream block before http {
content = re.sub(r'(\nhttp \{)', stream_block + r'\1', content, count=1)
with open(path, 'w') as f: f.write(content)
PYEOF
    docker exec "$_nc" nginx -t 2>/dev/null && _mt_nginx_reload || true
}

# Удаляет stream-блок из nginx.conf, восстанавливает прямые listen 443
_mt_nginx_stream_remove() {
    local _nc="${_MT_NGINX_CONTAINER:-remnawave-nginx}"
    local _conf="${_MT_NGINX_CONF:-/opt/nginx/nginx.conf}"
    [ ! -f "$_conf" ] && return
    python3 - "$_conf" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f: content = f.read()
content = re.sub(r'\n# BEGIN_MTPROTO_STREAM.*?# END_MTPROTO_STREAM\n', '\n', content, flags=re.DOTALL)
content = content.replace('    #mt# listen 443 ssl;', '    listen 443 ssl;')
content = content.replace('    #mt# listen 443 ssl default_server;', '    listen 443 ssl default_server;')
with open(path, 'w') as f: f.write(content)
PYEOF
    docker exec "$_nc" nginx -t 2>/dev/null && _mt_nginx_reload || true
}

_mt_block_apply() {
    # Блокировка через iptables INPUT на порту 443 (работает до nginx, на уровне хоста)
    _mt_db_ensure
    while IFS= read -r _entry; do
        [ -z "$_entry" ] && continue
        _mt_ipt -C INPUT -s "$_entry" -p tcp --dport 443 -j DROP 2>/dev/null \
            || _mt_ipt -I INPUT -s "$_entry" -p tcp --dport 443 -j DROP 2>/dev/null || true
    done < <(_mt_db_blocked_list)
}

_mt_block_clear_all() {
    _mt_ipt -S INPUT 2>/dev/null | grep -- "-p tcp --dport 443 -j DROP" | while read -r _rule; do
        _mt_ipt ${_rule/-A/-D} 2>/dev/null || true
    done
}

# Проверяет, заблокирован ли IP (точно или через CIDR в таблице blocked)
_mt_ip_is_blocked() {
    local _ip="$1"
    _mt_db_ensure
    # Точное совпадение
    _mt_db_blocked_has "$_ip" && return 0
    # CIDR — только точным совпадением (уже выше)
    [[ "$_ip" == */* ]] && return 1
    # Проверяем покрытие CIDR из таблицы
    while IFS= read -r _entry; do
        [[ "$_entry" != */* ]] && continue
        local _net _pfx _ip_int _net_int _mask
        _net="${_entry%/*}"; _pfx="${_entry#*/}"
        _ip_int=$(printf '%d' "0x$(printf '%02x%02x%02x%02x' ${_ip//./ } 2>/dev/null)" 2>/dev/null) || continue
        _net_int=$(printf '%d' "0x$(printf '%02x%02x%02x%02x' ${_net//./ })" 2>/dev/null) || continue
        _mask=$(( 0xFFFFFFFF << (32 - _pfx) & 0xFFFFFFFF ))
        [ $(( _ip_int & _mask )) -eq $(( _net_int & _mask )) ] && return 0
    done < <(_mt_db_blocked_list)
    return 1
}

_mt_do_access() {
    if ! _mt_installed; then
        echo -e "${RED}✖ MTProto не установлен${NC}"; _mt_press_enter; return
    fi
    _mt_load_env
    mkdir -p "$_MT_DIR"
    _mt_db_ensure

    # Синхронизируем iptables с БД: если заблокированных нет — снимаем все DROP-правила (тихо)
    local _file_entries
    _file_entries=$(_mt_db_blocked_count)
    if [ "${_file_entries:-0}" -eq 0 ]; then
        _mt_block_clear_all 2>/dev/null
    fi

    while true; do
        # ── Актуальные данные ──────────────────────────────────────────────
        local -a _blocked_list=()
        while IFS= read -r _e; do
            [ -n "$_e" ] && _blocked_list+=("$_e")
        done < <(_mt_db_blocked_list)

        local _client_ips _cur_ips=()
        _client_ips=$(_mt_get_active_ips)
        while IFS= read -r _ip; do [ -n "$_ip" ] && _cur_ips+=("$_ip"); done <<< "$_client_ips"

        # Сохраняем историю виденных IP в БД
        if [ -n "$_client_ips" ]; then
            while IFS= read -r _gip; do
                [ -z "$_gip" ] && continue
                _mt_db_seen_add "$_gip"
            done <<< "$_client_ips"
        fi

        # ── Все виденные IP (история ∪ онлайн) ────────────────────────────
        local -a _all_ips=()
        local _combined
        _combined=$(printf '%s\n' "$(_mt_db_seen_list)" "${_cur_ips[@]}")
        while IFS= read -r _ip; do
            [[ -z "$_ip" || "$_ip" =~ ^# ]] && continue
            _all_ips+=("$_ip")
        done < <(printf '%s\n' "${_combined}" | sort -u)

        # ── Группировка по /24: подсети с 2+ IP из истории ────────────────
        declare -A _sn_cnt=()
        for _ip in "${_all_ips[@]}"; do
            local _s24; _s24=$(echo "$_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
            _sn_cnt["$_s24"]=$(( ${_sn_cnt["$_s24"]:-0} + 1 ))
        done
        local -a _subnet_groups=()
        for _sn in "${!_sn_cnt[@]}"; do
            [ "${_sn_cnt[$_sn]}" -ge 2 ] && _subnet_groups+=("$_sn")
        done
        IFS=$'\n' _subnet_groups=($(printf '%s\n' "${_subnet_groups[@]}" | sort)); unset IFS

        # IP входящие в подсети (скрываем из основного списка)
        declare -A _in_subnet=()
        for _ip in "${_all_ips[@]}"; do
            local _s24; _s24=$(echo "$_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
            [ "${_sn_cnt[$_s24]:-0}" -ge 2 ] && _in_subnet["$_ip"]=1
        done

        # Заблокированные CIDR-подсети
        local -a _blocked_cidrs=()
        for _b in "${_blocked_list[@]}"; do
            [[ "$_b" == */* ]] && _blocked_cidrs+=("$_b")
        done

        # ── Строим меню ────────────────────────────────────────────────────
        local -a _ip_items=() _ip_vals=()

        if [ ${#_all_ips[@]} -eq 0 ]; then
            _ip_items+=("${DARKGRAY}(нет данных о подключениях)${NC}"); _ip_vals+=("sep")
        else
            local _sep_ac="──────────────────────────────────────"
            local _hdr_ac="Список IP адресов:"
            local _hdr_ac_pad=$(( (${#_sep_ac} - ${#_hdr_ac}) / 2 ))
            _ip_items+=($'\x01'"$(printf '%*s%s' $_hdr_ac_pad '' "$_hdr_ac")"); _ip_vals+=("sep")
            _ip_items+=($'\x02'"${_sep_ac}"); _ip_vals+=("sep")
            local _has_solo=0
            for _ip in "${_all_ips[@]}"; do
                [ "${_in_subnet[$_ip]:-0}" -eq 1 ] && continue
                local _geo_str
                _geo_str=$(_mt_db_geo_get "$_ip")
                [ -z "$_geo_str" ] && _geo_str="—"
                local _line; _line=$(printf '%-22s  %s' "$_ip" "$_geo_str")
                if _mt_ip_is_blocked "$_ip"; then
                    _ip_items+=("${RED}${_line}${NC}")
                elif printf '%s\n' "${_cur_ips[@]}" | grep -qxF "$_ip"; then
                    _ip_items+=("${GREEN}${_line}${NC}")
                else
                    _ip_items+=("$_line")
                fi
                _ip_vals+=("$_ip")
                _has_solo=1
            done
            [ "$_has_solo" -eq 0 ] && { _ip_items+=("${DARKGRAY}(все IP сгруппированы по подсетям)${NC}"); _ip_vals+=("sep"); }
        fi

        # Подозрительные подсети (2+ IP из истории)
        if [ ${#_subnet_groups[@]} -gt 0 ]; then
            local _hdr_sn2="Подозрительные подсети:"
            local _hdr_sn2_pad=$(( (${#_sep_ac} - ${#_hdr_sn2}) / 2 ))
            _ip_items+=($'\x02'"${_sep_ac}"); _ip_vals+=("sep")
            _ip_items+=($'\x01'"$(printf '%*s%s' $_hdr_sn2_pad '' "$_hdr_sn2")"); _ip_vals+=("sep")
            _ip_items+=($'\x02'"${_sep_ac}"); _ip_vals+=("sep")
            for _sn in "${_subnet_groups[@]}"; do
                local _total="${_sn_cnt[$_sn]}"
                # Считаем онлайн и заблокированных в этой подсети
                local _on_cnt=0 _bl_cnt=0
                for _ip in "${_all_ips[@]}"; do
                    local _s24; _s24=$(echo "$_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
                    [ "$_s24" != "$_sn" ] && continue
                    printf '%s\n' "${_cur_ips[@]}" | grep -qxF "$_ip" && (( _on_cnt++ )) || true
                    _mt_ip_is_blocked "$_ip" && (( _bl_cnt++ )) || true
                done
                # Гео — берём у первого IP в этой подсети с данными
                local _sn_geo="—"
                for _gip in "${_all_ips[@]}"; do
                    local _g24; _g24=$(echo "$_gip" | awk -F. '{print $1"."$2"."$3".0/24"}')
                    [ "$_g24" != "$_sn" ] && continue
                    local _gg; _gg=$(_mt_db_geo_get "$_gip")
                    if [ -n "$_gg" ]; then _sn_geo="$_gg"; break; fi
                done
                local _sn_line; _sn_line=$(printf '%-22s  %s (%d/%d)' "$_sn" "$_sn_geo" "$_bl_cnt" "$_total")
                # Цвет: красный если CIDR заблокирована, зелёный если есть онлайн, иначе обычный
                if _mt_ip_is_blocked "$_sn"; then
                    _ip_items+=("${RED}${_sn_line}${NC}")
                elif [ "$_on_cnt" -gt 0 ]; then
                    _ip_items+=("${GREEN}${_sn_line}${NC}")
                else
                    _ip_items+=("$_sn_line")
                fi
                _ip_vals+=("sn:${_sn}")
            done
        fi

        # Заблокированные CIDR-подсети НЕ из групп (ручной ввод)
        local -a _extra_cidrs=()
        for _bn in "${_blocked_cidrs[@]}"; do
            # Показываем отдельно только те CIDR, которые не совпадают с автогруппой
            local _is_group=0
            for _grp in "${_subnet_groups[@]}"; do
                [ "$_grp" = "$_bn" ] && _is_group=1 && break
            done
            [ "$_is_group" -eq 0 ] && _extra_cidrs+=("$_bn")
        done
        if [ ${#_extra_cidrs[@]} -gt 0 ]; then
            local _hdr_bl="Заблокированные подсети:"
            local _hdr_bl_pad=$(( (${#_sep_ac} - ${#_hdr_bl}) / 2 ))
            _ip_items+=($'\x02'"${_sep_ac}"); _ip_vals+=("sep")
            _ip_items+=($'\x01'"$(printf '%*s%s' $_hdr_bl_pad '' "$_hdr_bl")"); _ip_vals+=("sep")
            _ip_items+=($'\x02'"${_sep_ac}"); _ip_vals+=("sep")
            for _bn in "${_extra_cidrs[@]}"; do
                _ip_items+=("${RED}${_bn}${NC}")
                _ip_vals+=("$_bn")
            done
        fi

        _ip_items+=($'\x02'"${_sep_ac}"); _ip_vals+=("sep")
        _ip_items+=("✏️   Ввести IP или CIDR вручную");      _ip_vals+=("manual")
        _ip_items+=($'\x02'"${_sep_ac}"); _ip_vals+=("sep")
        _ip_items+=("⬅️   Назад");                           _ip_vals+=("back")

        # Находим индекс первого IP (пропускаем sep/заголовки)
        local _first_ip_idx=0
        for _fi in "${!_ip_vals[@]}"; do
            if [ "${_ip_vals[$_fi]}" != "sep" ] && [ "${_ip_vals[$_fi]}" != "manual" ] && [ "${_ip_vals[$_fi]}" != "back" ]; then
                _first_ip_idx=$_fi; break
            fi
        done
        export MENU_INITIAL_IDX=$_first_ip_idx

        # Заголовок: центрированный с статистикой
        local _blk_total=${#_blocked_list[@]}
        local _title="🚫 Управление доступом\n• Онлайн: ${#_cur_ips[@]}\n• Заблокировано: ${_blk_total}"

        show_arrow_menu "$_title" "${_ip_items[@]}"
        local _ic=$?
        [[ $_ic -eq 255 ]] && return
        local _sel="${_ip_vals[$_ic]:-sep}"

        case "$_sel" in
        sep) ;;
        back) return ;;
        manual)
            clear
            echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"
            echo -e "${RED}       🚫 Заблокировать IP / подсеть${NC}"
            echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"
            echo
            echo -e " ${DARKGRAY}Примеры:${NC}"
            echo -e "   ${WHITE}1.2.3.4${NC}          ${DARKGRAY}— конкретный IP${NC}"
            echo -e "   ${WHITE}1.2.3.0/24${NC}       ${DARKGRAY}— вся /24 подсеть (256 адресов)${NC}"
            echo -e "   ${WHITE}1.2.0.0/16${NC}       ${DARKGRAY}— /16 подсеть (65535 адресов)${NC}"
            echo
            local _new_entry=""
            _mt_read_input _new_entry "IP или CIDR:" ""
            _new_entry=$(echo "$_new_entry" | tr -d ' ')
            if [[ -n "$_new_entry" ]]; then
                if [[ "$_new_entry" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
                    if _mt_db_blocked_has "$_new_entry"; then
                        echo -e "${YELLOW}⚠ Уже в списке${NC}"
                    else
                        _mt_db_blocked_add "$_new_entry"
                        _mt_ipt -I INPUT -s "$_new_entry" -p tcp --dport 443 -j DROP 2>/dev/null || true
                        _mt_kill_src "$_new_entry"
                        echo -e "${GREEN}✅ Заблокировано: ${_new_entry}${NC}"
                    fi
                else
                    echo -e "${RED}✖ Неверный формат. Используйте IP или CIDR (1.2.3.4 или 1.2.3.0/24)${NC}"
                fi
                sleep 1.5
            fi
            ;;
        sn:*)
            # ── Подменю подсети ────────────────────────────────────────────
            local _sn_cidr="${_sel#sn:}"
            while true; do
                # Собираем все IP этой подсети из истории
                local -a _sn_ips=()
                for _ip in "${_all_ips[@]}"; do
                    local _s24; _s24=$(echo "$_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
                    [ "$_s24" = "$_sn_cidr" ] && _sn_ips+=("$_ip")
                done
                IFS=$'\n' _sn_ips=($(printf '%s\n' "${_sn_ips[@]}" | sort)); unset IFS

                local -a _sn_items=()
                for _sip in "${_sn_ips[@]}"; do
                    local _sg; _sg=$(_mt_db_geo_get "$_sip")
                    [ -z "$_sg" ] && _sg="—"
                    local _sline; _sline=$(printf '%-22s  %s' "$_sip" "$_sg")
                    if _mt_ip_is_blocked "$_sip"; then
                        _sn_items+=("${RED}${_sline}${NC}")
                    elif printf '%s\n' "${_cur_ips[@]}" | grep -qxF "$_sip"; then
                        _sn_items+=("${GREEN}${_sline}${NC}")
                    else
                        _sn_items+=("$_sline")
                    fi
                done

                local _sn_action_idx=$(( ${#_sn_ips[@]} + 1 ))
                local _sn_back_idx=$(( ${#_sn_ips[@]} + 3 ))
                _sn_items+=("──────────────────────────────────────")
                if _mt_ip_is_blocked "$_sn_cidr"; then
                    _sn_items+=("${GREEN}✅ Разблокировать подсеть ${_sn_cidr}${NC}")
                else
                    _sn_items+=("🚫 Заблокировать подсеть ${_sn_cidr}")
                fi
                _sn_items+=("──────────────────────────────────────")
                _sn_items+=("⬅️   Назад")

                show_arrow_menu "📡 Подсеть: ${_sn_cidr}" "${_sn_items[@]}"
                local _sc=$?

                if [[ $_sc -eq 255 || $_sc -eq $_sn_back_idx ]]; then
                    break
                elif [ "$_sc" -eq "$_sn_action_idx" ]; then
                    # Блок/разблок всей подсети как CIDR
                    if _mt_ip_is_blocked "$_sn_cidr"; then
                        _mt_db_blocked_rm "$_sn_cidr"
                        _mt_ipt -D INPUT -s "$_sn_cidr" -p tcp --dport 443 -j DROP 2>/dev/null || true
                        echo -e "${GREEN}✅ Подсеть разблокирована: ${_sn_cidr}${NC}"
                    else
                        _mt_db_blocked_add "$_sn_cidr"
                        _mt_ipt -I INPUT -s "$_sn_cidr" -p tcp --dport 443 -j DROP 2>/dev/null || true
                        _mt_kill_src "$_sn_cidr"
                        echo -e "${GREEN}✅ Подсеть заблокирована: ${_sn_cidr}${NC}"
                    fi
                    sleep 1.5
                    break
                elif [ "$_sc" -lt "${#_sn_ips[@]}" ]; then
                    # Клик на IP — toggle block
                    local _sip="${_sn_ips[$_sc]}"
                    if _mt_ip_is_blocked "$_sip"; then
                        _mt_db_blocked_rm "$_sip"
                        _mt_ipt -D INPUT -s "$_sip" -p tcp --dport 443 -j DROP 2>/dev/null || true
                        echo -e "${GREEN}✅ Разблокировано: ${_sip}${NC}"
                    else
                        _mt_db_blocked_add "$_sip"
                        _mt_ipt -I INPUT -s "$_sip" -p tcp --dport 443 -j DROP 2>/dev/null || true
                        _mt_kill_src "$_sip"
                        echo -e "${GREEN}✅ Заблокировано: ${_sip}${NC}"
                    fi
                    sleep 1.5
                    # Перечитываем _all_ips и cur_ips для обновления цветов в подменю
                    _client_ips=$(_mt_get_active_ips)
                    _cur_ips=()
                    while IFS= read -r _ip; do [ -n "$_ip" ] && _cur_ips+=("$_ip"); done <<< "$_client_ips"
                fi
            done
            ;;
        *)
            if [[ -n "$_sel" ]]; then
                if _mt_ip_is_blocked "$_sel"; then
                    _mt_db_blocked_rm "$_sel"
                    _mt_ipt -D INPUT -s "$_sel" -p tcp --dport 443 -j DROP 2>/dev/null || true
                    echo -e "${GREEN}✅ Разблокировано: ${_sel}${NC}"
                else
                    _mt_db_blocked_add "$_sel"
                    _mt_ipt -I INPUT -s "$_sel" -p tcp --dport 443 -j DROP 2>/dev/null || true
                    _mt_kill_src "$_sel"
                    echo -e "${GREEN}✅ Заблокировано: ${_sel}${NC}"
                fi
                sleep 1.5
            fi
            ;;
        esac
    done
}

manage_mtproto() {
    while true; do
        tput civis 2>/dev/null || true
        _mt_load_env
        local _installed=false _running=false
        _mt_installed && _installed=true
        _mt_running   && _running=true

        local _line1="📡 MTProto Proxy"

        local _stat_word _stat_color
        if   [ "$_running"   = true ]; then
            _stat_word="Запущен";       _stat_color="${GREEN}"
        elif [ "$_installed" = true ]; then
            _stat_word="Остановлен";    _stat_color="${YELLOW}"
        else
            _stat_word="Не установлен"; _stat_color="${DARKGRAY}"
        fi
        local _stat_plain="Статус: ● ${_stat_word}"
        local _l2_pad=$(( (38 - ${#_stat_plain}) / 2 ))
        local _l2_prefix; printf -v _l2_prefix "%${_l2_pad}s" ""

        local _title="${_line1}\n${_l2_prefix}${DARKGRAY}Статус: ${_stat_color}● ${_stat_word}${NC}"

        local -a _items=() _actions=()

        if [ "$_installed" = false ]; then
            _items+=("📦  Установить MTProto");     _actions+=("install")
        else
            _items+=("📦  Переустановить MTProto"); _actions+=("install")
            _items+=("⬆️   Обновить образ");          _actions+=("update")
            _items+=("──────────────────────────────────────"); _actions+=("sep")
            _items+=("📊  Статистика подключений");            _actions+=("stats")
            _items+=("🚫  Управление доступом");               _actions+=("access")
            _items+=("📄  Конфигурация и ссылка");             _actions+=("config")
            _items+=("🔑  Сменить конфигурацию");              _actions+=("change_config")
            _items+=("──────────────────────────────────────"); _actions+=("sep")
            if [ "$_running" = true ]; then
                _items+=("⏹️   Остановить прокси");    _actions+=("stop")
                _items+=("🔄  Перезапустить прокси"); _actions+=("restart")
            else
                _items+=("▶️   Запустить прокси");     _actions+=("start")
            fi
        fi

        _items+=("──────────────────────────────────────"); _actions+=("sep")
        _items+=("⬅️   Назад");                             _actions+=("back")

        show_arrow_menu "$_title" "${_items[@]}"
        local _choice=$?
        [[ $_choice -eq 255 ]] && return

        local _action="${_actions[$_choice]:-sep}"
        case "$_action" in
            install)       _mt_do_install || return ;;
            update)        _mt_do_update ;;
            stats)         _mt_do_stats || return ;;
            access)        _mt_do_access ;;
            config)        _mt_do_config || return ;;
            change_config) _mt_do_change_config ;;
            start)         _mt_do_start ;;
            stop)          _mt_do_stop ;;
            restart)       _mt_do_restart ;;
            back)          return ;;
            *)             continue ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# ТЕСТИРОВАНИЕ СЕРВЕРА
# ═══════════════════════════════════════════════════
manage_server_testing() {
    while true; do
        tput civis 2>/dev/null || true
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   🧪  ТЕСТИРОВАНИЕ СЕРВЕРА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        show_arrow_menu "🧪  Тестирование сервера" \
            "⚡  Тест скорости сети" \
            "🌍  Доступность популярных сервисов" \
            "🔒  Региональные ограничения" \
            "📍  Геолокация IP" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) run_speed_test     || return ;;
            1) run_services_check || return ;;
            2) run_regional_check || return ;;
            3) run_geolocation    || return ;;
            4) continue ;;
            5) return ;;
        esac
    done
}

run_speed_test() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}        ⚡ Тест скорости сети${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/speedtest_result.XXXXXX)
    (
        cd /tmp && \
        curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz" -o speedtest.tgz && \
        tar -xzf speedtest.tgz
    ) &
    show_spinner "Подготовка инструмента тестирования"
    echo
    (
        cd /tmp && \
        ./speedtest --accept-license --accept-gdpr 2>/dev/null > "$tmpfile" && \
        rm -rf speedtest.tgz speedtest
    ) &
    show_spinner "Запущен тест скорости сети" "Диагностика скорости сети завершёна"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    # Парсим результат
    local server isp latency download dl_ping upload ul_ping loss
    server=$(echo "$output" | grep -oP 'Server:\s*\K.*?(?=\s*\(id)' | sed 's/\s*$//')
    isp=$(echo "$output" | grep -oP 'ISP:\s*\K.*' | sed 's/\s*$//')
    latency=$(echo "$output" | grep -oP 'Idle Latency:\s*\K.*' | sed 's/\s*$//')
    download=$(echo "$output" | grep -oP 'Download:\s*\K[\d.]+\s*\S+' | sed 's/\s*$//')
    dl_ping=$(echo "$output" | sed -n '/Download:/{n;s/^\s*//;p;}' | grep -oP '^[\d.]+\s*ms' | sed 's/\s*$//')
    upload=$(echo "$output" | grep -oP 'Upload:\s*\K[\d.]+\s*\S+' | sed 's/\s*$//')
    ul_ping=$(echo "$output" | sed -n '/Upload:/{n;s/^\s*//;p;}' | grep -oP '^[\d.]+\s*ms' | sed 's/\s*$//')
    loss=$(echo "$output" | grep -oP 'Packet Loss:\s*\K.*' | sed 's/\s*$//')

    if [ -n "$server" ]; then
        local _cw=21
        echo -e "${DARKGRAY}──────────────── [ Сервер ] ─────────────────${NC}"
        echo
        echo -e " ${DARKGRAY}$(_mpad "Сервер подключения:" $_cw)${NC} ${WHITE}${server}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Провайдер:" $_cw)${NC} ${WHITE}${isp}${NC}"
        echo
        echo -e "${DARKGRAY}──────────────── [ Результат ] ─────────────────${NC}"
        echo
        echo -e " ${DARKGRAY}$(_mpad "Задержка:" $_cw)${NC} ${YELLOW}${latency}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Скорость загрузки:" $_cw)${NC} ${GREEN}${download}${NC}  ${DARKGRAY}пинг: ${dl_ping}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Скорость отправки:" $_cw)${NC} ${GREEN}${upload}${NC}  ${DARKGRAY}пинг: ${ul_ping}${NC}"
        echo -e " ${DARKGRAY}$(_mpad "Потеряно пакетов:" $_cw)${NC} ${WHITE}${loss}${NC}"
    else
        echo -e "${RED}Не удалось выполнить тест скорости${NC}"
        [ -n "$output" ] && echo -e "\n$output"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

run_services_check() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN} 🌍 Доступность популярных сервисов${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (bash <(curl -s "storage.umager.ru/checker_all_ru.sh") </dev/null > "$tmpfile" 2>&1) &
    show_spinner "Проверка доступности сервисов" "Диагностика доступности сервисов завершена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    _print_ipv4_info "$output"
    _print_checker_sections "$output"
    _print_ipv6_section "$output"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# ХЕЛПЕРЫ ДЛЯ ТЕСТОВ
# ═══════════════════════════════════════════════════
_country_name() {
    case "$1" in
        DE) echo "Германия" ;; RU) echo "Россия" ;;    US) echo "США" ;;
        NL) echo "Нидерланды" ;; GB) echo "Великобритания" ;; FR) echo "Франция" ;;
        FI) echo "Финляндия" ;; PL) echo "Польша" ;;   UA) echo "Украина" ;;
        KZ) echo "Казахстан" ;; TR) echo "Турция" ;;   JP) echo "Япония" ;;
        SG) echo "Сингапур" ;;  CN) echo "Китай" ;;    LV) echo "Латвия" ;;
        LT) echo "Литва" ;;     EE) echo "Эстония" ;;  SE) echo "Швеция" ;;
        NO) echo "Норвегия" ;;  DK) echo "Дания" ;;    CH) echo "Швейцария" ;;
        AT) echo "Австрия" ;;   IT) echo "Италия" ;;   ES) echo "Испания" ;;
        CZ) echo "Чехия" ;;     HU) echo "Венгрия" ;;  RO) echo "Румыния" ;;
        BG) echo "Болгария" ;;  HR) echo "Хорватия" ;; SK) echo "Словакия" ;;
        *) echo "$1" ;;
    esac
}

_svc_yn() {
    echo "$1" | sed 's/\bYes\b/Да/g; s/\bNo\b/Нет/g; s/\bRegion:/Регион:/g'
}

# Корректное выравнивание с учётом многобайтовой кириллицы:
# printf "%-Ns" считает байты, а не символы — _mpad компенсирует разницу
_mpad() {
    local s="$1" w="$2"
    local chars bytes
    chars=${#s}
    bytes=$(printf '%s' "$s" | wc -c)
    printf "%-$(( w + bytes - chars ))s" "$s"
}

# Выводит шапку IPv4 + провайдерскую инфо из вывода скрипта-чекера
_print_ipv4_info() {
    local output="$1"
    local raw_provider raw_cc ipv4_provider ipv4_country ipv4_city ipv4_asn
    raw_provider=$(echo "$output" | grep -oP '(?i)хостинг-провайдер:\s*\K.*' | head -1 | sed 's/\s*$//')
    raw_cc=$(echo "$raw_provider" | grep -oP '^[A-Z]{2}')
    if [ -n "$raw_cc" ]; then
        ipv4_provider=$(echo "$raw_provider" | sed "s/^$raw_cc/$(_country_name "$raw_cc")/")
    else
        ipv4_provider="$raw_provider"
    fi
    local raw_country
    raw_country=$(echo "$output" | grep -oP '(?i)Страна:\s*\K[A-Z]+' | head -1)
    ipv4_country=$(_country_name "$raw_country")
    ipv4_city=$(echo "$output" | grep -oP '(?i)Город:\s*\K.*' | head -1 | sed 's/\s*$//')
    ipv4_asn=$(echo "$output"  | grep -oP '(?i)ASN:\s*\K.*'   | head -1 | sed 's/\s*$//')

    local _cw=20
    echo -e "${DARKGRAY}──────────────── [ IPv4 ] ─────────────────${NC}"
    echo
    [ -n "$ipv4_provider" ] && echo -e " ${DARKGRAY}$(_mpad "Хостинг провайдер:" $_cw)${NC} ${WHITE}${ipv4_provider}${NC}"
    [ -n "$ipv4_country"  ] && echo -e " ${DARKGRAY}$(_mpad "Страна:" $_cw)${NC} ${WHITE}${ipv4_country}${NC}"
    [ -n "$ipv4_city"     ] && echo -e " ${DARKGRAY}$(_mpad "Город:" $_cw)${NC} ${WHITE}${ipv4_city}${NC}"
    [ -n "$ipv4_asn"      ] && echo -e " ${DARKGRAY}$(_mpad "ASN:" $_cw)${NC} ${WHITE}${ipv4_asn}${NC}"
    echo
}

# Выводит блоки секций из вывода чекера (строки типа ====[ Title ]====)
_print_checker_sections() {
    local output="$1"
    # Снимаем ANSI-коды; \r-overwrite: оставляем только последний кадр в строке
    local clean
    clean=$(echo "$output" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' | sed 's/.*\r//')

    # Проход 1: ищем максимальную длину имени сервиса для выравнивания колонки
    local max_name_len=0
    local _t _ts _tn
    while IFS= read -r _t; do
        echo "$_t" | grep -qP '=+\[.*\]=+' && continue
        echo "$_t" | grep -qP '^\s*=+\s*$'  && continue
        [[ -z "$(echo "$_t" | tr -d '[:space:]')" ]] && continue
        echo "$_t" | grep -q ':' || continue
        _ts=$(echo "$_t" | sed 's/->[[:space:]]*/  /g')
        _tn=$(echo "$_ts" | cut -d: -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ ${#_tn} -gt $max_name_len ] && max_name_len=${#_tn}
    done <<< "$clean"
    local col_w=$((max_name_len + 3))

    # Проход 2: вывод с выравниванием по колонке
    local in_section=false
    local first_section=true
    while IFS= read -r line; do
        # Заголовок секции: ===[ ... ]===
        if echo "$line" | grep -qP '=+\[.*\]=+'; then
            local title
            title=$(echo "$line" | grep -oP '\[.*?\]' | head -1)
            $first_section || echo
            echo -e "${DARKGRAY}──────────── ${title} ────────────${NC}"
            echo
            in_section=true
            first_section=false
            continue
        fi
        if $in_section; then
            # Конец секции — строка только из =
            if echo "$line" | grep -qP '^\s*=+\s*$'; then
                in_section=false; continue
            fi
            [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
            local svc_line svc_name svc_value
            svc_line=$(echo "$line" | sed 's/->[[:space:]]*/  /g; s/:[[:space:]]\{4,\}/: /g')
            svc_name=$(echo "$svc_line" | cut -d: -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            svc_value=$(echo "$svc_line" | cut -d: -f2- | sed 's/^[[:space:]:]*//' | sed 's/[[:space:]]*$//')
            svc_value=$(_svc_yn "$svc_value")
            # Цвет и форматирование значения
            local dv
            if [[ "$svc_value" =~ ^(Да|Yes)[[:space:]]*\(Регион:[[:space:]]*([A-Z]+)\) ]]; then
                dv="${GREEN}${BASH_REMATCH[1]}${NC} ${DARKGRAY}(Регион: ${GREEN}${BASH_REMATCH[2]}${NC}${DARKGRAY})${NC}"
            elif [[ "$svc_value" =~ ^(Да|Yes)$ ]]; then
                dv="${GREEN}${svc_value}${NC}"
            elif [[ "$svc_value" =~ ^(Нет|No)$ ]] || [[ "$svc_value" == *Failed* ]]; then
                dv="${RED}${svc_value}${NC}"
            elif [[ "$svc_value" =~ ^[A-Z]{2,4}$ ]]; then
                dv="${GREEN}${svc_value}${NC}"
            else
                dv="${WHITE}${svc_value}${NC}"
            fi
            echo -ne " ${DARKGRAY}$(printf "%-${col_w}s" "${svc_name}:")${NC}"
            echo -e "${dv}"
        fi
    done <<< "$clean"
}

# Выводит секцию IPv6 если IPv6 обнаружен в выводе чекера
_print_ipv6_section() {
    local output="$1"
    # Если явно написано что IPv6 не найден — не показываем блок
    if echo "$output" | grep -qi 'ipv6.*не обнаружен\|no.*ipv6\|ipv6.*not\|ipv6.*отсутствует'; then
        return
    fi
    # Если есть строки с IPv6 данными — показываем
    local ipv6_provider ipv6_country ipv6_city ipv6_asn
    ipv6_provider=$(echo "$output" | grep -oP '(?i)\[ipv6\].*хостинг-провайдер:\s*\K.*' | head -1 | sed 's/\s*$//')
    ipv6_country=$(echo "$output" | grep -oP '(?i)\[ipv6\].*страна:\s*\K[A-Z]+' | head -1)
    ipv6_city=$(echo "$output" | grep -oP '(?i)\[ipv6\].*город:\s*\K.*' | head -1 | sed 's/\s*$//')
    ipv6_asn=$(echo "$output" | grep -oP '(?i)\[ipv6\].*asn:\s*\K.*' | head -1 | sed 's/\s*$//')
    if [ -n "$ipv6_provider$ipv6_country$ipv6_city$ipv6_asn" ]; then
        echo
        echo -e "${DARKGRAY}──────────────── [ IPv6 ] ─────────────────${NC}"
        [ -n "$ipv6_provider" ] && echo -e " ${DARKGRAY}Хостинг провайдер:${NC} ${WHITE}${ipv6_provider}${NC}"
        [ -n "$ipv6_country"  ] && echo -e " ${DARKGRAY}Страна:${NC} ${WHITE}$(_country_name "$ipv6_country")${NC}"
        [ -n "$ipv6_city"     ] && echo -e " ${DARKGRAY}Город:${NC} ${WHITE}${ipv6_city}${NC}"
        [ -n "$ipv6_asn"      ] && echo -e " ${DARKGRAY}ASN:${NC} ${WHITE}${ipv6_asn}${NC}"
    fi
}

run_regional_check() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     🔒 Региональные ограничения${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    (bash <(curl -s "storage.umager.ru/checker_inst_ru.sh") </dev/null > "$tmpfile" 2>&1) &
    show_spinner "Проверка региональных ограничений" "Диагностика региональных ограничений завершена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    _print_ipv4_info "$output"
    _print_checker_sections "$output"
    _print_ipv6_section "$output"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

run_geolocation() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}        📍 Геолокация IP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local tmpfile
    tmpfile=$(mktemp /tmp/rw_test.XXXXXX)
    # Запускаем скрипт геолокации в фоне с таймаутом 20 сек
    (
        command -v lscpu >/dev/null 2>&1 || apt-get install -y util-linux >/dev/null 2>&1
        echo "Y" | bash <(curl -fsSL --connect-timeout 8 --max-time 15 "https://storage.umager.ru/ipregion.sh")
    ) > "$tmpfile" 2>&1 &
    show_spinner "Определение геолокации IP" "Диагностика геолокации завершена"
    echo

    local output
    output=$(cat "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    # Очищаем ANSI-коды, \r, и строки от apt/системы
    local clean
    clean=$(echo "$output" \
        | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\r//g' \
        | grep -vP '^\s*(Reading package|Building dependency|Reading state|upgraded|newly installed|util-linux|No VM|Made with)')

    # Извлекаем IP и ASN из заголовка
    local geo_ip geo_asn
    geo_ip=$(echo "$clean" | grep -oP '^IPv4:\s*\K\S+' | head -1)
    geo_asn=$(echo "$clean" | grep -oP '^ASN:\s*\K.*' | head -1 | sed 's/\s*$//')

    if [ -z "$geo_ip" ]; then
        echo -e "${RED}Не удалось получить данные геолокации${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
        tput civis 2>/dev/null || true
        while true; do
            local _k=""
            IFS= read -rsn1 _k
            case "$_k" in
                $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
                "")      tput cnorm 2>/dev/null || true; return 0 ;;
            esac
        done
    fi

    # Проход 1: найти максимальную длину имени сервиса по всем таблицам
    local _max_svc=0 _in_tbl=false
    while IFS= read -r _l; do
        local _lt
        _lt=$(echo "$_l" | sed 's/^[[:space:]]*//')
        if [[ -z "$_lt" ]]; then
            $_in_tbl && _in_tbl=false; continue
        fi
        echo "$_lt" | grep -qP '^Service\s' && { _in_tbl=true; continue; }
        if $_in_tbl; then
            local _sn
            _sn=$(echo "$_l" | sed 's/[[:space:]]\{2,\}.*//' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            [ ${#_sn} -gt $_max_svc ] && _max_svc=${#_sn}
        fi
    done <<< "$clean"
    local col_w=$(( _max_svc + 3 ))

    # Заголовок IPv4/ASN
    echo -e "${DARKGRAY}──────────────── [ IPv4 ] ─────────────────${NC}"
    echo
    echo -e " ${DARKGRAY}$(_mpad "IPv4:" 5)${NC} ${WHITE}${geo_ip}${NC}"
    [ -n "$geo_asn" ] && echo -e " ${DARKGRAY}$(_mpad "ASN:" 5)${NC} ${WHITE}${geo_asn}${NC}"
    echo

    # Проход 2: парсим секции и таблицы
    local _in_tbl=false _first=true
    while IFS= read -r line; do
        local _t
        _t=$(echo "$line" | sed 's/^[[:space:]]*//')
        # Пустая строка: сбрасываем режим таблицы и пропускаем
        if [[ -z "$_t" ]]; then
            $_in_tbl && _in_tbl=false; continue
        fi
        # Пропускаем строки IPv4/ASN (уже показаны)
        echo "$_t" | grep -qP '^(IPv4|ASN):' && continue
        # Заголовок таблицы "Service  IPv4"
        if echo "$_t" | grep -qP '^Service\s'; then
            _in_tbl=true; continue
        fi
        if $_in_tbl; then
            local svc_name svc_val
            svc_name=$(echo "$line" | sed 's/[[:space:]]\{2,\}.*//' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            svc_val=$(echo "$line" | grep -oP '[[:space:]]{2,}\K\S.*' | head -1 | sed 's/[[:space:]]*$//')
            [[ -z "$svc_val" ]] && continue
            local vc="${GREEN}"
            [[ "$svc_val" =~ ^(N/A|null|-)$ ]] && vc="${DARKGRAY}"
            echo -e " ${WHITE}$(_mpad "${svc_name}:" $col_w)${NC} ${vc}${svc_val}${NC}"
            continue
        fi
        # Заголовок секции: Popular services / CDN services / GeoIP services
        if echo "$_t" | grep -qP '^[A-Za-z][A-Za-z0-9 ]+$'; then
            $_first || echo
            echo -e "${DARKGRAY}──────────── [ ${_t} ] ────────────${NC}"
            echo
            _first=false
        fi
    done <<< "$clean"

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${BLUE}Enter${DARKGRAY}: Продолжить   ${BLUE}Esc${DARKGRAY}: Выход${NC}"
    tput civis 2>/dev/null || true
    while true; do
        tput civis 2>/dev/null || true
        local _k=""
        IFS= read -rsn1 _k
        case "$_k" in
            $'\x1b') tput cnorm 2>/dev/null || true; return 1 ;;
            "")      tput cnorm 2>/dev/null || true; return 0 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# ОПТИМИЗАЦИЯ СЕРВЕРА
# ═══════════════════════════════════════════════════
manage_server_optimization() {
    while true; do
        tput civis 2>/dev/null || true
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   ⚙️  ОПТИМИЗАЦИЯ СЕРВЕРА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        show_arrow_menu "⚙️  Оптимизация сервера" \
            "💾  SWAP" \
            "🚀  BBR" \
            "──────────────────────────────────────" \
            "⬅️   Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) manage_swap || break ;;
            1) manage_bbr || break ;;
            2) continue ;;
            3) return ;;
        esac
    done
}
