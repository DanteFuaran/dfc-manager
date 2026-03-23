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

# ─── Создаёт /opt/nginx/ с docker-compose.yml если не существует ───
ensure_nginx() {
    if [ -f "${DIR_NGINX}docker-compose.yml" ]; then
        return 0
    fi
    mkdir -p "${DIR_NGINX}" "${DIR_NGINX}ssl"
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
        if ! nginx -t -c "$$CONF" 2>/dev/null; then
          sed "/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/d" "$$CONF" > /tmp/nginx_nosub.conf &&
          CONF=/tmp/nginx_nosub.conf &&
          touch /dev/shm/.sub_disabled;
        else
          rm -f /dev/shm/.sub_disabled;
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
}

# ─── Извлекает внешние server-блоки из nginx.conf в память перед перезаписью файла ───
# Все блоки BEGIN_*_BLOCK кроме BEGIN_SUB_BLOCK ситаются внешними (Beszel и др.).
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

# ─── Копирует сертификат из letsencrypt в /opt/nginx/ssl/{domain}/ ───
# Использование: nginx_copy_cert "example.com"
nginx_copy_cert() {
    local domain="$1"
    local src="/etc/letsencrypt/live/${domain}"
    local dst="${DIR_NGINX}ssl/${domain}"
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
    ' "$conf_file" > "$tmp" && mv "$tmp" "$conf_file"
    rm -f "$block_file"
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
        sed -i "/^# BEGIN_${name}_BLOCK/,/^# END_${name}_BLOCK/d" "${DIR_NGINX}nginx.conf"
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
        sed -i "/^# BEGIN_${name}_BLOCK/,/^# END_${name}_BLOCK/d" "${DIR_NGINX}nginx.conf"
    fi
}

# ─── Восстанавливает внешние server-блоки в nginx.conf из памяти ───
# Вызывается после каждой перегенерации nginx.conf.
# Адаптирует listen-директивы под текущий конфиг (unix socket vs port 443).
nginx_restore_server_blocks() {
    [ -f "${DIR_NGINX}nginx.conf" ] || return 0
    local name content uses_socket=false
    if grep -q 'listen unix:/dev/shm/nginx.sock' "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        uses_socket=true
    fi
    for name in "${!_NGINX_EXTERNAL_BLOCKS[@]}"; do
        grep -qF "# BEGIN_${name}_BLOCK" "${DIR_NGINX}nginx.conf" 2>/dev/null && continue
        content="${_NGINX_EXTERNAL_BLOCKS[$name]}"
        if $uses_socket; then
            # Заменяем listen 443 → unix socket
            content=$(printf '%s\n' "$content" | sed \
                -e '/listen \[::\]:443/d' \
                -e 's|listen 443 ssl;|listen unix:/dev/shm/nginx.sock ssl proxy_protocol;|')
            # Добавляем proxy_protocol headers если отсутствуют
            if ! printf '%s' "$content" | grep -q 'real_ip_header proxy_protocol'; then
                content=$(printf '%s\n' "$content" | sed '/http2 on;/a\
    real_ip_header proxy_protocol;\
    set_real_ip_from unix:;')
            fi
        else
            # Заменяем unix socket → listen 443
            content=$(printf '%s\n' "$content" | sed \
                -e 's|listen unix:/dev/shm/nginx.sock ssl proxy_protocol;|listen 443 ssl;\n    listen [::]:443 ssl;|' \
                -e '/real_ip_header proxy_protocol;/d' \
                -e '/set_real_ip_from unix:;/d')
        fi
        _NGINX_EXTERNAL_BLOCKS["$name"]="$content"
        _nginx_insert_server_block "${DIR_NGINX}nginx.conf" "$name" "$content"
    done
}

# ─── Проверяет, есть ли пользователи nginx (Remnawave, Beszel и т.д.) ───
nginx_has_users() {
    if is_panel_installed || is_node_installed; then
        return 0
    fi
    [ -f "/opt/subscribe-page/docker-compose.yml" ] && return 0
    [ -f "/opt/remnasubpage/docker-compose.yml" ] && return 0
    # Внешние server-блоки в nginx.conf (Beszel и др.) — любой BEGIN_*_BLOCK кроме SUB
    if [ -f "${DIR_NGINX}nginx.conf" ] && \
       grep "^# BEGIN_.*_BLOCK$" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -qvF "# BEGIN_SUB_BLOCK"; then
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
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "remnawave-nginx"; then
        (cd "${DIR_NGINX}" && docker compose down nginx >/dev/null 2>&1; docker compose up -d nginx >/dev/null 2>&1)
    else
        (cd "${DIR_NGINX}" && docker compose up -d >/dev/null 2>&1)
    fi
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
# Если остались только блоки (Beszel и др.) — заменяет nginx.conf на минимальный.
nginx_ensure_conf_for_remaining() {
    if ! is_panel_installed && ! is_node_installed && \
       ! [ -f "/opt/subscribe-page/docker-compose.yml" ] && \
       ! [ -f "/opt/remnasubpage/docker-compose.yml" ]; then
        # Если в nginx.conf есть внешние блоки (Beszel и др.) — оставляем минимальный conf
        if [ -f "${DIR_NGINX}nginx.conf" ] && \
           grep "^# BEGIN_.*_BLOCK$" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -qvF "# BEGIN_SUB_BLOCK"; then
            nginx_generate_minimal_conf  # сохраняет блоки из памяти и восстанавливает их
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
