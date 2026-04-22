#!/bin/bash
# ═══════════════════════════════════════════════════════════
#   DFC Manager — Установщик Remnawave VPN Panel
#   DFC Manager v0.1.63
#   https://github.com/DanteFuaran/dfc-manager
#   Установка: bash <(curl -s https://raw.githubusercontent.com/DanteFuaran/dfc-manager/main/dfc-manager.sh)
# ═══════════════════════════════════════════════════════════

# ─── Bootstrap: запуск через curl или не из установленной копии ─────────
_INSTALL_DIR="/usr/local/dfc-manager"
_INSTALL_SCRIPT="${_INSTALL_DIR}/dfc-manager.sh"
# Если запущены не из установленной копии (напр. через curl/pipe/tmp) — установить или переключиться
if [ "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)" != "$_INSTALL_SCRIPT" ]; then
    if [ -f "$_INSTALL_SCRIPT" ] && [ -d "${_INSTALL_DIR}/lib" ]; then
        # Запущено через curl/pipe — обновляем существующую копию через git
        if command -v git >/dev/null 2>&1 && [ -d "${_INSTALL_DIR}/.git" ]; then
            git -C "${_INSTALL_DIR}" remote set-url origin "https://github.com/DanteFuaran/dfc-manager.git" 2>/dev/null || true
            git -C "${_INSTALL_DIR}" fetch --depth 1 origin main >/dev/null 2>&1 \
                && git -C "${_INSTALL_DIR}" reset --hard origin/main >/dev/null 2>&1 || true
        fi
        exec "$_INSTALL_SCRIPT" "$@"
    fi
    _BLUE='\033[1;34m'; _RED='\033[0;31m'; _NC='\033[0m'
    # Ветка: читаем из version-файла рядом со скриптом или из уже установленной копии.
    # Если запуск через curl/pipe — файловая система недоступна, используем значение из version-файла в репозитории.
    _BRANCH="main"  # <- этот фолбэк меняется только при смене ветки
    for _vf2 in "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)")/version" \
                "${_INSTALL_DIR}/version"; do
        if [ -f "$_vf2" ]; then
            _b2=$(grep '^branch:' "$_vf2" 2>/dev/null | cut -d: -f2 | tr -d ' ')
            [ -n "$_b2" ] && { _BRANCH="$_b2"; break; }
        fi
    done
    unset _vf2 _b2
    trap 'stty sane 2>/dev/null; tput cnorm 2>/dev/null; rm -rf "${_INSTALL_DIR}" 2>/dev/null; exit 130' INT TERM
    cd /opt >/dev/null 2>&1 || true
    mkdir -p /usr/local/bin || { echo -e "${_RED}✖ Ошибка создания /usr/local/bin${_NC}"; exit 1; }
    rm -rf "${_INSTALL_DIR}"
    if ! command -v git >/dev/null 2>&1; then
        echo -e "${_BLUE}⏳ Устанавливаю git...${_NC}"
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y -q git >/dev/null 2>&1 \
                || { echo -e "${_RED}✖ Не удалось установить git.${_NC}"; exit 1; }
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q git >/dev/null 2>&1 || { echo -e "${_RED}✖ Не удалось установить git.${_NC}"; exit 1; }
        else
            echo -e "${_RED}✖ git не установлен. Установите его вручную и повторите.${_NC}"; exit 1
        fi
    fi
    if ! timeout 60 git clone --depth 1 -b "$_BRANCH" \
            "https://github.com/DanteFuaran/dfc-manager.git" \
            "${_INSTALL_DIR}" >/dev/null 2>&1; then
        echo -e "${_RED}✖ Ошибка клонирования репозитория. Проверьте соединение с интернетом.${_NC}"
        rm -rf "${_INSTALL_DIR}"
        exit 1
    fi
    chmod +x "$_INSTALL_SCRIPT"
    exec "$_INSTALL_SCRIPT" "$@"
fi

# ─── Основной скрипт ─────────────────────────────────────────
cd /opt >/dev/null 2>&1 || true

set -euo pipefail

# Определяем директорию скрипта — bootstrap гарантирует запуск из _INSTALL_DIR
_resolved="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)" || true
if [ -n "$_resolved" ] && [ -f "$_resolved" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$_resolved")" && pwd)"
else
    SCRIPT_DIR="${_INSTALL_DIR%/}"
fi
unset _resolved

# ─── Загрузка модулей ───

# Core: базовые определения (порядок важен)
source "${SCRIPT_DIR}/lib/core/constants.sh"
source "${SCRIPT_DIR}/lib/core/colors.sh"
source "${SCRIPT_DIR}/lib/core/terminal.sh"
source "${SCRIPT_DIR}/lib/core/ui.sh"
source "${SCRIPT_DIR}/lib/extra/ufw.sh"
source "${SCRIPT_DIR}/lib/core/system.sh"
source "${SCRIPT_DIR}/lib/core/docker_install.sh"
source "${SCRIPT_DIR}/lib/core/nginx.sh"

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
source "${SCRIPT_DIR}/lib/install/subpage.sh"

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
source "${SCRIPT_DIR}/lib/extra/logrotate.sh"
source "${SCRIPT_DIR}/lib/extra/warp.sh"
source "${SCRIPT_DIR}/lib/extra/beszel.sh"
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
if [ "${DFC_INSTALLED_RUN:-}" != "1" ]; then
    export DFC_INSTALLED_RUN=1
    exec /usr/local/bin/dfc-manager
fi

# ─── Подготовка к запуску — спиннер единожды, минимум 1 сек ──────────────────
if [ "${DFC_AUTO_UPDATED:-}" != "1" ]; then
    export DFC_AUTO_UPDATED=1
    _UPDATE_FLAG="/tmp/.dfc_upd_$$"
    export _START_TIME=$(date +%s)
    clear
    (
        _api_repo="DanteFuaran/dfc-manager"
        _remote_sha=$(curl -sL --max-time 5 \
            -H "Cache-Control: no-cache" \
            "https://api.github.com/repos/${_api_repo}/commits/${SCRIPT_BRANCH}" 2>/dev/null \
            | grep -m1 '"sha"' | cut -d'"' -f4 2>/dev/null || true)
        _local_sha=$(git -C "${DIR_SCRIPT%/}" rev-parse HEAD 2>/dev/null || true)
        if [ -n "$_remote_sha" ] && [ -n "$_local_sha" ] && [ "$_remote_sha" != "$_local_sha" ]; then
            git -C "${DIR_SCRIPT%/}" fetch --depth=1 origin "${SCRIPT_BRANCH}" >/dev/null 2>&1
            git -C "${DIR_SCRIPT%/}" reset --hard FETCH_HEAD >/dev/null 2>&1
            chmod +x "${DIR_SCRIPT}dfc-manager.sh"
            _install_bin_wrappers
            touch "$_UPDATE_FLAG"
        fi
        rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null || true
        # Гарантируем минимум 1 сек на экране
        _ELAPSED=$(($(date +%s) - _START_TIME))
        [ $_ELAPSED -lt 1 ] && sleep $((1 - _ELAPSED))
    ) &
    show_spinner_prepare "Подготовка скрипта к запуску"

    if [ -f "$_UPDATE_FLAG" ]; then
        rm -f "$_UPDATE_FLAG"
        exec /usr/local/bin/dfc-manager
    fi
    unset _UPDATE_FLAG _START_TIME
fi

main_menu
