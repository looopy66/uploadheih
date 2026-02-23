日常数据上传脚本

https://img.shields.io/badge/GitHub-仓库-blue
https://img.shields.io/badge/license-MIT-green

本项目提供了一个自动化的 Shell 脚本，用于：

· 上传昨日的 atop 系统性能日志到 S3 兼容的对象存储（通过 rclone）。
· 生成并上传昨日的网络流量报告（基于 vnstat）到对象存储。

脚本支持手动运行时显示上传进度（仅流量报告部分），并自动记录操作日志到系统日志（logger）。

---

快速开始

一键安装（推荐）

使用以下命令之一，即可从 GitHub 直接下载并运行安装脚本：

使用 curl：

```bash
curl -sSL https://raw.githubusercontent.com/yourusername/daily-upload-script/main/install.sh | sudo bash
```

使用 wget：

```bash
wget -qO- https://raw.githubusercontent.com/yourusername/daily-upload-script/main/install.sh | sudo bash
```

⚠️ 请将 URL 中的 yourusername/daily-upload-script 替换为实际的 GitHub 仓库路径。如果您 fork 了本项目，请使用您自己的仓库地址。

安装脚本会自动：

· 检测包管理器并安装 rclone 和 vnstat。
· 将主脚本写入 /usr/local/bin/daily_upload.sh。
· 配置定时任务（每天 UTC 02:00 执行）。
· 提示您运行 rclone config 完成远程存储配置。

手动安装

如果您希望手动控制安装过程，可以克隆本仓库：

```bash
git clone https://github.com/yourusername/daily-upload-script.git
cd daily-upload-script
chmod +x install.sh
sudo ./install.sh
```

---

依赖

· rclone：用于文件上传到云存储（需预先配置）
· vnstat：用于获取网络流量统计数据
· 基础命令：sh、date、awk、logger、rm 等（通常系统自带）

---

配置

1. 配置 rclone

安装后需运行 rclone config 添加远程存储。请确保 remote 名称为 atop（如需修改，请编辑 /usr/local/bin/daily_upload.sh 中的 RCLONE_REMOTE 变量）。

示例配置（以 AWS S3 为例）：

```
rclone config
> n               # 新建 remote
> atop            # 名称输入 atop
> 选择对应的存储类型（如 s3）
> 填写 Access Key ID, Secret Access Key, Endpoint 等信息
> 保持默认或按需配置
```

2. 修改脚本中的存储路径（可选）

编辑 /usr/local/bin/daily_upload.sh，根据需要调整以下变量：

```bash
# atop 日志相关
ATOP_LOG_DIR="/var/log/atop"                  # atop 日志本地目录
ATOP_BUCKET_PATH="atop-bucket-66/atop-logs/hax" # atop 日志上传路径

# 流量报告相关
TRAFFIC_REPORT_DIR="/tmp"                      # 报告临时存放目录
TRAFFIC_BUCKET_PATH="atop-bucket-66/traffic-reports" # 流量报告上传路径
```

---

手动运行

直接执行脚本即可手动触发上传（会显示进度）：

```bash
sudo /usr/local/bin/daily_upload.sh
```

如果希望测试 atop 日志上传，请确保 /var/log/atop/ 中存在对应日期的日志文件（例如 atop_20250222）。

---

连接测试

使用以下一键测试命令验证 rclone 配置是否正确：

```bash
# 请替换 remote 和路径为您的实际值
RCLONE_REMOTE="atop"
TEST_PATH="atop-bucket-66/test"   # 测试目录（确保桶存在）

TEST_FILE="/tmp/rclone-test-$(date +%s).txt"
echo "rclone test at $(date)" > "$TEST_FILE"

echo "上传中..."
rclone copy "$TEST_FILE" "$RCLONE_REMOTE:$TEST_PATH/"

if [ $? -eq 0 ]; then
    echo "✅ 上传成功，远程文件列表："
    rclone ls "$RCLONE_REMOTE:$TEST_PATH/"
    
    # 清理远程测试文件
    rclone delete "$RCLONE_REMOTE:$TEST_PATH/$(basename "$TEST_FILE")"
else
    echo "❌ 上传失败，请检查配置和网络"
fi

rm -f "$TEST_FILE"
echo "测试完成"
```

更简洁的单行测试（使用 rcat）：

```bash
echo "test" | rclone rcat "atop:atop-bucket-66/test/test-$(date +%s).txt" && rclone ls "atop:atop-bucket-66/test/"
```

---

定时任务

安装脚本已自动添加 cron 任务：

```bash
cat /etc/cron.d/daily_upload
# 输出：0 2 * * * root /usr/local/bin/daily_upload.sh
```

表示每天 UTC 时间 02:00（即北京时间 10:00）执行。如需修改时间，直接编辑该文件即可。

---

日志查看

脚本执行日志通过 logger 写入系统日志，可使用以下命令查看：

```bash
# 查看最近的 atop 上传记录
grep "atop upload" /var/log/syslog  # Debian/Ubuntu
grep "atop upload" /var/log/messages # CentOS/RHEL

# 查看流量报告上传记录
grep "daily traffic report" /var/log/syslog
```

---

故障排除

1. rclone 上传失败

· 检查 remote 名称是否匹配：rclone listremotes
· 测试连通性：rclone ls atop:atop-bucket-66/
· 加上 --verbose 查看详细错误：rclone copy file atop:path/ -v

2. vnstat 无数据

· 确保 vnstat 服务已启动：systemctl status vnstat
· 手动更新数据库：vnstat -u
· 检查网络接口：vnstat --iflist

3. date 命令不支持 -d "yesterday"

· 某些嵌入式系统可能使用 busybox date，请替换为 date --date="1 day ago" 或安装 GNU date。

4. atop 日志文件未找到

· 确认 atop 已安装并正确配置日志轮转。
· 检查日志目录和文件名格式是否符合脚本预期（默认为 /var/log/atop/atop_YYYYMMDD）。

---

贡献

欢迎提交 Issue 和 Pull Request！请访问 GitHub 仓库 参与贡献。

---

许可证

MIT
