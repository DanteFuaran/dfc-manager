#!/bin/bash
# Совместимость со старым URL. Новый способ установки:
# bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/dfc-remna-install.sh)

_INSTALL_DIR="/usr/local/remnawave"

# Если скрипт уже установлен — запускаем напрямую (без загрузки)
if [ -f "${_INSTALL_DIR}/dfc-remna-install.sh" ] && [ -d "${_INSTALL_DIR}/lib" ]; then
    exec "${_INSTALL_DIR}/dfc-remna-install.sh" "$@"
fi

# Скачиваем во временный файл (process substitution теряет fd при exec)
_TMP=$(mktemp /tmp/dfc-remna-XXXXXX.sh)
trap 'rm -f "$_TMP"' EXIT INT TERM
if curl -fsSL -o "$_TMP" \
    "https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/dfc-remna-install.sh" \
    2>/dev/null; then
    chmod +x "$_TMP"
    bash "$_TMP" "$@"
else
    echo -e "\033[0;31m✖ Не удалось скачать скрипт. Проверьте соединение с интернетом.\033[0m"
    exit 1
fi
