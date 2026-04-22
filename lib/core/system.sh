# ═══════════════════════════════════════════════
# ПРОВЕРКИ СИСТЕМЫ
# ═══════════════════════════════════════════════

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "Скрипт нужно запускать с правами root"
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian)
                if [[ "$VERSION_ID" != "11" && "$VERSION_ID" != "12" ]]; then
                    print_error "Поддержка только Debian 11/12 и Ubuntu 22.04/24.04"
                    exit 1
                fi
                ;;
            ubuntu)
                if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
                    print_error "Поддержка только Debian 11/12 и Ubuntu 22.04/24.04"
                    exit 1
                fi
                ;;
            *)
                print_error "Поддержка только Debian 11/12 и Ubuntu 22.04/24.04"
                exit 1
                ;;
        esac
    else
        print_error "Не удалось определить ОС"
        exit 1
    fi
}

# ═══════════════════════════════════════════════
# УСТАНОВКА ПАКЕТОВ
# ═══════════════════════════════════════════════

install_packages() {
    (
        export DEBIAN_FRONTEND=noninteractive
        # Автоответ на вопросы dpkg: сохранить текущий конфиг пользователя
        local DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

        # Обновление и установка пакетов
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq $DPKG_OPTS ca-certificates curl jq ufw wget gnupg unzip nano dialog git \
            certbot python3-certbot-dns-cloudflare unattended-upgrades locales dnsutils \
            coreutils grep gawk logrotate cron bash-completion >/dev/null 2>&1

        systemctl start cron 2>/dev/null || true
        systemctl enable cron 2>/dev/null || true

        # Docker
        if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
            dfc_install_docker_engine_official || true
        fi
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true

        # ─── Оптимизация сети и ядра ───
        # Удаляем старые записи чтобы не дублировать
        sed -i '/^net\.core\.default_qdisc/d;
                /^net\.ipv4\.tcp_congestion_control/d;
                /^net\.core\.rmem_max/d;
                /^net\.core\.wmem_max/d;
                /^net\.core\.rmem_default/d;
                /^net\.core\.wmem_default/d;
                /^net\.ipv4\.tcp_rmem/d;
                /^net\.ipv4\.tcp_wmem/d;
                /^net\.ipv4\.tcp_slow_start_after_idle/d;
                /^net\.ipv4\.tcp_mtu_probing/d;
                /^net\.ipv4\.tcp_fastopen/d;
                /^net\.ipv4\.tcp_notsent_lowat/d;
                /^net\.core\.netdev_max_backlog/d;
                /^net\.core\.somaxconn/d;
                /^net\.ipv4\.tcp_max_syn_backlog/d;
                /^vm\.overcommit_memory/d' /etc/sysctl.conf 2>/dev/null

        cat >> /etc/sysctl.conf <<'SYSCTL'

# ─── DFC: BBR + TCP оптимизация ───
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Буферы сокетов — без них BBR не может использовать доступную полосу
# rmem_max/wmem_max — потолок (16MB), ядро авто-тюнит внутри диапазона
# rmem_default/wmem_default — оставляем 212992 (ядро поднимает по необходимости)
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 262144 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Не сбрасывать cwnd после простоя — критично для VPN
net.ipv4.tcp_slow_start_after_idle=0

# MTU probing — предотвращает blackhole на путях с нестандартным MTU
net.ipv4.tcp_mtu_probing=1

# TCP Fast Open для входящих и исходящих соединений
net.ipv4.tcp_fastopen=3

# Снижение latency для интерактивного трафика
net.ipv4.tcp_notsent_lowat=131072

# Обработка burst-нагрузок
net.core.netdev_max_backlog=4096
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096

# Redis/Valkey — предотвращает сбои фоновых сохранений
vm.overcommit_memory=1
SYSCTL
        sysctl -p >/dev/null 2>&1

        # UFW
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1
        # Открываем порт SSH (определяем из sshd_config, по умолчанию 22)
        local sshd_port
        sshd_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        sshd_port="${sshd_port:-22}"
        ufw allow "${sshd_port}/tcp" >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1
        echo "y" | ufw enable >/dev/null 2>&1

        # Автодополнение команд UFW
        ln -sf /usr/share/bash-completion/completions/ufw /etc/bash_completion.d/ufw 2>/dev/null || true
        if ! grep -q "/usr/share/bash-completion/bash_completion" /root/.bashrc 2>/dev/null; then
            printf 'if [ -f /usr/share/bash-completion/bash_completion ]; then\n    . /usr/share/bash-completion/bash_completion\nfi\n' >> /root/.bashrc
        fi
        source /usr/share/bash-completion/bash_completion 2>/dev/null || true
        source /usr/share/bash-completion/completions/ufw 2>/dev/null || true

        # IPv6 disable
        sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
        sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
        if ! grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf; then
            echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
        fi

        # Unattended-upgrades — автоматические обновления безопасности
        echo 'Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };' \
            > /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
        echo 'Unattended-Upgrade::Mail "root";' \
            >> /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
        echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true \
            | debconf-set-selections 2>/dev/null || true
        dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
        systemctl restart unattended-upgrades >/dev/null 2>&1 || true

        # Locales
        sed -i '/^#.*en_US.UTF-8/s/^#//' /etc/locale.gen 2>/dev/null || true
        locale-gen >/dev/null 2>&1 || true

        # DNS fallback — защита от потери DNS при перезагрузке systemd-resolved
        if [ -d /etc/systemd/resolved.conf.d ] || mkdir -p /etc/systemd/resolved.conf.d 2>/dev/null; then
            cat > /etc/systemd/resolved.conf.d/dns-fallback.conf <<'DNSCONF'
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=8.8.4.4 9.9.9.9
DNSCONF
            systemctl restart systemd-resolved >/dev/null 2>&1 || true
        fi

        # Создаём директорию для флага, если её нет
        mkdir -p "${DIR_SCRIPT}" 2>/dev/null || true
        touch "${DIR_SCRIPT}install_packages"
    ) &
    show_spinner "Установка необходимых пакетов"
    echo
    source /usr/share/bash-completion/bash_completion 2>/dev/null || true
    source /usr/share/bash-completion/completions/ufw 2>/dev/null || true
}

setup_firewall() {
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    # Открываем порт SSH (определяем из sshd_config, по умолчанию 22)
    local sshd_port
    sshd_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    sshd_port="${sshd_port:-22}"
    ufw allow "${sshd_port}/tcp" >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    echo "y" | ufw enable >/dev/null 2>&1 || true
}
