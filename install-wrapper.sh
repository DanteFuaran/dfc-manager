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

echo -e "${BLUE}Подготовка скрипта к запуску...${NC}"

# Если скрипт уже установлен — запускаем без лишних действий
if [ -f "${_INSTALL_DIR}/dfc-remna-install.sh" ] && [ -d "${_INSTALL_DIR}/lib" ]; then
    exec "${_INSTALL_DIR}/dfc-remna-install.sh"
fi

# ─── Первичная установка ─────────────────────────────────
mkdir -p "${_INSTALL_DIR}" || { echo -e "${RED}✖ Ошибка создания ${_INSTALL_DIR}${NC}"; exit 1; }

_TMP_FILE=$(mktemp)

if ! curl -fsSL --connect-timeout 15 --max-time 120 \
        "https://github.com/${_REPO}/archive/refs/heads/${_BRANCH}.tar.gz" \
        -o "${_TMP_FILE}" 2>/dev/null \
    || ! tar -xz -C "${_INSTALL_DIR}" --strip-components=1 -f "${_TMP_FILE}" 2>/dev/null; then
    rm -f "${_TMP_FILE}"
    echo -e "${RED}✖ Ошибка загрузки или распаковки архива. Проверьте соединение с интернетом.${NC}"
    exit 1
fi
rm -f "${_TMP_FILE}"

if [ ! -f "${_INSTALL_DIR}/dfc-remna-install.sh" ]; then
    echo -e "${RED}✖ Файл скрипта не найден. Архив повреждён?${NC}"
    exit 1
fi

chmod +x "${_INSTALL_DIR}/dfc-remna-install.sh"
mkdir -p /usr/local/bin
ln -sf "${_INSTALL_DIR}/dfc-remna-install.sh" /usr/local/bin/dfc-remna-install
ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri

exec "${_INSTALL_DIR}/dfc-remna-install.sh"
