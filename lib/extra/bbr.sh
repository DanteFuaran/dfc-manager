# ═══════════════════════════════════════════════════
# BBR
# ═══════════════════════════════════════════════════
manage_bbr() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}            🚀 BBR${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Проверяем текущий статус BBR
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local qdisc
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    if [ "$current_cc" = "bbr" ]; then
        print_success "BBR активен"
        echo -e "  ${WHITE}tcp_congestion_control${NC}: ${YELLOW}${current_cc}${NC}"
        echo -e "  ${WHITE}default_qdisc${NC}: ${YELLOW}${qdisc}${NC}"
        local rmem_max wmem_max tcp_ssi
        rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null)
        wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null)
        tcp_ssi=$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null)
        echo -e "  ${WHITE}rmem_max / wmem_max${NC}: ${YELLOW}$((rmem_max/1024/1024))MB / $((wmem_max/1024/1024))MB${NC}"
        if [ "$tcp_ssi" = "0" ]; then
            echo -e "  ${WHITE}slow_start_after_idle${NC}: ${YELLOW}отключён ✓${NC}"
        else
            echo -e "  ${WHITE}slow_start_after_idle${NC}: ${RED}включён (замедляет VPN)${NC}"
        fi
    else
        print_warning "BBR не активен (текущий: ${current_cc:-unknown})"
    fi
    echo

    if [ "$current_cc" = "bbr" ]; then
        # BBR включён — показываем только "Выключить"
        show_arrow_menu "🚀  Настройка BBR" \
            "❌  Выключить BBR" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?
        case $choice in
            0)
                echo
                (
                    sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1
                    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
                    # Возвращаем дефолтные буферы (без BBR большие буферы не нужны)
                    sysctl -w net.core.rmem_max=212992 >/dev/null 2>&1
                    sysctl -w net.core.wmem_max=212992 >/dev/null 2>&1
                    sysctl -w net.core.rmem_default=212992 >/dev/null 2>&1
                    sysctl -w net.core.wmem_default=212992 >/dev/null 2>&1
                    sysctl -w net.ipv4.tcp_slow_start_after_idle=1 >/dev/null 2>&1
                    sed -i '/# ─── DFC: BBR/d;
                            /net\.core\.default_qdisc/d;
                            /net\.ipv4\.tcp_congestion_control/d;
                            /net\.core\.rmem_max/d;
                            /net\.core\.wmem_max/d;
                            /net\.core\.rmem_default/d;
                            /net\.core\.wmem_default/d;
                            /net\.ipv4\.tcp_rmem/d;
                            /net\.ipv4\.tcp_wmem/d;
                            /net\.ipv4\.tcp_slow_start_after_idle/d;
                            /net\.ipv4\.tcp_mtu_probing/d;
                            /net\.ipv4\.tcp_fastopen/d;
                            /net\.ipv4\.tcp_notsent_lowat/d;
                            /net\.core\.netdev_max_backlog/d;
                            /net\.core\.somaxconn/d;
                            /net\.ipv4\.tcp_max_syn_backlog/d;
                            /Буферы сокетов/d;
                            /Не сбрасывать cwnd/d;
                            /MTU probing/d;
                            /TCP Fast Open/d;
                            /Снижение latency/d;
                            /Обработка burst/d' /etc/sysctl.conf 2>/dev/null
                    sysctl -p >/dev/null 2>&1
                ) &
                show_spinner "Выключение BBR"

                local new_cc
                new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
                if [ "$new_cc" = "cubic" ]; then
                    print_success "BBR выключен (переключено на cubic)"
                else
                    print_error "Не удалось выключить BBR"
                fi
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || return 1
                ;;
            *) return 0 ;;
        esac
    else
        # BBR выключен — показываем только "Включить"
        show_arrow_menu "🚀  Настройка BBR" \
            "✅  Включить BBR" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?
        case $choice in
            0)
                echo
                (
                    # Удаляем старые записи
                    sed -i '/# ─── DFC: BBR/d;
                            /net\.core\.default_qdisc/d;
                            /net\.ipv4\.tcp_congestion_control/d;
                            /net\.core\.rmem_max/d;
                            /net\.core\.wmem_max/d;
                            /net\.core\.rmem_default/d;
                            /net\.core\.wmem_default/d;
                            /net\.ipv4\.tcp_rmem/d;
                            /net\.ipv4\.tcp_wmem/d;
                            /net\.ipv4\.tcp_slow_start_after_idle/d;
                            /net\.ipv4\.tcp_mtu_probing/d;
                            /net\.ipv4\.tcp_fastopen/d;
                            /net\.ipv4\.tcp_notsent_lowat/d;
                            /net\.core\.netdev_max_backlog/d;
                            /net\.core\.somaxconn/d;
                            /net\.ipv4\.tcp_max_syn_backlog/d;
                            /Буферы сокетов/d;
                            /Не сбрасывать cwnd/d;
                            /MTU probing/d;
                            /TCP Fast Open/d;
                            /Снижение latency/d;
                            /Обработка burst/d' /etc/sysctl.conf 2>/dev/null
                    cat >> /etc/sysctl.conf <<'SYSCTL'

# ─── DFC: BBR + TCP оптимизация ───
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 262144 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_notsent_lowat=131072
net.core.netdev_max_backlog=4096
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
SYSTCL
                    sysctl -p >/dev/null 2>&1
                ) &
                show_spinner "Включение BBR"

                local new_cc
                new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
                if [ "$new_cc" = "bbr" ]; then
                    print_success "BBR успешно включён"
                else
                    print_error "Не удалось включить BBR"
                fi
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                show_continue_prompt || return 1
                ;;
            *) return 0 ;;
        esac
    fi
}
