#!/bin/bash
# ═══════════════════════════════════════════════════════════
#   DFC REMNA-INSTALL — Совместимость со старым URL
#   Новый способ установки:
#   bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/remnawave.sh)
# ═══════════════════════════════════════════════════════════

_INSTALL_DIR="/usr/local/remnawave"

# Если скрипт уже установлен — запускаем напрямую
if [ -f "${_INSTALL_DIR}/remnawave.sh" ] && [ -d "${_INSTALL_DIR}/lib" ]; then
    exec "${_INSTALL_DIR}/remnawave.sh" "$@"
fi

# Перенаправляем на актуальный скрипт (bootstrap внутри)
bash <(curl -fsSL "https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/remnawave.sh") "$@"
