# ═══════════════════════════════════════════════
# ВОССТАНОВЛЕНИЕ ТЕРМИНАЛА И ОБРАБОТКА ПРЕРЫВАНИЙ
# ═══════════════════════════════════════════════

# Сохраняем исходное состояние терминала (до любых изменений)
ORIGINAL_STTY=$(stty -g 2>/dev/null || echo "")

cleanup_terminal() {
    # Полное восстановление терминала
    tput cnorm 2>/dev/null || true
    tput sgr0 2>/dev/null || true
    printf "\033[0m\033[?25h" 2>/dev/null || true
    if [ -n "$ORIGINAL_STTY" ]; then
        stty "$ORIGINAL_STTY" 2>/dev/null || stty sane 2>/dev/null || true
    else
        stty sane 2>/dev/null || true
    fi
    # Явно восстанавливаем ключевые флаги (echo, icanon) — на случай если
    # read -s или stty -icanon не были корректно сброшены при выходе
    stty echo echoe icanon isig 2>/dev/null || true
}

# Удаление старых алиасов и команд
cleanup_old_aliases() {
    # Удаляем старый алиас ri (|| true чтобы не прерывать при set -e если файл не существует)
    sed -i "/alias ri='remna_install'/d" /etc/bash.bashrc 2>/dev/null || true
    sed -i "/alias ri='remna_install'/d" /etc/bashrc 2>/dev/null || true
    sed -i "/alias ri='remna_install'/d" /root/.bashrc 2>/dev/null || true
    sed -i "/alias ri='remna_install'/d" /root/.bash_aliases 2>/dev/null || true
    if [ -n "$HOME" ] && [ "$HOME" != "/root" ]; then
        sed -i "/alias ri='remna_install'/d" "$HOME/.bashrc" 2>/dev/null || true
        sed -i "/alias ri='remna_install'/d" "$HOME/.bash_aliases" 2>/dev/null || true
    fi
    rm -f /etc/profile.d/remna_install.sh 2>/dev/null || true
    rm -f /usr/local/bin/remna_install 2>/dev/null || true
    # Удаляем старые команды dfc-remna-install / dfc-ri
    rm -f /usr/local/bin/dfc-remna-install 2>/dev/null || true
    rm -f /usr/local/bin/dfc-ri 2>/dev/null || true
    # Удаляем старые команды remnawave (rw теперь — launcher dfc-manager, не удаляем)
    rm -f /usr/local/bin/remnawave 2>/dev/null || true
    rm -rf /usr/local/remnawave 2>/dev/null || true
    unalias ri 2>/dev/null || true
}

# Тихая самоочистка если ничего не установлено
cleanup_uninstalled() {
    # Удаляем скрипт и симлинки только если ни одно из приложений не установлено
    local _any=false
    [ -f "${DIR_PANEL}docker-compose.yml" ]                  && _any=true
    [ -f "${DIR_NODE}docker-compose.yml" ]                   && _any=true
    [ -f "/opt/remnasubpage/docker-compose.yml" ]            && _any=true
    [ -f "/opt/subscribe-page/docker-compose.yml" ]          && _any=true
    [ -f "/opt/beszel/docker-compose.yml" ]                  && _any=true
    [ -f "/opt/beszel-agent/docker-compose.yml" ]            && _any=true
    [ -f "/opt/mtproto/docker-compose.yml" ]                 && _any=true
    if [ "$_any" = false ]; then
        rm -f /usr/local/bin/dfc-manager /usr/local/bin/dfc /usr/local/bin/rw 2>/dev/null || true
        rm -rf "${DIR_SCRIPT}" 2>/dev/null || true
    fi
}

handle_interrupt() {
    trap '' INT TERM HUP
    if [ -n "${ORIGINAL_STTY:-}" ]; then
        stty "$ORIGINAL_STTY" 2>/dev/null || stty sane 2>/dev/null || true
    else
        stty sane 2>/dev/null || true
    fi
    stty echo echoe icanon isig 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf "\033[0m" 2>/dev/null || true
    clear
    printf '\033[0;31mСкрипт был остановлен пользователем\033[0m\n\n'
    cleanup_uninstalled 2>/dev/null || true
    exit 130
}

trap cleanup_terminal EXIT
trap handle_interrupt INT TERM HUP
