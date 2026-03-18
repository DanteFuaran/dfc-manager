# ═══════════════════════════════════════════════
# КОНСТАНТЫ И ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ═══════════════════════════════════════════════

DIR_REMNAWAVE="/usr/local/remnawave/"
DIR_PANEL="/opt/remnawave/"
DIR_NODE="/opt/remnanode/"

# Версия, ветка и репозиторий — единый источник: version
SCRIPT_VERSION="0.1.4"
SCRIPT_BRANCH="main"
SCRIPT_REPO="https://github.com/DanteFuaran/dfc-remna-install.git"
if [ -f "${DIR_REMNAWAVE}version" ]; then
    _sv=$(grep '^version:' "${DIR_REMNAWAVE}version" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    _br=$(grep '^branch:' "${DIR_REMNAWAVE}version" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    _rp=$(grep '^repo:' "${DIR_REMNAWAVE}version" 2>/dev/null | cut -d: -f2- | tr -d ' ')
    [ -n "$_sv" ] && SCRIPT_VERSION="$_sv"
    [ -n "$_br" ] && SCRIPT_BRANCH="$_br"
    [ -n "$_rp" ] && SCRIPT_REPO="$_rp"
    unset _sv _br _rp
fi

SCRIPT_URL="https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/remnawave.sh"
# Файлы кэша проверки обновлений (в стабильной директории, а не в /tmp)
UPDATE_AVAILABLE_FILE="${DIR_REMNAWAVE}update_available"
UPDATE_CHECK_TIME_FILE="${DIR_REMNAWAVE}last_update_check"
