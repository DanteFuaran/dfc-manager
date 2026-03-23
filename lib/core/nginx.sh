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
#   /opt/nginx/blocks/                 — сохранённые server-блоки (beszel и др.)
#   /opt/nginx/conf.d/                 — legacy conf.d (для совместимости)
#   /opt/nginx/ssl/                    — самоподписанные сертификаты
#
# Server-блоки Beszel и сторонних сервисов хранятся в /opt/nginx/blocks/
# и автоматически вставляются в nginx.conf при каждой генерации/перезагрузке.

DIR_NGINX="/opt/nginx/"

# ─── Создаёт /opt/nginx/ с docker-compose.yml если не существует ───
ensure_nginx() {
    if [ -f "${DIR_NGINX}docker-compose.yml" ]; then
        return 0
    fi
    mkdir -p "${DIR_NGINX}" "${DIR_NGINX}conf.d" "${DIR_NGINX}ssl" "${DIR_NGINX}blocks"
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
      - ./conf.d:/etc/nginx/conf.d:ro
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

# ─── Генерирует минимальный nginx.conf (без Remnawave) ───
# Используется когда установлены только сторонние сервисы (Beszel и т.д.)
nginx_generate_minimal_conf() {
    mkdir -p "${DIR_NGINX}conf.d" "${DIR_NGINX}blocks"
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

    include /etc/nginx/conf.d/*.conf;

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

# ─── Добавляет server-блок в nginx.conf и сохраняет в blocks/ для восстановления ───
# Использование: nginx_add_server_block "BESZEL" "$block_content"
nginx_add_server_block() {
    local name="${1^^}"
    local content="$2"
    mkdir -p "${DIR_NGINX}blocks"
    # Сохраняем блок для последующего восстановления после перегенерации nginx.conf
    printf '%s\n' "$content" > "${DIR_NGINX}blocks/${name}.block"
    if [ ! -f "${DIR_NGINX}nginx.conf" ]; then
        nginx_generate_minimal_conf
        return
    fi
    # Если блок уже вставлен — удаляем и вставляем заново (обновление)
    if grep -qF "# BEGIN_${name}_BLOCK" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
        sed -i "/^# BEGIN_${name}_BLOCK/,/^# END_${name}_BLOCK/d" "${DIR_NGINX}nginx.conf"
    fi
    _nginx_insert_server_block "${DIR_NGINX}nginx.conf" "$name" "$content"
}

# ─── Удаляет server-блок из nginx.conf и удаляет файл из blocks/ ───
nginx_remove_server_block() {
    local name="${1^^}"
    rm -f "${DIR_NGINX}blocks/${name}.block"
    if [ -f "${DIR_NGINX}nginx.conf" ]; then
        sed -i "/^# BEGIN_${name}_BLOCK/,/^# END_${name}_BLOCK/d" "${DIR_NGINX}nginx.conf"
    fi
}

# ─── Восстанавливает SERVER-блоки из blocks/ в nginx.conf если они там отсутствуют ───
# Вызывается после перегенерации nginx.conf чтобы не потерять Beszel и др.
nginx_restore_server_blocks() {
    local blocks_dir="${DIR_NGINX}blocks"
    [ -d "$blocks_dir" ] || return 0
    [ -f "${DIR_NGINX}nginx.conf" ] || return 0
    local block_file name content
    for block_file in "${blocks_dir}/"*.block; do
        [ -f "$block_file" ] || continue
        name=$(basename "$block_file" .block | tr '[:lower:]' '[:upper:]')
        if ! grep -qF "# BEGIN_${name}_BLOCK" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
            content=$(cat "$block_file")
            _nginx_insert_server_block "${DIR_NGINX}nginx.conf" "$name" "$content"
        fi
    done
}

# ─── Добавляет файл server-блока в conf.d (legacy, для совместимости) ───
nginx_add_block() {
    local name="$1"
    local content="$2"
    mkdir -p "${DIR_NGINX}conf.d"
    echo "$content" > "${DIR_NGINX}conf.d/${name}.conf"
}

# ─── Удаляет файл server-блока из conf.d (legacy) ───
nginx_remove_block() {
    local name="$1"
    rm -f "${DIR_NGINX}conf.d/${name}.conf"
}

# ─── Проверяет, есть ли пользователи nginx (Remnawave, Beszel и т.д.) ───
nginx_has_users() {
    # Remnawave использует основной nginx.conf (не conf.d)
    if is_panel_installed || is_node_installed; then
        return 0
    fi
    # Standalone страница подписки
    [ -f "/opt/subscribe-page/docker-compose.yml" ] && return 0
    [ -f "/opt/remnasubpage/docker-compose.yml" ] && return 0
    # Сохранённые server-блоки (Beszel и др.)
    local f
    for f in "${DIR_NGINX}blocks/"*.block; do
        [ -f "$f" ] && return 0
    done
    # Legacy conf.d
    for f in "${DIR_NGINX}conf.d/"*.conf; do
        [ -f "$f" ] && return 0
    done
    return 1
}

# ─── Стартует или перезапускает nginx ───
nginx_reload() {
    if ! [ -f "${DIR_NGINX}docker-compose.yml" ]; then
        return 1
    fi
    # Restore any server blocks that may have been wiped by nginx.conf regeneration
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
        # Remnawave удалён, проверяем наличие сохранённых блоков или conf.d
        local f has_blocks=false
        for f in "${DIR_NGINX}blocks/"*.block; do
            [ -f "$f" ] && { has_blocks=true; break; }
        done
        if ! $has_blocks; then
            for f in "${DIR_NGINX}conf.d/"*.conf; do
                [ -f "$f" ] && { has_blocks=true; break; }
            done
        fi
        if $has_blocks; then
            nginx_generate_minimal_conf  # also calls nginx_restore_server_blocks
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
        # Используется в blocks/?
        if grep -rq "/ssl/${dn}/" "${DIR_NGINX}blocks/" 2>/dev/null; then
            continue
        fi
        # Используется в conf.d/?
        if grep -rq "/ssl/${dn}/" "${DIR_NGINX}conf.d/" 2>/dev/null; then
            continue
        fi
        # Не используется — удаляем из ssl/ (letsencrypt остаётся)
        rm -rf "$d"
    done
}
