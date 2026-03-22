# ═══════════════════════════════════════════════
# ПРОВЕРКА ВЕРСИИ
# ═══════════════════════════════════════════════

# Читает версию из файла version (формат: "version: x.y.z")
parse_version_from_file() {
    local file="$1"
    if [ -f "$file" ]; then
        grep '^version:' "$file" 2>/dev/null | cut -d: -f2 | tr -d ' '
    fi
}

get_installed_version() {
    local ver=""
    # Приоритет: /opt/remnawave/version, затем /usr/local/remnawave/version
    for _vf in "${DIR_PANEL}version" "${DIR_SCRIPT}version"; do
        if [ -f "$_vf" ]; then
            ver=$(parse_version_from_file "$_vf")
            [ -n "$ver" ] && break
        fi
    done
    [ -z "$ver" ] && ver="$SCRIPT_VERSION"
    echo "$ver"
}

get_remote_version() {
    # Формируем raw URL из репозитория
    local raw_url
    raw_url=$(echo "$SCRIPT_REPO" | sed 's|github.com|raw.githubusercontent.com|; s|\.git$||')

    local latest_sha
    local api_repo
    api_repo=$(echo "$SCRIPT_REPO" | sed 's|https://github.com/||; s|\.git$||')
    latest_sha=$(curl -sL --max-time 5 \
        -H "Cache-Control: no-cache" \
        "https://api.github.com/repos/${api_repo}/commits/${SCRIPT_BRANCH}" 2>/dev/null \
        | grep -m 1 '"sha"' | cut -d'"' -f4 || true)

    local content=""
    if [ -n "$latest_sha" ]; then
        content=$(curl -sL --max-time 5 \
            "${raw_url}/${latest_sha}/version" 2>/dev/null || true)
    else
        content=$(curl -sL --max-time 5 \
            -H "Cache-Control: no-cache" \
            "${raw_url}/${SCRIPT_BRANCH}/version" 2>/dev/null || true)
    fi

    if [ -n "$content" ]; then
        echo "$content" | grep '^version:' | cut -d: -f2 | tr -d ' '
    fi
}

check_for_updates() {
    local remote_version
    remote_version=$(get_remote_version)

    if [ -z "$remote_version" ]; then
        return 1
    fi

    local local_version
    local_version=$(get_installed_version)

    if [ -z "$local_version" ] || [ "$remote_version" = "$local_version" ]; then
        return 1
    fi

    # Сравнение семантических версий
    local local_num remote_num
    local_num=$(echo "$local_version" | awk -F. '{printf "%03d%03d%03d", $1, $2, $3}')
    remote_num=$(echo "$remote_version" | awk -F. '{printf "%03d%03d%03d", $1, $2, $3}')

    if [ "$remote_num" -gt "$local_num" ] 2>/dev/null; then
        echo "$remote_version"
        return 0
    fi
    return 1
}

show_update_notification() {
    local new_version=$1
    echo
    echo -e "${YELLOW}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}🔔 ДОСТУПНО ОБНОВЛЕНИЕ!${NC}                        ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}                                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  Текущая версия:  ${WHITE}v$SCRIPT_VERSION${NC}                      ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  Новая версия:     ${GREEN}v$new_version${NC}                      ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}                                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  Обновите скрипт через меню:                    ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${BLUE}🔄 Обновить скрипт${NC}                             ${YELLOW}│${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────┘${NC}"
    echo
}
