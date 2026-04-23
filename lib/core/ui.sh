# ═══════════════════════════════════════════════
# УТИЛИТЫ ВЫВОДА
# ═══════════════════════════════════════════════

print_action()  { :; }
print_error()   { printf "${RED}✖ %b${NC}\n" "$1"; }
print_success() { printf "${GREEN}✅ %b${NC}\n" "$1"; }
print_warning() { printf "${YELLOW}⚠️  %b${NC}\n" "$1"; }

# Центрирует текст в 38-символьную ширину для боксов ══════════════════════════════════════
# Использование: center "текст" "$COLOR"
center() {
    local text="$1"
    local color="${2:-}"
    local width=38
    local text_len=${#text}
    local padding=$(( (width - text_len) / 2 ))
    [ $padding -lt 0 ] && padding=0
    printf "%*s${color}%s${NC}\n" $((padding + text_len)) "$text"
}

# Сбрасывает буферизованный ввод (например, клавиши, нажатые во время спиннеров)
_flush_stdin() {
    local _dummy
    while IFS= read -rsn1 -t 0 _dummy 2>/dev/null; do true; done
    true
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
    tput civis 2>/dev/null || true
    while kill -0 $pid 2>/dev/null; do
        printf "\r${BLUE}%s${NC}  ${BLUE}%s${NC}" "${spin[$i]}" "$msg"
        i=$(( (i+1) % 10 ))
        sleep $delay
    done
    wait $pid 2>/dev/null || true
    printf "\r\033[K"
    tput cnorm 2>/dev/null || true
}

show_spinner() {
    local pid=$!
    local delay=0.08
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0 msg="$1" done_msg="${2:-$1}"
    tput civis 2>/dev/null || true
    while kill -0 $pid 2>/dev/null; do
        printf "\r${GREEN}%s${NC}  %b" "${spin[$i]}" "$msg"
        i=$(( (i+1) % 10 ))
        sleep $delay
    done
    local exit_code=0
    wait $pid 2>/dev/null || exit_code=$?
    if [ $exit_code -eq 0 ]; then
        printf "\r\033[K${GREEN}\u2705${NC} %b\n" "$done_msg"
    else
        printf "\r\033[K${RED}\u2716${NC} %b\n" "$done_msg"
    fi
    tput cnorm 2>/dev/null || true
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
    tput civis 2>/dev/null || true
    while [ $elapsed -lt $seconds ]; do
        local remaining=$((seconds - elapsed))
        for ((j=0; j<12; j++)); do
            printf "\r\033[K${DARKGRAY}%s  %s (%d сек)${NC}" "${spin[$i]}" "$msg" "$remaining"
            sleep $delay
            i=$(( (i+1) % 10 ))
        done
        elapsed=$((elapsed + 1))
    done
    printf "\r\033[K${GREEN}✅${NC} %s\n" "$done_msg"
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
    ) &
    local _checker_pid=$!

    tput civis 2>/dev/null || true
    printf "\r${GREEN}%s${NC}  %s" "${spin[$i]}" "$msg"

    while kill -0 $_checker_pid 2>/dev/null; do
        i=$(( (i + 1) % 10 ))
        sleep $delay
        printf "\r${GREEN}%s${NC}  %s" "${spin[$i]}" "$msg"
    done
    wait $_checker_pid 2>/dev/null

    local _result
    _result=$(cat "$_done_file" 2>/dev/null)
    rm -f "$_done_file"

    if [ "$_result" = "ok" ]; then
        printf "\r${GREEN}✅${NC} %s\n" "$msg"
        tput cnorm 2>/dev/null || true
        return 0
    fi
    printf "\r${YELLOW}⚠️${NC}  %s (таймаут)\n" "$msg"
    tput cnorm 2>/dev/null || true
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
    stty -icanon -echo isig min 1 time 0 2>/dev/null || true

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

    while true; do
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        local _hdr="${MENU_TITLE_COLOR:-$BLUE}"
        if [[ "$title" == *\\* ]]; then
            local _first="${title%%\\n*}"
            local _rest="${title#*\\n}"
            local _clean
            _clean=$(echo -e "$_first" | sed 's/\x1b\[[0-9;]*m//g')
            local _vlen=${#_clean}
            local _pad=$(( (38 - _vlen) / 2 ))
            [ $_pad -lt 0 ] && _pad=0
            printf "%${_pad}s" ""
            echo -e "${_hdr}${_first}${NC}"
            # Вторая строка заголовка (статус и т.п.) — тоже по центру в ширину 38
            _clean=$(echo -e "$_rest" | sed 's/\x1b\[[0-9;]*m//g')
            _vlen=${#_clean}
            _pad=$(( (38 - _vlen) / 2 ))
            [ $_pad -lt 0 ] && _pad=0
            printf "%${_pad}s" ""
            echo -e "${_rest}"
        else
            local _clean
            _clean=$(echo -e "$title" | sed 's/\x1b\[[0-9;]*m//g')
            local _vlen=${#_clean}
            local _pad=$(( (38 - _vlen) / 2 ))
            [ $_pad -lt 0 ] && _pad=0
            printf "%${_pad}s" ""
            echo -e "${_hdr}$title${NC}"
        fi
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        [[ -z "${MENU_NO_BLANK:-}" ]] && echo
        unset MENU_NO_BLANK

        for i in "${!options[@]}"; do
            # Проверяем, является ли элемент разделителем
            if [[ "${options[$i]}" =~ ^[─━═\s]*$ ]]; then
                # Разделители без отступа - вровень с рамкой (синие)
                echo -e "${DARKGRAY}${options[$i]}${NC}"
            elif [[ "${options[$i]}" == $'\x02'* ]]; then
                # Серый разделитель (──────)
                echo -e "${DARKGRAY}${options[$i]:1}${NC}"
            elif [[ "${options[$i]}" == $'\x01'* ]]; then
                # Заголовок-секция (не выбирается), допускает цвета в тексте
                echo -e "${options[$i]:1}"
            elif [ $i -eq $selected ]; then
                local _clean_item; _clean_item=$(echo -e "${options[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
                echo -e "${BLUE}▶${NC} ${YELLOW}${_clean_item}${NC}"
            else
                echo -e "  ${options[$i]}"
            fi
        done

        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        local _esc_label="${MENU_ESC_LABEL:-Назад}"
        if [ -n "${MENU_KEY_HINT:-}" ]; then
            echo -e "${MENU_KEY_HINT}"
            unset MENU_KEY_HINT
        else
            echo -e "${DARKGRAY}${BLUE}↑↓${DARKGRAY}: Навигация  ${BLUE}Enter${DARKGRAY}: Выбор  ${BLUE}Esc${DARKGRAY}: ${_esc_label}${NC}"
        fi
        echo

        local key
        read -rsn1 key 2>/dev/null || key=""

        # Проверяем escape-последовательность для стрелок
        if [[ "$key" == $'\e' ]]; then
            local seq1="" seq2=""
            read -rsn1 -t 0.1 seq1 2>/dev/null || seq1=""
            if [[ "$seq1" == '[' ]]; then
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
                esac
            else
                # Чистый Esc без последовательности — назад
                _restore_term
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
            local _seq=""
            while IFS= read -r -s -n1 -t 0.1 _sc; do
                _seq+="$_sc"
                [[ "$_sc" =~ [A-Za-z~] ]] && break
            done
            if [[ -z "$_seq" ]]; then
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
    local prompt="$1"
    local var_name="$2"
    local input=""
    local char
    local _rl_stty
    _rl_stty=$(stty -g 2>/dev/null || echo "")
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
            local _seq=""
            while IFS= read -r -s -n1 -t 0.1 _sc; do
                _seq+="$_sc"
                [[ "$_sc" =~ [A-Za-z~] ]] && break
            done
            if [[ -z "$_seq" ]]; then
                echo
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
}

# Промпт "Enter: Продолжить    Esc: Назад"
# Возвращает: 0 = Enter (назад на одно меню), 1 = Esc (в главное меню)
show_continue_prompt() {
    _flush_stdin
    tput civis 2>/dev/null
    printf "${DARKGRAY}   ${BLUE}Enter${DARKGRAY}: Продолжить    ${BLUE}Esc${DARKGRAY}: Назад${NC}"
    while true; do
        local _cpk
        IFS= read -rsn1 _cpk 2>/dev/null
        if [[ "$_cpk" == "" ]] || [[ "$_cpk" == $'\n' ]] || [[ "$_cpk" == $'\r' ]]; then
            tput cnorm 2>/dev/null; echo
            return 0   # Enter → назад на одно меню
        elif [[ "$_cpk" == $'\x1b' ]]; then
            IFS= read -rsn1 -t 0.1 _cps 2>/dev/null || true
            if [[ -z "$_cps" ]]; then
                tput cnorm 2>/dev/null; echo
                return 1   # Esc → в главное меню
            else
                # Поглощаем третий символ escape-последовательности (стрелки: \x1b[A/B/C/D)
                IFS= read -rsn1 -t 0.1 2>/dev/null || true
            fi
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

    tput civis 2>/dev/null
    local _key _seq
    while true; do
        IFS= read -rsn1 _key 2>/dev/null
        if [[ "$_key" == "" ]] || [[ "$_key" == $'\n' ]] || [[ "$_key" == $'\r' ]]; then
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
            IFS= read -rsn1 -t 0.1 _seq 2>/dev/null || true
            if [[ -z "$_seq" ]]; then
                tput cnorm 2>/dev/null; echo
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
        MENU_KEY_HINT="${DARKGRAY}${BLUE}↑↓${DARKGRAY}: Навигация    ${BLUE}Enter${DARKGRAY}: Подтвердить     ${BLUE}Esc${DARKGRAY}: Отмена${NC}"
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
