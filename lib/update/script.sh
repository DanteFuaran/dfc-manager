# ═══════════════════════════════════════════════
# ОБНОВЛЕНИЕ И УДАЛЕНИЕ СКРИПТА
# ═══════════════════════════════════════════════

# ─── Удаление отдельных компонентов Remnawave ───────────────────────────────

_delete_component_panel() {
    if ! confirm_nav --delete "🗑️  Удаление панели Remnawave"; then
        return
    fi
    export DFC_UI_SPINNER_ALIGN=1
    trap 'unset DFC_UI_SPINNER_ALIGN; trap - INT TERM; trap - RETURN' RETURN
    trap '' INT TERM
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${RED}🗑️  Удаление панели Remnawave${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    (
        cd /opt/remnawave 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление панели Remnawave" "Панель Remnawave удалена"
    rm -rf /opt/remnawave

    # Обновляем nginx: минимальный конфиг или удаляем
    nginx_ensure_conf_for_remaining
    nginx_cleanup_unused_certs

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${GREEN}🗑️  Удаление панели Remnawave${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    print_success "Панель Remnawave удалена"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || true
}

_delete_component_node() {
    if ! confirm_nav --delete "🗑️  Удаление ноды Remnawave"; then
        return
    fi
    export DFC_UI_SPINNER_ALIGN=1
    trap 'unset DFC_UI_SPINNER_ALIGN; trap - INT TERM; trap - RETURN' RETURN
    trap '' INT TERM

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${RED}🗑️  Удаление ноды Remnawave${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Извлекаем инфо из nginx.conf до удаления (для перегенерации)
    local _sub_domain="" _sub_cert="" _sub_dir=""
    local _panel_domain="" _panel_cert="" _cookie_name="" _cookie_value=""

    if [ -f "/opt/subscribe-page/docker-compose.yml" ]; then
        _sub_dir="/opt/subscribe-page"
    elif [ -f "/opt/remnasubpage/docker-compose.yml" ]; then
        _sub_dir="/opt/remnasubpage"
    fi

    if [ -f "${DIR_NGINX}nginx.conf" ]; then
        # Извлекаем данные панели
        _panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
        _panel_cert=$(grep -A5 "server_name ${_panel_domain};" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -oP '/ssl/\K[^/]+' | head -1)
        [ -z "$_panel_cert" ] && _panel_cert="$_panel_domain"
        _cookie_name=$(grep -oP '~\*\K[^=]+(?==[^"]+\"\s+1)' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
        _cookie_value=$(grep -oP '~\*[^=]+=\K[^"]+(?=\"\s+1)' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)

        # Извлекаем данные subpage
        if [ -n "$_sub_dir" ]; then
            _sub_domain=$(sed -n '/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/{/server_name/{s/.*server_name\s\+//;s/;.*//;p;}}' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
            _sub_cert=$(sed -n '/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/{/ssl_certificate /{s|.*/ssl/||;s|/.*||;p;}}' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
        fi
    fi

    (
        cd /opt/remnanode 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
        rm -rf /opt/remnanode

        # Firewall: нода открывает 2222 (управление нодой). При удалении ноды закрываем эти правила.
        # 443 здесь НЕ закрываем, т.к. он может быть нужен панели/странице подписки/MT connect.
        ufw_delete_rules_by_port 2222 >/dev/null 2>&1 || true

        # Обновляем nginx: перегенерируем для оставшихся компонентов
        if is_panel_installed && [ -n "$_panel_domain" ] && [ -n "$_cookie_name" ] && [ -n "$_cookie_value" ]; then
            if [ -n "$_sub_dir" ] && [ -n "$_sub_domain" ] && [ -n "$_sub_cert" ]; then
                generate_docker_compose_panel "$_panel_cert" "$_sub_cert"
                generate_nginx_conf_panel "$_panel_domain" "$_sub_domain" \
                    "$_panel_cert" "$_sub_cert" \
                    "$_cookie_name" "$_cookie_value"
            else
                generate_docker_compose_panel_only "$_panel_cert"
                generate_nginx_conf_panel_only "$_panel_domain" "$_panel_cert" \
                    "$_cookie_name" "$_cookie_value"
            fi
            cd /opt/remnawave 2>/dev/null && docker compose up -d >/dev/null 2>&1 || true
            nginx_reload
        elif [ -n "$_sub_dir" ] && [ -n "$_sub_domain" ] && [ -n "$_sub_cert" ]; then
            generate_nginx_conf_subpage "$_sub_domain" "$_sub_cert" "$_sub_dir"
            nginx_reload
        else
            nginx_ensure_conf_for_remaining
        fi

        nginx_cleanup_unused_certs
    ) &
    show_spinner "Удаление Remnawave (Нода)" "Нода Remnawave успешно удалена!"

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${GREEN}🗑️  Удаление ноды Remnawave${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    print_success "Нода Remnawave успешно удалена!"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || true
}

_delete_component_subpage() {
    if ! confirm_nav --delete "🗑️  Удаление страницы подписки"; then
        return
    fi
    export DFC_UI_SPINNER_ALIGN=1
    trap 'unset DFC_UI_SPINNER_ALIGN; trap - INT TERM; trap - RETURN' RETURN
    trap '' INT TERM
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${RED}🗑️  Удаление страницы подписки${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Извлекаем информацию для перегенерации nginx.conf до удаления
    local _panel_domain="" _panel_cert="" _node_domain="" _node_cert="" _cookie_name="" _cookie_value=""
    if [ -f "${DIR_NGINX}nginx.conf" ]; then
        _panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "${DIR_NGINX}nginx.conf" 2>/dev/null | head -1)
        _panel_cert=$(grep -A5 "server_name ${_panel_domain};" "${DIR_NGINX}nginx.conf" 2>/dev/null | grep -oP '/ssl/\K[^/]+' | head -1)
        [ -z "$_panel_cert" ] && _panel_cert="$_panel_domain"

        # Извлекаем cookie
        _cookie_name=$(grep -oP '~\*\K[^=]+(?==[^"]+"\s+1)' "${DIR_NGINX}nginx.conf" | head -1)
        _cookie_value=$(grep -oP '~\*[^=]+=\K[^"]+(?="\s+1)' "${DIR_NGINX}nginx.conf" | head -1)

        # Извлекаем инфо о ноде (для перегенерации)
        if [ -f "/opt/remnanode/docker-compose.yml" ]; then
            _node_domain=$(awk '/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/{next} /server_name [^_]/{gsub(/.*server_name[[:space:]]+|;.*/,""); print; exit}' "${DIR_NGINX}nginx.conf" 2>/dev/null)
            _node_cert=$(awk '/# BEGIN_SUB_BLOCK/,/# END_SUB_BLOCK/{next} /ssl_certificate /{gsub(/.*\/ssl\/|\/fullchain.*|\/privkey.*/,""); print; exit}' "${DIR_NGINX}nginx.conf" 2>/dev/null)
        fi
    fi

    # Подготовка файлов: перегенерируем nginx.conf и останавливаем/удаляем subpage
    (
        # Останавливаем и удаляем subpage
        for _d in /opt/remnasubpage /opt/subscribe-page; do
            [ -d "$_d" ] || continue
            [ -f "${_d}/docker-compose.yml" ] && { cd "$_d" 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1 || true; }
            rm -rf "$_d" 2>/dev/null || true
        done

        # Также удаляем subscription-page из docker-compose панели/ноды если он встроен
        if is_panel_installed; then
            cd /opt/remnawave 2>/dev/null && docker compose rm -sf remnawave-subscription-page >/dev/null 2>&1 || true
            # SUB_PUBLIC_DOMAIN обязателен для панели — ставим fallback на домен панели
            if [ -n "$_panel_domain" ]; then
                sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$_panel_domain|" /opt/remnawave/.env 2>/dev/null || true
                grep -q '^SUB_PUBLIC_DOMAIN=' /opt/remnawave/.env 2>/dev/null || \
                    echo "SUB_PUBLIC_DOMAIN=$_panel_domain" >> /opt/remnawave/.env
            fi
        fi
        if [ -f "/opt/remnanode/docker-compose.yml" ]; then
            cd /opt/remnanode 2>/dev/null && docker compose rm -sf remnawave-subscription-page >/dev/null 2>&1 || true
        fi

        # Перегенерируем конфиги для оставшихся компонентов
        if is_panel_installed && [ -n "$_panel_domain" ] && [ -n "$_cookie_name" ] && [ -n "$_cookie_value" ]; then
            if [ -f "/opt/remnanode/docker-compose.yml" ] && [ -n "$_node_domain" ] && [ -n "$_node_cert" ]; then
                # Панель + нода (без subpage)
                _node_port=$(grep -oE 'NODE_PORT=[0-9]+' /opt/remnanode/docker-compose.yml 2>/dev/null | head -1 | cut -d= -f2)
                generate_docker_compose_panel_with_node "$_panel_cert" "$_node_cert" "${_node_port:-2222}"
                generate_nginx_conf_panel_with_node "$_panel_domain" "$_node_domain" \
                    "$_panel_cert" "$_node_cert" \
                    "$_cookie_name" "$_cookie_value"
            else
                # Только панель (без subpage)
                generate_docker_compose_panel_only "$_panel_cert"
                generate_nginx_conf_panel_only "$_panel_domain" "$_panel_cert" \
                    "$_cookie_name" "$_cookie_value"
            fi
            # Перезапускаем панель с обновлённым docker-compose
            cd /opt/remnawave 2>/dev/null && docker compose up -d >/dev/null 2>&1 || true
            nginx_reload
        elif [ -f "/opt/remnanode/docker-compose.yml" ] && [ -n "$_node_domain" ] && [ -n "$_node_cert" ]; then
            generate_nginx_conf_node "$_node_domain" "$_node_cert"
            cd /opt/remnanode 2>/dev/null && docker compose up -d >/dev/null 2>&1 || true
            nginx_reload
        fi
    ) &
    show_spinner "Подготовка файлов"

    nginx_cleanup_unused_certs

    local _sub_del_err=""
    # Ждём доступности панели (проверяем напрямую, т.к. nginx требует cookie)
    if [ -n "$_panel_domain" ]; then
        if ! show_spinner_until_ready "http://127.0.0.1:3001/health" "Запуск панели" 90; then
            _sub_del_err="Панель не отвечает после перезапуска. Проверьте состояние сервисов."
        fi
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    if [ -z "$_sub_del_err" ]; then
        echo -e "    ${GREEN}🗑️  Удаление страницы подписки${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        print_success "Страница подписки удалена"
    else
        echo -e "    ${RED}🗑️  Удаление страницы подписки${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        print_error "$_sub_del_err"
    fi
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    show_continue_prompt || true
}

# ─── Меню удаления всех компонентов ─────────────────────────────────────────

manage_delete_components() {
    while true; do
        tput civis 2>/dev/null || true
        local -a del_items=() del_actions=()

        is_panel_installed && {
            del_items+=("🖥️   Remnawave (Панель)"); del_actions+=("panel")
        }
        [ -f "/opt/remnanode/docker-compose.yml" ] && {
            del_items+=("🌐  Remnawave (Нода)"); del_actions+=("node")
        }
        ([ -f "/opt/remnasubpage/docker-compose.yml" ] || [ -f "/opt/subscribe-page/docker-compose.yml" ]) && {
            del_items+=("📄  Remnawave (Страница подписки)"); del_actions+=("subpage")
        }
        [ -f "/opt/beszel/docker-compose.yml" ] && {
            del_items+=("📊  Beszel (Мониторинг)"); del_actions+=("beszel")
        }
        [ -f "/opt/beszel-agent/docker-compose.yml" ] && {
            del_items+=("📊  Beszel (Агент)"); del_actions+=("beszel_agent")
        }
        _mt_installed && {
            del_items+=("📡  MTProto (Прокси)"); del_actions+=("mtproto")
        }

        # Ничего не осталось — показываем экран с сообщением
        if [ ${#del_actions[@]} -eq 0 ]; then
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${RED}   🗑️   Удаление компонентов${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo
            echo -e "  🔍  Компоненты не установлены"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt || true
            return
        fi

        del_items+=("──────────────────────────────────────"); del_actions+=("sep")
        if [ ${#del_actions[@]} -gt 1 ]; then
            del_items+=("🗑️   Удалить всё"); del_actions+=("delete_all")
            del_items+=("──────────────────────────────────────"); del_actions+=("sep")
        fi
        del_items+=("⬅️   Назад"); del_actions+=("back")

        show_arrow_menu "🗑️  Удаление компонентов" "${del_items[@]}"
        local del_choice=$?
        [[ $del_choice -eq 255 ]] && return
        local del_action="${del_actions[$del_choice]:-sep}"

        case "$del_action" in
            panel)        _delete_component_panel ;;
            node)         _delete_component_node ;;
            subpage)      _delete_component_subpage ;;
            beszel)       uninstall_beszel ;;
            beszel_agent) uninstall_beszel_agent ;;
            mtproto)      _mt_do_uninstall || true ;;
            delete_all)
                if ! confirm_nav --delete "🗑️  Удаление всех компонентов"; then
                    continue
                fi
                trap '' INT TERM
                (
                export DFC_UI_SPINNER_ALIGN=1
                if is_panel_installed; then
                    ( cd /opt/remnawave 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1 || true; rm -rf /opt/remnawave 2>/dev/null || true ) &
                    show_spinner --step "Удаление Remnawave (Панель)" "Удаление Remnawave (Панель)"
                fi
                if is_node_installed; then
                    ( cd /opt/remnanode 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1 || true; rm -rf /opt/remnanode 2>/dev/null || true ) &
                    show_spinner --step "Удаление Remnawave (Нода)" "Удаление Remnawave (Нода)"
                fi
                if is_subpage_remote_installed || [ -d "/opt/subscribe-page" ] || [ -d "/opt/remnasubpage" ]; then
                    ( for _d in /opt/subscribe-page /opt/remnasubpage; do
                        [ -d "$_d" ] || continue
                        [ -f "${_d}/docker-compose.yml" ] && { cd "$_d" 2>/dev/null && docker compose down -v --rmi all >/dev/null 2>&1 || true; }
                        rm -rf "$_d" 2>/dev/null || true
                      done; exit 0 ) &
                    show_spinner --step "Удаление Remnawave (Страница подписки)" "Удаление Remnawave (Страница подписки)"
                fi
                if [ -f "/opt/beszel/docker-compose.yml" ]; then
                    ( uninstall_beszel --force >/dev/null 2>&1 || true ) &
                    show_spinner --step "Удаление Beszel" "Beszel удалён"
                fi
                if [ -f "/opt/beszel-agent/docker-compose.yml" ]; then
                    ( uninstall_beszel_agent --force >/dev/null 2>&1 || true ) &
                    show_spinner --step "Удаление Beszel Agent" "Beszel Agent удалён"
                fi
                # Удаляем MTProto даже если контейнер уже снят, но есть остаточные
                # файлы (/opt/mtproto) или nginx-блоки MT_CONNECT_*.
                if _mt_installed || [ -d "/opt/mtproto" ] || \
                   grep -q "# BEGIN_MT_CONNECT_\|# BEGIN_MTPROTO_STREAM" "${DIR_NGINX}nginx.conf" 2>/dev/null; then
                    ( _mt_do_uninstall --force >/dev/null 2>&1 || true ) &
                    show_spinner --step "Удаление MTProto" "MTProto удалён"
                fi
                # Firewall: оставляем только allow SSH, остальные пронумерованные правила удаляем.
                ( ufw_delete_all_rules_except_ssh >/dev/null 2>&1 || true ) &
                show_spinner --step "Очистка Firewall (UFW)" "Очистка Firewall (UFW)"
                ( _nginx_extract_external_blocks 2>/dev/null; nginx_ensure_conf_for_remaining 2>/dev/null || true; nginx_cleanup_unused_certs 2>/dev/null || true ) &
                show_spinner --step "Очистка Nginx" "Nginx очищен"
                )
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "$(center "🗑️  Удаление завершено" "$GREEN")"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                echo -e "$(center "✅ Все компоненты были удалены" "$GREEN")"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                stty sane 2>/dev/null || true
                tput cnorm 2>/dev/null || true
                trap - INT TERM
                show_continue_prompt || true
                return
                ;;
            back)         return ;;
            sep)          continue ;;
        esac
    done
}

# Создаёт бинарные лаунчеры rw/dfc — исправляет ошибку
# "shell-init: error retrieving current directory: getcwd: cannot access parent directories"
# когда CWD пересоздана Docker'ом (например /opt/remnanode удалена и создана заново).
# Компилируем статический C-бинарник: он вызывает chdir("/opt") до любых shell-инициализаций.
_install_bin_wrappers() {
    ln -sf "${DIR_SCRIPT}dfc-manager.sh" /usr/local/bin/dfc-manager 2>/dev/null || true

    local _launcher_src="/tmp/.dfc_launcher_$$.c"
    local _launcher_bin="/tmp/.dfc_launcher_$$"

    cat > "$_launcher_src" << 'CSRC'
#include <unistd.h>
#define SCRIPT "/usr/local/dfc-manager/dfc-manager.sh"
int main(int argc, char *argv[], char *envp[]) {
    chdir("/opt");
    argv[0] = SCRIPT;
    execve(SCRIPT, argv, envp);
    return 1;
}
CSRC

    local _compiled=0
    # Пробуем статическую компиляцию (бинарь работает без зависимостей)
    if command -v gcc >/dev/null 2>&1; then
        gcc -O2 -static -o "$_launcher_bin" "$_launcher_src" 2>/dev/null && _compiled=1
    fi
    if [ "$_compiled" -eq 0 ] && command -v cc >/dev/null 2>&1; then
        cc -O2 -static -o "$_launcher_bin" "$_launcher_src" 2>/dev/null && _compiled=1
    fi
    # Если статика недоступна (нет libc-static) — динамическая компиляция
    if [ "$_compiled" -eq 0 ] && command -v gcc >/dev/null 2>&1; then
        gcc -O2 -o "$_launcher_bin" "$_launcher_src" 2>/dev/null && _compiled=1
    fi
    if [ "$_compiled" -eq 0 ] && command -v cc >/dev/null 2>&1; then
        cc -O2 -o "$_launcher_bin" "$_launcher_src" 2>/dev/null && _compiled=1
    fi
    rm -f "$_launcher_src"

    for _cmd in dfc rw; do
        # Удаляем симлинк/файл ПЕРЕД установкой — иначе cp следует за симлинком
        # и перезаписывает dfc-manager.sh вместо создания нового файла
        rm -f "/usr/local/bin/${_cmd}"
        if [ "$_compiled" -eq 1 ]; then
            cp "$_launcher_bin" "/usr/local/bin/${_cmd}"
            chmod +x "/usr/local/bin/${_cmd}"
        elif command -v python3 >/dev/null 2>&1; then
            # Python3 fallback: делает chdir до запуска bash, не печатает getcwd-ошибки
            printf '#!/usr/bin/env python3\nimport os,sys\nos.chdir("/opt")\nos.execvpe("/usr/local/dfc-manager/dfc-manager.sh",["/usr/local/dfc-manager/dfc-manager.sh"]+sys.argv[1:],os.environ)\n' \
                > "/usr/local/bin/${_cmd}"
            chmod +x "/usr/local/bin/${_cmd}"
        else
            # Последний резерв: bash-обёртка (bash мягче обрабатывает getcwd чем sh)
            printf '#!/bin/bash\ncd /opt 2>/dev/null || cd / 2>/dev/null || true\nexec /usr/local/dfc-manager/dfc-manager.sh "$@"\n' \
                > "/usr/local/bin/${_cmd}"
            chmod +x "/usr/local/bin/${_cmd}"
        fi
    done
    rm -f "$_launcher_bin"
}

install_script() {
    mkdir -p "${DIR_SCRIPT}"

    cleanup_old_aliases

    # Уже установлен — только актуализируем симлинки
    if [ -d "${DIR_SCRIPT}lib" ]; then
        chmod +x "${DIR_SCRIPT}dfc-manager.sh"
        _install_bin_wrappers
        return
    fi

    # Первичная установка — скачиваем полный архив (ветка берётся из $SCRIPT_BRANCH → version-файл)
    if ! curl -sL --connect-timeout 15 --max-time 120 "https://github.com/DanteFuaran/dfc-manager/archive/refs/heads/${SCRIPT_BRANCH}.tar.gz" \
        | tar -xz -C "${DIR_SCRIPT}" --strip-components=1; then
        print_error "Не удалось скачать скрипт"
        exit 1
    fi

    chmod +x "${DIR_SCRIPT}dfc-manager.sh"
    _install_bin_wrappers
}

update_script() {
    local force_update="${1:-}"
    clear
    printf "\033[1;34m══════════════════════════════════════\033[0m\n"
    printf "\033[32m        🔄  Обновление скрипта\033[0m\n"
    printf "\033[1;34m══════════════════════════════════════\033[0m\n"
    echo

    local installed_version="${SCRIPT_VERSION}"

    # Читаем версию из кэша, который уже записал check_for_updates при запуске
    # Если файла нет — делаем свежий запрос к сети
    local remote_version
    if [ -f "${UPDATE_AVAILABLE_FILE}" ]; then
        remote_version=$(cat "${UPDATE_AVAILABLE_FILE}")
    else
        remote_version=$(get_remote_version)
    fi
    # Если не удалось получить — показываем текущую
    [ -z "$remote_version" ] && remote_version="$installed_version"

    printf "\033[37mУстановленная версия: v%s\033[0m\n" "$installed_version"

    if [ -n "$remote_version" ] && [ "$remote_version" != "$installed_version" ]; then
        printf "\033[37mДоступная версия:     \033[32mv%s\033[0m\n" "$remote_version"
    elif [ -n "$remote_version" ]; then
        printf "\033[37mДоступная версия:     v%s\033[0m\n" "$remote_version"
    else
        # Нет кеша и сеть недоступна — показываем установленную версию как актуальную
        remote_version="$installed_version"
        printf "\033[37mДоступная версия:     v%s\033[0m\n" "$remote_version"
    fi
    echo
    printf "\033[1;30m──────────────────────────────────────\033[0m\n"

    if [ "$force_update" != "force" ] && [ "$installed_version" = "$remote_version" ]; then
        echo
        print_success "У вас уже установлена последняя версия"
        echo
        printf "\033[1;34m══════════════════════════════════════\033[0m\n"
        show_continue_prompt
        return 0
    fi

    printf "\033[1;30m \033[1;34mEnter\033[1;30m: Обновить     \033[1;34mEsc\033[1;30m: Отмена\033[0m\n"
    # Сбрасываем буфер stdin — чтобы Enter из меню не засчитался как подтверждение
    read -s -r -t 0.1 _flush 2>/dev/null || true
    tput civis
    local _key
    while true; do
        read -s -n 1 _key
        if [[ "$_key" == $'\x1b' ]]; then
            tput cnorm
            return 0
        elif [[ "$_key" == "" ]]; then
            tput cnorm
            # Возвращаемся на строку навигации и очищаем её
            tput cuu1
            printf "\033[K\n"
            break
        fi
    done

    (
        rm -rf "${DIR_SCRIPT}"
        mkdir -p "$(dirname "${DIR_SCRIPT%/}")"
        git clone --depth 1 -b "${SCRIPT_BRANCH}" "${SCRIPT_REPO}" "${DIR_SCRIPT%/}" >/dev/null 2>&1
        chmod +x "${DIR_SCRIPT}dfc-manager.sh"
        _install_bin_wrappers
    ) &
    show_spinner "Загрузка обновлений"

    if [ -f "${DIR_SCRIPT}dfc-manager.sh" ]; then
        # Гарантируем наличие version файла (в директории скрипта)
        if [ ! -f "${DIR_SCRIPT}version" ] || ! grep -q '^version:' "${DIR_SCRIPT}version" 2>/dev/null; then
            printf 'version: %s\nbranch: %s\nrepo: %s\n' \
                "${remote_version}" "${SCRIPT_BRANCH}" "${SCRIPT_REPO}" \
                > "${DIR_SCRIPT}version"
        fi

        rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
        print_success "Скрипт успешно обновлён до версии v$remote_version"
        echo
        printf "\033[1;34m══════════════════════════════════════\033[0m\n"
        show_continue_prompt || return 0
        exec /usr/local/bin/dfc-manager
    else
        print_error "Ошибка при обновлении скрипта"
        echo
        printf "\033[1;34m══════════════════════════════════════\033[0m\n"
        show_continue_prompt
        return 1
    fi
}

remove_script_all() {
    if ! confirm_nav --delete "💣 Удаление скрипта и данных"; then
        return 1
    fi

    (
    export DFC_UI_SPINNER_ALIGN=1
    echo

    # Beszel Hub
    if [ -f "/opt/beszel/docker-compose.yml" ]; then
        (
            cd /opt/beszel 2>/dev/null
            docker compose down -v --rmi all >/dev/null 2>&1 || true
            nginx_remove_server_block "BESZEL" 2>/dev/null || true
            if nginx_has_users; then
                nginx_reload
            else
                nginx_teardown
            fi
        ) &
        show_spinner "Удаление Beszel"
        rm -rf /opt/beszel
    fi

    # Beszel Agent
    if [ -f "/opt/beszel-agent/docker-compose.yml" ]; then
        local AGENT_PORT
        AGENT_PORT=$(cat /opt/beszel-agent/port 2>/dev/null)
        (
            cd /opt/beszel-agent 2>/dev/null
            docker compose down -v --rmi all >/dev/null 2>&1 || true
        ) &
        show_spinner --step "Удаление агента Beszel"
        [ -n "$AGENT_PORT" ] && ufw delete allow "${AGENT_PORT}/tcp" >/dev/null 2>&1 || true
        rm -rf /opt/beszel-agent
    fi

    # WARP
    if ip link show warp >/dev/null 2>&1; then
        (
            wg-quick down warp >/dev/null 2>&1 || true
            systemctl disable wg-quick@warp >/dev/null 2>&1 || true
            rm -f /etc/wireguard/warp.conf /usr/local/bin/wgcf \
                  /tmp/wgcf-account.toml /tmp/wgcf-profile.conf 2>/dev/null || true
            DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y wireguard >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
        ) &
        show_spinner "Удаление WARP"
        local WARP_PORT
        WARP_PORT=$(cat /etc/wireguard/.warp_port 2>/dev/null)
        [ -n "$WARP_PORT" ] && ufw delete allow "${WARP_PORT}/tcp" >/dev/null 2>&1 || true
        rm -f /etc/wireguard/.warp_port 2>/dev/null || true
    fi

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        (
            ufw disable >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get purge -y ufw >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
        ) &
        show_spinner "Удаление UFW"
    fi

    # Remnawave
    (
        [ -d "${DIR_PANEL}" ] && cd "${DIR_PANEL}" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        [ -d "/opt/remnasubpage" ] && cd "/opt/remnasubpage" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        [ -d "/opt/subscribe-page" ] && cd "/opt/subscribe-page" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        [ -d "${DIR_NODE}" ] && cd "${DIR_NODE}" && docker compose down -v --rmi all >/dev/null 2>&1 || true
        docker system prune -af >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление контейнеров Remnawave"
    _nginx_extract_external_blocks 2>/dev/null || true
    nginx_ensure_conf_for_remaining
    rm -rf "${DIR_PANEL}"
    rm -rf "/opt/remnasubpage"
    rm -rf "/opt/subscribe-page"
    rm -rf "${DIR_NODE}"
    rm -f /usr/local/bin/dfc-manager
    rm -f /usr/local/bin/dfc
    rm -f /usr/local/bin/rw
    rm -rf "${DIR_SCRIPT}"
    rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
    cleanup_old_aliases
    print_success "Скрипт и все данные удалены"
    echo
    )
    exit 0
}

remove_script() {
    if ! confirm_nav --delete "🗑️  Удаление скрипта"; then
        return
    fi

    rm -f /usr/local/bin/dfc-manager
    rm -f /usr/local/bin/dfc
    rm -f /usr/local/bin/rw
    rm -rf "${DIR_SCRIPT}"
    rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
    cleanup_old_aliases
    echo
    print_success "Скрипт удалён с сервера"
    echo
    exit 0
}
