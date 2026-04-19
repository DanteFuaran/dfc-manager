# ═══════════════════════════════════════════════
# ГЕНЕРАЦИЯ КОНФИГУРАЦИОННЫХ ФАЙЛОВ
# ═══════════════════════════════════════════════

# ─── Определение gateway и subnet существующей docker-сети ───
# Если remnawave-network уже существует (например от другого проекта),
# возвращает её gateway и subnet. Иначе — дефолтные значения 172.30.0.0/16.
get_remnawave_network_info() {
    local gateway subnet
    if docker network ls --format '{{.Name}}' | grep -qx "remnawave-network"; then
        gateway=$(docker network inspect remnawave-network --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
        subnet=$(docker network inspect remnawave-network --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
    fi
    echo "${gateway:-172.30.0.1} ${subnet:-172.30.0.0/16}"
}

# ─── Генерация .env файла ───
generate_env_file() {
    local panel_domain=$1
    local sub_domain=$2

    local jwt_auth_secret
    jwt_auth_secret=$(generate_secret)
    local jwt_api_secret
    jwt_api_secret=$(generate_secret)
    local webhook_secret
    webhook_secret=$(generate_webhook_secret)
    local metrics_user
    metrics_user=$(generate_username)
    local metrics_pass
    metrics_pass=$(generate_password)

    cat > /opt/remnawave/.env <<EOL
### APP ###
APP_PORT=3000
METRICS_PORT=3001

### API ###
# Possible values: max (start instances on all cores), number (start instances on number of cores), -1 (start instances on all cores - 1)
# !!! Do not set this value more than physical cores count in your machine !!!
# Review documentation: https://remna.st/docs/install/environment-variables#scaling-api
API_INSTANCES=$(nproc)

### DATABASE ###
# FORMAT: postgresql://{user}:{password}@{host}:{port}/{database}
DATABASE_URL="postgresql://postgres:postgres@remnawave-db:5432/postgres"

### REDIS ###
REDIS_HOST=remnawave-redis
REDIS_PORT=6379

### JWT ###
JWT_AUTH_SECRET=$jwt_auth_secret
JWT_API_TOKENS_SECRET=$jwt_api_secret

# Set the session idle timeout in the panel to avoid daily logins.
# Value in hours: 12–168
JWT_AUTH_LIFETIME=168

### TELEGRAM NOTIFICATIONS ###
IS_TELEGRAM_NOTIFICATIONS_ENABLED=false
TELEGRAM_BOT_TOKEN=change_me
TELEGRAM_NOTIFY_USERS_CHAT_ID=change_me
TELEGRAM_NOTIFY_NODES_CHAT_ID=change_me
TELEGRAM_NOTIFY_CRM_CHAT_ID=change_me

# Optional
# Only set if you want to use topics
TELEGRAM_NOTIFY_USERS_THREAD_ID=
TELEGRAM_NOTIFY_NODES_THREAD_ID=
TELEGRAM_NOTIFY_CRM_THREAD_ID=

### FRONT_END ###
# Used by CORS, you can leave it as * or place your domain there
FRONT_END_DOMAIN=$panel_domain

### SUBSCRIPTION PUBLIC DOMAIN ###
### DOMAIN, WITHOUT HTTP/HTTPS, DO NOT ADD / AT THE END ###
### Used in "profile-web-page-url" response header and in UI/API ###
### Review documentation: https://remna.st/docs/install/environment-variables#domains
SUB_PUBLIC_DOMAIN=$sub_domain

### If CUSTOM_SUB_PREFIX is set in @remnawave/subscription-page, append the same path to SUB_PUBLIC_DOMAIN. Example: SUB_PUBLIC_DOMAIN=sub-page.example.com/sub ###

### SWAGGER ###
SWAGGER_PATH=/docs
SCALAR_PATH=/scalar
IS_DOCS_ENABLED=false

### PROMETHEUS ###
### Metrics are available at /api/metrics
METRICS_USER=$metrics_user
METRICS_PASS=$metrics_pass

### Webhook configuration
### Enable webhook notifications (true/false, defaults to false if not set or empty)
WEBHOOK_ENABLED=false
### Webhook URL to send notifications to (can specify multiple URLs separated by commas if needed)
### Only http:// or https:// are allowed.
WEBHOOK_URL=https://your-webhook-url.com/endpoint
### This secret is used to sign the webhook payload, must be exact 64 characters. Only a-z, 0-9, A-Z are allowed.
WEBHOOK_SECRET_HEADER=$webhook_secret

### Bandwidth usage reached notifications
BANDWIDTH_USAGE_NOTIFICATIONS_ENABLED=false
# Only in ASC order (example: [60, 80]), must be valid array of integer(min: 25, max: 95) numbers. No more than 5 values.
BANDWIDTH_USAGE_NOTIFICATIONS_THRESHOLD=[60, 80]

### CLOUDFLARE ###
# USED ONLY FOR docker-compose-prod-with-cf.yml
# NOT USED BY THE APP ITSELF
CLOUDFLARE_TOKEN=ey...

### Database ###
### For Postgres Docker container ###
# NOT USED BY THE APP ITSELF
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres

### SUBSCRIPTION PAGE ###
REMNAWAVE_API_TOKEN=
EOL
    chmod 600 /opt/remnawave/.env 2>/dev/null
}

# ─── Docker-Compose: Панель + Нода (Full) ───
generate_docker_compose_full() {
    local panel_cert_domain=$1
    local sub_cert_domain=$2
    local node_cert_domain=$3

    # Проверяем, существует ли сеть remnawave-network
    local network_exists=false
    if docker network ls --format '{{.Name}}' | grep -qx "remnawave-network"; then
        network_exists=true
    fi

    # ─── Панель (/opt/remnawave/docker-compose.yml) ───
    mkdir -p "/opt/remnawave"
    cat > /opt/remnawave/docker-compose.yml <<'COMPOSE_PANEL'
services:
  remnawave-db:
    image: postgres:18.1
    container_name: 'remnawave-db'
    hostname: remnawave-db
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    ports:
      - '127.0.0.1:6767:5432'
    volumes:
      - remnawave-db-data:/var/lib/postgresql
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave:
    image: remnawave/backend:2
    container_name: remnawave
    hostname: remnawave
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    ports:
      - '127.0.0.1:3000:${APP_PORT:-3000}'
      - '127.0.0.1:3001:${METRICS_PORT:-3001}'
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${METRICS_PORT:-3001}/health']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-redis:
    image: valkey/valkey:9.0.0-alpine
    container_name: remnawave-redis
    hostname: remnawave-redis
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    networks:
      - remnawave-network
    command: >
      valkey-server
      --save ""
      --appendonly no
      --maxmemory 128mb
      --maxmemory-policy noeviction
      --loglevel warning
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

COMPOSE_PANEL

    if [ "$network_exists" = true ]; then
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_EXT'
networks:
  remnawave-network:
    name: remnawave-network
    external: true

COMPOSE_NETWORK_EXT
    else
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_NEW'
networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/16
    external: false

COMPOSE_NETWORK_NEW
    fi

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_VOLUMES'
volumes:
  remnawave-db-data:
    driver: local
    external: false
    name: remnawave-db-data
COMPOSE_VOLUMES

    # ─── Нода (/opt/remnanode/docker-compose.yml) ───
    mkdir -p "/opt/remnanode"
    cat > /opt/remnanode/docker-compose.yml <<'NODE_COMPOSE'
services:
  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    network_mode: host
    environment:
      - NODE_PORT=2222
      - SECRET_KEY="PUBLIC KEY FROM REMNAWAVE-PANEL"
    volumes:
      - /dev/shm:/dev/shm:rw
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 2222']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 15s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
NODE_COMPOSE

    # ─── Страница подписки (/opt/subscribe-page/docker-compose.yml) ───
    mkdir -p "/opt/subscribe-page"
    cat > /opt/subscribe-page/docker-compose.yml <<'SUBPAGE_COMPOSE'
services:
  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - /opt/remnawave/.env
    environment:
      - REMNAWAVE_PANEL_URL=http://remnawave:3000
      - APP_PORT=3010
    ports:
      - '127.0.0.1:3010:3010'
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 3010']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

networks:
  remnawave-network:
    name: remnawave-network
    external: true
SUBPAGE_COMPOSE

    ensure_nginx
}

# ─── Docker-Compose: Только Панель ───
generate_docker_compose_panel() {
    local panel_cert_domain=$1
    local sub_cert_domain=$2

    # Проверяем, существует ли сеть remnawave-network
    local network_exists=false
    if docker network ls | grep -q "remnawave-network"; then
        network_exists=true
    fi

    # ─── Панель (/opt/remnawave/docker-compose.yml) ───
    mkdir -p "/opt/remnawave"
    cat > /opt/remnawave/docker-compose.yml <<'COMPOSE_PANEL'
services:
  remnawave-db:
    image: postgres:18.1
    container_name: 'remnawave-db'
    hostname: remnawave-db
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    ports:
      - '127.0.0.1:6767:5432'
    volumes:
      - remnawave-db-data:/var/lib/postgresql
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave:
    image: remnawave/backend:2
    container_name: remnawave
    hostname: remnawave
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    ports:
      - '127.0.0.1:3000:${APP_PORT:-3000}'
      - '127.0.0.1:3001:${METRICS_PORT:-3001}'
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${METRICS_PORT:-3001}/health']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-redis:
    image: valkey/valkey:9.0.0-alpine
    container_name: remnawave-redis
    hostname: remnawave-redis
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    networks:
      - remnawave-network
    command: >
      valkey-server
      --save ""
      --appendonly no
      --maxmemory 128mb
      --maxmemory-policy noeviction
      --loglevel warning
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

COMPOSE_PANEL

    if [ "$network_exists" = true ]; then
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_EXT'
networks:
  remnawave-network:
    name: remnawave-network
    external: true

COMPOSE_NETWORK_EXT
    else
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_NEW'
networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: false

COMPOSE_NETWORK_NEW
    fi

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_VOLUMES'
volumes:
  remnawave-db-data:
    driver: local
    external: false
    name: remnawave-db-data
COMPOSE_VOLUMES

    # ─── Страница подписки (/opt/subscribe-page/docker-compose.yml) ───
    mkdir -p "/opt/subscribe-page"
    cat > /opt/subscribe-page/docker-compose.yml <<'SUBPAGE_COMPOSE'
services:
  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - /opt/remnawave/.env
    environment:
      - REMNAWAVE_PANEL_URL=http://remnawave:3000
      - APP_PORT=3010
    ports:
      - '127.0.0.1:3010:3010'
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 3010']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

networks:
  remnawave-network:
    name: remnawave-network
    external: true
SUBPAGE_COMPOSE

    ensure_nginx
}

# ─── Nginx: Главный конфиг — объединённый (заменяет /etc/nginx/nginx.conf) ───
# Общая http-обёртка, используемая всеми вариантами nginx.conf.
# Вызывается из generate_nginx_conf_full / generate_nginx_conf_panel / generate_nginx_conf_node.
# Сохраняет внешние server-блоки (Beszel и др.) перед перезаписью файла.
_nginx_http_header() {
    _nginx_extract_external_blocks
    cat > "${DIR_NGINX}nginx.conf" <<'NGINX_HTTP_HEAD'
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

    map_hash_bucket_size 128;

    access_log off;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;

    keepalive_timeout  65;

    # Gzip для JSON-подписок и статики
    gzip on;
    gzip_types application/json text/plain text/css application/javascript;
    gzip_min_length 256;
    gzip_vary on;

    # Лимит body (защита от DoS)
    client_max_body_size 1m;

NGINX_HTTP_HEAD
    # Восстанавливаем MTProto stream-блок (идёт перед http {}) если был в предыдущем конфиге
    _nginx_restore_stream_block
}

# ─── Nginx: Панель + Нода (Full) ───
generate_nginx_conf_full() {
    local panel_domain=$1
    local sub_domain=$2
    local selfsteal_domain=$3
    local panel_cert=$4
    local sub_cert=$5
    local node_cert=$6
    local cookie_name=$7
    local cookie_value=$8

    # http-обёртка
    _nginx_http_header

    cat >> "${DIR_NGINX}nginx.conf" <<EOL
server_names_hash_bucket_size 64;

# Не логируем частые Telegram webhook-запросы
map \$request_uri \$loggable {
    ~*/api/v1/telegram 0;
    default 1;
}

# Rate limiting для защиты от сканирования subscription page
limit_req_zone \$binary_remote_addr zone=sub_limit:10m rate=10r/s;

upstream remnawave {
    server 127.0.0.1:3000;
    keepalive 32;
}

upstream json {
    server 127.0.0.1:3010;
    keepalive 16;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      "";
}

map \$http_cookie \$auth_cookie {
    default 0;
    "~*${cookie_name}=${cookie_value}" 1;
}

map \$arg_${cookie_name} \$auth_query {
    default 0;
    "${cookie_value}" 1;
}

map "\$auth_cookie\$auth_query" \$authorized {
    "~1" 1;
    default 0;
}

map \$arg_${cookie_name} \$set_cookie_header {
    "${cookie_value}" "${cookie_name}=${cookie_value}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
    default "";
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:50m;
ssl_session_tickets off;

real_ip_header   proxy_protocol;
set_real_ip_from unix:;

server {
    server_name $panel_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$panel_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    add_header Set-Cookie \$set_cookie_header;

    location /api/ {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        error_page 418 = @unauthorized;
        recursive_error_pages on;
        if (\$authorized = 0) {
            return 418;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location @unauthorized {
        root /var/www/html;
        index index.html;
    }
}

# BEGIN_SUB_BLOCK
server {
    server_name $sub_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$sub_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    error_page 502 = @redirect;

    location / {
        limit_req zone=sub_limit burst=20 nodelay;
        limit_req_status 444;

        keepalive_timeout 0;

        proxy_http_version 1.1;
        proxy_pass http://json;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_intercept_errors on;
        error_page 400 404 500 @redirect;
    }

    location @redirect {
        return 444;
    }
}
# END_SUB_BLOCK

server {
    server_name $selfsteal_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$node_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";

    root /var/www/html;
    index index.html;

    error_page 400 = @drop;

    # Заголовки безопасности
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;

    # Только GET и HEAD методы
    if (\$request_method !~ ^(GET|HEAD)\$) {
        return 444;
    }

    location @drop {
        return 444;
    }

    # Блокировка скрытых файлов (.env, .git и др.)
    location ~ /\\. {
        return 444;
    }

    # Блокировка типичных целей сканирования
    location ~* \\.(php|asp|aspx|jsp|cgi)\$ {
        return 444;
    }
    location ~* ^/(wp-|wordpress|wp-admin|wp-content|wp-includes|wp-json|xmlrpc) {
        return 444;
    }
    location ~* ^/(cgi-bin|_debugbar|debug|telescope|actuator|console|admin|phpmyadmin|pma|myadmin) {
        return 444;
    }
    location ~* ^/(vendor|node_modules|storage|backup|config|credentials|docker) {
        return 444;
    }

    # robots.txt — запрет индексации
    location = /robots.txt {
        default_type text/plain;
        return 200 "User-agent: *\\nDisallow: /\\n";
    }

    # favicon — подавление 404
    location = /favicon.ico {
        access_log off;
        log_not_found off;
        return 204;
    }
    location = /favicon.png {
        access_log off;
        log_not_found off;
        return 204;
    }

    # Главная страница (selfsteal) — без rate limit (панель делает health-check)
    location = / {
        try_files /index.html =444;
    }

    # Статика
    location ~* ^/(css|js|img|images|fonts|static)/ {
        try_files \$uri =444;
        expires 1h;
        add_header Cache-Control "public, no-transform";
    }

    # Всё остальное — разрыв соединения
    location / {
        return 444;
    }
}

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    listen 443 ssl default_server;
    server_name _;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    ssl_reject_handshake on;
    return 444;
}
} # ─── end http ───
EOL
    nginx_restore_server_blocks
}

# ─── Nginx: Только Панель ───
generate_nginx_conf_panel() {
    local panel_domain=$1
    local sub_domain=$2
    local panel_cert=$3
    local sub_cert=$4
    local cookie_name=$5
    local cookie_value=$6

    # http-обёртка
    _nginx_http_header

    cat >> "${DIR_NGINX}nginx.conf" <<EOL
server_names_hash_bucket_size 64;

# Не логируем частые Telegram webhook-запросы
map \$request_uri \$loggable {
    ~*/api/v1/telegram 0;
    default 1;
}

# Rate limiting для защиты от сканирования subscription page
limit_req_zone \$binary_remote_addr zone=sub_limit:10m rate=10r/s;

upstream remnawave {
    server 127.0.0.1:3000;
    keepalive 32;
}

upstream json {
    server 127.0.0.1:3010;
    keepalive 16;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      "";
}

map \$http_cookie \$auth_cookie {
    default 0;
    "~*${cookie_name}=${cookie_value}" 1;
}

map \$arg_${cookie_name} \$auth_query {
    default 0;
    "${cookie_value}" 1;
}

map \$http_authorization \$is_bearer_auth {
    default 0;
    "~*^Bearer \S+" 1;
}

map "\$auth_cookie\$auth_query\$is_bearer_auth" \$authorized {
    "~1" 1;
    default 0;
}

map \$arg_${cookie_name} \$set_cookie_header {
    "${cookie_value}" "${cookie_name}=${cookie_value}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
    default "";
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:50m;
ssl_session_tickets off;

server {
    server_name $panel_domain;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$panel_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    add_header Set-Cookie \$set_cookie_header;

    location /api/ {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        if (\$authorized = 0) {
            return 444;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# BEGIN_SUB_BLOCK
server {
    server_name $sub_domain;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$sub_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    error_page 502 = @redirect;

    location / {
        limit_req zone=sub_limit burst=20 nodelay;
        limit_req_status 444;

        keepalive_timeout 0;

        proxy_http_version 1.1;
        proxy_pass http://json;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_intercept_errors on;
        error_page 400 404 500 @redirect;
    }

    location @redirect {
        return 444;
    }
}
# END_SUB_BLOCK

# ─── Default Direct
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}
} # ─── end http ───
EOL
    nginx_restore_server_blocks
}

# ─── Nginx: Только Нода ───
generate_nginx_conf_node() {
    local selfsteal_domain=$1
    local node_cert=$2
    local target_dir="${3:-/opt/remnawave}"

    # Удаляем если nginx.conf — директория (может быть создана Docker)
    [ -d "${DIR_NGINX}/nginx.conf" ] && rm -rf "${DIR_NGINX}/nginx.conf"

    # http-обёртка
    _nginx_http_header

    cat >> "${DIR_NGINX}nginx.conf" <<EOL
server_names_hash_bucket_size 64;

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}

# Фильтрация логов: скрываем запросы сканеров (400, 404, 444) для чистоты логов
map \$status \$loggable {
    ~^(400|404|444)\$ 0;
    default            1;
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:50m;
ssl_session_tickets off;

server {
    server_name $selfsteal_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$node_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";

    real_ip_header   proxy_protocol;
    set_real_ip_from unix:;

    root /var/www/html;
    index index.html;

    # Логирование только успешных запросов (сканеры не засоряют логи)
    access_log /dev/stdout combined if=\$loggable;

    error_page 400 = @drop;

    # Заголовки безопасности
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;

    # Только GET и HEAD методы (selfsteal — статическая страница)
    if (\$request_method !~ ^(GET|HEAD)\$) {
        return 444;
    }

    location @drop {
        return 444;
    }

    # Блокировка сканеров уязвимостей: скрытые файлы (.env, .git, .aws и др.)
    location ~ /\\. {
        return 444;
    }

    # Блокировка PHP-файлов, WordPress, cgi-bin и прочих типичных целей сканирования
    location ~* \\.(php|asp|aspx|jsp|cgi)\$ {
        return 444;
    }
    location ~* ^/(wp-|wordpress|wp-admin|wp-content|wp-includes|wp-json|xmlrpc) {
        return 444;
    }
    location ~* ^/(cgi-bin|_debugbar|debug|telescope|actuator|console|admin|phpmyadmin|pma|myadmin) {
        return 444;
    }
    location ~* ^/(vendor|node_modules|storage|backup|config|credentials|docker) {
        return 444;
    }

    # robots.txt — запрет индексации (отдаём без обращения к файловой системе)
    location = /robots.txt {
        default_type text/plain;
        return 200 "User-agent: *\\nDisallow: /\\n";
    }

    # favicon — пустой ответ (подавляет 404 в логах браузеров)
    location = /favicon.ico {
        access_log off;
        log_not_found off;
        return 204;
    }
    location = /favicon.png {
        access_log off;
        log_not_found off;
        return 204;
    }

    # Главная страница (selfsteal)
    location = / {
        try_files /index.html =444;
    }

    # Статика (CSS/JS/картинки) только из разрешённых директорий
    location ~* ^/(css|js|img|images|fonts|static)/ {
        try_files \$uri =444;
        expires 1h;
        add_header Cache-Control "public, no-transform";
    }

    # Всё остальное — разрыв соединения
    location / {
        return 444;
    }
}

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    ssl_reject_handshake on;
    return 444;
}
} # ─── end http ───
EOL
    nginx_restore_server_blocks
}

# ─── Docker-Compose: Только Панель (без страницы подписки) ───
generate_docker_compose_panel_only() {
    local panel_cert_domain=$1

    local network_exists=false
    if docker network ls --format '{{.Name}}' | grep -qx "remnawave-network"; then
        network_exists=true
    fi

    cat > /opt/remnawave/docker-compose.yml <<'COMPOSE_HEAD'
services:
  remnawave-db:
    image: postgres:18.1
    container_name: 'remnawave-db'
    hostname: remnawave-db
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    ports:
      - '127.0.0.1:6767:5432'
    volumes:
      - remnawave-db-data:/var/lib/postgresql
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave:
    image: remnawave/backend:2
    container_name: remnawave
    hostname: remnawave
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    ports:
      - '127.0.0.1:3000:${APP_PORT:-3000}'
      - '127.0.0.1:3001:${METRICS_PORT:-3001}'
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${METRICS_PORT:-3001}/health']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-redis:
    image: valkey/valkey:9.0.0-alpine
    container_name: remnawave-redis
    hostname: remnawave-redis
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    networks:
      - remnawave-network
    command: >
      valkey-server
      --save ""
      --appendonly no
      --maxmemory 128mb
      --maxmemory-policy noeviction
      --loglevel warning
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-nginx:
    image: nginx:1.28
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
COMPOSE_HEAD

    cat >> /opt/remnawave/docker-compose.yml <<COMPOSE_CERT
      - /etc/letsencrypt/live/$panel_cert_domain/fullchain.pem:/etc/nginx/ssl/$panel_cert_domain/fullchain.pem:ro
      - /etc/letsencrypt/live/$panel_cert_domain/privkey.pem:/etc/nginx/ssl/$panel_cert_domain/privkey.pem:ro
COMPOSE_CERT

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_TAIL'
    network_mode: host
    healthcheck:
      test: ['CMD-SHELL', 'kill -0 $(cat /run/nginx.pid) 2>/dev/null']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    depends_on:
      - remnawave
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

COMPOSE_TAIL

    if [ "$network_exists" = true ]; then
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_EXTERNAL'
networks:
  remnawave-network:
    name: remnawave-network
    external: true

COMPOSE_NETWORK_EXTERNAL
    else
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_NEW'
networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: false

COMPOSE_NETWORK_NEW
    fi

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_VOLUMES'

volumes:
  remnawave-db-data:
    driver: local
    external: false
    name: remnawave-db-data
COMPOSE_VOLUMES

    _strip_nginx_from_compose "/opt/remnawave/docker-compose.yml"
}

# ─── Nginx: Только Панель (без страницы подписки) ───
generate_nginx_conf_panel_only() {
    local panel_domain=$1
    local panel_cert=$2
    local cookie_name=$3
    local cookie_value=$4

    # http-обёртка
    _nginx_http_header

    cat >> "${DIR_NGINX}nginx.conf" <<EOL
server_names_hash_bucket_size 64;

# Не логируем частые Telegram webhook-запросы
map \$request_uri \$loggable {
    ~*/api/v1/telegram 0;
    default 1;
}

upstream remnawave {
    server 127.0.0.1:3000;
    keepalive 32;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      "";
}

map \$http_cookie \$auth_cookie {
    default 0;
    "~*${cookie_name}=${cookie_value}" 1;
}

map \$arg_${cookie_name} \$auth_query {
    default 0;
    "${cookie_value}" 1;
}

map \$http_authorization \$is_bearer_auth {
    default 0;
    "~*^Bearer \S+" 1;
}

map "\$auth_cookie\$auth_query\$is_bearer_auth" \$authorized {
    "~1" 1;
    default 0;
}

map \$arg_${cookie_name} \$set_cookie_header {
    "${cookie_value}" "${cookie_name}=${cookie_value}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
    default "";
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:50m;
ssl_session_tickets off;

server {
    server_name $panel_domain;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$panel_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    add_header Set-Cookie \$set_cookie_header;

    location /api/ {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        if (\$authorized = 0) {
            return 444;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# ─── Default Direct
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}
} # ─── end http ───
EOL
    nginx_restore_server_blocks
}

# ─── Docker-Compose: Панель + Нода (без страницы подписки) ───
generate_docker_compose_panel_with_node() {
    local panel_cert_domain=$1
    local node_cert_domain=$2

    local network_exists=false
    if docker network ls --format '{{.Name}}' | grep -qx "remnawave-network"; then
        network_exists=true
    fi

    # ─── Панель (/opt/remnawave/docker-compose.yml) ───
    mkdir -p "/opt/remnawave"
    cat > /opt/remnawave/docker-compose.yml <<'COMPOSE_PANEL'
services:
  remnawave-db:
    image: postgres:18.1
    container_name: 'remnawave-db'
    hostname: remnawave-db
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    ports:
      - '127.0.0.1:6767:5432'
    volumes:
      - remnawave-db-data:/var/lib/postgresql
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave:
    image: remnawave/backend:2
    container_name: remnawave
    hostname: remnawave
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    ports:
      - '127.0.0.1:3000:${APP_PORT:-3000}'
      - '127.0.0.1:3001:${METRICS_PORT:-3001}'
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${METRICS_PORT:-3001}/health']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-redis:
    image: valkey/valkey:9.0.0-alpine
    container_name: remnawave-redis
    hostname: remnawave-redis
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    networks:
      - remnawave-network
    command: >
      valkey-server
      --save ""
      --appendonly no
      --maxmemory 128mb
      --maxmemory-policy noeviction
      --loglevel warning
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

COMPOSE_PANEL

    if [ "$network_exists" = true ]; then
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_EXT'
networks:
  remnawave-network:
    name: remnawave-network
    external: true

COMPOSE_NETWORK_EXT
    else
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_NEW'
networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/16
    external: false

COMPOSE_NETWORK_NEW
    fi

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_VOLUMES'
volumes:
  remnawave-db-data:
    driver: local
    external: false
    name: remnawave-db-data
COMPOSE_VOLUMES

    # ─── Нода (/opt/remnanode/docker-compose.yml) ───
    mkdir -p "/opt/remnanode"
    cat > /opt/remnanode/docker-compose.yml <<'NODE_COMPOSE'
services:
  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    network_mode: host
    environment:
      - NODE_PORT=2222
      - SECRET_KEY="PUBLIC KEY FROM REMNAWAVE-PANEL"
    volumes:
      - /dev/shm:/dev/shm:rw
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 2222']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 15s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
NODE_COMPOSE

    ensure_nginx
}

# ─── Nginx: Панель + Нода (без страницы подписки) ───
generate_nginx_conf_panel_with_node() {
    local panel_domain=$1
    local selfsteal_domain=$2
    local panel_cert=$3
    local node_cert=$4
    local cookie_name=$5
    local cookie_value=$6

    _nginx_http_header

    cat >> "${DIR_NGINX}nginx.conf" <<EOL
server_names_hash_bucket_size 64;

# Не логируем частые Telegram webhook-запросы
map \$request_uri \$loggable {
    ~*/api/v1/telegram 0;
    default 1;
}

upstream remnawave {
    server 127.0.0.1:3000;
    keepalive 32;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      "";
}

map \$http_cookie \$auth_cookie {
    default 0;
    "~*${cookie_name}=${cookie_value}" 1;
}

map \$arg_${cookie_name} \$auth_query {
    default 0;
    "${cookie_value}" 1;
}

map \$http_authorization \$is_bearer_auth {
    default 0;
    "~*^Bearer \S+" 1;
}

map "\$auth_cookie\$auth_query\$is_bearer_auth" \$authorized {
    "~1" 1;
    default 0;
}

map \$arg_${cookie_name} \$set_cookie_header {
    "${cookie_value}" "${cookie_name}=${cookie_value}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
    default "";
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:50m;
ssl_session_tickets off;

real_ip_header   proxy_protocol;
set_real_ip_from unix:;

server {
    server_name $panel_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$panel_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    add_header Set-Cookie \$set_cookie_header;

    location /api/ {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        error_page 418 = @unauthorized;
        recursive_error_pages on;
        if (\$authorized = 0) {
            return 418;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location @unauthorized {
        root /var/www/html;
        index index.html;
    }
}

server {
    server_name $selfsteal_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$node_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";

    root /var/www/html;
    index index.html;

    error_page 400 = @drop;

    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;

    if (\$request_method !~ ^(GET|HEAD)\$) {
        return 444;
    }

    location @drop {
        return 444;
    }

    location ~ /\\. {
        return 444;
    }

    location ~* \\.(php|asp|aspx|jsp|cgi)\$ {
        return 444;
    }
    location ~* ^/(wp-|wordpress|wp-admin|wp-content|wp-includes|wp-json|xmlrpc) {
        return 444;
    }
    location ~* ^/(cgi-bin|_debugbar|debug|telescope|actuator|console|admin|phpmyadmin|pma|myadmin) {
        return 444;
    }
    location ~* ^/(vendor|node_modules|storage|backup|config|credentials|docker) {
        return 444;
    }

    location = /robots.txt {
        default_type text/plain;
        return 200 "User-agent: *\\nDisallow: /\\n";
    }

    location = /favicon.ico {
        access_log off;
        log_not_found off;
        return 204;
    }
    location = /favicon.png {
        access_log off;
        log_not_found off;
        return 204;
    }

    location = / {
        try_files /index.html =444;
    }

    location ~* ^/(css|js|img|images|fonts|static)/ {
        try_files \$uri =444;
        expires 1h;
        add_header Cache-Control "public, no-transform";
    }

    location / {
        return 444;
    }
}

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    listen 443 ssl default_server;
    server_name _;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    ssl_reject_handshake on;
    return 444;
}
} # ─── end http ───
EOL
    nginx_restore_server_blocks
}

# ─── Docker-Compose: Только Страница подписки (standalone) ───
generate_docker_compose_subpage() {
    local sub_cert_domain=$1
    local panel_url=$2
    local api_token=$3
    local target_dir=$4

    cat > "${target_dir}/docker-compose.yml" <<EOL
services:
  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - REMNAWAVE_PANEL_URL=${panel_url}
      - APP_PORT=3010
      - REMNAWAVE_API_TOKEN=${api_token}
    ports:
      - '127.0.0.1:3010:3010'
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 3010']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-nginx:
    image: nginx:1.28
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    network_mode: host
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt/live/${sub_cert_domain}/fullchain.pem:/etc/nginx/ssl/${sub_cert_domain}/fullchain.pem:ro
      - /etc/letsencrypt/live/${sub_cert_domain}/privkey.pem:/etc/nginx/ssl/${sub_cert_domain}/privkey.pem:ro
    healthcheck:
      test: ['CMD-SHELL', 'kill -0 \$(cat /run/nginx.pid) 2>/dev/null']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    depends_on:
      - remnawave-subscription-page
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL

    ensure_nginx
    _strip_nginx_from_compose "${target_dir}/docker-compose.yml"
}

# ─── Nginx: Только Страница подписки (standalone) ───
generate_nginx_conf_subpage() {
    local sub_domain=$1
    local sub_cert=$2
    local target_dir=$3

    _nginx_http_header

    cat >> "${DIR_NGINX}nginx.conf" <<EOL
server_names_hash_bucket_size 64;

limit_req_zone \$binary_remote_addr zone=sub_limit:10m rate=10r/s;

upstream json {
    server 127.0.0.1:3010;
    keepalive 16;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}

map \$status \$loggable {
    ~^(400|404|444)\$ 0;
    default            1;
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:50m;
ssl_session_tickets off;

server {
    server_name $sub_domain;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$sub_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    error_page 502 = @redirect;

    location / {
        limit_req zone=sub_limit burst=20 nodelay;
        limit_req_status 444;

        keepalive_timeout 0;

        proxy_http_version 1.1;
        proxy_pass http://json;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_intercept_errors on;
        error_page 400 404 500 @redirect;
    }

    location @redirect {
        return 444;
    }
}

# ─── Default Direct
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}
} # ─── end http ───
EOL
    nginx_restore_server_blocks
}

# ─── Nginx: Нода + Страница подписки (unix socket) ───
generate_nginx_conf_node_with_subpage() {
    local selfsteal_domain=$1
    local node_cert=$2
    local sub_domain=$3
    local sub_cert=$4
    local target_dir="${5:-/opt/remnanode}"

    [ -d "${DIR_NGINX}/nginx.conf" ] && rm -rf "${DIR_NGINX}/nginx.conf"

    _nginx_http_header

    cat >> "${DIR_NGINX}nginx.conf" <<EOL
server_names_hash_bucket_size 64;

limit_req_zone \$binary_remote_addr zone=sub_limit:10m rate=10r/s;

upstream json {
    server 127.0.0.1:3010;
    keepalive 16;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}

map \$status \$loggable {
    ~^(400|404|444)\$ 0;
    default            1;
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:50m;
ssl_session_tickets off;

server {
    server_name $selfsteal_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$node_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";

    real_ip_header   proxy_protocol;
    set_real_ip_from unix:;

    root /var/www/html;
    index index.html;

    access_log /dev/stdout combined if=\$loggable;

    error_page 400 = @drop;

    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;

    if (\$request_method !~ ^(GET|HEAD)\$) {
        return 444;
    }

    location @drop {
        return 444;
    }

    location ~ /\\. {
        return 444;
    }

    location ~* \\.(php|asp|aspx|jsp|cgi)\$ {
        return 444;
    }
    location ~* ^/(wp-|wordpress|wp-admin|wp-content|wp-includes|wp-json|xmlrpc) {
        return 444;
    }
    location ~* ^/(cgi-bin|_debugbar|debug|telescope|actuator|console|admin|phpmyadmin|pma|myadmin) {
        return 444;
    }
    location ~* ^/(vendor|node_modules|storage|backup|config|credentials|docker) {
        return 444;
    }

    location = /robots.txt {
        default_type text/plain;
        return 200 "User-agent: *\\nDisallow: /\\n";
    }

    location = /favicon.ico {
        access_log off;
        log_not_found off;
        return 204;
    }
    location = /favicon.png {
        access_log off;
        log_not_found off;
        return 204;
    }

    location = / {
        try_files /index.html =444;
    }

    location ~* ^/(css|js|img|images|fonts|static)/ {
        try_files \$uri =444;
        expires 1h;
        add_header Cache-Control "public, no-transform";
    }

    location / {
        return 444;
    }
}

# BEGIN_SUB_BLOCK
server {
    server_name $sub_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$sub_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";

    real_ip_header   proxy_protocol;
    set_real_ip_from unix:;

    access_log /dev/stdout combined if=\$loggable;

    error_page 502 = @redirect;

    location / {
        limit_req zone=sub_limit burst=20 nodelay;
        limit_req_status 444;

        keepalive_timeout 0;

        proxy_http_version 1.1;
        proxy_pass http://json;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$proxy_protocol_addr;
        proxy_set_header X-Forwarded-For \$proxy_protocol_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_intercept_errors on;
        error_page 400 404 500 @redirect;
    }

    location @redirect {
        return 444;
    }
}
# END_SUB_BLOCK

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    ssl_reject_handshake on;
    return 444;
}
} # ─── end http ───
EOL
    nginx_restore_server_blocks
}

# ─── Docker-Compose: Нода + Страница подписки (один сервер, новая установка) ───
generate_docker_compose_node_with_subpage() {
    local node_cert_domain=$1
    local sub_cert_domain=$2
    local panel_url=$3
    local api_token=$4
    local certificate=$5
    local target_dir="${6:-/opt/remnanode}"

    # ─── Нода (/opt/remnanode/docker-compose.yml) ───
    mkdir -p "$target_dir"
    cat > "${target_dir}/docker-compose.yml" <<EOL
services:
  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    network_mode: host
    environment:
      - NODE_PORT=2222
      - SECRET_KEY=$(echo -e "$certificate")
    volumes:
      - /dev/shm:/dev/shm:rw
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 2222']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 15s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL

    # ─── Страница подписки (/opt/subscribe-page/docker-compose.yml) ───
    mkdir -p "/opt/subscribe-page"
    cat > /opt/subscribe-page/docker-compose.yml <<EOL
services:
  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - REMNAWAVE_PANEL_URL=${panel_url}
      - APP_PORT=3010
      - REMNAWAVE_API_TOKEN=${api_token}
    ports:
      - '127.0.0.1:3010:3010'
    healthcheck:
      test: ['CMD-SHELL', 'nc -z 127.0.0.1 3010']
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL

    ensure_nginx
}

# ═══════════════════════════════════════════════

