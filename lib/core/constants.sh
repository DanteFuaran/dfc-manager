# ═══════════════════════════════════════════════
# КОНСТАНТЫ И ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ═══════════════════════════════════════════════

DIR_SCRIPT="/usr/local/dfc-manager/"
DIR_PANEL="/opt/remnawave/"
DIR_NODE="/opt/remnanode/"
DIR_SUB="/opt/subscribe-page/"

# Версия, ветка и репозиторий — источник: /usr/local/dfc-manager/version (всегда присутствует)
SCRIPT_VERSION="0.1.51"
SCRIPT_BRANCH="main"
SCRIPT_REPO="https://github.com/DanteFuaran/dfc-manager.git"
# Синхронизируем git remote на публичный URL (на случай если осталась старая запись с учётными данными в URL)
if command -v git >/dev/null 2>&1 && [ -d "${DIR_SCRIPT}.git" ]; then
    _cur_remote=$(git -C "${DIR_SCRIPT%/}" remote get-url origin 2>/dev/null || true)
    _pub_remote="https://github.com/DanteFuaran/dfc-manager.git"
    [ "$_cur_remote" != "$_pub_remote" ] && \
        git -C "${DIR_SCRIPT%/}" remote set-url origin "$_pub_remote" 2>/dev/null || true
    unset _cur_remote _pub_remote
fi
_vf="${DIR_SCRIPT}version"
if [ -f "$_vf" ]; then
    _sv=$(grep '^version:' "$_vf" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ') || true
    _br=$(grep '^branch:'  "$_vf" 2>/dev/null | cut -d: -f2 | tr -d ' ') || true
    _rp=$(grep '^repo:'    "$_vf" 2>/dev/null | cut -d: -f2- | tr -d ' ') || true
    [ -n "$_sv" ] && SCRIPT_VERSION="$_sv"
    [ -n "$_br" ] && SCRIPT_BRANCH="$_br"
    [ -n "$_rp" ] && SCRIPT_REPO="$_rp"
fi
unset _sv _br _rp _vf

# SCRIPT_URL строится динамически из $SCRIPT_BRANCH — менять только version-файл
SCRIPT_URL="https://raw.githubusercontent.com/DanteFuaran/dfc-manager/refs/heads/${SCRIPT_BRANCH}/dfc-manager.sh"
# Файлы кэша проверки обновлений (в стабильной директории, а не в /tmp)
UPDATE_AVAILABLE_FILE="${DIR_SCRIPT}update_available"
UPDATE_CHECK_TIME_FILE="${DIR_SCRIPT}last_update_check"
