#!/bin/bash

echo "========================================"
echo "      开始安装 cpolar 内网穿透工具      "
echo "========================================"

# 1. 自动下载并安装 cpolar（默认使用国内下载链接）
echo "[1/4] 正在执行官方安装脚本..."
curl -L https://www.cpolar.com/static/downloads/install-release-cpolar.sh | sudo bash

# 2. 检查是否安装成功
if ! command -v cpolar &> /dev/null; then
    echo "安装失败，请检查网络或系统环境！"
    exit 1
fi

echo "[2/4] cpolar 安装成功，当前版本："
cpolar version
echo "----------------------------------------"

# 3. 交互式输入 Token 进行认证
echo "[3/4] 配置 cpolar 认证 Token"
echo "请登录 cpolar 官网后台 (https://dashboard.cpolar.com/get-started) 获取您的 Authtoken"
read -p "请输入您的 Authtoken (输入后按回车): " authtoken

if [ -n "$authtoken" ]; then
    # 执行 token 配置操作
    cpolar authtoken "$authtoken"
    echo "Token 认证配置完成！"
else
    echo "未输入 Token。您可以稍后手动执行: cpolar authtoken <您的token>"
fi

# 4. 将 cpolar 注册为系统服务并启动
echo "[4/4] 正在配置并启动 systemd 后台服务..."
sudo systemctl enable cpolar
sudo systemctl start cpolar

echo "========================================"
echo "          cpolar 部署与启动完成！         "
echo "========================================"
echo "您可以运行以下命令检查服务状态："
echo "sudo systemctl status cpolar"
echo ""
echo "如需测试穿透功能，请运行: cpolar http 8080"