# ═══════════════════════════════════════════════════
# ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ — ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════════
manage_extra_settings() {
    while true; do
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   ⚙️  ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        show_arrow_menu "⚙️  Дополнительные настройки" \
            "🔥  Firewall (UFW)" \
            "🌐  WARP" \
            "💾  SWAP" \
            "🚀  BBR" \
            "🛡️   Fail2ban" \
            "📝  Logrotate" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?
        [[ $choice -eq 255 ]] && return

        case $choice in
            0) manage_ufw || break ;;
            1) manage_warp || break ;;
            2) manage_swap || break ;;
            3) manage_bbr || break ;;
            4) manage_fail2ban || break ;;
            5) manage_logrotate || break ;;
            6) continue ;;
            7) return ;;
        esac
    done
}
