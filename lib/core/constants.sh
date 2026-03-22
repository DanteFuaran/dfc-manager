# ═══════════════════════════════════════════════
# КОНСТАНТЫ И ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ═══════════════════════════════════════════════

DIR_SCRIPT="/usr/local/dfc-manager/"
DIR_PANEL="/opt/remnawave/"
DIR_NODE="/opt/remnanode/"

# Версия, ветка и репозиторий — единый источник: /opt/remnawave/version
SCRIPT_VERSION="0.0.4"
SCRIPT_BRANCH="main"
SCRIPT_REPO="https://github.com/DanteFuaran/dfc-manager.git"
# Приоритет: /opt/remnawave/version (рядом с .env), затем /usr/local/dfc-manager/version
for _vf in "${DIR_PANEL}version" "${DIR_SCRIPT}version"; do
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

# SCRIPT_URL строится динамически из $SCRIPT_BRANCH — менять только version-файл
SCRIPT_URL="https://raw.githubusercontent.com/DanteFuaran/dfc-manager/refs/heads/${SCRIPT_BRANCH}/dfc-manager.sh"
# Файлы кэша проверки обновлений (в стабильной директории, а не в /tmp)
UPDATE_AVAILABLE_FILE="${DIR_SCRIPT}update_available"
UPDATE_CHECK_TIME_FILE="${DIR_SCRIPT}last_update_check"
