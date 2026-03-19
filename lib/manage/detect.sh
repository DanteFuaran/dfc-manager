# ═══════════════════════════════════════════════
# ОПРЕДЕЛЕНИЕ ПУТИ К REMNAWAVE
# ═══════════════════════════════════════════════

# Проверяет, установлена ли панель (/opt/remnawave)
is_panel_installed() {
    [ -f "/opt/remnawave/docker-compose.yml" ]
}

# Проверяет, установлена ли нода (/opt/remnanode или как сервис в /opt/remnawave)
is_node_installed() {
    [ -f "/opt/remnanode/docker-compose.yml" ] || \
        grep -q 'container_name: remnanode' "/opt/remnawave/docker-compose.yml" 2>/dev/null
}

# Проверяет, установлена ли удалённая страница подписки
# (standalone в /opt/remnasubpage или добавлена к ноде в /opt/remnanode)
is_subpage_remote_installed() {
    [ -f "/opt/remnasubpage/docker-compose.yml" ] || \
        grep -q 'remnawave-subscription-page' "/opt/remnanode/docker-compose.yml" 2>/dev/null
}

# Возвращает путь к установленному компоненту:
# сначала /opt/remnawave (панель), затем /opt/remnanode (нода).
# Если ничего не найдено — выводит ошибку и возвращает 1.
detect_remnawave_path() {
    if is_panel_installed; then
        echo "/opt/remnawave"
        return 0
    fi
    if is_node_installed; then
        echo "/opt/remnanode"
        return 0
    fi
    if [ -f "/opt/remnasubpage/docker-compose.yml" ]; then
        echo "/opt/remnasubpage"
        return 0
    fi
    print_error "Remnawave не найдена. Убедитесь, что панель или нода установлены."
    return 1
}
