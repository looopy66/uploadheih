自用   
记得修改脚本内下面的内容

部分s3存储桶需要自己手动创建相关路径   

🌐 日常数据上传脚本 (Daily Upload Script)

一个轻量级 Shell 脚本，自动上传 atop 系统日志 并生成 网络流量报告 到 S3 兼容的对象存储（通过 rclone）。

---

📋 功能特性

· 📤 自动上传昨日的 atop 日志文件（/var/log/atop/atop_YYYYMMDD）到指定的 S3 路径   
· 📊 基于 vnstat 生成昨日的网络流量报告（包含当日和累计流量）   
· 🔄 手动运行时显示上传进度（仅流量报告部分）   
· 📝 操作日志通过 logger 写入系统日志，便于追踪   
· ⏰ 支持定时任务（默认每天 UTC 02:00 执行）   
· 🛠️ 一键安装脚本自动安装 vnstat 并配置 crontab   
  
---

⚠️ 重要前提

在运行安装脚本之前，您必须已经安装并配置好 rclone！   
本脚本不会自动安装 rclone，而是检查其是否存在，若不存在则提示手动安装并退出。

1. 安装 rclone

根据您的 Linux 发行版，使用以下命令之一安装 rclone：

发行版 安装命令
Debian / Ubuntu sudo apt update && sudo apt install rclone
CentOS / RHEL 7+ sudo yum install epel-release && sudo yum install rclone
CentOS / RHEL 8+ sudo dnf install epel-release && sudo dnf install rclone
Fedora sudo dnf install rclone
Arch Linux sudo pacman -S rclone
openSUSE sudo zypper install rclone
Alpine Linux sudo apk add rclone

其他系统请参考 rclone 官方安装文档。

2. 配置 rclone remote

安装完成后，运行 rclone config 创建一个 remote（建议命名为 atop，与脚本默认名称一致）。

示例配置（以 AWS S3 为例）：

```bash
rclone config
> n               # 新建 remote
> atop            # 输入名称（必须与脚本中的 RCLONE_REMOTE 一致）
> 选择存储类型（例如 4 表示 s3）
> 填写 Access Key ID、Secret Access Key、Endpoint（可选）、区域等
> 后续选项保持默认即可
```

验证配置是否成功：

```bash
rclone ls atop:your-bucket-name/
```

确保您的存储桶（Bucket）已存在（rclone 不会自动创建桶）。

---

🚀 快速安装

完成上述准备工作后，使用以下任一命令一键安装本脚本：

使用 curl

```bash
curl -sSL https://raw.githubusercontent.com/looopy66/uploadheih/refs/heads/main/upload.sh | sudo bash
```

使用 wget

```bash
wget -qO- https://raw.githubusercontent.com/looopy66/uploadheih/refs/heads/main/upload.sh | sudo bash
```

📍 快速卸载   

使用 curl

```bash
curl -sSL https://raw.githubusercontent.com/looopy66/uploadheih/refs/heads/main/uninstall.sh | sudo bash
```

使用 wget

```bash
wget -qO- https://raw.githubusercontent.com/looopy66/uploadheih/refs/heads/main/uninstall.sh | sudo bash
```

安装脚本会自动：

· 检查 rclone 是否已安装（若未安装则提示并退出）
· 安装 vnstat（如未安装）
· 将主脚本写入 /usr/local/bin/daily_upload.sh
· 在 /etc/cron.d/daily_upload 中添加定时任务（每天 UTC 02:00 执行）
· 提示您完成 rclone 配置（如尚未配置）

---

⚙️ 配置指南

安装完成后，您可能需要根据实际环境调整脚本中的配置变量。
编辑 /usr/local/bin/daily_upload.sh，修改以下部分：

```bash
# ===== 配置区域 =====
RCLONE_REMOTE="atop"                         # rclone remote 名称（应与您配置的一致）
# atop 日志相关
ATOP_LOG_DIR="/var/log/atop"                  # atop 日志本地目录
ATOP_BUCKET_PATH="atop-bucket-66/atop-logs/hax" # atop 日志上传路径
# 流量报告相关
TRAFFIC_REPORT_DIR="/tmp"                      # 报告临时存放目录
TRAFFIC_BUCKET_PATH="atop-bucket-66/traffic-reports" # 流量报告上传路径
# ===================
```

确保存储桶路径正确，且存储桶已存在。

---

▶️ 使用说明

手动运行

直接执行脚本即可触发上传（会显示流量报告的上传进度）：

```bash
sudo /usr/local/bin/daily_upload.sh
```

如果 atop 日志目录中存在昨天的日志文件（例如 atop_20250222），它们也会被上传。

定时任务

默认 cron 任务已添加，每天 UTC 02:00（即北京时间 10:00）自动运行。
如需修改执行时间，请编辑 /etc/cron.d/daily_upload 文件。

---

🧪 连接测试

在配置完成后，建议运行以下测试命令验证 rclone 连通性：

```bash
# 一键测试（请替换 remote 和路径为您的实际值）
RCLONE_REMOTE="atop"
TEST_PATH="atop-bucket-66/test"   # 测试目录（确保桶存在）

TEST_FILE="/tmp/rclone-test-$(date +%s).txt"
echo "rclone test at $(date)" > "$TEST_FILE"

echo "📤 上传测试文件..."
rclone copy "$TEST_FILE" "$RCLONE_REMOTE:$TEST_PATH/"

if [ $? -eq 0 ]; then
    echo "✅ 上传成功，远程文件列表："
    rclone ls "$RCLONE_REMOTE:$TEST_PATH/"
    # 清理
    rclone delete "$RCLONE_REMOTE:$TEST_PATH/$(basename "$TEST_FILE")"
else
    echo "❌ 上传失败，请检查配置和网络"
fi

rm -f "$TEST_FILE"
echo "🎉 测试完成"
```

更简洁的单行测试（使用 rcat）：

```bash
echo "test" | rclone rcat "atop:atop-bucket-66/test/test-$(date +%s).txt" && rclone ls "atop:atop-bucket-66/test/"
```

---

📍 日志查看

脚本通过 logger 记录操作，可使用以下命令查看：

Debian/Ubuntu

```bash
grep "atop upload\|daily traffic report" /var/log/syslog
```

CentOS/RHEL

```bash
grep "atop upload\|daily traffic report" /var/log/messages
```

---

🐛 故障排除

问题 可能原因 解决方法
rclone 上传失败 remote 名称错误 / 权限不足 / 网络不通 rclone listremotes 检查名称；rclone ls atop:bucket/ 测试连通性；添加 -vv 参数查看详细日志
vnstat 无数据 服务未启动 / 接口未监控 systemctl status vnstat；vnstat --iflist 查看可用接口；vnstat -u 强制更新
date 命令不支持 -d 系统使用 busybox date 修改脚本中的 YESTERDAY 获取方式为 date --date="1 day ago" +%Y%m%d
atop 日志未找到 日志路径或文件名格式不符 检查 /var/log/atop/ 下是否有类似 atop_20250222 的文件；修改脚本中的 ATOP_LOG_DIR 变量

---

🤝 贡献

欢迎提交 Issue 和 Pull Request！

· 报告 Bug：新建 Issue
· 提出新功能：讨论

---

📄 许可证

MIT © yourname
