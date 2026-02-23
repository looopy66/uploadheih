#!/bin/bash
# 一键安装脚本：交互式配置 + 自动安装 vnstat + 写入脚本 + 配置定时任务 + 自动测试上传

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   日常数据上传脚本 安装程序${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本（例如使用 sudo）${NC}"
    exit 1
fi

# ---------- 检查 rclone ----------
if ! command -v rclone >/dev/null 2>&1; then
    echo -e "${RED}错误: rclone 未安装。${NC}"
    echo "请先安装 rclone 并配置 remote，然后再运行此脚本。"
    echo "安装参考: https://rclone.org/install/"
    exit 1
else
    echo -e "${GREEN}✓ rclone 已安装${NC}"
fi

# ---------- 交互式配置（带默认值）----------
echo ""
echo -e "${YELLOW}请配置以下参数（直接回车使用默认值）：${NC}"

# rclone remote 名称（默认：atop）
DEFAULT_REMOTE="atop"
read -p "rclone remote 名称 [${DEFAULT_REMOTE}]: " RCLONE_REMOTE
RCLONE_REMOTE=${RCLONE_REMOTE:-$DEFAULT_REMOTE}

# atop 日志目录（默认：/var/log/atop）
DEFAULT_ATOP_LOG_DIR="/var/log/atop"
read -p "atop 日志本地目录 [${DEFAULT_ATOP_LOG_DIR}]: " ATOP_LOG_DIR
ATOP_LOG_DIR=${ATOP_LOG_DIR:-$DEFAULT_ATOP_LOG_DIR}

# atop 日志上传路径（默认：atop-bucket-66/atop-logs/hax）
echo -e "${YELLOW}⚠️  请确保存储桶（bucket）已在对象存储中手动创建子路径。${NC}"
DEFAULT_ATOP_BUCKET="atop-bucket-66/atop-logs/hax"
read -p "atop 日志上传路径（桶名/路径）[${DEFAULT_ATOP_BUCKET}]: " ATOP_BUCKET_PATH
ATOP_BUCKET_PATH=${ATOP_BUCKET_PATH:-$DEFAULT_ATOP_BUCKET}

# 流量报告临时目录（默认：/tmp）
DEFAULT_TRAFFIC_DIR="/tmp"
read -p "流量报告临时目录 [${DEFAULT_TRAFFIC_DIR}]: " TRAFFIC_REPORT_DIR
TRAFFIC_REPORT_DIR=${TRAFFIC_REPORT_DIR:-$DEFAULT_TRAFFIC_DIR}

# 流量报告上传路径（默认：atop-bucket-66/traffic-reports）
echo -e "${YELLOW}⚠️  请确保存储桶（bucket）已在对象存储中手动创建子路径。${NC}"
DEFAULT_TRAFFIC_BUCKET="atop-bucket-66/traffic-reports"
read -p "流量报告上传路径（桶名/路径）[${DEFAULT_TRAFFIC_BUCKET}]: " TRAFFIC_BUCKET_PATH
TRAFFIC_BUCKET_PATH=${TRAFFIC_BUCKET_PATH:-$DEFAULT_TRAFFIC_BUCKET}

# 显示配置摘要
echo ""
echo -e "${GREEN}配置摘要：${NC}"
echo "  rclone remote:          $RCLONE_REMOTE"
echo "  atop 日志目录:           $ATOP_LOG_DIR"
echo "  atop 上传路径:           $RCLONE_REMOTE:$ATOP_BUCKET_PATH/"
echo "  流量报告临时目录:         $TRAFFIC_REPORT_DIR"
echo "  流量报告上传路径:         $RCLONE_REMOTE:$TRAFFIC_BUCKET_PATH/"
echo ""

# ---------- 安装 vnstat（如未安装）----------
install_vnstat() {
    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y vnstat
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release && yum install -y vnstat
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y epel-release && dnf install -y vnstat
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Syu --noconfirm vnstat
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y vnstat
    elif command -v apk >/dev/null 2>&1; then
        apk add vnstat
    else
        echo -e "${RED}不支持的包管理器，请手动安装 vnstat${NC}"
        exit 1
    fi
}

if ! command -v vnstat >/dev/null 2>&1; then
    echo -e "${YELLOW}正在安装 vnstat...${NC}"
    install_vnstat
    echo -e "${GREEN}✓ vnstat 安装完成${NC}"
else
    echo -e "${GREEN}✓ vnstat 已安装${NC}"
fi

# ---------- 写入主脚本（使用占位符）----------
SCRIPT_PATH="/usr/local/bin/daily_upload.sh"
echo -e "${YELLOW}正在生成主脚本 -> $SCRIPT_PATH ...${NC}"

cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/sh
# 合并脚本：上传昨日 atop 日志 + 生成并上传昨日网络流量报告
# 包含手动运行时的进度显示（仅流量报告部分）

# ===== 配置区域（由安装程序自动替换）=====
RCLONE_REMOTE="__RCLONE_REMOTE__"
ATOP_LOG_DIR="__ATOP_LOG_DIR__"
ATOP_BUCKET_PATH="__ATOP_BUCKET_PATH__"
TRAFFIC_REPORT_DIR="__TRAFFIC_REPORT_DIR__"
TRAFFIC_BUCKET_PATH="__TRAFFIC_BUCKET_PATH__"
# ========================================

YESTERDAY=$(date -d "yesterday" +%Y%m%d)

# ---------- 函数：上传 atop 日志 ----------
upload_atop_log() {
    LOG_FILE="$ATOP_LOG_DIR/atop_$YESTERDAY"
    if [ -f "$LOG_FILE" ]; then
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

    # 4. 上传报告
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

# ---------- 主程序 ----------
upload_atop_log
generate_and_upload_traffic_report

exit 0
EOF

# 替换占位符
sed -i "s|__RCLONE_REMOTE__|$RCLONE_REMOTE|g" "$SCRIPT_PATH"
sed -i "s|__ATOP_LOG_DIR__|$ATOP_LOG_DIR|g" "$SCRIPT_PATH"
sed -i "s|__ATOP_BUCKET_PATH__|$ATOP_BUCKET_PATH|g" "$SCRIPT_PATH"
sed -i "s|__TRAFFIC_REPORT_DIR__|$TRAFFIC_REPORT_DIR|g" "$SCRIPT_PATH"
sed -i "s|__TRAFFIC_BUCKET_PATH__|$TRAFFIC_BUCKET_PATH|g" "$SCRIPT_PATH"

chmod +x "$SCRIPT_PATH"
echo -e "${GREEN}✓ 主脚本生成完成${NC}"

# ---------- 配置定时任务 ----------
CRON_FILE="/etc/cron.d/daily_upload"
CRON_LINE="0 2 * * * root $SCRIPT_PATH"

if [ -f "$CRON_FILE" ]; then
    echo -e "${YELLOW}定时任务文件已存在，跳过写入（请手动检查 $CRON_FILE）${NC}"
else
    echo "$CRON_LINE" > "$CRON_FILE"
    echo
fi

# ---------- 自动测试上传 ----------
echo ""
echo -e "${YELLOW}正在自动测试上传功能...${NC}"
echo -e "${YELLOW}（请确保存储桶 ${RCLONE_REMOTE}:${TRAFFIC_BUCKET_PATH%%/*} 已手动创建）${NC}"

TEST_FILE="/tmp/rclone-auto-test-$(date +%s).txt"
echo "rclone auto test at $(date)" > "$TEST_FILE"

echo "📤 上传测试文件到 $RCLONE_REMOTE:$TRAFFIC_BUCKET_PATH/ ..."
if rclone copy "$TEST_FILE" "$RCLONE_REMOTE:$TRAFFIC_BUCKET_PATH/" 2>/dev/null; then
    echo -e "${GREEN}✅ 测试文件上传成功！${NC}"
    # 列出远程文件确认
    if rclone ls "$RCLONE_REMOTE:$TRAFFIC_BUCKET_PATH/" | grep -q "$(basename "$TEST_FILE")"; then
        echo "远程文件存在"
    fi
    # 清理远程测试文件
    rclone delete "$RCLONE_REMOTE:$TRAFFIC_BUCKET_PATH/$(basename "$TEST_FILE")" 2>/dev/null && echo "已清理远程测试文件"
else
    echo -e "${RED}❌ 测试文件上传失败！${NC}"
    echo -e "请检查："
    echo -e "  1. rclone remote '${RCLONE_REMOTE}' 是否正确配置（当前可用 remote：$(rclone listremotes | tr '\n' ' ')）"
    echo -e "  2. 存储桶 '${TRAFFIC_BUCKET_PATH%%/*}' 是否存在且可写"
    echo -e "  3. 网络连接是否正常"
    echo -e "您可以手动运行 'rclone ls ${RCLONE_REMOTE}:${TRAFFIC_BUCKET_PATH%%/*}/' 来诊断"
fi

rm -f "$TEST_FILE"
echo -e "${GREEN}自动测试完成${NC}"

# ---------- 最终提示 ----------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo ""
echo -e "${YELLOW}您的主脚本位置：${NC} $SCRIPT_PATH"
echo -e "${YELLOW}如需修改配置，请直接编辑该文件。${NC}"
echo ""
echo -e "${YELLOW}手动运行脚本测试完整功能：${NC}"
echo "  sudo $SCRIPT_PATH"
echo ""
echo -e "${GREEN}========================================${NC}"
