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
        apt-get upgrade -y -qq $DPKG_OPTS >/dev/null 2>&1
        apt-get install -y -qq $DPKG_OPTS ca-certificates curl jq ufw wget gnupg unzip nano dialog git \
            certbot python3-certbot-dns-cloudflare unattended-upgrades locales dnsutils \
            coreutils grep gawk logrotate >/dev/null 2>&1

        # Cron
        if ! dpkg -l | grep -q '^ii.*cron '; then
            apt-get install -y -qq $DPKG_OPTS cron >/dev/null 2>&1
        fi
        systemctl start cron 2>/dev/null || true
        systemctl enable cron 2>/dev/null || true

        # Logrotate
        if ! dpkg -l | grep -q '^ii.*logrotate '; then
            apt-get install -y -qq $DPKG_OPTS logrotate >/dev/null 2>&1
        fi

        # Docker
        if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
            curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
            sh /tmp/get-docker.sh >/dev/null 2>&1
            rm -f /tmp/get-docker.sh
        fi
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true

        # BBR
        if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
        fi

        # Memory overcommit (рекомендовано для Redis/Valkey — предотвращает сбои фоновых сохранений)
        if ! sysctl vm.overcommit_memory 2>/dev/null | grep -q "= 1"; then
            sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1
            if ! grep -q 'vm.overcommit_memory' /etc/sysctl.conf 2>/dev/null; then
                echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf
            else
                sed -i 's/vm.overcommit_memory=.*/vm.overcommit_memory=1/' /etc/sysctl.conf
            fi
        fi

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
        apt-get install --reinstall -y -qq bash-completion ufw >/dev/null 2>&1
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

        # Locales
        sed -i '/^#.*en_US.UTF-8/s/^#//' /etc/locale.gen 2>/dev/null || true
        locale-gen >/dev/null 2>&1 || true

        # Создаём директорию для флага, если её нет
        mkdir -p "${DIR_REMNAWAVE}" 2>/dev/null || true
        touch "${DIR_REMNAWAVE}install_packages"
    ) &
    echo
    show_spinner "Установка необходимых пакетов"
    
    # Активация автодополнения для текущей shell сессии
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
