#!/bin/bash
# Совместимость со старым URL — перенаправляет на dfc-remna-install.sh
exec bash <(curl -fsSL "https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/dfc-remna-install.sh") "$@"
