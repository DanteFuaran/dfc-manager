# ═══════════════════════════════════════════════
# УТИЛИТЫ ВЫВОДА
# ═══════════════════════════════════════════════

print_action()  { :; }
print_error()   { printf "${RED}✖  %b${NC}\n" "$1"; }
# Как у show_spinner: зелёная галочка с колонки 0, текст сообщения обычным цветом
print_success() { printf "${GREEN}\u2705${NC}\033[0m %b\n" "$1"; }
print_final_success() { printf "${GREEN}✅ %b${NC}\n" "$1"; }
print_warning() { printf "${YELLOW}⚠️  %b${NC}\n" "$1"; }
print_cert_exists() { printf "${GREEN}✅ Сертификат для %s уже существует${NC}\n" "$1"; }

# Центрирует текст в 38-символьную ширину для боксов ══════════════════════════════════════
# Использование: center "текст" "$COLOR"
center() {
    local text="$1"
    local color="${2:-}"
    local width=38
    local n=${#text}
    local pl=$(( (width - n) / 2 ))
    local pr=$(( width - pl - n ))
    [ $pl -lt 0 ] && pl=0
    [ $pr -lt 0 ] && pr=0
    printf "%*s${color}%s${NC}%*s\n" $pl "" "$text" $pr ""
}

# Сбрасывает буферизованный ввод (например, клавиши, нажатые во время спиннеров)
_flush_stdin() {
    local _dummy _chunk
    while IFS= read -rsn1 -t 0 _dummy 2>/dev/null; do true; done
    while IFS= read -r -t 0 -N 4096 _chunk 2>/dev/null && [ -n "$_chunk" ]; do true; done
    true
}

# Перед интерактивным промптом: stdin + управляющий терминал (клавиши могут идти в /dev/tty при «особом» fd 0)
_dfc_prompt_prepare_input() {
    _flush_stdin
    [ ! -r /dev/tty ] && return 0
    local _d _c
    while IFS= read -r -s -N 1 -t 0 _d </dev/tty 2>/dev/null; do true; done
    while IFS= read -r -t 0 -N 4096 _c </dev/tty 2>/dev/null && [ -n "$_c" ]; do true; done
}

# Сброс входного буфера TTY в ядре (read -t 0 не всегда вычищает icanon-хвост от Enter во время спиннеров)
_dfc_tcflush_dev_tty() {
    [ ! -r /dev/tty ] && return 0
    command -v python3 >/dev/null 2>&1 || return 0
    python3 -c 'import os,termios; f=os.open("/dev/tty",os.O_RDWR); termios.tcflush(f,termios.TCIFLUSH); os.close(f)' 2>/dev/null || true
}

# FD дубликата /dev/tty для show_continue_prompt (закрыть при Ctrl+C и EXIT)
_DFC_CONTINUE_PROMPT_TTYFD=""

dfc_close_continue_prompt_ttyfd() {
    if [[ "${_DFC_CONTINUE_PROMPT_TTYFD:-}" =~ ^[0-9]+$ ]]; then
        eval "exec ${_DFC_CONTINUE_PROMPT_TTYFD}>&-" 2>/dev/null || true
        _DFC_CONTINUE_PROMPT_TTYFD=""
    fi
}

# Одиночные клавиши (промпты, меню). -echoctl: иначе после stty sane Esc на экране как ^[
_dfc_stty_cbreak_prompt() {
    local _tin="${1-}"
    if [ -n "$_tin" ]; then
        if ! stty -F "$_tin" -icanon -echo -echoctl isig min 1 time 0 2>/dev/null; then
            stty -F "$_tin" -icanon -echo isig min 1 time 0 2>/dev/null || true
        fi
    else
        if ! stty -icanon -echo -echoctl isig min 1 time 0 2>/dev/null; then
            stty -icanon -echo isig min 1 time 0 2>/dev/null || true
        fi
    fi
}

# После перевода TTY в cbreak: вычитать весь накопленный ввод (Enter во время спиннеров в icanon и т.п.).
# Восстанавливает min 1 time 0 и режим из _dfc_stty_cbreak_prompt.
_dfc_drain_tty_after_cbreak() {
    local _tin="${1-}"
    local _b
    if [ -n "$_tin" ]; then
        stty -F "$_tin" min 0 time 0 2>/dev/null || return 0
        while IFS= read -r -s -N 1 -t 0 _b < "$_tin" 2>/dev/null; do :; done
        _dfc_stty_cbreak_prompt "$_tin"
    else
        stty min 0 time 0 2>/dev/null || return 0
        while IFS= read -r -s -N 1 -t 0 _b 2>/dev/null; do :; done
        _dfc_stty_cbreak_prompt ""
    fi
}

# Docker Compose может открыть /dev/tty даже при закрытом stdin — новая сессия + без «TTY»-режима вывода.
# Без setsid фоновый клиент при обращении к терминалу может получить SIGTTIN и остановиться (спиннер «висит»).
_dfc_detach_run() {
    CI=true DOCKER_PROGRESS=plain DOCKER_CLI_HINTS=false COMPOSE_ANSI=never \
        _dfc_setsid_exec "$@"
}

# Выполнить команду в отдельной сессии (setsid или эквивалент через python3).
_dfc_setsid_exec() {
    if command -v setsid >/dev/null 2>&1; then
        exec setsid "$@"
    elif command -v python3 >/dev/null 2>&1; then
        exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"
    else
        exec "$@"
    fi
}

# Спиннер: отключаем только локальный echo — иначе Enter/символы во время анимации дают лишние строки на экране.
# Режим ввода (icanon/isig) не меняем; ввод не «съедается».
_spinner_lock_input() {
    _SPINNER_STTY=""
    _SPINNER_TTY_F=""
    if [ -t 0 ]; then
        _SPINNER_STTY=$(stty -g 2>/dev/null || echo "")
        stty -echo -echoctl 2>/dev/null || stty -echo 2>/dev/null || true
    elif [ -r /dev/tty ]; then
        _SPINNER_TTY_F=/dev/tty
        _SPINNER_STTY=$(stty -F "$_SPINNER_TTY_F" -g 2>/dev/null || echo "")
        stty -F "$_SPINNER_TTY_F" -echo -echoctl 2>/dev/null || stty -F "$_SPINNER_TTY_F" -echo 2>/dev/null || true
    fi
    tput civis 2>/dev/null || true
}

# Фон остановлен по SIGTTIN/SIGTTOU: родитель может быть в S, а остановлен — любой процесс в той же pgrp.
# Раньше смотрели только лидера $pid — дочерний docker/compose оставался в T, wait висел бесконечно.
_spinner_unstick_background_pid() {
    local _p="${1:?}" _pgid _line _killg=false
    kill -0 "$_p" 2>/dev/null || return 0
    _pgid=$(LC_ALL=C ps -o pgid= -p "$_p" 2>/dev/null | tr -d ' ')
    [ -n "$_pgid" ] || _pgid="$_p"
    # Только базовое состояние (первый символ STAT): T/t = остановлен. Шаблон *t* давал ложные срабатывания.
    if LC_ALL=C ps -g "$_pgid" -o stat= >/dev/null 2>&1; then
        while IFS= read -r _line; do
            _line=$(printf '%s' "$_line" | tr -d ' ')
            [ -z "$_line" ] && continue
            case "${_line:0:1}" in T|t) _killg=true; break ;; esac
        done < <(LC_ALL=C ps -g "$_pgid" -o stat= 2>/dev/null || true)
    else
        while IFS= read -r _line; do
            _line=$(printf '%s' "$_line" | tr -d ' ')
            [ -z "$_line" ] && continue
            case "${_line:0:1}" in T|t) _killg=true; break ;; esac
        done < <(LC_ALL=C ps -o stat= -p "$_p" 2>/dev/null || true)
    fi
    if [ "$_killg" = true ]; then
        kill -KILL -- "-${_pgid}" 2>/dev/null || kill -KILL -- "-${_p}" 2>/dev/null || kill -KILL "$_p" 2>/dev/null || true
    fi
}

_spinner_unlock_input() {
    if [ -n "${_SPINNER_STTY:-}" ]; then
        if [ -n "${_SPINNER_TTY_F:-}" ]; then
            stty -F "$_SPINNER_TTY_F" "$_SPINNER_STTY" 2>/dev/null || stty -F "$_SPINNER_TTY_F" sane 2>/dev/null || true
        else
            stty "$_SPINNER_STTY" 2>/dev/null || stty sane 2>/dev/null || true
        fi
    fi
    _SPINNER_STTY=""
    _SPINNER_TTY_F=""
    if [ -z "${KEEP_CURSOR_HIDDEN:-}" ]; then
        tput cnorm 2>/dev/null || true
    fi
}

# ═══════════════════════════════════════════════
# СПИННЕРЫ
# ═══════════════════════════════════════════════

# Спиннер подготовки к запуску: синий, без финального сообщения
show_spinner_prepare() {
    local pid=$!
    local delay=0.08
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0 msg="$1"
    _SPINNER_INTERRUPTED=0
    trap '_SPINNER_INTERRUPTED=1' INT
    _spinner_lock_input
    while kill -0 $pid 2>/dev/null && [ "${_SPINNER_INTERRUPTED:-0}" != 1 ]; do
        _spinner_unstick_background_pid "$pid"
        printf "\r\033[K${BLUE}%s${NC}\033[0m  ${BLUE}%s${NC}" "${spin[$i]}" "$msg"
        i=$(( (i+1) % 10 ))
        sleep $delay || true
    done
    if [ "${_SPINNER_INTERRUPTED:-0}" = 1 ]; then
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        wait $pid 2>/dev/null || true
        printf "\r\033[K"
        _spinner_unlock_input
        dfc_restore_interrupt_traps
        printf "${YELLOW}Прервано (Ctrl+C).${NC}\n" >&2
        return 130
    fi
    wait $pid 2>/dev/null || true
    _spinner_unlock_input
    dfc_restore_interrupt_traps
    printf "\r\033[K"
}

# Спиннер длительной операции. Финальная строка по умолчанию — зелёная.
# Фоновую работу запускайте с закрытым stdin: ( команды ) </dev/null &
# Для docker compose внутри фона вызывайте _dfc_detach_run docker compose …
# Явный PID: ( … ) </dev/null &  show_spinner --pid $! "Сообщение" [done_msg]
#   show_spinner "Сообщение" [done_msg]
# Промежуточный шаг: зелёный спиннер/галочка, текст NC (финальные баннеры скриптов — отдельно):
#   show_spinner --step "Сообщение" [done_msg]
# Цепочка фаз (--chain): при успехе только очистить строку (без ✅), следующий спиннер — на её месте:
#   show_spinner --step --chain "Фаза 1"; show_spinner --step --chain "Фаза 2"; …
# Если KEEP_CURSOR_HIDDEN=1 — после спиннера курсор снова скрыт (между шагами установки не мелькает).
show_spinner() {
    local _step_nc=false
    local _chain=false
    local _spin_pid=""
    while [[ "${1:-}" == "--step" || "${1:-}" == "--chain" || "${1:-}" == "--pid" ]]; do
        case "$1" in
            --step)  _step_nc=true; shift ;;
            --chain) _chain=true; shift ;;
            --pid)   _spin_pid="${2:?}"; shift 2 ;;
            *) break ;;
        esac
    done
    local pid="${_spin_pid:-$!}"
    if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]]; then
        printf "${RED}\u2716 show_spinner: нет PID фоновой задачи${NC}\n" >&2
        return 1
    fi
    local delay=0.08
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0 msg="${1:?}" done_msg="${2:-$1}"
    tput civis 2>/dev/null || true
    _SPINNER_INTERRUPTED=0
    trap '_SPINNER_INTERRUPTED=1' INT
    _spinner_lock_input
    while kill -0 $pid 2>/dev/null && [ "${_SPINNER_INTERRUPTED:-0}" != 1 ]; do
        _spinner_unstick_background_pid "$pid"
        # Если какая-то команда случайно включила курсор (cnorm) — прячем обратно.
        tput civis 2>/dev/null || true
        if [ "$_step_nc" = true ]; then
            printf "\r\033[K${GREEN}%s${NC}\033[0m  %s" "${spin[$i]}" "$msg"
        else
            printf "\r\033[K${GREEN}%s${NC}\033[0m  %s" "${spin[$i]}" "$msg"
        fi
        i=$(( (i+1) % 10 ))
        sleep $delay || true
    done
    if [ "${_SPINNER_INTERRUPTED:-0}" = 1 ]; then
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        wait $pid 2>/dev/null || true
        printf "\r\033[K"
        _spinner_unlock_input
        dfc_restore_interrupt_traps
        printf "${YELLOW}Операция прервана (Ctrl+C).${NC}\n" >&2
        return 130
    fi
    local exit_code=0
    wait $pid 2>/dev/null || exit_code=$?
    if [ $exit_code -eq 0 ]; then
        if [ "$_chain" = true ]; then
            printf "\r\033[K"
        elif [ "$_step_nc" = true ]; then
            printf "\r\033[K${GREEN}\u2705${NC}\033[0m %s\n" "$done_msg"
        else
            printf "\r\033[K${GREEN}\u2705${NC}\033[0m %s\n" "$done_msg"
        fi
    else
        printf "\r\033[K${RED}\u2716 %s${NC}\n" "$done_msg"
    fi
    _spinner_unlock_input
    dfc_restore_interrupt_traps
    return $exit_code
}

show_spinner_timer() {
    local seconds=$1
    local msg="$2"
    local done_msg="${3:-$msg}"
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local delay=0.08
    local elapsed=0
    _SPINNER_INTERRUPTED=0
    trap '_SPINNER_INTERRUPTED=1' INT
    _spinner_lock_input
    while [ $elapsed -lt $seconds ] && [ "${_SPINNER_INTERRUPTED:-0}" != 1 ]; do
        local remaining=$((seconds - elapsed))
        for ((j=0; j<12; j++)); do
            [ "${_SPINNER_INTERRUPTED:-0}" = 1 ] && break
            tput civis 2>/dev/null || true
            printf "\r\033[K${GREEN}%s${NC}\033[0m  %s ${DARKGRAY}(%d сек)${NC}" "${spin[$i]}" "$msg" "$remaining"
            sleep $delay || true
            i=$(( (i+1) % 10 ))
        done
        elapsed=$((elapsed + 1))
    done
    if [ "${_SPINNER_INTERRUPTED:-0}" = 1 ]; then
        printf "\r\033[K"
        _spinner_unlock_input
        dfc_restore_interrupt_traps
        printf "${YELLOW}Операция прервана (Ctrl+C).${NC}\n" >&2
        return 130
    fi
    printf "\r\033[K${GREEN}\u2705${NC}\033[0m %s\n" "$done_msg"
    _spinner_unlock_input
    dfc_restore_interrupt_traps
}

show_spinner_until_ready() {
    local url="$1"
    local msg="$2"
    local timeout=${3:-120}
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0 delay=0.08
    local _done_file
    _done_file=$(mktemp)

    # Фоновый процесс: проверяет URL раз в секунду, не блокируя анимацию
    (
        local t=0
        while [ $t -lt "$timeout" ]; do
            if curl -s -f --max-time 3 "$url" \
                --header 'X-Forwarded-For: 127.0.0.1' \
                --header 'X-Forwarded-Proto: https' \
                > /dev/null 2>&1; then
                echo "ok" > "$_done_file"
                exit 0
            fi
            sleep 1
            t=$((t + 1))
        done
        echo "timeout" > "$_done_file"
    ) </dev/null &
    local _checker_pid=$!

    _SPINNER_INTERRUPTED=0
    trap '_SPINNER_INTERRUPTED=1' INT
    _spinner_lock_input
    printf "\r\033[K${GREEN}%s${NC}\033[0m  %s" "${spin[$i]}" "$msg"

    while kill -0 $_checker_pid 2>/dev/null && [ "${_SPINNER_INTERRUPTED:-0}" != 1 ]; do
        _spinner_unstick_background_pid "$_checker_pid"
        i=$(( (i + 1) % 10 ))
        sleep $delay || true
        printf "\r\033[K${GREEN}%s${NC}\033[0m  %s" "${spin[$i]}" "$msg"
    done
    if [ "${_SPINNER_INTERRUPTED:-0}" = 1 ]; then
        kill -TERM "$_checker_pid" 2>/dev/null || true
        wait $_checker_pid 2>/dev/null || true
        rm -f "$_done_file"
        printf "\r\033[K"
        _spinner_unlock_input
        dfc_restore_interrupt_traps
        printf "${YELLOW}Операция прервана (Ctrl+C).${NC}\n" >&2
        return 130
    fi
    wait $_checker_pid 2>/dev/null

    local _result
    _result=$(cat "$_done_file" 2>/dev/null)
    rm -f "$_done_file"

    if [ "$_result" = "ok" ]; then
        printf "\r\033[K${GREEN}\u2705${NC}\033[0m %s\n" "$msg"
        _spinner_unlock_input
        dfc_restore_interrupt_traps
        return 0
    fi
    printf "\r\033[K${YELLOW}⚠️${NC}\033[0m  %s (таймаут)\n" "$msg"
    _spinner_unlock_input
    dfc_restore_interrupt_traps
    return 1
}

# ═══════════════════════════════════════════════
# МЕНЮ СО СТРЕЛОЧКАМИ
# ═══════════════════════════════════════════════

show_arrow_menu() {
    set +e
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=${MENU_INITIAL_IDX:-0}
    # Если начальный индекс указан — сбрасываем переменную
    unset MENU_INITIAL_IDX

    # Если stdin не является TTY — не пытаемся читать, возвращаем 255
    if ! [ -t 0 ]; then
        return 255
    fi

    # Сохраняем настройки терминала
    local original_stty=""
    original_stty=$(stty -g 2>/dev/null || echo "")

    # Скрываем курсор
    tput civis 2>/dev/null || true

    # Отключаем canonical mode и echo, включаем чтение отдельных символов
    _dfc_stty_cbreak_prompt ""

    # Функция восстановления терминала
    _restore_stty() {
        if [ -n "${original_stty:-}" ]; then
            stty "$original_stty" 2>/dev/null || stty sane 2>/dev/null || true
        else
            stty sane 2>/dev/null || true
        fi
    }
    _restore_term() {
        _restore_stty
        tput cnorm 2>/dev/null || true
    }

    # Обработчик ошибок для этой функции
    trap "_restore_stty" RETURN

    _flush_stdin

    # ── Кешируем заголовок (sed только один раз, не при каждом рендере) ──────────
    local _hdr="${MENU_TITLE_COLOR:-$BLUE}"
    local _title_pad1="" _title_line1="$title" _title_pad2="" _title_line2=""
    local _title_two_line=false
    # Только при явной последовательности \n (два символа), иначе ANSI (\033) попадает
    # в *\\* и заголовок дублируется.
    if [[ "$title" == *\\n* ]]; then
        _title_two_line=true
        local _t1="${title%%\\n*}" _t2="${title#*\\n}"
        local _tc1; _tc1=$(printf '%b' "$_t1" | sed 's/\x1b\[[0-9;]*m//g')
        local _p1=$(( (38 - ${#_tc1}) / 2 )); [ $_p1 -lt 0 ] && _p1=0
        _title_pad1=$(printf "%${_p1}s" "")
        _title_line1="$_t1"
        local _tc2; _tc2=$(printf '%b' "$_t2" | sed 's/\x1b\[[0-9;]*m//g')
        local _p2=$(( (38 - ${#_tc2}) / 2 )); [ $_p2 -lt 0 ] && _p2=0
        _title_pad2=$(printf "%${_p2}s" "")
        _title_line2="$_t2"
    else
        local _tc; _tc=$(printf '%b' "$title" | sed 's/\x1b\[[0-9;]*m//g')
        local _p=$(( (38 - ${#_tc}) / 2 )); [ $_p -lt 0 ] && _p=0
        _title_pad1=$(printf "%${_p}s" "")
    fi

    # ── Кешируем очищенные строки пунктов меню (sed вне цикла рендера) ───────────
    local -a _clean_opts=()
    local _ci
    for _ci in "${!options[@]}"; do
        if [[ "${options[$_ci]}" == $'\x01'* ]] || [[ "${options[$_ci]}" == $'\x02'* ]] || \
           [[ "${options[$_ci]}" =~ ^[─━═\ \t]*$ ]]; then
            _clean_opts[$_ci]="${options[$_ci]}"
        else
            local _s; _s=$(printf '%b' "${options[$_ci]}" | sed 's/\x1b\[[0-9;]*m//g')
            _clean_opts[$_ci]="$_s"
        fi
    done

    # ── Фиксируем подсказку навигации один раз до цикла ──────────────────────────
    local _esc_label="${MENU_ESC_LABEL:-Назад}"
    local _key_hint
    if [ -n "${MENU_KEY_HINT:-}" ]; then
        _key_hint="${MENU_KEY_HINT}"
        unset MENU_KEY_HINT
    else
        _key_hint="${DARKGRAY}${BLUE}↑↓${DARKGRAY}: Навигация  ${BLUE}Enter${DARKGRAY}: Выбор  ${BLUE}Esc${DARKGRAY}: ${_esc_label}${NC}"
    fi
    local _no_blank="${MENU_NO_BLANK:-}"
    unset MENU_NO_BLANK MENU_ESC_LABEL MENU_TITLE_COLOR

    while true; do
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        if [ "$_title_two_line" = true ]; then
            printf "%s" "$_title_pad1"
            echo -e "${_hdr}${_title_line1}${NC}"
            printf "%s" "$_title_pad2"
            echo -e "${_title_line2}"
        else
            printf "%s" "$_title_pad1"
            echo -e "${_hdr}${title}${NC}"
        fi
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        [[ -z "$_no_blank" ]] && echo

        local i
        for i in "${!options[@]}"; do
            if [[ "${options[$i]}" =~ ^[─━═\ \t]*$ ]]; then
                echo -e "${DARKGRAY}${options[$i]}${NC}"
            elif [[ "${options[$i]}" == $'\x02'* ]]; then
                echo -e "${DARKGRAY}${options[$i]:1}${NC}"
            elif [[ "${options[$i]}" == $'\x01'* ]]; then
                echo -e "${options[$i]:1}"
            elif [ $i -eq $selected ]; then
                echo -e "${BLUE}▶${NC} ${YELLOW}${_clean_opts[$i]}${NC}"
            else
                echo -e "  ${options[$i]}"
            fi
        done

        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "$_key_hint"
        echo
        echo
        # После подсказки навигации — ровно 2 пустые строки.

        local key
        read -rsn1 key 2>/dev/null || key=""

        # Проверяем escape-последовательность для стрелок
        # CSI: \e[A–\e[D  |  SS3 (часть терминалов): \eOA–\eOD — иначе после \e читается «O»,
        # ветка «чистый Esc» срабатывала на влево/вправо и возвращала 255 (другой экран).
        if [[ "$key" == $'\e' ]]; then
            local seq1="" seq2=""
            read -rsn1 -t 0.1 seq1 2>/dev/null || seq1=""
            if [[ "$seq1" == '[' || "$seq1" == 'O' ]]; then
                read -rsn1 -t 0.1 seq2 2>/dev/null || seq2=""
                case "$seq2" in
                    'A')  # Стрелка вверх
                        ((selected--))
                        if [ $selected -lt 0 ]; then
                            selected=$((num_options - 1))
                        fi
                        # Пропускаем разделители и заголовки вверх
                        while [[ "${options[$selected]}" =~ ^[─═\s]*$ ]] || [[ "${options[$selected]}" == $'\x01'* ]] || [[ "${options[$selected]}" == $'\x02'* ]]; do
                            ((selected--))
                            if [ $selected -lt 0 ]; then
                                selected=$((num_options - 1))
                            fi
                        done
                        ;;
                    'B')  # Стрелка вниз
                        ((selected++))
                        if [ $selected -ge $num_options ]; then
                            selected=0
                        fi
                        # Пропускаем разделители и заголовки вниз
                        while [[ "${options[$selected]}" =~ ^[─═\s]*$ ]] || [[ "${options[$selected]}" == $'\x01'* ]] || [[ "${options[$selected]}" == $'\x02'* ]]; do
                            ((selected++))
                            if [ $selected -ge $num_options ]; then
                                selected=0
                            fi
                        done
                        ;;
                    'C'|'D')  # Влево/вправо — не используем (случайный выход «назад» на SS3 больше не возможен)
                        ;;
                esac
            else
                # Чистый Esc без последовательности — назад (курсор скрыт до следующего экрана ввода)
                _restore_stty
                tput civis 2>/dev/null || true
                return 255
            fi
        else
            local key_code
            if [ -n "$key" ]; then
                key_code=$(printf '%d' "'$key" 2>/dev/null || echo 0)
            else
                key_code=13
            fi

            if [ "$key_code" -eq 10 ] || [ "$key_code" -eq 13 ]; then
                # Заголовки-секции нельзя выбрать — обрабатываем как нажатие вниз
                if [[ "${options[$selected]}" == $'\x01'* ]]; then
                    ((selected++))
                    [ $selected -ge $num_options ] && selected=0
                    while [[ "${options[$selected]}" =~ ^[─═\s]*$ ]] || [[ "${options[$selected]}" == $'\x01'* ]]; do
                        ((selected++))
                        [ $selected -ge $num_options ] && selected=0
                    done
                    continue
                fi
                # Восстанавливаем stty, курсор оставляем скрытым (следующий экран сам скроет/покажет)
                _restore_stty
                tput civis 2>/dev/null || true
                return $selected
            fi
        fi
    done
}

# ═══════════════════════════════════════════════
# ВВОД ТЕКСТА
# ═══════════════════════════════════════════════

# После байта ESC: 0 = одиночный Esc (отмена ввода), 1 = CSI/SS3/Meta — поглощено, ввод продолжается
# $1 — путь к TTY (например /dev/tty); пусто — stdin.
# $2 — необязательный номер fd (>=3): read -u fd вместо файла/stdin.
_dfc_after_esc_is_bare() {
    local _tty="${1-}"
    local _u="${2-}"
    local _sc="" _o2=""
    if [[ "$_u" =~ ^[0-9]+$ ]] && [ "$_u" -ge 3 ]; then
        if ! IFS= read -r -s -N 1 -t 0.15 _sc -u "$_u" 2>/dev/null || [[ -z "$_sc" ]]; then
            return 0
        fi
    elif [ -n "$_tty" ]; then
        if ! IFS= read -r -s -N 1 -t 0.15 _sc < "$_tty" 2>/dev/null || [[ -z "$_sc" ]]; then
            return 0
        fi
    else
        if ! IFS= read -r -s -N 1 -t 0.15 _sc 2>/dev/null || [[ -z "$_sc" ]]; then
            return 0
        fi
    fi
    if [[ "$_sc" == '[' ]]; then
        local _c=""
        while true; do
            if [[ "$_u" =~ ^[0-9]+$ ]] && [ "$_u" -ge 3 ]; then
                IFS= read -r -s -N 1 -t 0.15 _c -u "$_u" 2>/dev/null || break
            elif [ -n "$_tty" ]; then
                IFS= read -r -s -N 1 -t 0.15 _c < "$_tty" 2>/dev/null || break
            else
                IFS= read -r -s -N 1 -t 0.15 _c 2>/dev/null || break
            fi
            [[ "$_c" =~ [A-Za-z~] ]] && break
        done
        return 1
    elif [[ "$_sc" == 'O' ]]; then
        if [[ "$_u" =~ ^[0-9]+$ ]] && [ "$_u" -ge 3 ]; then
            IFS= read -r -s -N 1 -t 0.15 _o2 -u "$_u" 2>/dev/null || true
        elif [ -n "$_tty" ]; then
            IFS= read -r -s -N 1 -t 0.15 _o2 < "$_tty" 2>/dev/null || true
        else
            IFS= read -r -s -N 1 -t 0.15 _o2 2>/dev/null || true
        fi
        return 1
    fi
    return 1
}

# Ввод текста с подсказкой
reading() {
    local prompt="$1"
    local var_name="$2"
    local input=""
    local char
    local _rl_stty
    _rl_stty=$(stty -g 2>/dev/null || echo "")
    echo
    tput cnorm 2>/dev/null
    echo -en "${BLUE}➜${NC}  ${YELLOW}${prompt}${NC} \033[32m"
    while IFS= read -r -s -n1 char; do
        if [[ -z "$char" ]]; then
            break
        elif [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\x08' ]]; then
            if [[ -n "$input" ]]; then
                input="${input%?}"
                echo -en "\b \b"
            fi
        elif [[ "$char" == $'\x1b' ]]; then
            if _dfc_after_esc_is_bare; then
                echo -en "\033[0m"
                echo
                if [ -n "${_rl_stty:-}" ]; then stty "$_rl_stty" 2>/dev/null || true; fi
                printf -v "$var_name" ''
                return 2
            fi
        else
            input+="$char"
            echo -en "$char"
        fi
    done
    echo -en "\033[0m"
    if [ -n "${_rl_stty:-}" ]; then stty "$_rl_stty" 2>/dev/null || true; fi
    echo
    printf -v "$var_name" '%s' "$input"
    return 0
}

reading_inline() {
    local _no_eol=false
    if [[ "${1:-}" == "--no-eol" ]]; then
        _no_eol=true
        shift
    fi
    local prompt="$1"
    local var_name="$2"
    local default_val="${3:-}"
    local input=""
    local char
    local _rl_stty
    _rl_stty=$(stty -g 2>/dev/null || echo "")
    tput cnorm 2>/dev/null || true
    # Промпты без ANSI: двоеточие в конце — серым (как подсказки в скобках)
    local _p="$prompt"
    while [[ "${_p: -1:1}" == " " ]]; do _p="${_p% }"; done
    if [[ "$prompt" == *$'\033'* ]]; then
        # Внешний жёлтый для текста без своих кодов; вложенные DARKGRAY/YELLOW в промпте перекрывают
        echo -en "${BLUE}➜${NC}  ${YELLOW}${prompt}${NC} \033[32m"
    elif [[ -n "$default_val" ]]; then
        echo -en "${BLUE}➜${NC}  ${YELLOW}${prompt}${NC}${DARKGRAY} [${default_val}]:${NC} \033[32m"
    elif [[ "${_p: -1:1}" == ":" ]]; then
        echo -en "${BLUE}➜${NC}  ${YELLOW}${_p%:}${DARKGRAY}:${NC} \033[32m"
    else
        echo -en "${BLUE}➜${NC}  ${YELLOW}${prompt}${NC} \033[32m"
    fi
    while IFS= read -r -s -n1 char; do
        if [[ -z "$char" ]]; then
            break
        elif [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\x08' ]]; then
            if [[ -n "$input" ]]; then
                input="${input%?}"
                echo -en "\b \b"
            fi
        elif [[ "$char" == $'\x1b' ]]; then
            if _dfc_after_esc_is_bare; then
                echo
                tput civis 2>/dev/null || true
                printf -v "$var_name" ''
                return 2
            fi
        else
            input+="$char"
            echo -en "$char"
        fi
    done
    echo -en "\033[0m"
    if [ -n "${_rl_stty:-}" ]; then stty "$_rl_stty" 2>/dev/null || true; fi
    if [[ "$_no_eol" != true ]]; then
        echo
    fi
    if [[ -z "$input" && -n "${default_val:-}" ]]; then
        input="$default_val"
    fi
    printf -v "$var_name" '%s' "$input"
}

# Промпт "Enter: Продолжить    Esc: Назад" (или Esc: <ярлык>, если передан первый аргумент, напр. «Выход»)
# Первый аргумент -q — не печатать строку подсказки (она уже выведена выше).
# Возвращает: 0 = Enter (назад на одно меню), 1 = Esc (в главное меню)
# Стрелки и прочие ESC-последовательности поглощаются целиком (не оставляют мусор в stdin).
show_continue_prompt() {
    local _quiet=false
    if [[ "${1:-}" == "-q" ]]; then _quiet=true; shift; fi
    local _esc_lbl="${1:-Назад}"
    local _cp_stty=""
    local _tin=""
    local _cpfd=""
    [ -r /dev/tty ] && _tin=/dev/tty
    _dfc_prompt_prepare_input
    [ -n "$_tin" ] && _dfc_tcflush_dev_tty
    # Отдельный fd к управляющему TTY: ввод не «прилипает» к старому stdin после спиннеров/docker
    if [ -n "$_tin" ]; then
        exec {_cpfd}<>"$_tin" || _cpfd=""
        [[ "$_cpfd" =~ ^[0-9]+$ ]] && _DFC_CONTINUE_PROMPT_TTYFD="$_cpfd"
    fi
    if [ -n "$_tin" ]; then
        _cp_stty=$(stty -F "$_tin" -g 2>/dev/null || echo "")
        # sane: после спиннеров (icanon+echo) и docker в TTY дисциплина может быть в «ломаных» флагах
        stty -F "$_tin" sane 2>/dev/null || true
        _dfc_stty_cbreak_prompt "$_tin"
        _dfc_drain_tty_after_cbreak "$_tin"
    elif [ -t 0 ]; then
        _cp_stty=$(stty -g 2>/dev/null || echo "")
        stty sane 2>/dev/null || true
        _dfc_stty_cbreak_prompt ""
        _dfc_drain_tty_after_cbreak ""
    fi
    [ -n "$_tin" ] && _dfc_tcflush_dev_tty
    # Видимый курсор: иначе кажется, что меню «мертвое», а ввод уехал на новую строку
    tput cnorm 2>/dev/null || true
    if [[ "$_quiet" != true ]]; then
        printf "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Продолжить    ${BLUE}Esc${DARKGRAY}: ${_esc_lbl}${NC}"
    fi
    while true; do
        local _cpk=""
        if [[ "$_cpfd" =~ ^[0-9]+$ ]]; then
            IFS= read -r -s -N 1 _cpk -u "$_cpfd" 2>/dev/null || _cpk=""
        else
            IFS= read -r -s -N 1 _cpk 2>/dev/null || _cpk=""
        fi
        if [[ "$_cpk" == $'\x03' ]]; then
            dfc_close_continue_prompt_ttyfd
            if [ -n "$_tin" ]; then
                if [ -n "${_cp_stty:-}" ]; then stty -F "$_tin" "$_cp_stty" 2>/dev/null || stty -F "$_tin" sane 2>/dev/null || true; fi
            elif [ -n "${_cp_stty:-}" ]; then
                stty "$_cp_stty" 2>/dev/null || stty sane 2>/dev/null || true
            fi
            handle_interrupt
        fi
        if [[ "$_cpk" == "" ]] || [[ "$_cpk" == $'\n' ]] || [[ "$_cpk" == $'\r' ]]; then
            dfc_close_continue_prompt_ttyfd
            if [ -n "$_tin" ]; then
                if [ -n "${_cp_stty:-}" ]; then stty -F "$_tin" "$_cp_stty" 2>/dev/null || stty -F "$_tin" sane 2>/dev/null || true; fi
            elif [ -n "${_cp_stty:-}" ]; then
                stty "$_cp_stty" 2>/dev/null || stty sane 2>/dev/null || true
            fi
            tput cnorm 2>/dev/null || true
            echo
            return 0
        elif [[ "$_cpk" == $'\x1b' ]]; then
            _esc_bare=false
            if [[ "$_cpfd" =~ ^[0-9]+$ ]]; then
                _dfc_after_esc_is_bare "" "$_cpfd" && _esc_bare=true
            elif [ -n "$_tin" ]; then
                _dfc_after_esc_is_bare "$_tin" && _esc_bare=true
            else
                _dfc_after_esc_is_bare "" && _esc_bare=true
            fi
            if [[ "$_esc_bare" == true ]]; then
                dfc_close_continue_prompt_ttyfd
                if [ -n "$_tin" ]; then
                    if [ -n "${_cp_stty:-}" ]; then stty -F "$_tin" "$_cp_stty" 2>/dev/null || stty -F "$_tin" sane 2>/dev/null || true; fi
                elif [ -n "${_cp_stty:-}" ]; then
                    stty "$_cp_stty" 2>/dev/null || stty sane 2>/dev/null || true
                fi
                tput cnorm 2>/dev/null || true
                echo
                return 1
            fi
            continue
        fi
    done
}

# Ошибка установки с возможностью просмотра логов
# Возвращает: 0 = Enter→продолжить, 1 = Esc→главное меню
show_install_error() {
    local message="$1"
    local log_file="${2:-}"

    print_error "$message"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    printf "${DARKGRAY}  ${BLUE}Enter${DARKGRAY}: Показать логи     ${BLUE}Esc${DARKGRAY}: Главное меню${NC}"

    local _tin=""
    [ -r /dev/tty ] && _tin=/dev/tty
    _dfc_prompt_prepare_input

    local _ie_stty=""
    if [ -n "$_tin" ]; then
        _ie_stty=$(stty -F "$_tin" -g 2>/dev/null || echo "")
        stty -F "$_tin" sane 2>/dev/null || true
        _dfc_stty_cbreak_prompt "$_tin"
        _dfc_drain_tty_after_cbreak "$_tin"
    elif [ -t 0 ]; then
        _ie_stty=$(stty -g 2>/dev/null || echo "")
        stty sane 2>/dev/null || true
        _dfc_stty_cbreak_prompt ""
        _dfc_drain_tty_after_cbreak ""
    fi

    tput civis 2>/dev/null
    local _key _seq
    while true; do
        _key=""
        if [ -n "$_tin" ]; then
            IFS= read -r -s -N 1 _key < "$_tin" 2>/dev/null || _key=""
        else
            IFS= read -r -s -N 1 _key 2>/dev/null || _key=""
        fi
        if [[ "$_key" == "" ]] || [[ "$_key" == $'\n' ]] || [[ "$_key" == $'\r' ]]; then
            if [ -n "$_tin" ]; then
                [ -n "$_ie_stty" ] && stty -F "$_tin" "$_ie_stty" 2>/dev/null || stty -F "$_tin" sane 2>/dev/null || true
            elif [ -n "$_ie_stty" ]; then
                stty "$_ie_stty" 2>/dev/null || stty sane 2>/dev/null || true
            fi
            tput cnorm 2>/dev/null; echo
            echo
            if [ -n "$log_file" ] && [ -s "$log_file" ]; then
                echo -e "${DARKGRAY}$(cat "$log_file" 2>/dev/null)${NC}"
            else
                echo -e "${DARKGRAY}Логи недоступны${NC}"
            fi
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            show_continue_prompt
            return $?
        elif [[ "$_key" == $'\x1b' ]]; then
            if _dfc_after_esc_is_bare "$_tin"; then
                if [ -n "$_tin" ]; then
                    [ -n "$_ie_stty" ] && stty -F "$_tin" "$_ie_stty" 2>/dev/null || stty -F "$_tin" sane 2>/dev/null || true
                elif [ -n "$_ie_stty" ]; then
                    stty "$_ie_stty" 2>/dev/null || stty sane 2>/dev/null || true
                fi
                tput cnorm 2>/dev/null || true
                echo
                return 1
            fi
        fi
    done
}

# Двухпунктное подтверждение (↑↓, Enter, Esc), как show_arrow_menu.
# confirm_nav [--delete] "Заголовок"  — только заголовок: красный шрифт, пункты «✔️   Подтвердить» / «❌  Отменить»,
#   Enter в подсказке: «Выбор»; CONFIRM_WARN_LINE не используется (детали — вторая строка заголовка через \n).
# confirm_nav "Заголовок" "Пункт да" "Пункт нет"  — синий заголовок; опционально CONFIRM_WARN_LINE над пунктами.
# Возврат: 0 — подтверждено (первый пункт), 1 — отмена (второй пункт или Esc).
confirm_nav() {
    local _del=false
    [[ "${1:-}" == "--delete" ]] && { _del=true; shift; }
    local _title="${1:?}"
    local _yes _no

    if [ "$_del" = true ]; then
        _yes="✔️   Подтвердить"
        _no="❌  Отменить"
    else
        _yes="${2:?}"
        _no="${3:?}"
    fi

    local -a _opts=()
    if [ -n "${CONFIRM_WARN_LINE:-}" ] && [ "$_del" != true ]; then
        _opts+=($'\x01'"${CONFIRM_WARN_LINE}")
    fi
    _opts+=("$_yes" "$_no")

    if [ "$_del" = true ]; then
        MENU_TITLE_COLOR="${RED}"
        MENU_KEY_HINT="${DARKGRAY}${BLUE}↑↓${DARKGRAY}: Навигация  ${BLUE}Enter${DARKGRAY}: Выбор  ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
    else
        MENU_TITLE_COLOR="${BLUE}"
        MENU_KEY_HINT="${DARKGRAY}${BLUE}↑↓${DARKGRAY}: Навигация  ${BLUE}Enter${DARKGRAY}: Подтвердить  ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
    fi
    MENU_ESC_LABEL="Отмена"
    if [ -n "${CONFIRM_WARN_LINE:-}" ] && [ "$_del" != true ]; then
        MENU_INITIAL_IDX=1
    else
        MENU_INITIAL_IDX=0
    fi
    show_arrow_menu "$_title" "${_opts[@]}"
    local _r=$?
    unset MENU_TITLE_COLOR MENU_KEY_HINT MENU_ESC_LABEL MENU_INITIAL_IDX
    [[ $_r -eq 255 ]] || [[ $_r -eq 1 ]] && return 1
    [[ $_r -eq 0 ]] && return 0
    return 1
}

# Совместимость: общее подтверждение без предупреждения.
confirm_action() {
    confirm_nav "Подтвердите действие" "Подтвердить" "Отменить" || return 1
}
