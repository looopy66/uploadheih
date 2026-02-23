#!/bin/bash
# 一键安装脚本：自动安装依赖、写入上传脚本、配置定时任务

set -e  # 遇到错误立即退出

# 颜色输出（可选）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始安装日常上传脚本所需环境...${NC}"

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本（例如使用 sudo）${NC}"
    exit 1
fi

# ---------- 检测包管理器并安装软件 ----------
install_packages() {
    local packages="$1"
    if command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y $packages
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release  # 为 rclone 启用 EPEL
        yum install -y $packages
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y epel-release
        dnf install -y $packages
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Syu --noconfirm $packages
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y $packages
    elif command -v apk >/dev/null 2>&1; then
        apk add $packages
    else
        echo -e "${RED}不支持的包管理器，请手动安装 rclone 和 vnstat${NC}"
        exit 1
    fi
}

# 检查并安装 rclone
if ! command -v rclone >/dev/null 2>&1; then
    echo -e "${YELLOW}未找到 rclone，正在安装...${NC}"
    install_packages "rclone"
else
    echo -e "${GREEN}rclone 已安装，跳过${NC}"
fi

# 检查并安装 vnstat
if ! command -v vnstat >/dev/null 2>&1; then
    echo -e "${YELLOW}未找到 vnstat，正在安装...${NC}"
    install_packages "vnstat"
else
    echo -e "${GREEN}vnstat 已安装，跳过${NC}"
fi

# ---------- 写入合并脚本到 /usr/local/bin ----------
SCRIPT_PATH="/usr/local/bin/daily_upload.sh"
echo -e "${YELLOW}正在写入合并脚本到 $SCRIPT_PATH ...${NC}"

cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/sh
# 合并脚本：上传昨日 atop 日志 + 生成并上传昨日网络流量报告
# 包含手动运行时的进度显示（仅流量报告部分）

# ===== 配置区域 =====
RCLONE_REMOTE="atop"                         # rclone remote 名称
# atop 日志相关
ATOP_LOG_DIR="/var/log/atop"                  # atop 日志本地目录
ATOP_BUCKET_PATH="atop-bucket-66/atop-logs/hax" # atop 日志上传路径
# 流量报告相关
TRAFFIC_REPORT_DIR="/tmp"                      # 报告临时存放目录（可修改）
TRAFFIC_BUCKET_PATH="atop-bucket-66/traffic-reports" # 流量报告上传路径
# ===================

YESTERDAY=$(date -d "yesterday" +%Y%m%d)

# ---------- 函数：上传 atop 日志 ----------
upload_atop_log() {
    LOG_FILE="$ATOP_LOG_DIR/atop_$YESTERDAY"
    if [ -f "$LOG_FILE" ]; then
        # 使用 --checksum 确保文件一致性
        rclone copy "$LOG_FILE" "$RCLONE_REMOTE:$ATOP_BUCKET_PATH/" --checksum
        if [ $? -eq 0 ]; then
            rm "$LOG_FILE"
            logger "atop upload: successfully uploaded and removed $LOG_FILE"
        else
            logger "atop upload: failed to copy $LOG_FILE"
        fi
    else
        logger "atop upload: $LOG_FILE not found"
    fi
}

# ---------- 函数：生成并上传流量报告 ----------
generate_and_upload_traffic_report() {
    REPORT_FILE="$TRAFFIC_REPORT_DIR/traffic_report_$YESTERDAY.txt"

    # 1. 获取昨日流量
    if command -v vnstat >/dev/null 2>&1; then
        VNSTAT_OUT=$(vnstat -d 1 --oneline 2>/dev/null)
        if [ -n "$VNSTAT_OUT" ]; then
            DOWN_VAL=$(echo "$VNSTAT_OUT" | awk -F';' '{print $4}')
            DOWN_UNIT=$(echo "$VNSTAT_OUT" | awk -F';' '{print $5}')
            UP_VAL=$(echo "$VNSTAT_OUT" | awk -F';' '{print $6}')
            UP_UNIT=$(echo "$VNSTAT_OUT" | awk -F';' '{print $7}')
            YESTERDAY_DOWN="$DOWN_VAL $DOWN_UNIT"
            YESTERDAY_UP="$UP_VAL $UP_UNIT"
        else
            YESTERDAY_DOWN="N/A"
            YESTERDAY_UP="N/A"
        fi
    else
        YESTERDAY_DOWN="vnstat not installed"
        YESTERDAY_UP="vnstat not installed"
    fi

    # 2. 获取总累计流量
    if command -v vnstat >/dev/null 2>&1; then
        TOTAL_STATS=$(vnstat --oneline 2>/dev/null | head -1)
        if [ -n "$TOTAL_STATS" ]; then
            TOTAL_DOWN=$(echo "$TOTAL_STATS" | awk -F';' '{print $8" "$9}')
            TOTAL_UP=$(echo "$TOTAL_STATS" | awk -F';' '{print $10" "$11}')
        else
            TOTAL_DOWN="N/A"
            TOTAL_UP="N/A"
        fi
    else
        TOTAL_DOWN="vnstat not installed"
        TOTAL_UP="vnstat not installed"
    fi

    # 3. 生成报告文件
    {
        echo "日期: $YESTERDAY"
        echo "当日下载量: $YESTERDAY_DOWN"
        echo "当日上传量: $YESTERDAY_UP"
        echo "总下载量: $TOTAL_DOWN"
        echo "总上传量: $TOTAL_UP"
    } > "$REPORT_FILE"

    # 4. 上传报告（手动运行时显示进度）
    if [ -t 1 ]; then
        echo "开始上传流量报告 $REPORT_FILE ..."
        rclone copy --progress "$REPORT_FILE" "$RCLONE_REMOTE:$TRAFFIC_BUCKET_PATH/"
    else
        rclone copy "$REPORT_FILE" "$RCLONE_REMOTE:$TRAFFIC_BUCKET_PATH/"
    fi

    if [ $? -eq 0 ]; then
        [ -t 1 ] && echo "流量报告上传成功"
        logger "daily traffic report: uploaded $REPORT_FILE"
        rm "$REPORT_FILE"
    else
        [ -t 1 ] && echo "流量报告上传失败，请检查错误"
        logger "daily traffic report: failed to upload $REPORT_FILE"
    fi
}

# ---------- 主程序：依次执行两个任务 ----------
upload_atop_log
generate_and_upload_traffic_report

exit 0
EOF

chmod +x "$SCRIPT_PATH"
echo -e "${GREEN}脚本已写入并添加执行权限${NC}"

# ---------- 配置定时任务（每天 UTC 02:00）----------
CRON_FILE="/etc/cron.d/daily_upload"
CRON_LINE="0 2 * * * root $SCRIPT_PATH"

if [ -f "$CRON_FILE" ]; then
    echo -e "${YELLOW}定时任务文件已存在，跳过写入（请手动检查 $CRON_FILE）${NC}"
else
    echo "$CRON_LINE" > "$CRON_FILE"
    echo -e "${GREEN}定时任务已添加：每天 UTC 时间 02:00 执行 $SCRIPT_PATH${NC}"
fi

# ---------- 提示用户进行 rclone 配置 ----------
echo ""
echo -e "${GREEN}安装完成！${NC}"
echo -e "${YELLOW}请执行以下命令配置 rclone 远程存储（remote 名称必须为 'atop' 或修改脚本中的 RCLONE_REMOTE 变量）：${NC}"
echo "  rclone config"
echo ""
echo -e "${YELLOW}配置完成后，建议手动测试脚本：${NC}"
echo "  $SCRIPT_PATH"
echo ""
echo -e "${YELLOW}如果需要修改脚本中的配置变量（如存储桶路径），请编辑：${NC}"
echo "  $SCRIPT_PATH"
echo ""

exit 0
