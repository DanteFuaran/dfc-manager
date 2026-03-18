# ═══════════════════════════════════════════════
# КОНСТАНТЫ И ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ═══════════════════════════════════════════════

DIR_REMNAWAVE="/usr/local/remnawave/"
DIR_PANEL="/opt/remnawave/"
DIR_NODE="/opt/remnanode/"

# Версия, ветка и репозиторий — единый источник: /opt/remnawave/version
SCRIPT_VERSION="0.1.6"
SCRIPT_BRANCH="main"
SCRIPT_REPO="https://github.com/DanteFuaran/dfc-remna-install.git"
# Приоритет: /opt/remnawave/version (рядом с .env), затем /usr/local/remnawave/version
for _vf in "${DIR_PANEL}version" "${DIR_REMNAWAVE}version"; do
    if [ -f "$_vf" ]; then
        _sv=$(grep '^version:' "$_vf" 2>/dev/null | cut -d: -f2 | tr -d ' ')
        _br=$(grep '^branch:'  "$_vf" 2>/dev/null | cut -d: -f2 | tr -d ' ')
        _rp=$(grep '^repo:'    "$_vf" 2>/dev/null | cut -d: -f2- | tr -d ' ')
        [ -n "$_sv" ] && SCRIPT_VERSION="$_sv"
        [ -n "$_br" ] && SCRIPT_BRANCH="$_br"
        [ -n "$_rp" ] && SCRIPT_REPO="$_rp"
        unset _sv _br _rp _vf
        break
    fi
done
unset _vf

SCRIPT_URL="https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/remnawave.sh"
# Файлы кэша проверки обновлений (в стабильной директории, а не в /tmp)
UPDATE_AVAILABLE_FILE="${DIR_REMNAWAVE}update_available"
UPDATE_CHECK_TIME_FILE="${DIR_REMNAWAVE}last_update_check"
