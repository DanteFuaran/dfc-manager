#!/bin/bash
# ═══════════════════════════════════════════════════════════
#   DFC REMNA-INSTALL — Bootstrap wrapper
#   cd /opt && bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/install-wrapper.sh)
# ═══════════════════════════════════════════════════════════

cd /opt >/dev/null 2>&1 || true

BLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

trap 'stty sane 2>/dev/null; tput cnorm 2>/dev/null; exit 130' INT TERM

_INSTALL_DIR="/usr/local/remnawave"
_REPO="DanteFuaran/dfc-remna-install"
_BRANCH="main"

echo -e "${BLUE}Подготовка скрипта к запуску...${NC}"

# Если скрипт уже установлен — запускаем установленную версию
if [ -f "${_INSTALL_DIR}/remnawave.sh" ] && [ -d "${_INSTALL_DIR}/lib" ]; then
    exec "${_INSTALL_DIR}/remnawave.sh"
fi

# ─── Первичная установка ─────────────────────────────────
mkdir -p /usr/local/bin || { echo -e "${RED}✖ Ошибка создания /usr/local/bin${NC}"; exit 1; }

if ! timeout 60 git clone --depth 1 -b "${_BRANCH}" "https://github.com/${_REPO}.git" "${_INSTALL_DIR}" >/dev/null 2>&1; then
    echo -e "${RED}✖ Ошибка клонирования репозитория. Проверьте соединение с интернетом.${NC}"
    rm -rf "${_INSTALL_DIR}"
    exit 1
fi

if [ ! -f "${_INSTALL_DIR}/remnawave.sh" ]; then
    echo -e "${RED}✖ Файл скрипта не найден в репозитории.${NC}"
    rm -rf "${_INSTALL_DIR}"
    exit 1
fi

chmod +x "${_INSTALL_DIR}/remnawave.sh"
ln -sf "${_INSTALL_DIR}/remnawave.sh" /usr/local/bin/remnawave
ln -sf /usr/local/bin/remnawave /usr/local/bin/rw

exec "${_INSTALL_DIR}/remnawave.sh"
