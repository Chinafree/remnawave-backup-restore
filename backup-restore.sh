#!/bin/bash

set -e

VERSION="2.2.1"
INSTALL_DIR="/opt/rw-backup-restore"
BACKUP_DIR="$INSTALL_DIR/backup"
CONFIG_FILE="$INSTALL_DIR/config.env"
SCRIPT_NAME="backup-restore.sh"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
RETAIN_BACKUPS_DAYS=7
SYMLINK_PATH="/usr/local/bin/rw-backup"
REMNALABS_ROOT_DIR=""
ENV_NODE_FILE=".env-node"
ENV_FILE=".env"
SCRIPT_REPO_URL="https://raw.githubusercontent.com/Chinafree/remnawave-backup-restore/main/backup-restore.sh"
SCRIPT_RUN_PATH="$(realpath "$0")"
GD_CLIENT_ID=""
GD_CLIENT_SECRET=""
GD_REFRESH_TOKEN=""
GD_FOLDER_ID=""
UPLOAD_METHOD="telegram"
CRON_TIMES=""
TG_MESSAGE_THREAD_ID=""
UPDATE_AVAILABLE=false
BACKUP_EXCLUDE_PATTERNS="*.log *.tmp .git"

BOT_BACKUP_ENABLED="false"
BOT_BACKUP_PATH=""
BOT_BACKUP_SELECTED=""
BOT_BACKUP_DB_USER="postgres"


if [[ -t 0 ]]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    GRAY=$'\e[37m'
    LIGHT_GRAY=$'\e[90m'
    CYAN=$'\e[36m'
    RESET=$'\e[0m'
    BOLD=$'\e[1m'
else
    RED=""
    GREEN=""
    YELLOW=""
    GRAY=""
    LIGHT_GRAY=""
    CYAN=""
    RESET=""
    BOLD=""
fi

print_message() {
    local type="$1"
    local message="$2"
    local color_code="$RESET"

    case "$type" in
        "INFO") color_code="$GRAY" ;;
        "SUCCESS") color_code="$GREEN" ;;
        "WARN") color_code="$YELLOW" ;;
        "ERROR") color_code="$RED" ;;
        "ACTION") color_code="$CYAN" ;;
        "LINK") color_code="$CYAN" ;;
        *) type="INFO" ;;
    esac

    echo -e "${color_code}[$type]${RESET} $message"
}

setup_symlink() {
    echo ""
    if [[ "$EUID" -ne 0 ]]; then
        print_message "WARN" "管理符号链接 ${BOLD}${SYMLINK_PATH}${RESET} 需要 root 权限。跳过设置。"
        return 1
    fi

    if [[ -L "$SYMLINK_PATH" && "$(readlink -f "$SYMLINK_PATH")" == "$SCRIPT_PATH" ]]; then
        print_message "SUCCESS" "符号链接 ${BOLD}${SYMLINK_PATH}${RESET} 已存在并指向 ${BOLD}${SCRIPT_PATH}${RESET}。"
        return 0
    fi

    print_message "INFO" "正在创建或更新符号链接 ${BOLD}${SYMLINK_PATH}${RESET}..."
    rm -f "$SYMLINK_PATH"
    if [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        if ln -s "$SCRIPT_PATH" "$SYMLINK_PATH"; then
            print_message "SUCCESS" "符号链接 ${BOLD}${SYMLINK_PATH}${RESET} 已成功设置。"
        else
            print_message "ERROR" "无法创建符号链接 ${BOLD}${SYMLINK_PATH}${RESET}。请检查权限。"
            return 1
        fi
    else
        print_message "ERROR" "目录 ${BOLD}$(dirname "$SYMLINK_PATH")${RESET} 未找到。符号链接未创建。"
        return 1
    fi
    echo ""
    return 0
}

configure_bot_backup() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}设置 Telegram 机器人备份${RESET}"
        echo ""
        
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            echo -e "  机器人:   ${BOLD}${GREEN}${BOT_BACKUP_SELECTED}${RESET}"
            echo -e "  路径:     ${BOLD}${WHITE}${BOT_BACKUP_PATH}${RESET}"
            
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                echo -e "  模式:     ${BOLD}${RED}仅机器人${RESET}"
            else
                echo -e "  模式:     ${BOLD}${GREEN}面板 + 机器人${RESET}"
            fi
        else
            print_message "INFO" "机器人备份: ${RED}${BOLD}已关闭${RESET}"
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                print_message "WARN" "注意: 面板备份也被跳过（没有任何内容会被备份！）"
            else
                print_message "INFO" "模式: 仅备份 Remnawave 面板"
            fi
        fi
        echo ""
        
        echo " 1. 设置 / 修改 机器人 参数"
        
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                if [[ "$REMNALABS_ROOT_DIR" != "none" && -n "$REMNALABS_ROOT_DIR" ]]; then
                    echo " 2. 重新启用面板备份 (模式: 面板 + 机器人)"
                fi
            else
                echo " 2. 排除面板备份 (模式: 仅机器人)"
            fi
        fi

        echo " 3. 完全关闭机器人备份"
        echo ""
        echo " 0. 返回主菜单"
        echo ""
        
        read -rp " ${GREEN}[?]${RESET} 请选择: " choice
        
        case $choice in
            1)
                clear
                echo -e "${GREEN}${BOLD}选择要备份的机器人${RESET}"
                echo ""
                echo " 1. 耶稣的机器人 (remnawave-telegram-shop)"
                echo " 2. Machka 的机器人 (remnawave-tg-shop)"
                echo " 3. Snoups 的机器人 (remnashop)"
                echo " 0. 返回"
                echo ""
                
                local bot_choice
                read -rp " ${GREEN}[?]${RESET} 请选择: " bot_choice
                case "$bot_choice" in
                    1) BOT_BACKUP_SELECTED="耶稣的机器人"; bot_folder="remnawave-telegram-shop" ;;
                    2) BOT_BACKUP_SELECTED="Machka 的机器人"; bot_folder="remnawave-tg-shop" ;;
                    3) BOT_BACKUP_SELECTED="Snoups 的机器人"; bot_folder="remnashop" ;;
                    0) continue ;;
                    *) print_message "ERROR" "输入无效"; sleep 1; continue ;;
                esac
                
                echo ""
                print_message "ACTION" "请选择机器人的目录路径:"
                echo " 1. /opt/$bot_folder"
                echo " 2. /root/$bot_folder"
                echo " 3. /opt/stacks/$bot_folder"
                echo " 4. 指定自定义路径"
                echo ""
                
                local path_choice
                read -rp " ${GREEN}[?]${RESET} 请选择: " path_choice
                case "$path_choice" in
                    1) BOT_BACKUP_PATH="/opt/$bot_folder" ;;
                    2) BOT_BACKUP_PATH="/root/$bot_folder" ;;
                    3) BOT_BACKUP_PATH="/opt/stacks/$bot_folder" ;;
                    4) 
                        echo ""
                        read -rp " 请输入完整路径: " custom_bot_path
                        if [[ -z "$custom_bot_path" || ! "$custom_bot_path" = /* ]]; then
                            print_message "ERROR" "路径必须为绝对路径！"
                            sleep 2; continue
                        fi
                        BOT_BACKUP_PATH="${custom_bot_path%/}" 
                        ;;
                    *) print_message "ERROR" "输入无效"; sleep 1; continue ;;
                esac

                echo ""
                read -rp " $(echo -e "${GREEN}[?]${RESET} 机器人数据库用户名 (默认 postgres): ")" bot_db_user
                BOT_BACKUP_DB_USER="${bot_db_user:-postgres}"

                if [[ "$SKIP_PANEL_BACKUP" == "false" ]]; then
                    echo ""
                    print_message "ACTION" "是否禁用面板备份，仅保留机器人备份?"
                    read -rp " $(echo -e "${GREEN}[?]${RESET} 输入 (${GREEN}y${RESET}/${RED}n${RESET}): ")" only_bot_confirm
                    if [[ "$only_bot_confirm" =~ ^[yY]$ ]]; then
                        SKIP_PANEL_BACKUP="true"
                    fi
                fi

                BOT_BACKUP_ENABLED="true"
                save_config
                print_message "SUCCESS" "机器人设置已保存并启用。"
                read -rp "按 Enter 继续..."
                ;;

            2)
                if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                    SKIP_PANEL_BACKUP="false"
                    print_message "SUCCESS" "模式已更改: 面板 + 机器人"
                else
                    SKIP_PANEL_BACKUP="true"
                    print_message "SUCCESS" "模式已更改: 仅机器人"
                fi
                save_config
                read -rp "按 Enter 继续..."
                ;;

            3)
                BOT_BACKUP_ENABLED="false"
                BOT_BACKUP_PATH=""
                BOT_BACKUP_SELECTED=""
                
                echo ""
                print_message "SUCCESS" "机器人备份已禁用。"

                if [[ "$SKIP_PANEL_BACKUP" == "true" && "$REMNALABS_ROOT_DIR" != "none" && -n "$REMNALABS_ROOT_DIR" ]]; then
                    print_message "WARN" "当前模式下面板备份也被禁用。"
                    read -rp " $(echo -e "${GREEN}[?]${RESET} 是否重新启用面板备份? (y/n): ")" restore_p
                    if [[ "$restore_p" =~ ^[yY]$ ]]; then
                        SKIP_PANEL_BACKUP="false"
                        print_message "SUCCESS" "面板备份已恢复。"
                    fi
                fi
                
                save_config
                read -rp "按 Enter 继续..."
                ;;

            0) break ;;
            *) print_message "ERROR" "输入无效" ; sleep 1 ;;
        esac
    done
}

get_bot_params() {
    local bot_name="$1"
    
    case "$bot_name" in
        "耶稣的机器人")
            echo "remnawave-telegram-shop-db|remnawave-telegram-shop-db-data|remnawave-telegram-shop|db"
            ;;
        "Machka 的机器人")
            echo "remnawave-tg-shop-db|remnawave-tg-shop-db-data|remnawave-tg-shop|remnawave-tg-shop-db"
            ;;
        "Snoups 的机器人")
            echo "remnashop-db|remnashop-db-data|remnashop|remnashop-db"
            ;;
        *)
            echo "|||"
            ;;
    esac
}

check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        print_message "ERROR" "此服务器未安装 Docker。恢复操作需要 Docker。"
        read -rp " ${GREEN}[?]${RESET} 是否现在安装 Docker? (${GREEN}y${RESET}/${RED}n${RESET}): " install_choice
        
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            print_message "INFO" "正在静默安装 Docker..."
            if curl -fsSL https://get.docker.com | sh > /dev/null 2>&1; then
                print_message "SUCCESS" "Docker 安装成功。"
            else
                print_message "ERROR" "安装 Docker 时发生错误。"
                return 1
            fi
        else
            print_message "INFO" "操作已被用户取消。"
            return 1
        fi
    fi
    return 0
}

create_bot_backup() {
    if [[ "$BOT_BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi
    
    print_message "INFO" "正在为 Telegram 机器人创建备份: ${BOLD}${BOT_BACKUP_SELECTED}${RESET}..."
    
    local bot_params=$(get_bot_params "$BOT_BACKUP_SELECTED")
    IFS='|' read -r BOT_CONTAINER_NAME BOT_VOLUME_NAME BOT_DIR_NAME BOT_SERVICE_NAME <<< "$bot_params"
    
    if [[ -z "$BOT_CONTAINER_NAME" ]]; then
        print_message "ERROR" "未知机器人: $BOT_BACKUP_SELECTED"
        print_message "INFO" "继续创建不包含机器人的备份..."
        return 0
    fi

    local BOT_BACKUP_FILE_DB="bot_dump_${TIMESTAMP}.sql.gz"
    local BOT_DIR_ARCHIVE="bot_dir_${TIMESTAMP}.tar.gz"
    
    if ! docker inspect "$BOT_CONTAINER_NAME" > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' "$BOT_CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
        print_message "WARN" "未找到或未运行容器 '$BOT_CONTAINER_NAME'。跳过机器人备份。"
        return 0
    fi
    
    print_message "INFO" "正在创建 PostgreSQL 转储..."
    if ! docker exec -t "$BOT_CONTAINER_NAME" pg_dumpall -c -U "$BOT_BACKUP_DB_USER" | gzip -9 > "$BACKUP_DIR/$BOT_BACKUP_FILE_DB"; then
        print_message "ERROR" "创建机器人 PostgreSQL 转储时出错。继续但不包含机器人备份..."
        return 0
    fi
    
    if [ -d "$BOT_BACKUP_PATH" ]; then
        print_message "INFO" "正在归档机器人目录 ${BOLD}${BOT_BACKUP_PATH}${RESET}..."
        local exclude_args=""
        for pattern in $BACKUP_EXCLUDE_PATTERNS; do
            exclude_args+="--exclude=$pattern "
        done
        
        if eval "tar -czf '$BACKUP_DIR/$BOT_DIR_ARCHIVE' $exclude_args -C '$(dirname "$BOT_BACKUP_PATH")' '$(basename "$BOT_BACKUP_PATH")'"; then
            print_message "SUCCESS" "机器人目录已成功归档。"
        else
            print_message "ERROR" "归档机器人目录时出错。"
            return 1
        fi
    else
        print_message "WARN" "未找到机器人目录 ${BOLD}${BOT_BACKUP_PATH}${RESET}！继续但不包含目录归档..."
        return 0
    fi
    
    BACKUP_ITEMS+=("$BOT_BACKUP_FILE_DB" "$BOT_DIR_ARCHIVE")
    
    print_message "SUCCESS" "机器人备份已成功创建。"
    echo ""
    return 0
}

restore_bot_backup() {
    local temp_restore_dir="$1"
    
    local BOT_DUMP_FILE=$(find "$temp_restore_dir" -name "bot_dump_*.sql.gz" | head -n 1)
    local BOT_DIR_ARCHIVE=$(find "$temp_restore_dir" -name "bot_dir_*.tar.gz" | head -n 1)
    
    if [[ -z "$BOT_DUMP_FILE" && -z "$BOT_DIR_ARCHIVE" ]]; then
        return 2
    fi

    check_docker_installed || return 1

    clear
    print_message "INFO" "在归档中检测到 Telegram 机器人备份。"
    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} 是否恢复 Telegram 机器人? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: ")" restore_bot_confirm
    
    if [[ "$restore_bot_confirm" != "y" ]]; then
        print_message "INFO" "已取消机器人恢复。"
        return 1
    fi
    
    echo ""
    print_message "ACTION" "备份中是哪个机器人?"
    echo " 1. 耶稣的机器人 (remnawave-telegram-shop)"
    echo " 2. Machka 的机器人 (remnawave-tg-shop)"
    echo " 3. Snoups 的机器人 (remnashop)"
    echo ""
    
    local bot_choice
    local selected_bot_name
    while true; do
        read -rp " ${GREEN}[?]${RESET} 请选择机器人: " bot_choice
        case "$bot_choice" in
            1) selected_bot_name="耶稣的机器人"; break ;;
            2) selected_bot_name="Machka 的机器人"; break ;;
            3) selected_bot_name="Snoups 的机器人"; break ;;
            *) print_message "ERROR" "输入无效。" ;;
        esac
    done
    
    echo ""
    print_message "ACTION" "请选择机器人恢复路径:"
    if [[ "$selected_bot_name" == "耶稣的机器人" ]]; then
        echo " 1. /opt/remnawave-telegram-shop"
        echo " 2. /root/remnawave-telegram-shop"
        echo " 3. /opt/stacks/remnawave-telegram-shop"
    elif [[ "$selected_bot_name" == "Machka 的机器人" ]]; then
        echo " 1. /opt/remnawave-tg-shop"
        echo " 2. /root/remnawave-tg-shop"
        echo " 3. /opt/stacks/remnawave-tg-shop"
    else
        echo " 1. /opt/remnashop"
        echo " 2. /root/remnashop"
        echo " 3. /opt/stacks/remnashop"
    fi
    echo " 4. 指定自定义路径"
    echo ""
    echo " 0. 返回"
    echo ""

    local restore_path
    local path_choice
    while true; do
        read -rp " ${GREEN}[?]${RESET} 请选择路径: " path_choice
        case "$path_choice" in
        1)
            if [[ "$selected_bot_name" == "耶稣的机器人" ]]; then
                restore_path="/opt/remnawave-telegram-shop"
            elif [[ "$selected_bot_name" == "Machka 的机器人" ]]; then
                restore_path="/root/remnawave-tg-shop"
            else
                restore_path="/opt/remnashop"
            fi
            break
            ;;
        2)
            if [[ "$selected_bot_name" == "耶稣的机器人" ]]; then
                restore_path="/root/remnawave-telegram-shop"
            elif [[ "$selected_bot_name" == "Machka 的机器人" ]]; then
                restore_path="/root/remnawave-tg-shop"
            else
                restore_path="/root/remnashop"
            fi
            break
            ;;
        3)
            if [[ "$selected_bot_name" == "耶稣的机器人" ]]; then
                restore_path="/opt/stacks/remnawave-telegram-shop"
            elif [[ "$selected_bot_name" == "Machka 的机器人" ]]; then
                restore_path="/opt/stacks/remnawave-tg-shop"
            else
                restore_path="/opt/stacks/remnashop"
            fi
            break
            ;;
        4)
            echo ""
            print_message "INFO" "请输入用于恢复机器人的完整路径:"
            read -rp " 路径: " custom_restore_path
        
            if [[ -z "$custom_restore_path" ]]; then
                print_message "ERROR" "路径不能为空。"
                echo ""
                read -rp "按 Enter 继续..."
                continue
            fi
        
            if [[ ! "$custom_restore_path" = /* ]]; then
                print_message "ERROR" "路径必须为绝对路径（以 / 开头）。"
                echo ""
                read -rp "按 Enter 继续..."
                continue
            fi
        
            custom_restore_path="${custom_restore_path%/}"
            restore_path="$custom_restore_path"
            print_message "SUCCESS" "已设置自定义恢复路径: ${BOLD}${restore_path}${RESET}"
            break
            ;;
        0)
            print_message "INFO" "已取消机器人恢复。"
            return 0
            ;;
        *)
            print_message "ERROR" "输入无效。"
            ;;
        esac
    done

    local bot_params=$(get_bot_params "$selected_bot_name")
    IFS='|' read -r BOT_CONTAINER_NAME BOT_VOLUME_NAME BOT_DIR_NAME BOT_SERVICE_NAME <<< "$bot_params"
    
    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} 请输入机器人数据库用户名 (默认 postgres): ")" restore_bot_db_user
    restore_bot_db_user="${restore_bot_db_user:-postgres}"
    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} 请输入机器人数据库名 (默认 postgres): ")" restore_bot_db_name
    restore_bot_db_name="${restore_bot_db_name:-postgres}"
    echo ""
    print_message "INFO" "开始恢复 Telegram 机器人..."
    
    if [[ -d "$restore_path" ]]; then
        print_message "INFO" "目录 ${BOLD}${restore_path}${RESET} 已存在。停止容器并清理中..."
    
        if cd "$restore_path" 2>/dev/null && ([[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]); then
            print_message "INFO" "正在停止现有的机器人容器..."
            docker compose down 2>/dev/null || print_message "WARN" "无法停止容器（可能已经停止）。"
        else
            print_message "INFO" "未找到 Docker Compose 文件 (.yml 或 .yaml)，跳过停止容器。"
        fi
    fi
        
    cd /
        
    print_message "INFO" "删除旧目录..."
    if [[ -d "$restore_path" ]]; then
        if ! rm -rf "$restore_path"; then
            print_message "ERROR" "无法删除目录 ${BOLD}${restore_path}${RESET}。"
            return 1
        fi
        print_message "SUCCESS" "旧目录已删除。"
    else
        print_message "INFO" "目录 ${BOLD}${restore_path}${RESET} 不存在。这是一次全新安装。"
    fi
    
    print_message "INFO" "创建新目录..."
    if ! mkdir -p "$restore_path"; then
        print_message "ERROR" "无法创建目录 ${BOLD}${restore_path}${RESET}。"
        return 1
    fi
    print_message "SUCCESS" "新目录已创建。"
    echo ""
    
    if [[ -n "$BOT_DIR_ARCHIVE" ]]; then
        print_message "INFO" "从归档恢复机器人目录..."
        local temp_extract_dir="$BACKUP_DIR/bot_extract_temp_$$"
        mkdir -p "$temp_extract_dir"
        
        if tar -xzf "$BOT_DIR_ARCHIVE" -C "$temp_extract_dir"; then
            local extracted_dir=$(find "$temp_extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)

            if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                if cp -rf "$extracted_dir"/. "$restore_path/" 2>/dev/null; then
                    print_message "SUCCESS" "机器人目录文件已恢复 (文件夹: $(basename "$extracted_dir"))."
                else
                    print_message "ERROR" "复制机器人文件时出错。"
                    rm -rf "$temp_extract_dir"
                    return 1
                fi
            else
                print_message "ERROR" "未能在归档中找到机器人目录。"
                rm -rf "$temp_extract_dir"
                return 1
            fi
        else
            print_message "ERROR" "解压机器人目录归档时出错。"
            rm -rf "$temp_extract_dir"
            return 1
        fi
        rm -rf "$temp_extract_dir"
    else
        print_message "WARN" "未在备份中找到机器人目录归档。"
        return 1
    fi
    
    print_message "INFO" "检查并移除旧的数据库卷..."
    if docker volume ls -q | grep -Fxq "$BOT_VOLUME_NAME"; then
        local containers_using_volume
        containers_using_volume=$(docker ps -aq --filter volume="$BOT_VOLUME_NAME")
    
        if [[ -n "$containers_using_volume" ]]; then
            print_message "INFO" "发现使用卷 $BOT_VOLUME_NAME 的容器。正在删除..."
            docker rm -f $containers_using_volume >/dev/null 2>&1
        fi
    
        if docker volume rm "$BOT_VOLUME_NAME" >/dev/null 2>&1; then
            print_message "SUCCESS" "旧数据库卷 $BOT_VOLUME_NAME 已删除。"
        else
            print_message "WARN" "无法删除卷 $BOT_VOLUME_NAME。"
        fi
    else
        print_message "INFO" "未找到旧的数据库卷。"
    fi
    echo ""
    
    if ! cd "$restore_path"; then
        print_message "ERROR" "无法进入恢复后的目录 ${BOLD}${restore_path}${RESET}。"
        return 1
    fi
    
    if [[ ! -f "docker-compose.yml" && ! -f "docker-compose.yaml" ]]; then
    print_message "ERROR" "在恢复目录中未找到 docker-compose.yml 或 docker-compose.yaml 文件。"
    return 1
    fi
    
    print_message "INFO" "启动数据库容器..."
    if ! docker compose up -d "$BOT_SERVICE_NAME"; then
        print_message "ERROR" "无法启动机器人数据库容器。"
        return 1
    fi
    
    echo ""
    print_message "INFO" "等待数据库就绪..."
    local wait_count=0
    local max_wait=60
    
    until [ "$(docker inspect --format='{{.State.Health.Status}}' "$BOT_CONTAINER_NAME" 2>/dev/null)" == "healthy" ]; do
        sleep 2
        echo -n "."
        wait_count=$((wait_count + 1))
        if [ $wait_count -gt $max_wait ]; then
            echo ""
            print_message "ERROR" "等待机器人数据库就绪超时。"
            return 1
        fi
    done
    echo ""
    print_message "SUCCESS" "机器人数据库已就绪。"
    
    if [[ -n "$BOT_DUMP_FILE" ]]; then
        print_message "INFO" "正在从转储恢复机器人数据库..."
        local BOT_DUMP_UNCOMPRESSED="${BOT_DUMP_FILE%.gz}"
        
        if ! gunzip "$BOT_DUMP_FILE"; then
            print_message "ERROR" "无法解压机器人数据库转储。"
            return 1
        fi
        
        mkdir -p "$temp_restore_dir"

        if ! docker exec -i "$BOT_CONTAINER_NAME" psql -q -U "$restore_bot_db_user" -d "$restore_bot_db_name" > /dev/null 2> "$temp_restore_dir/restore_errors.log" < "$BOT_DUMP_UNCOMPRESSED"; then
            print_message "ERROR" "恢复机器人数据库时出错。"
            echo ""
            if [[ -f "$temp_restore_dir/restore_errors.log" ]]; then
                print_message "WARN" "${YELLOW}恢复错误日志:${RESET}"
                cat "$temp_restore_dir/restore_errors.log"
            fi
            [[ -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
            echo ""
            read -rp "按 Enter 返回菜单..."
            return 1
        fi

        print_message "SUCCESS" "机器人数据库已成功恢复。"
    else
        print_message "WARN" "归档中未找到数据库转储。"
    fi
    
    echo ""
    print_message "INFO" "启动机器人其余容器..."
    if ! docker compose up -d; then
        print_message "ERROR" "无法启动机器人所有容器。"
        return 1
    fi
    
    sleep 3
    return 0
}

save_config() {
    print_message "INFO" "正在将配置保存到 ${BOLD}${CONFIG_FILE}${RESET}..."
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_USER="$DB_USER"
UPLOAD_METHOD="$UPLOAD_METHOD"
GD_CLIENT_ID="$GD_CLIENT_ID"
GD_CLIENT_SECRET="$GD_CLIENT_SECRET"
GD_REFRESH_TOKEN="$GD_REFRESH_TOKEN"
GD_FOLDER_ID="$GD_FOLDER_ID"
CRON_TIMES="$CRON_TIMES"
REMNALABS_ROOT_DIR="$REMNALABS_ROOT_DIR"
TG_MESSAGE_THREAD_ID="$TG_MESSAGE_THREAD_ID"
BOT_BACKUP_ENABLED="$BOT_BACKUP_ENABLED"
BOT_BACKUP_PATH="$BOT_BACKUP_PATH"
BOT_BACKUP_SELECTED="$BOT_BACKUP_SELECTED"
BOT_BACKUP_DB_USER="$BOT_BACKUP_DB_USER"
SKIP_PANEL_BACKUP="$SKIP_PANEL_BACKUP"
EOF
    chmod 600 "$CONFIG_FILE" || { print_message "ERROR" "无法为 ${BOLD}${CONFIG_FILE}${RESET} 设置权限 (600)。请检查权限。"; }
    print_message "SUCCESS" "配置已保存。"
}

load_or_create_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        print_message "INFO" "正在加载配置..."
        source "$CONFIG_FILE"
        echo ""

        UPLOAD_METHOD=${UPLOAD_METHOD:-telegram}
        DB_USER=${DB_USER:-postgres}
        CRON_TIMES=${CRON_TIMES:-}
        REMNALABS_ROOT_DIR=${REMNALABS_ROOT_DIR:-}
        TG_MESSAGE_THREAD_ID=${TG_MESSAGE_THREAD_ID:-}
        SKIP_PANEL_BACKUP=${SKIP_PANEL_BACKUP:-false}
        
        local config_updated=false

        if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
            print_message "WARN" "配置文件中缺少用于 Telegram 的必要变量。"
            print_message "ACTION" "请填写缺失的 Telegram 信息（必填）:"
            echo ""
            print_message "INFO" "在 ${CYAN}@BotFather${RESET} 创建 Telegram 机器人并获取 API Token"
            [[ -z "$BOT_TOKEN" ]] && read -rp "    请输入 API Token: " BOT_TOKEN
            echo ""
            print_message "INFO" "请输入 Chat ID（用于发送到群组）或你的 Telegram ID（用于直接发送到机器人）"
            echo -e "       可用机器人 ${CYAN}@username_to_id_bot${RESET} 查询 Chat ID/Telegram ID"
            [[ -z "$CHAT_ID" ]] && read -rp "    请输入 ID: " CHAT_ID
            echo ""
            print_message "INFO" "可选: 若要发送到群组特定话题（topic），请输入话题 ID (Message Thread ID)"
            echo -e "       若留空则发送到默认话题或直接发送给机器人"
            read -rp "    请输入 Message Thread ID: " TG_MESSAGE_THREAD_ID
            echo ""
            config_updated=true
        fi

        if [[ "$SKIP_PANEL_BACKUP" != "true" && -z "$DB_USER" ]]; then
            print_message "INFO" "请输入面板的数据库用户名 (默认 postgres):"
            read -rp "    输入: " input_db_user
            DB_USER=${input_db_user:-postgres}
            config_updated=true
            echo ""
        fi
        
        if [[ "$SKIP_PANEL_BACKUP" != "true" && -z "$REMNALABS_ROOT_DIR" ]]; then
            print_message "ACTION" "你的 Remnawave 面板安装在何处?"
            echo " 1. /opt/remnawave"
            echo " 2. /root/remnawave"
            echo " 3. /opt/stacks/remnawave"
            echo " 4. 指定自定义路径"
            echo ""

            local remnawave_path_choice
            while true; do
                read -rp " ${GREEN}[?]${RESET} 请选择: " remnawave_path_choice
                case "$remnawave_path_choice" in
                1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                4) 
                    echo ""
                    print_message "INFO" "请输入 Remnawave 面板的完整路径:"
                    read -rp " 路径: " custom_remnawave_path
    
                    if [[ -z "$custom_remnawave_path" ]]; then
                        print_message "ERROR" "路径不能为空。"
                        echo ""
                        read -rp "按 Enter 继续..."
                        continue
                    fi
    
                    if [[ ! "$custom_remnawave_path" = /* ]]; then
                        print_message "ERROR" "路径必须为绝对路径（以 / 开头）。"
                        echo ""
                        read -rp "按 Enter 继续..."
                        continue
                    fi
    
                    custom_remnawave_path="${custom_remnawave_path%/}"
    
                    if [[ ! -d "$custom_remnawave_path" ]]; then
                        print_message "WARN" "目录 ${BOLD}${custom_remnawave_path}${RESET} 不存在。"
                        read -rp "$(echo -e "${GREEN}[?]${RESET} 是否继续使用此路径? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: ")" confirm_custom_path
                        if [[ "$confirm_custom_path" != "y" ]]; then
                            echo ""
                            read -rp "按 Enter 继续..."
                            continue
                        fi
                    fi
    
                    REMNALABS_ROOT_DIR="$custom_remnawave_path"
                    print_message "SUCCESS" "已设置自定义路径: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                    break 
                    ;;
                *) print_message "ERROR" "输入无效。" ;;
                esac
            done
            config_updated=true
            echo ""
        fi

        if [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "WARN" "配置文件中 Google Drive 的数据不完整。"
                print_message "WARN" "上传方式将切换为 ${BOLD}Telegram${RESET}。"
                UPLOAD_METHOD="telegram"
                config_updated=true
            fi
        fi

        if [[ "$UPLOAD_METHOD" == "google_drive" && ( -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ) ]]; then
            print_message "WARN" "配置文件缺少 Google Drive 的必要变量。"
            print_message "ACTION" "请填写缺失的 Google Drive 信息:"
            echo ""
            echo "如果你没有 Client ID 和 Client Secret"
            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
            print_message "LINK" "请参考此指南: ${CYAN}${guide_url}${RESET}"
            echo ""
            [[ -z "$GD_CLIENT_ID" ]] && read -rp "    请输入 Google Client ID: " GD_CLIENT_ID
            [[ -z "$GD_CLIENT_SECRET" ]] && read -rp "    请输入 Google Client Secret: " GD_CLIENT_SECRET
            clear
            
            if [[ -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "WARN" "要获得 Refresh Token 需要在浏览器中完成授权。"
                print_message "INFO" "打开下面的链接进行授权并复制返回的代码:"
                echo ""
                local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code"
                print_message "INFO" "${CYAN}${auth_url}${RESET}"
                echo ""
                read -rp "    请输入浏览器返回的代码: " AUTH_CODE
                
                print_message "INFO" "正在获取 Refresh Token..."
                local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                    -d client_id="$GD_CLIENT_ID" \
                    -d client_secret="$GD_CLIENT_SECRET" \
                    -d code="$AUTH_CODE" \
                    -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                    -d grant_type="authorization_code")
                
                GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                
                if [[ -z "$GD_REFRESH_TOKEN" || "$GD_REFRESH_TOKEN" == "null" ]]; then
                    print_message "ERROR" "无法获取 Refresh Token。请检查 Client ID、Client Secret 与输入的代码。"
                    print_message "WARN" "由于 Google Drive 设置未完成，上传方式将切换为 ${BOLD}Telegram${RESET}。"
                    UPLOAD_METHOD="telegram"
                    config_updated=true
                fi
            fi
            echo ""
            echo "    📁 指定 Google Drive 文件夹的方法:"
            echo "    1. 在浏览器中创建并打开目标文件夹。"
            echo "    2. 查看地址栏链接，格式类似："
            echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
            echo "    3. 复制 /folders/ 后面的部分 — 这就是 Folder ID。"
            echo "    4. 留空则上传到 Google Drive 根目录。"
            echo ""
            read -rp "    请输入 Google Drive Folder ID (留空为根目录): " GD_FOLDER_ID
            config_updated=true
        fi

        if $config_updated; then
            save_config
        else
            print_message "SUCCESS" "配置已成功从 ${BOLD}${CONFIG_FILE}${RESET} 加载。"
        fi

    else
        if [[ "$SCRIPT_RUN_PATH" != "$SCRIPT_PATH" ]]; then
            print_message "INFO" "未找到配置。脚本从临时位置运行。"
            print_message "INFO" "将脚本移到安装目录: ${BOLD}${SCRIPT_PATH}${RESET}..."
            mkdir -p "$INSTALL_DIR" || { print_message "ERROR" "无法创建安装目录 ${BOLD}${INSTALL_DIR}${RESET}。"; exit 1; }
            mkdir -p "$BACKUP_DIR" || { print_message "ERROR" "无法创建备份目录 ${BOLD}${BACKUP_DIR}${RESET}。"; exit 1; }

            if mv "$SCRIPT_RUN_PATH" "$SCRIPT_PATH"; then
                chmod +x "$SCRIPT_PATH"
                clear
                print_message "SUCCESS" "脚本已成功移动到 ${BOLD}${SCRIPT_PATH}${RESET}。"
                print_message "ACTION" "从新位置重启脚本以��成设置。"
                exec "$SCRIPT_PATH" "$@"
                exit 0
            else
                print_message "ERROR" "无法将脚本移动到 ${BOLD}${SCRIPT_PATH}${RESET}。"
                exit 1
            fi
        else
            print_message "INFO" "未找到配置，正在创建新的配置..."
            echo ""

            print_message "ACTION" "请选择脚本的工作模式:"
            echo " 1. 完整 (Remnawave 面板 + 可选机器人)"
            echo " 2. 仅机器人 (如果面板安装在另一台服务器)"
            echo ""
            read -rp " ${GREEN}[?]${RESET} 你的选择: " main_mode_choice
            
            if [[ "$main_mode_choice" == "2" ]]; then
                SKIP_PANEL_BACKUP="true"
                REMNALABS_ROOT_DIR="none"
            else
                SKIP_PANEL_BACKUP="false"
            fi
            echo ""

            print_message "INFO" "设置 Telegram 通知:"
            print_message "INFO" "在 ${CYAN}@BotFather${RESET} 创建 Telegram 机器人并获取 API Token"
            read -rp "    请输入 API Token: " BOT_TOKEN
            echo ""
            print_message "INFO" "请输入 Chat ID（用于群组）或你的 Telegram ID（用于直接发送）"
            echo -e "       可用机器人 ${CYAN}@username_to_id_bot${RESET} 查询 Chat ID/Telegram ID"
            read -rp "    请输入 ID: " CHAT_ID
            echo ""
            print_message "INFO" "可选: 若要发送到群组特定话题，请输入话题 ID (Message Thread ID)"
            echo -e "       留空则发送到默认话题或直接发送给机器人"
            read -rp "    请输入 Message Thread ID: " TG_MESSAGE_THREAD_ID
            echo ""

            if [[ "$SKIP_PANEL_BACKUP" == "false" ]]; then
                print_message "INFO" "请输入数据库用户名 (默认 postgres):"
                read -rp "    输入: " input_db_user
                DB_USER=${input_db_user:-postgres}
                echo ""

                print_message "ACTION" "你的 Remnawave 面板安装在何处?"
                echo " 1. /opt/remnawave"
                echo " 2. /root/remnawave"
                echo " 3. /opt/stacks/remnawave"
                echo " 4. 指定自定义路径"
                echo ""

                local remnawave_path_choice
                while true; do
                    read -rp " ${GREEN}[?]${RESET} 请选择: " remnawave_path_choice
                    case "$remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    4) 
                        echo ""
                        print_message "INFO" "请输入 Remnawave 面板的完整路径:"
                        read -rp " 路径: " custom_remnawave_path
                        if [[ -n "$custom_remnawave_path" ]]; then
                            REMNALABS_ROOT_DIR="${custom_remnawave_path%/}"
                            break
                        fi
                        ;;
                    *) print_message "ERROR" "输入无效。" ;;
                    esac
                done
            fi

            mkdir -p "$INSTALL_DIR"
            mkdir -p "$BACKUP_DIR"
            save_config
            print_message "SUCCESS" "已将新配置保存到 ${BOLD}${CONFIG_FILE}${RESET}"
        fi
    fi

    if [[ "$SKIP_PANEL_BACKUP" != "true" && ! -d "$REMNALABS_ROOT_DIR" ]]; then
        print_message "ERROR" "未在 $REMNALABS_ROOT_DIR 找到 Remnawave 目录。请检查 $CONFIG_FILE 的设置。"
        exit 1
    fi
    echo ""
}

escape_markdown_v2() {
    local text="$1"
    echo "$text" | sed \
        -e 's/\\/\\\\/g' \
        -e 's/_/\\_/g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g' \
        -e 's/(/\\(/g' \
        -e 's/)/\\)/g' \
        -e 's/~/\~/g' \
        -e 's/`/\\`/g' \
        -e 's/>/\\>/g' \
        -e 's/#/\\#/g' \
        -e 's/+/\\+/g' \
        -e 's/-/\\-/g' \
        -e 's/=/\\=/g' \
        -e 's/|/\\|/g' \
        -e 's/{/\\{/g' \
        -e 's/}/\\}/g' \
        -e 's/\./\\./g' \
        -e 's/!/\!/g'
}

get_remnawave_version() {
    local version_output
    version_output=$(docker exec remnawave sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json
 2>/dev/null)
    if [[ -z "$version_output" ]]; then
        echo "未定义"
    else
        echo "$version_output"
    fi
}

send_telegram_message() {
    local message="$1"
    local parse_mode="${2:-MarkdownV2}"
    local escaped_message
    escaped_message=$(escape_markdown_v2 "$message")

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        print_message "ERROR" "Telegram BOT_TOKEN 或 CHAT_ID 未配置。消息未发送。"
        return 1
    fi

    local url="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    local data_params=(
        -d chat_id="$CHAT_ID"
        -d text="$escaped_message"
    )

    [[ -n "$parse_mode" ]] && data_params+=(-d parse_mode="$parse_mode")
    [[ -n "$TG_MESSAGE_THREAD_ID" ]] && data_params+=(-d message_thread_id="$TG_MESSAGE_THREAD_ID")

    local response
    response=$(curl -s -X POST "$url" "${data_params[@]}" -w "\n%{http_code}")
    local body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" -eq 200 ]]; then
        return 0
    else
        echo -e "${RED}❌ 发送 Telegram 消息失败。HTTP 代码: ${BOLD}$http_code${RESET}"
        echo -e "Telegram 返回: ${body}"
        return 1
    fi
}

send_telegram_document() {
    local file_path="$1"
    local caption="$2"
    local parse_mode="MarkdownV2"
    local escaped_caption
    escaped_caption=$(escape_markdown_v2 "$caption")

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        print_message "ERROR" "Telegram BOT_TOKEN 或 CHAT_ID 未配置。文件未发送。"
        return 1
    fi

    local form_params=(
        -F chat_id="$CHAT_ID"
        -F document=@"$file_path"
        -F parse_mode="$parse_mode"
        -F caption="$escaped_caption"
    )

    if [[ -n "$TG_MESSAGE_THREAD_ID" ]]; then
        form_params+=(-F message_thread_id="$TG_MESSAGE_THREAD_ID")
    fi

    local api_response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        "${form_params[@]}" \
        -w "%{http_code}" -o /dev/null 2>&1)

    local curl_status=$?

    if [ $curl_status -ne 0 ]; then
        echo -e "${RED}❌ CURL 发送文件到 Telegram 时发生错误。退出码: ${BOLD}$curl_status${RESET}。请检查网络连接或 API 配置。"
        return 1
    fi

    local http_code="${api_response: -3}"

    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        echo -e "${RED}❌ Telegram API 返回错误 HTTP 代码: ${BOLD}$http_code${RESET}. 返回: ${BOLD}$api_response${RESET}. 可能文件过大或 API 配置有误。"
        return 1
    fi
}

get_google_access_token() {
    if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
        print_message "ERROR" "Google Drive 的 Client ID、Client Secret 或 Refresh Token 未配置。"
        return 1
    fi

    local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
        -d client_id="$GD_CLIENT_ID" \
        -d client_secret="$GD_CLIENT_SECRET" \
        -d refresh_token="$GD_REFRESH_TOKEN" \
        -d grant_type="refresh_token")
    
    local access_token=$(echo "$token_response" | jq -r .access_token 2>/dev/null)
    local expires_in=$(echo "$token_response" | jq -r .expires_in 2>/dev/null)

    if [[ -z "$access_token" || "$access_token" == "null" ]]; then
        local error_msg=$(echo "$token_response" | jq -r .error_description 2>/dev/null)
        print_message "ERROR" "无法获取 Google Drive 的 Access Token。可能 Refresh Token 已过期或无效。错误: ${error_msg}"
        print_message "ACTION" "请在“设置发送方式”菜单中重新配置 Google Drive。"
        return 1
    fi
    echo "$access_token"
    return 0
}

send_google_drive_document() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local access_token=$(get_google_access_token)

    if [[ -z "$access_token" ]]; then
        print_message "ERROR" "未获取到 Access Token，无法上传到 Google Drive。"
        return 1
    fi

    local mime_type="application/gzip"
    local upload_url="https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"

    local metadata_file=$(mktemp)
    
    local metadata="{\"name\": \"$file_name\", \"mimeType\": \"$mime_type\""
    if [[ -n "$GD_FOLDER_ID" ]]; then
        metadata="${metadata}, \"parents\": [\"$GD_FOLDER_ID\"]"
    fi
    metadata="${metadata}}"
    
    echo "$metadata" > "$metadata_file"

    local response=$(curl -s -X POST "$upload_url" \
        -H "Authorization: Bearer $access_token" \
        -F "metadata=@$metadata_file;type=application/json" \
        -F "file=@$file_path;type=$mime_type")

    rm -f "$metadata_file"

    local file_id=$(echo "$response" | jq -r .id 2>/dev/null)
    local error_message=$(echo "$response" | jq -r .error.message 2>/dev/null)
    local error_code=$(echo "$response" | jq -r .error.code 2>/dev/null)

    if [[ -n "$file_id" && "$file_id" != "null" ]]; then
        return 0
    else
        print_message "ERROR" "上传到 Google Drive 时出错。代码: ${error_code:-Unknown}. 信息: ${error_message:-Unknown error}. API 返回: $response"
        return 1
    fi
}

create_backup() {
    print_message "INFO" "开始创建备份..."
    echo ""
    
    REMNAWAVE_VERSION=$(get_remnawave_version)
    TIMESTAMP=$(date +%Y-%m-%d"_"%H_%M_%S)
    BACKUP_FILE_DB="dump_${TIMESTAMP}.sql.gz"
    BACKUP_FILE_FINAL="remnawave_backup_${TIMESTAMP}.tar.gz"
    
    mkdir -p "$BACKUP_DIR" || { 
        echo -e "${RED}❌ 错误: 无法创建备份目录。请检查权限.${RESET}"
        send_telegram_message "❌ 错误: 无法创建备份目录 ${BOLD}$BACKUP_DIR${RESET}。" "None"
        exit 1
    }
    
    BACKUP_ITEMS=()
    
    if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
        print_message "INFO" "跳过 Remnawave 面板的备份。"
    else
        if ! docker inspect remnawave-db > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' remnawave-db 2>/dev/null | grep -q "true"; then
            echo -e "${RED}❌ 错误: 容器 ${BOLD}'remnawave-db'${RESET} 未找到或未运行。无法创建数据库备份。${RESET}"
            local error_msg="❌ 错误: 容器 ${BOLD}'remnawave-db'${RESET} 未找到或未运行。无法创建备份。"
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "$error_msg" "None"
            elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
                print_message "ERROR" "由于数据库容器错误，无法上传到 Google Drive。"
            fi
            exit 1
        fi
        
        print_message "INFO" "正在创建 PostgreSQL 转储并压缩..."
        if ! docker exec -t "remnawave-db" pg_dumpall -c -U "$DB_USER" | gzip -9 > "$BACKUP_DIR/$BACKUP_FILE_DB"; then
            STATUS=$?
            echo -e "${RED}❌ 创建 PostgreSQL 转储时出错。退出码: ${BOLD}$STATUS${RESET}. 请检查数据库用户名及权限。${RESET}"
            local error_msg="❌ 创建 PostgreSQL 转储时出错。退出码: ${BOLD}${STATUS}${RESET}"
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "$error_msg" "None"
            elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
                print_message "ERROR" "由于数据库转储错误，无法上传到 Google Drive。"
            fi
            exit $STATUS
        fi
        
        print_message "SUCCESS" "PostgreSQL 转储已成功创建。"
        echo ""
        
        print_message "INFO" "正在归档 Remnawave 目录..."
        REMNAWAVE_DIR_ARCHIVE="remnawave_dir_${TIMESTAMP}.tar.gz"
        
        if [ -d "$REMNALABS_ROOT_DIR" ]; then
            print_message "INFO" "归档目录 ${BOLD}${REMNALABS_ROOT_DIR}${RESET}..."
            
            local exclude_args=""
            for pattern in $BACKUP_EXCLUDE_PATTERNS; do
                exclude_args+="--exclude=$pattern "
            done
            
            if eval "tar -czf '$BACKUP_DIR/$REMNAWAVE_DIR_ARCHIVE' $exclude_args -C '$(dirname "$REMNALABS_ROOT_DIR")' '$(basename "$REMNALABS_ROOT_DIR")'"; then
                print_message "SUCCESS" "Remnawave 目录已成功归档。"
                BACKUP_ITEMS=("$BACKUP_FILE_DB" "$REMNAWAVE_DIR_ARCHIVE")
            else
                STATUS=$?
                echo -e "${RED}❌ 归档 Remnawave 目录时出错。退出码: ${BOLD}$STATUS${RESET}.${RESET}"
                local error_msg="❌ 归档 Remnawave 目录时出错。退出码: ${BOLD}${STATUS}${RESET}"
                if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                    send_telegram_message "$error_msg" "None"
                fi
                exit $STATUS
            fi
        else
            print_message "ERROR" "未找到目录 ${BOLD}${REMNALABS_ROOT_DIR}${RESET}！"
            exit 1
        fi
    fi
    
    echo ""
    
    create_bot_backup
    
    if [[ ${#BACKUP_ITEMS[@]} -eq 0 ]]; then
        print_message "ERROR" "没有可备份的数据！请启用面板或机器人备份。"
        exit 1
    fi
    
    if ! tar -czf "$BACKUP_DIR/$BACKUP_FILE_FINAL" -C "$BACKUP_DIR" "${BACKUP_ITEMS[@]}"; then
        STATUS=$?
        echo -e "${RED}❌ 创建最终备份归档时出错。退出码: ${BOLD}$STATUS${RESET}.${RESET}"
        local error_msg="❌ 创建最终备份归档时出错。退出码: ${BOLD}${STATUS}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        fi
        exit $STATUS
    fi
    
    print_message "SUCCESS" "最终备份归档已创建: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}"
    echo ""
    
    print_message "INFO" "正在清理中间备份文件..."
    for item in "${BACKUP_ITEMS[@]}"; do
        rm -f "$BACKUP_DIR/$item"
    done
    print_message "SUCCESS" "中间文件已删除。"
    echo ""
    
    print_message "INFO" "正在发送备份 (${UPLOAD_METHOD})..."
    
    local DATE=$(date +'%Y-%m-%d %H:%M:%S')
    local backup_size=$(du -h "$BACKUP_DIR/$BACKUP_FILE_FINAL" | awk '{print $1}')
    
    local backup_info=""
    if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
        backup_info=$'\n🤖 *仅 Telegram 机器人*'
    elif [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
        backup_info=$'\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"$'\n🤖 *+ Telegram 机器人*'
    else
        backup_info=$'\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"$'\n🖥️ *仅面板*'
    fi

    local caption_text=$'💾 #backup_success\n➖➖➖➖➖➖➖➖➖\n✅ *备份已成功创建*'"${backup_info}"$'\n📁 *数据库 + 目录*\n📏 *大小:* '"${backup_size}"
    local backup_size=$(du -h "$BACKUP_DIR/$BACKUP_FILE_FINAL" | awk '{print $1}')

    if [[ -f "$BACKUP_DIR/$BACKUP_FILE_FINAL" ]]; then
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            if send_telegram_document "$BACKUP_DIR/$BACKUP_FILE_FINAL" "$caption_text"; then
                print_message "SUCCESS" "备份已成功发送至 Telegram。"
            else
                echo -e "${RED}❌ 发送备份到 Telegram 时出错。请检查 Telegram API 设置（Token、Chat ID）。${RESET}"
            fi
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            if send_google_drive_document "$BACKUP_DIR/$BACKUP_FILE_FINAL"; then
                print_message "SUCCESS" "备份已成功上传到 Google Drive。"
                local tg_success_message="${caption_text//备份已成功创建/备份已成功创建并上传到 Google Drive}"
                
                if send_telegram_message "$tg_success_message"; then
                    print_message "SUCCESS" "已在 Telegram 发送关于上传到 Google Drive 的通知。"
                else
                    print_message "ERROR" "上传到 Google Drive 后无法发送 Telegram 通知。"
                fi
            else
                echo -e "${RED}❌ 上传备份到 Google Drive 时出错。请检查 Google Drive API 设置。${RESET}"
                send_telegram_message "❌ 错误: 无法将备份上传到 Google Drive。详情请查看服务器日志。" "None"
            fi
        else
            print_message "WARN" "未知的发送方式: ${BOLD}${UPLOAD_METHOD}${RESET}. 备份未发送。"
            send_telegram_message "❌ 错误: 未知的备份发送方式: ${BOLD}${UPLOAD_METHOD}${RESET}. 文件: ${BOLD}${BACKUP_FILE_FINAL}${RESET}" "None"
        fi
    else
        echo -e "${RED}❌ 错误: 创建后未找到最终备份文件: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}. 发送已取消。${RESET}"
        local error_msg="❌ 错误: 创建后未找到备份文件: ${BOLD}${BACKUP_FILE_FINAL}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "无法上传到 Google Drive: 未找到备份文件。"
        fi
        exit 1
    fi
    
    echo ""
    
    print_message "INFO" "应用备份保留策略 (保留最近 ${BOLD}${RETAIN_BACKUPS_DAYS}${RESET} 天的备份)..."
    find "$BACKUP_DIR" -maxdepth 1 -name "remnawave_backup_*.tar.gz" -mtime +$RETAIN_BACKUPS_DAYS -delete
    print_message "SUCCESS" "保留策略已应用。旧备份已删除。"
    
    echo ""
    
    {
        check_update_status >/dev/null 2>&1
        
        if [[ "$UPDATE_AVAILABLE" == true ]]; then
            local CURRENT_VERSION="$VERSION"
            local REMOTE_VERSION_LATEST
            REMOTE_VERSION_LATEST=$(curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | grep -m 1 "^VERSION=" | cut -d'"' -f2)
            
            if [[ -n "$REMOTE_VERSION_LATEST" ]]; then
                local update_msg=$'⚠️ *有可用的脚本更新*\n🔄 *当前版本:* '"${CURRENT_VERSION}"$'\n🆕 *最新版本:* '"${REMOTE_VERSION_LATEST}"
                send_telegram_message "$update_msg" >/dev/null 2>&1
            fi
        fi
    } &
}

setup_auto_send() {
    echo ""
    if [[ $EUID -ne 0 ]]; then
        print_message "WARN" "设置 cron 需要 root 权限。请使用 '${BOLD}sudo'${RESET} 运行。"
        read -rp "按 Enter 继续..."
        return
    fi
    while true; do
        clear
        echo -e "${GREEN}${BOLD}设置自动发送${RESET}"
        echo ""
        if [[ -n "$CRON_TIMES" ]]; then
            print_message "INFO" "自动发送已设置为: ${BOLD}${CRON_TIMES}${RESET} （UTC+0）。"
        else
            print_message "INFO" "自动发送 ${BOLD}已关闭${RESET}。"
        fi
        echo ""
        echo "   1. 启用/覆盖 自动发送备份"
        echo "   2. 关闭 自动发送备份"
        echo "   0. 返回主菜单"
        echo ""
        read -rp "${GREEN}[?]${RESET} 请选择: " choice
        echo ""
        case $choice in
            1)
                local server_offset_str=$(date +%z)
                local offset_sign="${server_offset_str:0:1}"
                local offset_hours=$((10#${server_offset_str:1:2}))
                local offset_minutes=$((10#${server_offset_str:3:2}))

                local server_offset_total_minutes=$((offset_hours * 60 + offset_minutes))
                if [[ "$offset_sign" == "-" ]]; then
                    server_offset_total_minutes=$(( -server_offset_total_minutes ))
                fi

                echo "选择自动发送选项:"
                echo "  1) 输入时间（例如: 08:00 12:00 18:00）"
                echo "  2) 每小时"
                echo "  3) 每日"
                read -rp "你的选择: " send_choice
                echo ""

                cron_times_to_write=()
                user_friendly_times_local=""
                invalid_format=false

                if [[ "$send_choice" == "1" ]]; then
                    echo "请输入希望的发送时间（UTC+0，例如 08:00 12:00）:"
                    read -rp "时间（用空格分隔）: " times
                    IFS=' ' read -ra arr <<< "$times"

                    for t in "${arr[@]}"; do
                        if [[ $t =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
                            local hour_utc_input=$((10#${BASH_REMATCH[1]}))
                            local min_utc_input=$((10#${BASH_REMATCH[2]}))

                            if (( hour_utc_input >= 0 && hour_utc_input <= 23 && min_utc_input >= 0 && min_utc_input <= 59 )); then
                                local total_minutes_utc=$((hour_utc_input * 60 + min_utc_input))
                                local total_minutes_local=$((total_minutes_utc + server_offset_total_minutes))

                                while (( total_minutes_local < 0 )); do
                                    total_minutes_local=$((total_minutes_local + 24 * 60))
                                done
                                while (( total_minutes_local >= 24 * 60 )); do
                                    total_minutes_local=$((total_minutes_local - 24 * 60))
                                done

                                local hour_local=$((total_minutes_local / 60))
                                local min_local=$((total_minutes_local % 60))

                                cron_times_to_write+=("$min_local $hour_local")
                                user_friendly_times_local+="$t "
                            else
                                print_message "ERROR" "时间值无效: ${BOLD}$t${RESET} (小时 0-23, 分钟 0-59)。"
                                invalid_format=true
                                break
                            fi
                        else
                            print_message "ERROR" "时间格式无效: ${BOLD}$t${RESET} (应为 HH:MM)。"
                            invalid_format=true
                            break
                        fi
                    done
                elif [[ "$send_choice" == "2" ]]; then
                    cron_times_to_write=("@hourly")
                    user_friendly_times_local="@hourly"
                elif [[ "$send_choice" == "3" ]]; then
                    cron_times_to_write=("@daily")
                    user_friendly_times_local="@daily"
                else
                    print_message "ERROR" "选择无效。"
                    continue
                fi

                echo ""

                if [ "$invalid_format" = true ] || [ ${#cron_times_to_write[@]} -eq 0 ]; then
                    print_message "ERROR" "由于时间输入错误，未设置自动发送。请重试。"
                    continue
                fi

                print_message "INFO" "正在设置 cron 任务以便自动发送..."

                local temp_crontab_file=$(mktemp)

                if ! crontab -l > "$temp_crontab_file" 2>/dev/null; then
                    touch "$temp_crontab_file"
                fi

                if ! grep -q "^SHELL=" "$temp_crontab_file"; then
                    echo "SHELL=/bin/bash" | cat - "$temp_crontab_file" > "$temp_crontab_file.tmp"
                    mv "$temp_crontab_file.tmp" "$temp_crontab_file"
                    print_message "INFO" "已在 crontab 中添加 SHELL=/bin/bash。"
                fi

                if ! grep -q "^PATH=" "$temp_crontab_file"; then
                    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin" | cat - "$temp_crontab_file" > "$temp_crontab_file.tmp"
                    mv "$temp_crontab_file.tmp" "$temp_crontab_file"
                    print_message "INFO" "已在 crontab 中添加 PATH 变量。"
                else
                    print_message "INFO" "crontab 中已存在 PATH 变量。"
                fi

                grep -vF "$SCRIPT_PATH backup" "$temp_crontab_file" > "$temp_crontab_file.tmp"
                mv "$temp_crontab_file.tmp" "$temp_crontab_file"

                for time_entry_local in "${cron_times_to_write[@]}"; do
                    if [[ "$time_entry_local" == "@hourly" ]] || [[ "$time_entry_local" == "@daily" ]]; then
                        echo "$time_entry_local $SCRIPT_PATH backup >> /var/log/rw_backup_cron.log 2>&1" >> "$temp_crontab_file"
                    else
                        echo "$time_entry_local * * * $SCRIPT_PATH backup >> /var/log/rw_backup_cron.log 2>&1" >> "$temp_crontab_file"
                    fi
                done

                if crontab "$temp_crontab_file"; then
                    print_message "SUCCESS" "CRON 任务已成功安装。"
                else
                    print_message "ERROR" "无法安装 CRON 任务。请检查权限并确认 crontab 可用。"
                fi

                rm -f "$temp_crontab_file"

                CRON_TIMES="${user_friendly_times_local% }"
                save_config
                print_message "SUCCESS" "自动发送已设置为: ${BOLD}${CRON_TIMES}${RESET} （UTC+0）。"
                ;;
            2)
                print_message "INFO" "正在关闭自动发送..."
                (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -

                CRON_TIMES=""
                save_config
                print_message "SUCCESS" "自动发送已成功关闭。"
                ;;
            0) break ;;
            *) print_message "ERROR" "输入无效。请选择一个有效选项。" ;;
        esac
        echo ""
        read -rp "按 Enter 继续..."
    done
    echo ""
}
    
restore_backup() {
    clear
    echo "${GREEN}${BOLD}从备份恢复${RESET}"
    echo ""

    print_message "INFO" "请将备份文件放到目录: ${BOLD}${BACKUP_DIR}${RESET}"
    echo ""

    if ! compgen -G "$BACKUP_DIR/remnawave_backup_*.tar.gz" > /dev/null; then
        print_message "ERROR" "错误: 在 ${BOLD}${BACKUP_DIR}${RESET} 未找到备份文件。"
        read -rp "按 Enter 返回菜单..."
        return
    fi

    readarray -t SORTED_BACKUP_FILES < <(
        find "$BACKUP_DIR" -maxdepth 1 -name "remnawave_backup_*.tar.gz" -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-
    )

    echo ""
    echo "请选择要恢复的文件:"
    local i=1
    for file in "${SORTED_BACKUP_FILES[@]}"; do
        echo " $i) ${file##*/}"
        i=$((i+1))
    done
    echo ""
    echo " 0) 返回主菜单"
    echo ""

    local user_choice selected_index
    while true; do
        read -rp "${GREEN}[?]${RESET} 输入文件编号 (0 退出): " user_choice
        [[ "$user_choice" == "0" ]] && return
        [[ "$user_choice" =~ ^[0-9]+$ ]] || { print_message "ERROR" "输入无效。"; continue; }
        selected_index=$((user_choice - 1))
        (( selected_index >= 0 && selected_index < ${#SORTED_BACKUP_FILES[@]} )) && break
        print_message "ERROR" "编号无效。"
    done

    SELECTED_BACKUP="${SORTED_BACKUP_FILES[$selected_index]}"

    clear
    print_message "INFO" "正在解压备份归档..."
    local temp_restore_dir="$BACKUP_DIR/restore_temp_$$"
    mkdir -p "$temp_restore_dir"

    if ! tar -xzf "$SELECTED_BACKUP" -C "$temp_restore_dir"; then
        print_message "ERROR" "解压归档时出错。"
        rm -rf "$temp_restore_dir"
        read -rp "按 Enter 返回菜单..."
        return
    fi

    print_message "SUCCESS" "归档已解压。"
    echo ""

    local PANEL_DUMP
    PANEL_DUMP=$(find "$temp_restore_dir" -name "dump_*.sql.gz" | head -n 1)
    local PANEL_DIR_ARCHIVE
    PANEL_DIR_ARCHIVE=$(find "$temp_restore_dir" -name "remnawave_dir_*.tar.gz" | head -n 1)

    local PANEL_STATUS=2 
    local BOT_STATUS=2

    if [[ -z "$PANEL_DUMP" || -z "$PANEL_DIR_ARCHIVE" ]]; then
        print_message "WARN" "在备份中未找到面板文件。"
        PANEL_STATUS=2
    else
        print_message "WARN" "检测到面板备份。恢复将覆盖当前数据库。"
        read -rp "$(echo -e "${GREEN}[?]${RESET} 是否恢复面板? (${GREEN}Y${RESET} - 是 / ${RED}N${RESET} - 跳过): ")" confirm_panel
        echo ""
        if [[ "$confirm_panel" =~ ^[Yy]$ ]]; then
            check_docker_installed || { rm -rf "$temp_restore_dir"; return 1; }
            print_message "INFO" "请输入数据库名 (默认 postgres):"
            read -rp "输入: " restore_db_name
            restore_db_name="${restore_db_name:-postgres}"

            if [[ -d "$REMNALABS_ROOT_DIR" ]]; then
                cd "$REMNALABS_ROOT_DIR" 2>/dev/null && docker compose down 2>/dev/null
                cd ~
                rm -rf "$REMNALABS_ROOT_DIR"
            fi

            mkdir -p "$REMNALABS_ROOT_DIR"
            local extract_dir="$BACKUP_DIR/extract_temp_$$"
            mkdir -p "$extract_dir"
            tar -xzf "$PANEL_DIR_ARCHIVE" -C "$extract_dir"
            local extracted_dir
            extracted_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            cp -rf "$extracted_dir"/. "$REMNALABS_ROOT_DIR/"
            rm -rf "$extract_dir"

            docker volume rm remnawave-db-data 2>/dev/null || true
            cd "$REMNALABS_ROOT_DIR" || { print_message "ERROR" "未找到目录"; return; }
            docker compose up -d remnawave-db

            print_message "INFO" "等待数据库就绪..."
            until [[ "$(docker inspect --format='{{.State.Health.Status}}' remnawave-db)" == "healthy" ]]; do
                sleep 2
                echo -n "."
            done
            echo ""

            print_message "INFO" "正在恢复数据库..."
            gunzip "$PANEL_DUMP"
            local sql_file="${PANEL_DUMP%.gz}"
            local restore_log="$temp_restore_dir/restore_errors.log"

            if ! docker exec -i remnawave-db psql -q -U "$DB_USER" -d "$restore_db_name" > /dev/null 2> "$restore_log" < "$sql_file"; then
                echo ""
                print_message "ERROR" "恢复数据库时出错。"
                [[ -f "$restore_log" ]] && cat "$restore_log"
                rm -rf "$temp_restore_dir"
                read -rp "按 Enter 返回菜单..."
                return 1
            fi

            print_message "SUCCESS" "数据库恢复成功。"
            echo ""
            print_message "INFO" "正在启动其他容器..."
            
            if docker compose up -d; then
                print_message "SUCCESS" "面板已成功启动。"
                PANEL_STATUS=0
            else
                print_message "ERROR" "无法启动面板容器。"
                rm -rf "$temp_restore_dir"
                read -rp "按 Enter 返回菜单..."
                return 1
            fi
        else
            print_message "INFO" "用户选择跳过面板恢复。"
            PANEL_STATUS=2
        fi
    fi

    echo ""

    if [[ "$PANEL_STATUS" == "0" ]]; then
        print_message "WARN" "面板已就绪。按 Enter 继续..."
        read -rp ""
    fi

    if restore_bot_backup "$temp_restore_dir"; then
        BOT_STATUS=0
    else
        local res=$?
        if [[ "$res" == "2" ]]; then BOT_STATUS=2; else BOT_STATUS=1; fi
    fi

    rm -rf "$temp_restore_dir"
    sleep 2
    
    REMNAWAVE_VERSION=$(get_remnawave_version)
    local telegram_msg
    telegram_msg=$'💾 #restore_success\n➖➖➖➖➖➖➖➖➖\n✅ *恢复完成*\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"

    if [[ "$PANEL_STATUS" == "0" && "$BOT_STATUS" == "0" ]]; then
        telegram_msg+=$'\n✨ *面板和 Telegram 机器人*'
    elif [[ "$PANEL_STATUS" == "0" ]]; then
        telegram_msg+=$'\n📦 *仅面板*'
    elif [[ "$BOT_STATUS" == "0" ]]; then
        telegram_msg+=$'\n🤖 *仅 Telegram 机器人*'
    else
        telegram_msg+=$'\n⚠️ *未恢复任何内容*'
    fi

    print_message "SUCCESS" "恢复过程已完成。"
    send_telegram_message "$telegram_msg" >/dev/null 2>&1
    read -rp "按 Enter 返回主菜单..."
}

update_script() {
    print_message "INFO" "开始检查脚本更新..."
    echo ""
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}⛔ 更新脚本需要 root 权限。请使用 '${BOLD}sudo'${RESET} 运行。${RESET}"
        read -rp "按 Enter 继续..."
        return
    fi

    print_message "INFO" "从 GitHub 获取脚本最新版本信息..."
    local TEMP_REMOTE_VERSION_FILE
    TEMP_REMOTE_VERSION_FILE=$(mktemp)

    if ! curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | head -n 100 > "$TEMP_REMOTE_VERSION_FILE"; then
        print_message "ERROR" "无法从 GitHub 下载新版本信息。请检查 URL 或网络连接。"
        rm -f "$TEMP_REMOTE_VERSION_FILE"
        read -rp "按 Enter 继续..."
        return
    fi

    REMOTE_VERSION=$(grep -m 1 "^VERSION=" "$TEMP_REMOTE_VERSION_FILE" | cut -d'"' -f2)
    rm -f "$TEMP_REMOTE_VERSION_FILE"

    if [[ -z "$REMOTE_VERSION" ]]; then
        print_message "ERROR" "无法从远程脚本提取版本信息。可能 VERSION 变量的格式不同。"
        read -rp "按 Enter 继续..."
        return
    fi

    print_message "INFO" "当前版本: ${BOLD}${YELLOW}${VERSION}${RESET}"
    print_message "INFO" "可用版本: ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}"
    echo ""

    compare_versions() {
        local v1="$1"
        local v2="$2"

        local v1_num="${v1//[^0-9.]/}"
        local v2_num="${v2//[^0-9.]/}"

        local v1_sfx="${v1//$v1_num/}"
        local v2_sfx="${v2//$v2_num/}"

        if [[ "$v1_num" == "$v2_num" ]]; then
            if [[ -z "$v1_sfx" && -n "$v2_sfx" ]]; then
                return 0
            elif [[ -n "$v1_sfx" && -z "$v2_sfx" ]]; then
                return 1
            elif [[ "$v1_sfx" < "$v2_sfx" ]]; then
                return 0
            else
                return 1
            fi
        else
            if printf '%s\n' "$v1_num" "$v2_num" | sort -V | head -n1 | grep -qx "$v1_num"; then
                return 0
            else
                return 1
            fi
        fi
    }

    if compare_versions "$VERSION" "$REMOTE_VERSION"; then
        print_message "ACTION" "发现可用更新: ${BOLD}${REMOTE_VERSION}${RESET}。"
        echo -e -n "是否更新脚本? 输入 ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: "
        read -r confirm_update
        echo ""

        if [[ "${confirm_update,,}" != "y" ]]; then
            print_message "WARN" "用户取消更新。返回主菜单。"
            read -rp "按 Enter 继续..."
            return
        fi
    else
        print_message "INFO" "你已安装最新脚本版本。无需更新。"
        read -rp "按 Enter 继续..."
        return
    fi

    local TEMP_SCRIPT_PATH="${INSTALL_DIR}/backup-restore.sh.tmp"
    print_message "INFO" "正在下载更新..."
    if ! curl -fsSL "$SCRIPT_REPO_URL" -o "$TEMP_SCRIPT_PATH"; then
        print_message "ERROR" "无法下载脚本新版本。"
        read -rp "按 Enter 继续..."
        return
    fi

    if [[ ! -s "$TEMP_SCRIPT_PATH" ]] || ! head -n 1 "$TEMP_SCRIPT_PATH" | grep -q -e '^#!.*bash'; then
        print_message "ERROR" "下载的文件为空或不是可执行的 bash 脚本。更新中止。"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "按 Enter 继续..."
        return
    fi

    print_message "INFO" "正在删除旧的脚本备份..."
    find "$(dirname "$SCRIPT_PATH")" -maxdepth 1 -name "${SCRIPT_NAME}.bak.*" -type f -delete
    echo ""

    local BACKUP_PATH_SCRIPT="${SCRIPT_PATH}.bak.$(date +%s)"
    print_message "INFO" "正在创建当前脚本的备份..."
    cp "$SCRIPT_PATH" "$BACKUP_PATH_SCRIPT" || {
        echo -e "${RED}❌ 无法创建脚本备份 ${BOLD}${SCRIPT_PATH}${RESET}. 更新取消。${RESET}"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "按 Enter 继续..."
        return
    }
    echo ""

    mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH" || {
        echo -e "${RED}❌ 无法将临时文件移动到 ${BOLD}${SCRIPT_PATH}${RESET}. 请检查权限。${RESET}"
        echo -e "${YELLOW}⚠️ 正在从备份恢复 ${BOLD}${BACKUP_PATH_SCRIPT}${RESET}...${RESET}"
        mv "$BACKUP_PATH_SCRIPT" "$SCRIPT_PATH"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "按 Enter 继续..."
        return
    }

    chmod +x "$SCRIPT_PATH"
    print_message "SUCCESS" "脚本已成功更新到版本 ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}。"
    echo ""
    print_message "INFO" "为使更改生效脚本将重启..."
    read -rp "按 Enter 重启脚本。"
    exec "$SCRIPT_PATH" "$@"
    exit 0
}

remove_script() {
    print_message "WARN" "${YELLOW}注意!${RESET} 将删除: "
    echo  " - 脚本本身"
    echo  " - 安装目录及所有备份"
    echo  " - 符号链接（如存在）"
    echo  " - cron 任务"
    echo ""
    echo -e -n "确定要继续吗? 输入 ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: "
    read -r confirm
    echo ""
    
    if [[ "${confirm,,}" != "y" ]]; then
    print_message "WARN" "已取消删除。"
    read -rp "按 Enter 继续..."
    return
    fi

    if [[ "$EUID" -ne 0 ]]; then
        print_message "WARN" "完全删除需要 root 权限。请使用 ${BOLD}sudo${RESET} 运行。"
        read -rp "按 Enter 继续..."
        return
    fi

    print_message "INFO" "正在删除 cron 任务..."
    if crontab -l 2>/dev/null | grep -qF "$SCRIPT_PATH backup"; then
        (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -
        print_message "SUCCESS" "自动备份的 cron 任务已删除。"
    else
        print_message "INFO" "未找到自动备份的 cron 任务。"
    fi
    echo ""

    print_message "INFO" "正在删除符号链接..."
    if [[ -L "$SYMLINK_PATH" ]]; then
        rm -f "$SYMLINK_PATH" && print_message "SUCCESS" "符号链接 ${BOLD}${SYMLINK_PATH}${RESET} 已删除。" || print_message "WARN" "无法删除符号链接 ${BOLD}${SYMLINK_PATH}${RESET}。请检查权限。"
    elif [[ -e "$SYMLINK_PATH" ]]; then
        print_message "WARN" "${BOLD}${SYMLINK_PATH}${RESET} 存在，但不是符号链接。建议人工检查。"
    else
        print_message "INFO" "未找到符号链接 ${BOLD}${SYMLINK_PATH}${RESET}。"
    fi
    echo ""

    print_message "INFO" "正在删除安装目录及所有数据..."
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR" && print_message "SUCCESS" "安装目录 ${BOLD}${INSTALL_DIR}${RESET}（包含脚本、配置、备份）已删除。" || print_message "WARN" "无法完全删除 ${BOLD}${INSTALL_DIR}${RESET}。请检查权限。"
    else
        print_message "INFO" "未找到安装目录 ${BOLD}${INSTALL_DIR}${RESET}。"
    fi
    exit 0
}

configure_upload_method() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}设置备份发送方式${RESET}"
        echo ""
        print_message "INFO" "当前方式: ${BOLD}${UPLOAD_METHOD^^}${RESET}"
        echo ""
        echo "   1. 设置为: Telegram"
        echo "   2. 设置为: Google Drive"
        echo ""
        echo "   0. 返回主菜单"
        echo ""
        read -rp "${GREEN}[?]${RESET} 请选择: " choice
        echo ""

        case $choice in
            1)
                UPLOAD_METHOD="telegram"
                save_config
                print_message "SUCCESS" "发送方式已设置为 ${BOLD}Telegram${RESET}。"
                if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
                    print_message "ACTION" "请填写 Telegram 信息:"
                    echo ""
                    print_message "INFO" "在 ${CYAN}@BotFather${RESET} 创建 Telegram 机器人并获取 API Token"
                    read -rp "   请输入 API Token: " BOT_TOKEN
                    echo ""
                    print_message "INFO" "可以通过 ${CYAN}@userinfobot${RESET} 获取你的 Telegram ID"
                    read -rp "   请输入 Telegram ID: " CHAT_ID
                    save_config
                    print_message "SUCCESS" "Telegram 设置已保存。"
                fi
                ;;
            2)
                UPLOAD_METHOD="google_drive"
                print_message "SUCCESS" "发送方式已设置为 ${BOLD}Google Drive${RESET}。"
                
                local gd_setup_successful=true

                if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
                    print_message "ACTION" "请填写 Google Drive API 的信息。"
                    echo ""
                    echo "如果你没有 Client ID 和 Client Secret"
                    local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                    print_message "LINK" "请参考此指南: ${CYAN}${guide_url}${RESET}"
                    read -rp "   请输入 Google Client ID: " GD_CLIENT_ID
                    read -rp "   请输入 Google Client Secret: " GD_CLIENT_SECRET
                    
                    clear
                    
                    print_message "WARN" "要获取 Refresh Token 需要在浏览器中完成授权。"
                    print_message "INFO" "打开下面的链接进行授权并复制返回的代码:"
                    echo ""
                    local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code"
                    print_message "INFO" "${CYAN}${auth_url}${RESET}"
                    echo ""
                    read -rp "请输入浏览器返回的代码: " AUTH_CODE
                    
                    print_message "INFO" "正在获取 Refresh Token..."
                    local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                        -d client_id="$GD_CLIENT_ID" \
                        -d client_secret="$GD_CLIENT_SECRET" \
                        -d code="$AUTH_CODE" \
                        -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                        -d grant_type="authorization_code")
                    
                    GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                    
                    if [[ -z "$GD_REFRESH_TOKEN" || "$GD_REFRESH_TOKEN" == "null" ]]; then
                        print_message "ERROR" "无法获取 Refresh Token。请检查输入的信息。"
                        print_message "WARN" "设置未完成，发送方式将切换回 ${BOLD}Telegram${RESET}。"
                        UPLOAD_METHOD="telegram"
                        gd_setup_successful=false
                    else
                        print_message "SUCCESS" "Refresh Token 获取成功。"
                    fi
                    echo
                    
                    if $gd_setup_successful; then
                        echo "   📁 指定 Google Drive 文件夹的方法:"
                        echo "   1. 在浏览器中创建并打开目标文件夹。"
                        echo "   2. 查看地址栏链接，格式类似："
                        echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                        echo "   3. 复制 /folders/ 后面的部分 — 这就是 Folder ID。"
                        echo "   4. 留空则上传到 Google Drive 根目录。"
                        echo

                        read -rp "   请输入 Google Drive Folder ID (留空为根目录): " GD_FOLDER_ID
                    fi
                fi

                save_config

                if $gd_setup_successful; then
                    print_message "SUCCESS" "Google Drive 设置已保存。"
                else
                    print_message "SUCCESS" "发送方式已切换回 ${BOLD}Telegram${RESET}。"
                fi
                ;;
            0) break ;;
            *) print_message "ERROR" "输入无效。请选择一个有效项。" ;;
        esac
        echo ""
        read -rp "按 Enter 继续..."
    done
    echo ""
}

configure_settings() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}脚本配置设置${RESET}"
        echo ""
        echo "   1. Telegram 设置"
        echo "   2. Google Drive 设置"
        echo "   3. Remnawave 的数据库用户名"
        echo "   4. Remnawave 路径"
        echo ""
        echo "   0. 返回主菜单"
        echo ""
        read -rp "${GREEN}[?]${RESET} 请选择: " choice
        echo ""

        case $choice in
            1)
                while true; do
                    clear
                    echo -e "${GREEN}${BOLD}Telegram 设置${RESET}"
                    echo ""
                    print_message "INFO" "当前 API Token: ${BOLD}${BOT_TOKEN}${RESET}"
                    print_message "INFO" "当前 ID: ${BOLD}${CHAT_ID}${RESET}"
                    print_message "INFO" "当前 Message Thread ID: ${BOLD}${TG_MESSAGE_THREAD_ID:-未设置}${RESET}"
                    echo ""
                    echo "   1. 更改 API Token"
                    echo "   2. 更改 ID"
                    echo "   3. 更改 Message Thread ID（用于群组主题）"
                    echo ""
                    echo "   0. 返回"
                    echo ""
                    read -rp "${GREEN}[?]${RESET} 请选择: " telegram_choice
                    echo ""

                    case $telegram_choice in
                        1)
                            print_message "INFO" "在 ${CYAN}@BotFather${RESET} 创建 Telegram 机器人并获取 API Token"
                            read -rp "   请输入新的 API Token: " NEW_BOT_TOKEN
                            BOT_TOKEN="$NEW_BOT_TOKEN"
                            save_config
                            print_message "SUCCESS" "API Token 更新成功。"
                            ;;
                        2)
                            print_message "INFO" "请输入 Chat ID（用于群组）或你的 Telegram ID（直接发送）"
                            echo -e "       可使用 ${CYAN}@username_to_id_bot${RESET} 查询 Chat ID/Telegram ID"
                            read -rp "   请输入新的 ID: " NEW_CHAT_ID
                            CHAT_ID="$NEW_CHAT_ID"
                            save_config
                            print_message "SUCCESS" "ID 更新成功。"
                            ;;
                        3)
                            print_message "INFO" "可选: 输入群组话题 ID (Message Thread ID)"
                            echo -e "       留空则发送到默认话题或直接发送到机器人"
                            read -rp "   请输入 Message Thread ID: " NEW_TG_MESSAGE_THREAD_ID
                            TG_MESSAGE_THREAD_ID="$NEW_TG_MESSAGE_THREAD_ID"
                            save_config
                            print_message "SUCCESS" "Message Thread ID 更新成功。"
                            ;;
                        0) break ;;
                        *) print_message "ERROR" "输入无效。请选择一个有效项。" ;;
                    esac
                    echo ""
                    read -rp "按 Enter 继续..."
                done
                ;;

            2)
                while true; do
                    clear
                    echo -e "${GREEN}${BOLD}Google Drive 设置${RESET}"
                    echo ""
                    print_message "INFO" "当前 Client ID: ${BOLD}${GD_CLIENT_ID:0:8}...${RESET}"
                    print_message "INFO" "当前 Client Secret: ${BOLD}${GD_CLIENT_SECRET:0:8}...${RESET}"
                    print_message "INFO" "当前 Refresh Token: ${BOLD}${GD_REFRESH_TOKEN:0:8}...${RESET}"
                    print_message "INFO" "当前 Drive Folder ID: ${BOLD}${GD_FOLDER_ID:-根目录}${RESET}"
                    echo ""
                    echo "   1. 更改 Google Client ID"
                    echo "   2. 更改 Google Client Secret"
                    echo "   3. 更改 Google Refresh Token (需要重新授权)"
                    echo "   4. 更改 Google Drive Folder ID"
                    echo ""
                    echo "   0. 返回"
                    echo ""
                    read -rp "${GREEN}[?]${RESET} 请选择: " gd_choice
                    echo ""

                    case $gd_choice in
                        1)
                            echo "如果你没有 Client ID 和 Client Secret"
                            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                            print_message "LINK" "请参考: ${CYAN}${guide_url}${RESET}"
                            read -rp "   请输入新的 Google Client ID: " NEW_GD_CLIENT_ID
                            GD_CLIENT_ID="$NEW_GD_CLIENT_ID"
                            save_config
                            print_message "SUCCESS" "Google Client ID 更新成功。"
                            ;;
                        2)
                            echo "如果你没有 Client ID 和 Client Secret"
                            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                            print_message "LINK" "请参考: ${CYAN}${guide_url}${RESET}"
                            read -rp "   请输入新的 Google Client Secret: " NEW_GD_CLIENT_SECRET
                            GD_CLIENT_SECRET="$NEW_GD_CLIENT_SECRET"
                            save_config
                            print_message "SUCCESS" "Google Client Secret 更新成功。"
                            ;;
                        3)
                            clear
                            print_message "WARN" "获取新的 Refresh Token 需要在浏览器中授权。"
                            print_message "INFO" "打开下面链接进行授权并复制返回的代码:"
                            echo ""
                            local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code"
                            print_message "LINK" "${CYAN}${auth_url}${RESET}"
                            echo ""
                            read -rp "请输入浏览器返回的代码: " AUTH_CODE
                            
                            print_message "INFO" "正在获取 Refresh Token..."
                            local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                                -d client_id="$GD_CLIENT_ID" \
                                -d client_secret="$GD_CLIENT_SECRET" \
                                -d code="$AUTH_CODE" \
                                -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                                -d grant_type="authorization_code")
                            
                            NEW_GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                            
                            if [[ -z "$NEW_GD_REFRESH_TOKEN" || "$NEW_GD_REFRESH_TOKEN" == "null" ]]; then
                                print_message "ERROR" "无法获取 Refresh Token。请检查输入的数据。"
                                print_message "WARN" "设置未完成。"
                            else
                                GD_REFRESH_TOKEN="$NEW_GD_REFRESH_TOKEN"
                                save_config
                                print_message "SUCCESS" "Refresh Token 更新成功。"
                            fi
                            ;;
                        4)
                            echo
                            echo "   📁 指定 Google Drive 文件夹的方法:"
                            echo "   1. 在浏览器中创建并打开目标文件夹。"
                            echo "   2. 查看地址栏链接，格式类似："
                            echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                            echo "   3. 复制 /folders/ 后面的部分 — 这就是 Folder ID。"
                            echo "   4. 留空则上传到 Google Drive 根目录。"
                            echo
                            read -rp "   请输入新的 Google Drive Folder ID (留空为根目录): " NEW_GD_FOLDER_ID
                            GD_FOLDER_ID="$NEW_GD_FOLDER_ID"
                            save_config
                            print_message "SUCCESS" "Google Drive Folder ID 更新成功。"
                            ;;
                        0) break ;;
                        *) print_message "ERROR" "输入无效。请选择一个有效项。" ;;
                    esac
                    echo ""
                    read -rp "按 Enter 继续..."
                done
                ;;
            3)
                clear
                echo -e "${GREEN}${BOLD}PostgreSQL 用户名${RESET}"
                echo ""
                print_message "INFO" "当前 PostgreSQL 用户名: ${BOLD}${DB_USER}${RESET}"
                echo ""
                read -rp "   请输入新的 PostgreSQL 用户名 (默认 postgres): " NEW_DB_USER
                DB_USER="${NEW_DB_USER:-postgres}"
                save_config
                print_message "SUCCESS" "PostgreSQL 用户名已更新为 ${BOLD}${DB_USER}${RESET}。"
                echo ""
                read -rp "按 Enter 继续..."
                ;;
            4)
                clear
                echo -e "${GREEN}${BOLD}Remnawave 路径${RESET}"
                echo ""
                print_message "INFO" "当前 Remnawave 路径: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                echo ""
                print_message "ACTION" "请选择 Remnawave 新路径:"
                echo " 1. /opt/remnawave"
                echo " 2. /root/remnawave"
                echo " 3. /opt/stacks/remnawave"
                echo " 4. 指定自定义路径"
                echo ""
                echo " 0. 返回"
                echo ""

                local new_remnawave_path_choice
                while true; do
                    read -rp " ${GREEN}[?]${RESET} 请选择: " new_remnawave_path_choice
                    case "$new_remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    4) 
                        echo ""
                        print_message "INFO" "请输入 Remnawave 面板的完整路径:"
                        read -rp " 路径: " new_custom_remnawave_path
        
                        if [[ -z "$new_custom_remnawave_path" ]]; then
                            print_message "ERROR" "路径不能为空。"
                            echo ""
                            read -rp "按 Enter 继续..."
                            continue
                        fi
        
                        if [[ ! "$new_custom_remnawave_path" = /* ]]; then
                            print_message "ERROR" "路径必须为绝对路径（以 / 开头）。"
                            echo ""
                            read -rp "按 Enter 继续..."
                            continue
                        fi
        
                        new_custom_remnawave_path="${new_custom_remnawave_path%/}"
        
                        if [[ ! -d "$new_custom_remnawave_path" ]]; then
                            print_message "WARN" "目录 ${BOLD}${new_custom_remnawave_path}${RESET} 不存在。"
                            read -rp "$(echo -e "${GREEN}[?]${RESET} 是否继续使用此路径? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: ")" confirm_new_custom_path
                            if [[ "$confirm_new_custom_path" != "y" ]]; then
                                echo ""
                                read -rp "按 Enter 继续..."
                                continue
                            fi
                        fi
        
                        REMNALABS_ROOT_DIR="$new_custom_remnawave_path"
                        print_message "SUCCESS" "已设置新的自定义路径: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                        break 
                        ;;
                    0) 
                        return
                        ;;
                    *) print_message "ERROR" "输入无效。" ;;
                    esac
                done
                save_config
                print_message "SUCCESS" "Remnawave 路径已更新为 ${BOLD}${REMNALABS_ROOT_DIR}${RESET}。"
                echo ""
                read -rp "按 Enter 继续..."
                ;;
            0) break ;;
            *) print_message "ERROR" "输入无效。请选择一个有效项。" ;;
        esac
        echo ""
    done
}

check_update_status() {
    local TEMP_REMOTE_VERSION_FILE
    TEMP_REMOTE_VERSION_FILE=$(mktemp)

    if ! curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | head -n 100 > "$TEMP_REMOTE_VERSION_FILE"; then
        UPDATE_AVAILABLE=false
        rm -f "$TEMP_REMOTE_VERSION_FILE"
        return
    fi

    local REMOTE_VERSION
    REMOTE_VERSION=$(grep -m 1 "^VERSION=" "$TEMP_REMOTE_VERSION_FILE" | cut -d'"' -f2)
    rm -f "$TEMP_REMOTE_VERSION_FILE"

    if [[ -z "$REMOTE_VERSION" ]]; then
        UPDATE_AVAILABLE=false
        return
    fi

    compare_versions_for_check() {
        local v1="$1"
        local v2="$2"

        local v1_num="${v1//[^0-9.]/}"
        local v2_num="${v2//[^0-9.]/}"

        local v1_sfx="${v1//$v1_num/}"
        local v2_sfx="${v2//$v2_num/}"

        if [[ "$v1_num" == "$v2_num" ]]; then
            if [[ -z "$v1_sfx" && -n "$v2_sfx" ]]; then
                return 0
            elif [[ -n "$v1_sfx" && -z "$v2_sfx" ]]; then
                return 1
            elif [[ "$v1_sfx" < "$v2_sfx" ]]; then
                return 0
            else
                return 1
            fi
        else
            if printf '%s\n' "$v1_num" "$v2_num" | sort -V | head -n1 | grep -qx "$v1_num"; then
                return 0
            else
                return 1
            fi
        fi
    }

    if compare_versions_for_check "$VERSION" "$REMOTE_VERSION"; then
        UPDATE_AVAILABLE=true
    else
        UPDATE_AVAILABLE=false
    fi
}

main_menu() {
    while true; do
        check_update_status
        clear
        echo -e "${GREEN}${BOLD}REMNAWAVE BACKUP & RESTORE by distillium${RESET} "
        if [[ "$UPDATE_AVAILABLE" == true ]]; then
            echo -e "${BOLD}${LIGHT_GRAY}版本: ${VERSION} ${RED}有可用更新${RESET}"
        else
            echo -e "${BOLD}${LIGHT_GRAY}版本: ${VERSION}${RESET}"
        fi
        echo ""
        echo "   1. 手动创建备份"
        echo "   2. 从备份恢复"
        echo ""
        echo "   3. 配置 Telegram 机器人备份"
        echo "   4. 配置自动发送与通知"
        echo "   5. 配置备份发送方式"
        echo "   6. 脚本配置"
        echo ""
        echo "   7. 更新脚本"
        echo "   8. 删除脚本"
        echo ""
        echo "   0. 退出"
        echo -e "   —  快速运行: ${BOLD}${GREEN}rw-backup${RESET} 可在系统任意位置使用"
        echo ""

        read -rp "${GREEN}[?]${RESET} 请选择: " choice
        echo ""
        case $choice in
            1) create_backup ; read -rp "按 Enter 继续..." ;;
            2) restore_backup ;;
            3) configure_bot_backup ;;
            4) setup_auto_send ;;
            5) configure_upload_method ;;
            6) configure_settings ;;
            7) update_script ;;
            8) remove_script ;;
            0) echo "退出..."; exit 0 ;;
            *) print_message "ERROR" "输入无效。请选择一个有效项。" ; read -rp "按 Enter 继续..." ;;
        esac
    done
}

if ! command -v jq &> /dev/null; then
    print_message "INFO" "正在安装 'jq' 用于解析 JSON..."
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ 错误: 安装 'jq' 需要 root 权限。请手动安装 'jq'（例如使用 'sudo apt-get install jq'）。${RESET}"
        exit 1
    fi
    if command -v apt-get &> /dev/null; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y jq > /dev/null 2>&1 || { echo -e "${RED}❌ 错误: 无法安装 'jq'.${RESET}"; exit 1; }
        print_message "SUCCESS" "'jq' 已成功安装。"
    else
        print_message "ERROR" "未找到 apt-get 包管理器。请手动安装 'jq'。"
        exit 1
    fi
fi

if [[ -z "$1" ]]; then
    load_or_create_config
    setup_symlink
    main_menu
elif [[ "$1" == "backup" ]]; then
    load_or_create_config
    create_backup
elif [[ "$1" == "restore" ]]; then
    load_or_create_config
    restore_backup
elif [[ "$1" == "update" ]]; then
    update_script
elif [[ "$1" == "remove" ]]; then
    remove_script
else
    echo -e "${RED}❌ 用法错误。可用命令: ${BOLD}${0} [backup|restore|update|remove]${RESET}${RESET}"
    exit 1
fi
