# ═══════════════════════════════════════════════
# ЦЕНТРАЛИЗОВАННОЕ УПРАВЛЕНИЕ NGINX
# ═══════════════════════════════════════════════
#
# /opt/nginx/ — единая точка для nginx. Все приложения (Remnawave,
# Beszel и др.) используют общий nginx-контейнер.
#
# Структура:
#   /opt/nginx/docker-compose.yml   — фиксированный compose
#   /opt/nginx/nginx.conf           — основной конфиг (полный или минимальный)
#   /opt/nginx/conf.d/              — блоки сторонних сервисов (beszel.conf и т.д.)
#   /opt/nginx/ssl/                 — самоподписанные сертификаты
#
# Сертификаты Let's Encrypt монтируются целиком: /etc/letsencrypt → /etc/letsencrypt
# Самоподписанные: /opt/nginx/ssl/ → /etc/nginx/ssl/
#
# В nginx.conf:  include /etc/nginx/conf.d/*.conf;
# — автоматически подхватывает блоки из conf.d/

DIR_NGINX="/opt/nginx/"

# ─── Создаёт /opt/nginx/ с docker-compose.yml если не существует ───
ensure_nginx() {
    if [ -f "${DIR_NGINX}docker-compose.yml" ]; then
        return 0
    fi
    mkdir -p "${DIR_NGINX}" "${DIR_NGINX}conf.d" "${DIR_NGINX}ssl"
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
    mkdir -p "${DIR_NGINX}conf.d"
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
}

# ─── Добавляет файл server-блока в conf.d ───
# Использование: nginx_add_block "beszel" "$block_content"
nginx_add_block() {
    local name="$1"
    local content="$2"
    mkdir -p "${DIR_NGINX}conf.d"
    echo "$content" > "${DIR_NGINX}conf.d/${name}.conf"
}

# ─── Удаляет файл server-блока из conf.d ───
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
    # Standalone-компоненты через conf.d
    local f
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
# Если остались только conf.d-блоки — заменяет nginx.conf на минимальный.
nginx_ensure_conf_for_remaining() {
    if ! is_panel_installed && ! is_node_installed; then
        # Remnawave удалён, но возможно остались conf.d-блоки
        local f has_blocks=false
        for f in "${DIR_NGINX}conf.d/"*.conf; do
            [ -f "$f" ] && { has_blocks=true; break; }
        done
        if $has_blocks; then
            nginx_generate_minimal_conf
            nginx_reload
        else
            nginx_teardown
        fi
    fi
}
