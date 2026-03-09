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
API_INSTANCES=1

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
    network_mode: host
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
COMPOSE_HEAD

    # Монтируем сертификаты для каждого домена
    for cert in "$panel_cert_domain" "$sub_cert_domain" "$node_cert_domain"; do
        cat >> /opt/remnawave/docker-compose.yml <<COMPOSE_CERT
      - /etc/letsencrypt/live/$cert/fullchain.pem:/etc/nginx/ssl/$cert/fullchain.pem:ro
      - /etc/letsencrypt/live/$cert/privkey.pem:/etc/nginx/ssl/$cert/privkey.pem:ro
COMPOSE_CERT
    done

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_TAIL'
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: sh -c 'rm -f /dev/shm/nginx.sock && exec nginx -g "daemon off;"'
    depends_on:
      - remnawave
      - remnawave-subscription-page
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    depends_on:
      remnawave:
        condition: service_healthy
    environment:
      - REMNAWAVE_PANEL_URL=http://remnawave:3000
      - APP_PORT=3010
      - REMNAWAVE_API_TOKEN
    ports:
      - '127.0.0.1:3010:3010'
    networks:
      - remnawave-network
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
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
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
COMPOSE_HEAD

    # Монтируем сертификаты для каждого домена
    for cert in "$panel_cert_domain" "$sub_cert_domain"; do
        cat >> /opt/remnawave/docker-compose.yml <<COMPOSE_CERT
      - /etc/letsencrypt/live/$cert/fullchain.pem:/etc/nginx/ssl/$cert/fullchain.pem:ro
      - /etc/letsencrypt/live/$cert/privkey.pem:/etc/nginx/ssl/$cert/privkey.pem:ro
COMPOSE_CERT
    done

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_TAIL'
    network_mode: host
    depends_on:
      - remnawave
      - remnawave-subscription-page
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    depends_on:
      remnawave:
        condition: service_healthy
    environment:
      - REMNAWAVE_PANEL_URL=http://remnawave:3000
      - APP_PORT=3010
      - REMNAWAVE_API_TOKEN
    ports:
      - '127.0.0.1:3010:3010'
    networks:
      - remnawave-network
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

COMPOSE_TAIL

    # Добавляем networks секцию в зависимости от существования сети
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

    cat > /opt/remnawave/nginx.conf <<EOL
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
}

upstream json {
    server 127.0.0.1:3010;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
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
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;

server {
    server_name $panel_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$panel_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    add_header Set-Cookie \$set_cookie_header;

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
    server_name $sub_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$sub_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    location / {
        limit_req zone=sub_limit burst=20 nodelay;
        limit_req_status 444;

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
        error_page 400 404 500 502 @redirect;
    }

    location @redirect {
        return 444;
    }
}

server {
    server_name $selfsteal_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$node_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";

    root /var/www/html;
    index index.html;

    # Заголовки безопасности
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;

    # Только GET и HEAD методы
    if (\$request_method !~ ^(GET|HEAD)\$) {
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
    server_name _;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    ssl_reject_handshake on;
    return 444;
}
EOL
}

# ─── Nginx: Только Панель ───
generate_nginx_conf_panel() {
    local panel_domain=$1
    local sub_domain=$2
    local panel_cert=$3
    local sub_cert=$4
    local cookie_name=$5
    local cookie_value=$6

    cat > /opt/remnawave/nginx.conf <<EOL
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
}

upstream json {
    server 127.0.0.1:3010;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
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
ssl_session_cache shared:MozSSL:10m;
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

server {
    server_name $sub_domain;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$sub_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    location / {
        limit_req zone=sub_limit burst=20 nodelay;
        limit_req_status 444;

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
        error_page 400 404 500 502 @redirect;
    }

    location @redirect {
        return 444;
    }
}

server {
    listen 443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}
EOL
}

# ─── Nginx: Только Нода ───
generate_nginx_conf_node() {
    local selfsteal_domain=$1
    local node_cert=$2
    local target_dir="${3:-/opt/remnawave}"

    # Удаляем если nginx.conf — директория (может быть создана Docker)
    [ -d "${target_dir}/nginx.conf" ] && rm -rf "${target_dir}/nginx.conf"

    cat > "${target_dir}/nginx.conf" <<EOL
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
ssl_session_cache shared:MozSSL:10m;
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
EOL
}
