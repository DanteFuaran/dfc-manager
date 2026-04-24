#!/usr/bin/env bash
# Certbot --pre-hook / --post-hook: временно открыть/закрыть порт 80 для HTTP-01.
# Вызывается из cron; не зависит от интерактивного окружения dfc-manager.
_MYDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "${_MYDIR}/ufw.sh"

case "${1:-}" in
    pre)
        ufw_allow_http01_temp
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        sleep 2
        ;;
    post)
        ufw_revert_http01_temp
        iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        ;;
    *) ;;
esac
