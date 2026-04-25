# ═══════════════════════════════════════════════
# ЦЕНТРАЛИЗОВАННОЕ УПРАВЛЕНИЕ NGINX
# ═══════════════════════════════════════════════
#
# /opt/nginx/ — единая точка для nginx. Все приложения (Remnawave,
# Beszel и др.) используют общий nginx-контейнер.
#
# Структура:
#   /opt/nginx/docker-compose.yml      — фиксированный compose
#   /opt/nginx/nginx.conf              — основной конфиг (полный или минимальный)
#   /opt/nginx/ssl/                    — сертификаты
#
# Внешние server-блоки (Beszel и др.) вставляются напрямую в nginx.conf.
# Перед каждой перегенерацией nginx.conf блоки извлекаются в память
# и вставляются обратно после записи — без любых вспомогательных файлов.

DIR_NGINX="/opt/nginx/"

# В памяти: внешние server-блоки, сохранённые перед перегенерацией nginx.conf
declare -A _NGINX_EXTERNAL_BLOCKS=() 2>/dev/null || true

# В памяти: MTProto stream-блок (BEGIN_MTPROTO_STREAM...END_MTPROTO_STREAM)
_NGINX_MTPROTO_STREAM=""

# В памяти: MTProto connect server-блоки (BEGIN_MT_CONNECT_domain...END_MT_CONNECT_domain)
declare -A _NGINX_MT_CONNECT_BLOCKS=() 2>/dev/null || true

# ─── Создаёт /opt/nginx/ с docker-compose.yml если не существует ───
# Если docker-compose.yml создан внешним установщиком (remnasale-license и т.д.),
# обновляет его до полной версии, сохраняя кастомные volume-монтирования.
ensure_nginx() {
    mkdir -p "${DIR_NGINX}" "${DIR_NGINX}ssl"
    local _extra_vols=()
    if [ -f "${DIR_NGINX}docker-compose.yml" ]; then
        # Уже содержит все нужные volume-ы — ничего делать не надо
        if grep -q '/dev/shm:/dev/shm' "${DIR_NGINX}docker-compose.yml" 2>/dev/null; then
            return 0
        fi
        # Внешний docker-compose (remnasale-license и т.д.) — сохраняем кастомные volume-ы
        while IFS= read -r _v; do
            case "$_v" in
                *nginx.conf*|*/etc/nginx/ssl*|*letsencrypt*|*/dev/shm*|*/var/www/html:*) ;;
                *) _extra_vols+=("$_v") ;;
            esac
        done < <(grep -E '^\s+-\s+.+:.+' "${DIR_NGINX}docker-compose.yml" 2>/dev/null)
    fi
    cat > "${DIR_NGINX}docker-compose.yml" <<'COMPOSE'
services:
  nginx:
    image: nginx:1.28
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    network_mode: host
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: >
      sh -c '
        rm -f /dev/shm/nginx.sock &&
        CONF=/etc/nginx/nginx.conf &&
        if nginx -t -c "$$CONF" 2>/dev/null; then
          rm -f /dev/shm/.sub_disabled;
        else
          sed "/listen \[::\]:/d" "$$CONF" > /tmp/nginx_noipv6.conf &&
          if nginx -t -c /tmp/nginx_noipv6.conf 2>/dev/null; then
            CONF=/tmp/nginx_noipv6.conf;
            rm -f /dev/shm/.sub_disabled;
          else
            sed "/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/d" "$$CONF" > /tmp/nginx_nosub.conf &&
            sed -i "/listen \[::\]:/d" /tmp/nginx_nosub.conf &&
            CONF=/tmp/nginx_nosub.conf &&
            touch /dev/shm/.sub_disabled;
          fi;
        fi &&
        exec nginx -c "$$CONF" -g "daemon off;"
      '
    healthcheck:
      test: ['CMD-SHELL', 'kill -0 $$(cat /run/nginx.pid) 2>/dev/null']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
COMPOSE
    # Восстанавливаем кастомные volume-ы из предыдущего compose (remnasale-license site и т.д.)
    local _v
    for _v in "${_extra_vols[@]+"${_extra_vols[@]}"}"; do
        [ -z "$_v" ] && continue
        grep -qF "$_v" "${DIR_NGINX}docker-compose.yml" 2>/dev/null && continue
        sed -i "/\/var\/www\/html:\/var\/www\/html/a\\${_v}" "${DIR_NGINX}docker-compose.yml"
    done
}

# ─── Извлекает внешние server-блоки из nginx.conf в память перед перезаписью файла ───
# Все блоки BEGIN_*_BLOCK кроме BEGIN_SUB_BLOCK ситаются внешними (Beszel и др.).
# Также сохраняет MTProto stream-блок и MT_CONNECT server-блоки.
_nginx_extract_external_blocks() {
    [ -f "${DIR_NGINX}nginx.conf" ] || return 0  # если файл отсутствует — ничего извлекать
    local k; for k in "${!_NGINX_EXTERNAL_BLOCKS[@]}"; do unset "_NGINX_EXTERNAL_BLOCKS[$k]"; done
    local in_block=0 block_name="" buf="" line
    while IFS= read -r line; do
        [ "$line" = "# BEGIN_SUB_BLOCK" ] && { in_block=99; continue; }
        [ "$line" = "# END_SUB_BLOCK" ]   && { in_block=0; buf=""; continue; }
        [ "$in_block" -eq 99 ] && continue
        case "$line" in
            "# BEGIN_"*"_BLOCK")
                [ "$in_block" -eq 0 ] && {
                    block_name="${line#\# BEGIN_}"; block_name="${block_name%_BLOCK}"
                    in_block=1; buf=""
                } ;;
            "# END_"*"_BLOCK")
                [ "$in_block" -eq 1 ] && {
                    _NGINX_EXTERNAL_BLOCKS["$block_name"]="${buf%$'\n'}"
                    in_block=0; buf=""; block_name=""
                } ;;
            *)
                [ "$in_block" -eq 1 ] && buf+="${line}"$'\n' ;;
        esac
    done < "${DIR_NGINX}nginx.conf"

    # Сохраняем MTProto stream-блок (идёт перед http {})
    _NGINX_MTPROTO_STREAM=""
    if grep -q "# BEGIN_MTPROTO_STREAM" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        _NGINX_MTPROTO_STREAM=$(awk '/# BEGIN_MTPROTO_STREAM/,/# END_MTPROTO_STREAM/' "${DIR_NGINX}nginx.conf")
    fi

    # Сохраняем MT_CONNECT server-блоки (идут внутри http {})
    local k2; for k2 in "${!_NGINX_MT_CONNECT_BLOCKS[@]}"; do unset "_NGINX_MT_CONNECT_BLOCKS[$k2]"; done
    local in_mt=0 mt_domain="" mt_buf=""
    while IFS= read -r line; do
        if [[ "$line" == "# BEGIN_MT_CONNECT_"* ]]; then
            in_mt=1; mt_domain="${line#\# BEGIN_MT_CONNECT_}"; mt_buf=""
        elif [[ "$line" == "# END_MT_CONNECT_"* ]]; then
            [ "$in_mt" -eq 1 ] && _NGINX_MT_CONNECT_BLOCKS["$mt_domain"]="${mt_buf%$'\n'}"
            in_mt=0; mt_domain=""
        elif [ "$in_mt" -eq 1 ]; then
            mt_buf+="${line}"$'\n'
        fi
    done < "${DIR_NGINX}nginx.conf"
}

# ─── Генерирует минимальный nginx.conf (без Remnawave) ───
# Используется когда установлены только сторонние сервисы (Beszel и т.д.)
nginx_generate_minimal_conf() {
    _nginx_extract_external_blocks
    cat > "${DIR_NGINX}nginx.conf" <<'NGINX'
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /run/nginx.pid;

events {
    worker_connections  8192;
    use epoll;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    access_log off;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;

    keepalive_timeout  65;

    gzip on;
    gzip_types application/json text/plain text/css application/javascript;
    gzip_min_length 256;
    gzip_vary on;

    client_max_body_size 1m;

} # ─── end http ───
NGINX
    # Restore saved server blocks (e.g. Beszel) into new minimal conf
    nginx_restore_server_blocks
}

# ─── Восстанавливает MTProto stream-блок перед http {} ───
# Вызывается после каждой перегенерации nginx.conf (из _nginx_http_header в config.sh).
_nginx_restore_stream_block() {
    [ -z "${_NGINX_MTPROTO_STREAM:-}" ] && return 0
    [ -f "${DIR_NGINX}nginx.conf" ] || return 0
    grep -q "# BEGIN_MTPROTO_STREAM" "${DIR_NGINX}nginx.conf" 2>/dev/null && return 0
    local tmp stream_file
    tmp=$(mktemp); stream_file=$(mktemp)
    printf '%s\n' "$_NGINX_MTPROTO_STREAM" > "$stream_file"
    awk -v sf="$stream_file" '
        /^http \{/ {
            while ((getline line < sf) > 0) print line
            close(sf)
            print ""
        }
        { print }
    ' "${DIR_NGINX}nginx.conf" > "$tmp" && cat "$tmp" > "${DIR_NGINX}nginx.conf"
    rm -f "$tmp" "$stream_file"
}

# ─── Восстанавливает MT_CONNECT server-блоки внутри http {} ───
# Вызывается из nginx_restore_server_blocks.
_nginx_restore_mt_connect_blocks() {
    [ -f "${DIR_NGINX}nginx.conf" ] || return 0

    # Определяем текущий режим nginx.conf.
    # ВАЖНО: проверяем unix-сокет ТОЛЬКО вне MT_CONNECT блоков, иначе сам MT_CONNECT
    # блок (который может временно содержать unix-директиву) создаёт ложное срабатывание.
    local _uses_socket=false _has_listen_443=false _has_stream_block=false
    if grep -q "# BEGIN_MTPROTO_STREAM" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        _has_stream_block=true
        _uses_socket=true
    else
        # Ищем unix-сокет в частях конфига без MT_CONNECT блоков
        local _conf_no_mt
        _conf_no_mt=$(python3 -c "
import sys, re
with open('${DIR_NGINX}nginx.conf') as f: c = f.read()
c = re.sub(r'# BEGIN_MT_CONNECT_.*?# END_MT_CONNECT_[^\n]*\n?', '', c, flags=re.DOTALL)
print(c)
" 2>/dev/null) || _conf_no_mt=$(grep -v "BEGIN_MT_CONNECT\|END_MT_CONNECT" "${DIR_NGINX}nginx.conf" 2>/dev/null || true)
        if echo "$_conf_no_mt" | grep -q 'listen unix:/dev/shm/nginx.sock' 2>/dev/null; then
            _uses_socket=true
        fi
    fi
    if grep -Eq '^\s*listen\s+443\s+ssl' "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        _has_listen_443=true
    fi

    # Fallback: если блоки не сохранены (MTProto установлен без nginx), генерируем из .env
    local _mt_env="/opt/mtproto/.env"
    if [ ${#_NGINX_MT_CONNECT_BLOCKS[@]} -eq 0 ] && [ -f "$_mt_env" ]; then
        local _si="" _ss="" _sp="" _sn=""
        _si=$(grep '^SERVER_IP=' "$_mt_env" 2>/dev/null | cut -d= -f2)
        _ss=$(grep '^PROXY_SECRET=' "$_mt_env" 2>/dev/null | cut -d= -f2)
        _sp=$(grep '^PROXY_PORT=' "$_mt_env" 2>/dev/null | cut -d= -f2)
        _sn=$(grep '^PROXY_NAME=' "$_mt_env" 2>/dev/null | cut -d= -f2)
        # Только для доменов (не IP), с существующим сертификатом
        if [ -n "$_si" ] && [[ ! "$_si" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
           && [ -f "/opt/nginx/ssl/${_si}/fullchain.pem" -o -f "/etc/letsencrypt/live/${_si}/fullchain.pem" ]; then
            # Копируем сертификат в nginx ssl если нет
            if [ ! -f "/opt/nginx/ssl/${_si}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${_si}/fullchain.pem" ]; then
                mkdir -p "/opt/nginx/ssl/${_si}"
                cp -fL "/etc/letsencrypt/live/${_si}/fullchain.pem" "/opt/nginx/ssl/${_si}/fullchain.pem"
                cp -fL "/etc/letsencrypt/live/${_si}/privkey.pem" "/opt/nginx/ssl/${_si}/privkey.pem"
            fi
            local _html_path="/var/www/html/mtproto-connect.html"
            # Режим listen: stream → только unix+PP; coexistent Remnawave (unix+443) → unix+443 без real_ip;
            # иначе прямой 443.
            local _fb_listen _fb_real_ip=""
            if [ "$_has_stream_block" = true ]; then
                _fb_listen="    listen unix:/dev/shm/nginx.sock proxy_protocol;"
                _fb_real_ip="    real_ip_header proxy_protocol;
    set_real_ip_from unix:;"
            elif [ "$_uses_socket" = true ]; then
                _fb_listen="    listen unix:/dev/shm/nginx.sock proxy_protocol;
    listen 443 ssl;
    listen [::]:443 ssl;"
            else
                _fb_listen="    listen 443 ssl;
    listen [::]:443 ssl;"
            fi
            _NGINX_MT_CONNECT_BLOCKS["$_si"]="server {
    server_name ${_si};
${_fb_listen}
    http2 on;
${_fb_real_ip:+
${_fb_real_ip}
}
    ssl_certificate \"/etc/nginx/ssl/${_si}/fullchain.pem\";
    ssl_certificate_key \"/etc/nginx/ssl/${_si}/privkey.pem\";

    add_header X-Robots-Tag \"noindex, nofollow, noarchive, nosnippet, noimageindex\" always;

    location = /connect {
        default_type text/html;
        alias ${_html_path};
    }

    location / {
        return 444;
    }
}"
            # Также обновляем HTML-файл
            if type _mt_write_proxy_page &>/dev/null; then
                _mt_write_proxy_page "$_si" "$_ss" "$_sp" "$_sn" 2>/dev/null || true
            fi
        fi
    fi

    local domain content tmp block_file
    for domain in "${!_NGINX_MT_CONNECT_BLOCKS[@]}"; do
        grep -qF "# BEGIN_MT_CONNECT_${domain}" "${DIR_NGINX}nginx.conf" 2>/dev/null && continue
        content="${_NGINX_MT_CONNECT_BLOCKS[$domain]}"
        # Адаптируем listen-директивы под текущее состояние сервера.
        # Это необходимо когда архитектура изменилась (например, установили ноду после MT).
        if [ "$_has_stream_block" = true ]; then
            # Stream владеет 443: только unix + proxy_protocol к шлюзу 8444.
            content=$(printf '%s\n' "$content" \
                | sed -E '/^\s*listen\s+(\[::\]:)?443\s+ssl/d')
            if ! printf '%s' "$content" | grep -q 'listen unix:/dev/shm/nginx.sock'; then
                content=$(printf '%s\n' "$content" | sed \
                    '/server_name /a\    listen unix:/dev/shm/nginx.sock proxy_protocol;')
            fi
            if ! printf '%s' "$content" | grep -q 'real_ip_header proxy_protocol'; then
                content=$(printf '%s\n' "$content" | sed '/http2 on;/a\
    real_ip_header proxy_protocol;\
    set_real_ip_from unix:;')
            fi
        elif [ "$_uses_socket" = true ]; then
            # Как у server{} панели: unix + 443; без real_ip (браузер на 443 без PROXY).
            content=$(printf '%s\n' "$content" \
                | sed -e '/real_ip_header proxy_protocol/d' \
                      -e '/set_real_ip_from unix:/d')
            if ! printf '%s' "$content" | grep -q 'listen unix:/dev/shm/nginx.sock'; then
                content=$(printf '%s\n' "$content" | sed \
                    '/server_name /a\    listen unix:/dev/shm/nginx.sock proxy_protocol;')
            fi
            if ! printf '%s' "$content" | grep -qE '^\s*listen\s+443\s+ssl'; then
                content=$(printf '%s\n' "$content" | sed \
                    '/listen unix:\/dev\/shm\/nginx.sock ssl proxy_protocol;/a\    listen 443 ssl;\n    listen [::]:443 ssl;')
            fi
        else
            # Прямой режим: только listen 443.
            content=$(printf '%s\n' "$content" \
                | sed -e '/listen unix:\/dev\/shm\/nginx.sock/d' \
                      -e '/real_ip_header proxy_protocol/d' \
                      -e '/set_real_ip_from unix:/d')
            if ! printf '%s' "$content" | grep -qE '^\s*listen\s+443\s+ssl'; then
                content=$(printf '%s\n' "$content" | sed \
                    '/server_name /a\    listen 443 ssl;\n    listen [::]:443 ssl;')
            fi
        fi
        tmp=$(mktemp); block_file=$(mktemp)
        printf '# BEGIN_MT_CONNECT_%s\n%s\n# END_MT_CONNECT_%s\n' "$domain" "$content" "$domain" > "$block_file"
        awk -v bf="$block_file" '
            /end http/ {
                while ((getline line < bf) > 0) print line
                close(bf)
            }
            { print }
        ' "${DIR_NGINX}nginx.conf" > "$tmp" && cat "$tmp" > "${DIR_NGINX}nginx.conf"
        rm -f "$tmp" "$block_file"
    done
}

# ─── Копирует сертификат из letsencrypt в /opt/nginx/ssl/{domain}/ ───
# Использование: nginx_copy_cert "example.com"
nginx_copy_cert() {
    local domain="$1"
    local le_base="$domain"
    local r
    r=$(le_live_basename "$domain" 2>/dev/null) || r=""
    [ -n "$r" ] && le_base="$r"
    local src="/etc/letsencrypt/live/${le_base}"
    local dst="${DIR_NGINX}ssl/${le_base}"
    [ -f "${src}/fullchain.pem" ] || return 1
    mkdir -p "$dst"
    cp -fL "${src}/fullchain.pem" "${dst}/fullchain.pem"
    cp -fL "${src}/privkey.pem"   "${dst}/privkey.pem"
}

# ─── Вставляет server-блок перед '} # ─── end http ───' в nginx.conf ───
_nginx_insert_server_block() {
    local conf_file="$1"
    local name="$2"
    local content="$3"
    local tmp="${conf_file}.tmp"
    local block_file
    block_file=$(mktemp)
    printf '# BEGIN_%s_BLOCK\n%s\n# END_%s_BLOCK\n' "$name" "$content" "$name" > "$block_file"
    awk -v blockfile="$block_file" '
        /^} # ─── end http ───/ {
            while ((getline line < blockfile) > 0) print line
            close(blockfile)
        }
        { print }
    ' "$conf_file" > "$tmp" && cat "$tmp" > "$conf_file"
    rm -f "$tmp" "$block_file"
}

# ─── Добавляет server-блок напрямую в nginx.conf ───
# Использование: nginx_add_server_block "BESZEL" "$block_content"
nginx_add_server_block() {
    local name="${1^^}"
    local content="$2"
    if [ ! -f "${DIR_NGINX}nginx.conf" ]; then
        nginx_generate_minimal_conf
    fi
    # Удаляем старый блок если есть, затем вставляем свежий
    if grep -qF "# BEGIN_${name}_BLOCK" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        local _t; _t=$(mktemp)
        sed "/^# BEGIN_${name}_BLOCK/,/^# END_${name}_BLOCK/d" "${DIR_NGINX}nginx.conf" > "$_t" && cat "$_t" > "${DIR_NGINX}nginx.conf"
        rm -f "$_t"
    fi
    _nginx_insert_server_block "${DIR_NGINX}nginx.conf" "$name" "$content"
    # Обновляем кэш для будущих перегенераций nginx.conf
    _NGINX_EXTERNAL_BLOCKS["$name"]="$content"
}

# ─── Удаляет server-блок из nginx.conf ───
nginx_remove_server_block() {
    local name="${1^^}"
    unset "_NGINX_EXTERNAL_BLOCKS[$name]" 2>/dev/null || true
    if [ -f "${DIR_NGINX}nginx.conf" ]; then
        local _t; _t=$(mktemp)
        sed "/^# BEGIN_${name}_BLOCK/,/^# END_${name}_BLOCK/d" "${DIR_NGINX}nginx.conf" > "$_t" && cat "$_t" > "${DIR_NGINX}nginx.conf"
        rm -f "$_t"
    fi
}

# ─── Восстанавливает внешние server-блоки в nginx.conf из памяти ───
# Вызывается после каждой перегенерации nginx.conf.
# Адаптирует listen-директивы под текущий конфиг (unix socket vs port 443).
nginx_restore_server_blocks() {
    [ -f "${DIR_NGINX}nginx.conf" ] || return 0
    local name content uses_socket=false has_port_443=false
    if grep -q 'listen unix:/dev/shm/nginx.sock' "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        uses_socket=true
    fi
    # Проверяем, есть ли listen 443 в базовом конфиге (панель + нода или только панель).
    # Если нет (standalone нода) — порт 443 предназначен для xray, внешние блоки не должны на нём слушать.
    if grep -q 'listen 443 ssl;' "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        has_port_443=true
    fi
    for name in "${!_NGINX_EXTERNAL_BLOCKS[@]}"; do
        grep -qF "# BEGIN_${name}_BLOCK" "${DIR_NGINX}nginx.conf" 2>/dev/null && continue
        content="${_NGINX_EXTERNAL_BLOCKS[$name]}"
        if $uses_socket; then
            # Убираем IPv6
            content=$(printf '%s\n' "$content" | sed '/listen \[::\]:443/d')
            # Добавляем unix socket listen если отсутствует
            if ! printf '%s' "$content" | grep -q 'listen unix:/dev/shm/nginx.sock'; then
                if $has_port_443; then
                    # Панель + нода: сохраняем listen 443 ssl; наряду с unix socket
                    content=$(printf '%s\n' "$content" | sed \
                        's|listen 443 ssl;|listen unix:/dev/shm/nginx.sock proxy_protocol;\n    listen 443 ssl;|')
                else
                    # Standalone нода: порт 443 для xray — заменяем на unix socket
                    content=$(printf '%s\n' "$content" | sed \
                        's|listen 443 ssl;|listen unix:/dev/shm/nginx.sock proxy_protocol;|')
                fi
            fi
            # Standalone нода: убираем оставшиеся listen 443 ssl; (если были рядом с socket)
            if ! $has_port_443 && printf '%s' "$content" | grep -q 'listen 443 ssl;'; then
                content=$(printf '%s\n' "$content" | sed '/listen 443 ssl;/d')
            fi
            # Добавляем proxy_protocol headers если отсутствуют
            if ! printf '%s' "$content" | grep -q 'real_ip_header proxy_protocol'; then
                content=$(printf '%s\n' "$content" | sed '/http2 on;/a\
    real_ip_header proxy_protocol;\
    set_real_ip_from unix:;')
            fi
        else
            # Убираем unix socket и proxy_protocol, добавляем listen 443
            if ! printf '%s' "$content" | grep -q 'listen 443 ssl;'; then
                content=$(printf '%s\n' "$content" | sed \
                    's|listen unix:/dev/shm/nginx.sock proxy_protocol;|listen 443 ssl;\n    listen [::]:443 ssl;|')
            else
                content=$(printf '%s\n' "$content" | sed \
                    '/listen unix:\/dev\/shm\/nginx.sock/d')
            fi
            content=$(printf '%s\n' "$content" | sed \
                -e '/real_ip_header proxy_protocol;/d' \
                -e '/set_real_ip_from unix:;/d')
        fi
        _NGINX_EXTERNAL_BLOCKS["$name"]="$content"
        _nginx_insert_server_block "${DIR_NGINX}nginx.conf" "$name" "$content"
    done
    # Восстанавливаем MT_CONNECT server-блоки (MTProto connect pages)
    _nginx_restore_mt_connect_blocks
}

# ─── Проверяет, есть ли пользователи nginx (Remnawave, Beszel и т.д.) ───
nginx_has_users() {
    if is_panel_installed || is_node_installed; then
        return 0
    fi
    [ -f "/opt/subscribe-page/docker-compose.yml" ] && return 0
    [ -f "/opt/remnasubpage/docker-compose.yml" ] && return 0
    # Только блоки Beszel (управляемые dfc-manager) считаются пользователями nginx
    if [ -f "${DIR_NGINX}nginx.conf" ] && \
       grep -q "^# BEGIN_BESZEL_BLOCK$" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ─── Стартует или перезапускает nginx ───
nginx_reload() {
    if ! [ -f "${DIR_NGINX}docker-compose.yml" ]; then
        return 1
    fi
    # Перезагружаем сервер-блоки из памяти перед перезагрузкой
    [ -f "${DIR_NGINX}nginx.conf" ] && nginx_restore_server_blocks
    # Убираем IPv6 директивы если IPv6 не поддерживается ядром
    nginx_strip_ipv6_if_disabled
    # Убираем дублированные listen директивы
    _nginx_dedup_listen
    # Удаляем bak если остался от предыдущих версий
    rm -f "${DIR_NGINX}nginx.conf.bak" 2>/dev/null || true
    # Проверяем конфиг перед перезапуском (монтируем ssl и letsencrypt)
    # Продолжаем даже если тест упал — реальный контейнер nginx:1.28 может принять конфиг
    docker run --rm \
         -v "${DIR_NGINX}nginx.conf:/etc/nginx/nginx.conf:ro" \
         -v "${DIR_NGINX}ssl:/etc/nginx/ssl:ro" \
         -v "/etc/letsencrypt:/etc/letsencrypt:ro" \
         nginx:latest nginx -t >/dev/null 2>&1 || true
    # Если контейнер уже работает — graceful reload (без downtime)
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'remnawave-nginx'; then
        cd "${DIR_NGINX}" && docker compose up -d >/dev/null 2>&1
        docker exec remnawave-nginx nginx -s reload >/dev/null 2>&1
    else
        cd "${DIR_NGINX}" && docker compose up -d >/dev/null 2>&1
    fi
}

# ─── Убирает дублированные listen директивы в каждом server-блоке ───
_nginx_dedup_listen() {
    [ -f "${DIR_NGINX}nginx.conf" ] || return 0
    local tmp="${DIR_NGINX}nginx.conf.dedup"
    awk '
    /^[[:space:]]*server[[:space:]]*\{/ { in_server=1; delete seen }
    /^[[:space:]]*\}/ { in_server=0 }
    in_server && /^[[:space:]]*listen[[:space:]]/ {
        if (seen[$0]++) next
    }
    { print }
    ' "${DIR_NGINX}nginx.conf" > "$tmp" && cat "$tmp" > "${DIR_NGINX}nginx.conf"
    rm -f "$tmp"
}

# ─── Убирает listen [::]: директивы из nginx.conf если IPv6 отключён ───
nginx_strip_ipv6_if_disabled() {
    [ -f "${DIR_NGINX}nginx.conf" ] || return 0
    # Проверяем доступность IPv6 — через proc или ip команду
    if [ -f /proc/net/if_inet6 ] && [ -s /proc/net/if_inet6 ]; then
        return 0  # IPv6 работает — ничего не делаем
    fi
    if ip -6 addr show 2>/dev/null | grep -q 'inet6'; then
        return 0  # IPv6 работает — ничего не делаем
    fi
    # IPv6 недоступен — удаляем все "listen [::]:..." строки
    local _t; _t=$(mktemp)
    sed '/listen \[\:\:\]:/d' "${DIR_NGINX}nginx.conf" > "$_t" && cat "$_t" > "${DIR_NGINX}nginx.conf"
    rm -f "$_t"
}

# ─── Полностью удаляет nginx ───
nginx_teardown() {
    if [ -d "${DIR_NGINX}" ]; then
        (cd "${DIR_NGINX}" 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1) || true
        rm -rf "${DIR_NGINX}"
    fi
}

# ─── Удаляет сервис remnawave-nginx из docker-compose.yml ───
# Вызывается после generate_docker_compose_*(), т.к. nginx теперь в /opt/nginx/
_strip_nginx_from_compose() {
    local compose_file="$1"
    [ -f "$compose_file" ] || return 0
    awk '
    /^  remnawave-nginx:/ { skip=1; next }
    skip && /^[^ ]/ { skip=0 }
    skip && /^  [a-z]/ { skip=0 }
    !skip { print }
    ' "$compose_file" > "${compose_file}.tmp" && mv "${compose_file}.tmp" "$compose_file"
}

# ─── Проверяет, нужен ли nginx.conf пересоздать как минимальный ───
# Вызывается после удаления компонента Remnawave.
# Если остался Beszel — заменяет nginx.conf на минимальный.
nginx_ensure_conf_for_remaining() {
    if ! is_panel_installed && ! is_node_installed && \
       ! [ -f "/opt/subscribe-page/docker-compose.yml" ] && \
       ! [ -f "/opt/remnasubpage/docker-compose.yml" ]; then
        # Проверяем прочих "пользователей" nginx:
        # - BESZEL_BLOCK (панель/агент Beszel)
        # - MT_CONNECT_* или MTPROTO_STREAM (MTProto)
        local _has_beszel=false _has_mtproto=false
        if [ -f "${DIR_NGINX}nginx.conf" ] && \
           grep -q "^# BEGIN_BESZEL_BLOCK$" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
            _has_beszel=true
        fi
        if type _mt_installed &>/dev/null && _mt_installed; then
            _has_mtproto=true
        elif [ -f "${DIR_NGINX}nginx.conf" ] && \
             grep -qE "# BEGIN_(MT_CONNECT_|MTPROTO_STREAM)" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
            _has_mtproto=true
        fi
        if $_has_beszel || $_has_mtproto; then
            nginx_generate_minimal_conf  # сохраняет блоки из памяти и восстанавливает их (включая MT_CONNECT)
            nginx_reload
        else
            nginx_teardown
        fi
    fi
}

# ─── Удаляет сертификаты из /opt/nginx/ssl/ которые больше не используются ───
# Проверяет ссылки в nginx.conf (включая вставленные server-блоки) — если домен
# не упоминается, удаляет его.
nginx_cleanup_unused_certs() {
    [ -d "${DIR_NGINX}ssl" ] || return 0
    local d dn
    for d in "${DIR_NGINX}ssl/"*/; do
        [ -d "$d" ] || continue
        dn=$(basename "$d")
        # Используется в nginx.conf (включая вставленные server-блоки)?
        if [ -f "${DIR_NGINX}nginx.conf" ] && grep -q "/ssl/${dn}/" "${DIR_NGINX}nginx.conf"; then
            continue
        fi
        # Удалено из ssl/ (letsencrypt остаётся)
        rm -rf "$d"
    done
}
