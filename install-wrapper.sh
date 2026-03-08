#!/bin/bash
# ═══════════════════════════════════════════════════════════
#   DFC REMNA-INSTALL — Bootstrap wrapper
#   bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/install-wrapper.sh)
# ═══════════════════════════════════════════════════════════

cd /opt >/dev/null 2>&1 || true

BLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

trap 'stty sane 2>/dev/null; tput cnorm 2>/dev/null; exit 130' INT TERM

_INSTALL_DIR="/usr/local/dfc-remna-install"
_REPO="DanteFuaran/dfc-remna-install"
_BRANCH="main"

_run_spinner() {
    local msg="$1" pid="$2"
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BLUE}%s${NC}  %s" "${spin[$i]}" "$msg"
        i=$(( (i+1) % 10 ))
        sleep 0.08
    done
    printf "\r\033[K"
    tput cnorm 2>/dev/null || true
}

# Если скрипт уже установлен — запускаем
if [ -f "${_INSTALL_DIR}/dfc-remna-install.sh" ] && [ -d "${_INSTALL_DIR}/lib" ]; then
    ( sleep 0.5 ) &
    _run_spinner "Подготовка скрипта к запуску..." $!
    wait $! 2>/dev/null || true
    exec "${_INSTALL_DIR}/dfc-remna-install.sh"
fi

# ─── Первичная установка ─────────────────────────────────
mkdir -p /usr/local/bin || { echo -e "${RED}✖ Ошибка создания /usr/local/bin${NC}"; exit 1; }

_msg="Подготовка скрипта к запуску..."
git clone --depth 1 -b "${_BRANCH}" "https://github.com/${_REPO}.git" "${_INSTALL_DIR}" >/dev/null 2>&1 &
_clone_pid=$!
_run_spinner "$_msg" $_clone_pid
wait $_clone_pid
_clone_exit=$?

if [ $_clone_exit -ne 0 ]; then
    echo -e "${RED}✖ Ошибка клонирования репозитория. Проверьте соединение с интернетом.${NC}"
    rm -rf "${_INSTALL_DIR}"
    exit 1
fi

if [ ! -f "${_INSTALL_DIR}/dfc-remna-install.sh" ]; then
    echo -e "${RED}✖ Файл скрипта не найден в репозитории.${NC}"
    rm -rf "${_INSTALL_DIR}"
    exit 1
fi

chmod +x "${_INSTALL_DIR}/dfc-remna-install.sh"
ln -sf "${_INSTALL_DIR}/dfc-remna-install.sh" /usr/local/bin/dfc-remna-install
ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri

exec "${_INSTALL_DIR}/dfc-remna-install.sh"
