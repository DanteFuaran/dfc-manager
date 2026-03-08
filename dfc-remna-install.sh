#!/bin/bash
# ═══════════════════════════════════════════════════════════
#   DFC REMNA-INSTALL — Установщик Remnawave VPN Panel
#   https://github.com/DanteFuaran/dfc-remna-install
# ═══════════════════════════════════════════════════════════

_INSTALL_DIR="/usr/local/dfc-remna-install"
_REPO="DanteFuaran/dfc-remna-install"
_BRANCH="main"

cd /opt >/dev/null 2>&1 || true

# Bootstrap: при запуске через bash <(curl ...) скрипт читается из /dev/fd/N
# В этом случае рядом нет lib/ — скачиваем архив и переключаемся на установленную копию
_SELF="${BASH_SOURCE[0]}"
if [[ "$_SELF" == /dev/fd/* ]] || [[ "$_SELF" == /proc/* ]]; then
    # Если скрипт уже установлен — молча запускаем существующую копию (она сама обновится)
    if [ -f "${_INSTALL_DIR}/dfc-remna-install.sh" ] && [ -d "${_INSTALL_DIR}/lib" ]; then
        export REMNA_INSTALLED_RUN=1
        exec "${_INSTALL_DIR}/dfc-remna-install.sh"
    fi

    # Inline-спиннер (lib ещё не загружен)
    _GREEN='\033[0;32m'; _RED='\033[0;31m'
    _spinner_pid=""
    _start_spinner() {
        local _msg="$1"
        ( local _spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') _i=0
          tput civis 2>/dev/null || true
          while true; do
              printf "\r\033[0;32m%s\033[0m  %s" "${_spin[$_i]}" "$_msg"
              _i=$(( (_i+1) % 10 ))
              sleep 0.08
          done ) &
        _spinner_pid=$!
    }
    _stop_spinner() {
        local _msg="$1" _ok="${2:-1}"
        [ -n "$_spinner_pid" ] && kill "$_spinner_pid" 2>/dev/null; wait "$_spinner_pid" 2>/dev/null || true
        _spinner_pid=""
        if [ "$_ok" = "1" ]; then
            printf "\r${_GREEN}✅\033[0m %s\n" "$_msg"
        else
            printf "\r${_RED}✖\033[0m  %s\n" "$_msg"
        fi
        tput cnorm 2>/dev/null || true
    }

    # Первичная установка — скачиваем архив
    echo -e "\033[0;34mПодготовка к запуску...\033[0m"
    mkdir -p "${_INSTALL_DIR}" || { echo "✖ Ошибка создания ${_INSTALL_DIR}"; exit 1; }

    _TMP_FILE=$(mktemp)
    _start_spinner "Подготовка скрипта к запуску"

    if ! curl -fsSL --connect-timeout 15 --max-time 120 \
            "https://github.com/${_REPO}/archive/refs/heads/${_BRANCH}.tar.gz" \
            -o "${_TMP_FILE}" 2>/dev/null \
        || ! tar -xz -C "${_INSTALL_DIR}" --strip-components=1 -f "${_TMP_FILE}" 2>/dev/null; then
        _stop_spinner "Подготовка скрипта к запуску" 0
        rm -f "${_TMP_FILE}"
        echo "✖ Ошибка загрузки или распаковки архива. Проверьте соединение с интернетом."
        exit 1
    fi
    rm -f "${_TMP_FILE}"

    if [ ! -f "${_INSTALL_DIR}/dfc-remna-install.sh" ]; then
        _stop_spinner "Подготовка скрипта к запуску" 0
        echo "✖ Файл скрипта не найден. Архив повреждён?"
        exit 1
    fi

    _stop_spinner "Подготовка скрипта к запуску"
    chmod +x "${_INSTALL_DIR}/dfc-remna-install.sh"
    mkdir -p /usr/local/bin
    ln -sf "${_INSTALL_DIR}/dfc-remna-install.sh" /usr/local/bin/dfc-remna-install
    ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri
    export REMNA_INSTALLED_RUN=1
    exec "${_INSTALL_DIR}/dfc-remna-install.sh"
fi

set -euo pipefail

# Определяем директорию скрипта (уже установлен), резолвим симлинки
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ─── Загрузка модулей ───

# Core: базовые определения (порядок важен)
source "${SCRIPT_DIR}/lib/core/constants.sh"
source "${SCRIPT_DIR}/lib/core/colors.sh"
source "${SCRIPT_DIR}/lib/core/terminal.sh"
source "${SCRIPT_DIR}/lib/core/ui.sh"
source "${SCRIPT_DIR}/lib/core/system.sh"

# Install: генераторы и утилиты установки
source "${SCRIPT_DIR}/lib/install/generators.sh"
source "${SCRIPT_DIR}/lib/install/log_rotation.sh"
source "${SCRIPT_DIR}/lib/install/domain.sh"
source "${SCRIPT_DIR}/lib/install/certificates.sh"
source "${SCRIPT_DIR}/lib/install/templates.sh"
source "${SCRIPT_DIR}/lib/install/api.sh"
source "${SCRIPT_DIR}/lib/install/config.sh"
source "${SCRIPT_DIR}/lib/install/full.sh"
source "${SCRIPT_DIR}/lib/install/panel.sh"
source "${SCRIPT_DIR}/lib/install/node.sh"

# Manage: управление установкой
source "${SCRIPT_DIR}/lib/manage/detect.sh"
source "${SCRIPT_DIR}/lib/manage/services.sh"
source "${SCRIPT_DIR}/lib/manage/database.sh"
source "${SCRIPT_DIR}/lib/manage/domains.sh"
source "${SCRIPT_DIR}/lib/manage/access.sh"
source "${SCRIPT_DIR}/lib/manage/node.sh"
source "${SCRIPT_DIR}/lib/manage/template.sh"

# Extra: дополнительные настройки
source "${SCRIPT_DIR}/lib/extra/swap.sh"
source "${SCRIPT_DIR}/lib/extra/bbr.sh"
source "${SCRIPT_DIR}/lib/extra/fail2ban.sh"
source "${SCRIPT_DIR}/lib/extra/ufw.sh"
source "${SCRIPT_DIR}/lib/extra/logrotate.sh"
source "${SCRIPT_DIR}/lib/extra/warp.sh"
source "${SCRIPT_DIR}/lib/extra/menu.sh"

# Update: обновление и удаление
source "${SCRIPT_DIR}/lib/update/version.sh"
source "${SCRIPT_DIR}/lib/update/script.sh"

# Menu: главное меню
source "${SCRIPT_DIR}/lib/menu/main.sh"

# ═══════════════════════════════════════════════
# ТОЧКА ВХОДА
# ═══════════════════════════════════════════════


check_root
check_os

# Если запущены НЕ из установленной копии - скачиваем свежую и переключаемся
install_script
if [ "${REMNA_INSTALLED_RUN:-}" != "1" ]; then
    export REMNA_INSTALLED_RUN=1
    exec /usr/local/bin/dfc-remna-install
fi

# Проверка обновлений (всегда)
current_time=$(date +%s)
last_check=0

if [ -f "${UPDATE_CHECK_TIME_FILE}" ]; then
    last_check=$(cat "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null || echo 0)
fi

# Проверяем раз в час (3600 секунд)
time_diff=$((current_time - last_check))
if [ $time_diff -gt 3600 ] || [ ! -f "${UPDATE_AVAILABLE_FILE}" ]; then
    new_version=$(check_for_updates) || true
    if [ -n "$new_version" ]; then
        echo "$new_version" > "${UPDATE_AVAILABLE_FILE}"
    else
        rm -f "${UPDATE_AVAILABLE_FILE}" 2>/dev/null || true
    fi
    echo "$current_time" > "${UPDATE_CHECK_TIME_FILE}"
fi

main_menu
