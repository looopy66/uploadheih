#!/bin/bash
# 一键卸载脚本：删除定时任务、主脚本，并卸载 rclone 和 vnstat（需明确确认）

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}   日常数据上传脚本 卸载程序${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${YELLOW}警告：此操作将删除本地安装的脚本和定时任务，并卸载 rclone 和 vnstat。${NC}"
echo -e "${YELLOW}远程存储桶中的文件不会被删除。${NC}"
echo ""

read -p "是否继续卸载？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "卸载已取消。"
    exit 0
fi

# 检查 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本（例如使用 sudo）${NC}"
    exit 1
fi

# ---------- 删除定时任务 ----------
CRON_FILE="/etc/cron.d/daily_upload"
if [ -f "$CRON_FILE" ]; then
    rm -f "$CRON_FILE"
    echo -e "${GREEN}✓ 已删除定时任务：$CRON_FILE${NC}"
else
    echo -e "${YELLOW}定时任务文件不存在，跳过${NC}"
fi

# ---------- 删除主脚本 ----------
SCRIPT_PATH="/usr/local/bin/daily_upload.sh"
if [ -f "$SCRIPT_PATH" ]; then
    rm -f "$SCRIPT_PATH"
    echo -e "${GREEN}✓ 已删除主脚本：$SCRIPT_PATH${NC}"
else
    echo -e "${YELLOW}主脚本不存在，跳过${NC}"
fi

# ---------- 卸载 rclone 和 vnstat（必须明确确认）----------
echo ""
echo -e "${YELLOW}准备卸载 rclone 和 vnstat...${NC}"
echo -e "${RED}注意：如果系统中有其他程序依赖这些包，卸载可能导致它们无法正常工作。${NC}"

while true; do
    read -p "是否继续卸载 rclone 和 vnstat？(y/n) " -n 1 -r
    echo
    case $REPLY in
        [Yy])
            # 根据包管理器卸载
            if command -v apt >/dev/null 2>&1; then
                apt remove -y rclone vnstat
                echo -e "${GREEN}✓ 已通过 apt 卸载 rclone 和 vnstat${NC}"
            elif command -v yum >/dev/null 2>&1; then
                yum remove -y rclone vnstat
                echo -e "${GREEN}✓ 已通过 yum 卸载 rclone 和 vnstat${NC}"
            elif command -v dnf >/dev/null 2>&1; then
                dnf remove -y rclone vnstat
                echo -e "${GREEN}✓ 已通过 dnf 卸载 rclone 和 vnstat${NC}"
            elif command -v pacman >/dev/null 2>&1; then
                pacman -Rns --noconfirm rclone vnstat
                echo -e "${GREEN}✓ 已通过 pacman 卸载 rclone 和 vnstat${NC}"
            elif command -v zypper >/dev/null 2>&1; then
                zypper remove -y rclone vnstat
                echo -e "${GREEN}✓ 已通过 zypper 卸载 rclone 和 vnstat${NC}"
            elif command -v apk >/dev/null 2>&1; then
                apk del rclone vnstat
                echo -e "${GREEN}✓ 已通过 apk 卸载 rclone 和 vnstat${NC}"
            else
                echo -e "${RED}不支持的包管理器，请手动卸载 rclone 和 vnstat。${NC}"
            fi
            break
            ;;
        [Nn])
            echo "跳过卸载 rclone 和 vnstat。"
            break
            ;;
        *)
            echo "请输入 y 或 n。"
            ;;
    esac
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}卸载完成！${NC}"
echo -e "${YELLOW}存储桶中的文件未被删除，如有需要请手动清理。${NC}"
echo -e "${GREEN}========================================${NC}"
