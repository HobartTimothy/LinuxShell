#!/bin/bash

# ==============================================================================
# Redis 完全卸载与系统环境复原脚本
# ==============================================================================

# 默认基础参数
INSTALL_DIR="/usr/local/redis"

# ANSI 颜色定义
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_RESET='\033[0m'

# 帮助文档
usage() {
    echo -e "${C_CYAN}使用方法:${C_RESET} $0 [选项]"
    echo -e "${C_CYAN}选项:${C_RESET}"
    echo -e "  -d, --dir       指定要卸载的 Redis 安装根目录. 默认: /usr/local/redis"
    echo -e "  -h, --help      显示本帮助信息"
    exit 1
}

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--dir) INSTALL_DIR="$2"; shift ;;
        -h|--help) usage ;;
        *) echo -e "${C_RED}未知参数: $1${C_RESET}"; usage ;;
    esac
    shift
done

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo -e "${C_RED}错误: 此脚本必须以 root 权限运行 (sudo)。${C_RESET}" 1>&2
   exit 1
fi

echo -e "${C_CYAN}======================================================================${C_RESET}"
echo -e " ⚠️  ${C_RED}警告: 您正在执行 Redis 完全卸载程序${C_RESET}"
echo -e " 目标卸载目录: ${C_YELLOW}${INSTALL_DIR}${C_RESET}"
echo -e " 本操作将无条件擦除该目录下的所有【配置文件】、【日志】以及【生产持久化数据】！"
echo -e "${C_CYAN}======================================================================${C_RESET}"
read -p "您确认要彻底清除吗? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "卸载流程已被用户中断放弃。"
    exit 0
fi

# 1. 关停并注销 Systemd 服务
echo -e "\n[1/4] 正在注销并关停所有相关的 Systemd 服务..."
if systemctl list-unit-files | grep -q "^redis.service"; then
    systemctl stop redis >/dev/null 2>&1
    systemctl disable redis >/dev/null 2>&1
    rm -f /etc/systemd/system/redis.service
fi

for file in /etc/systemd/system/redis-*.service; do
    if [ -f "$file" ]; then
        SERVICE_NAME=$(basename "$file")
        systemctl stop "$SERVICE_NAME" >/dev/null 2>&1
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
        rm -f "$file"
    fi
done
systemctl daemon-reload

# 2. 强杀残留进程
echo "[2/4] 正在强制阻断并终止残留的 Redis 进程..."
pkill -9 redis-server >/dev/null 2>&1
pkill -9 redis-cli >/dev/null 2>&1

# 3. 物理粉碎安装目录
echo "[3/4] 正在物理粉碎 Redis 安装根目录..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "目录 $INSTALL_DIR 及其数据已完全删除。"
else
    echo "未检测到目录 $INSTALL_DIR，跳过文件清理。"
fi

# 4. 还原内核环境参数
echo "[4/4] 正在还原系统内核参数与限制环境..."
SYSCTL_CONF="/etc/sysctl.conf"
LIMITS_CONF="/etc/security/limits.conf"

sed -i '/vm.overcommit_memory = 1/d' $SYSCTL_CONF
sed -i '/net.core.somaxconn = 2048/d' $SYSCTL_CONF
sysctl -p >/dev/null 2>&1

sed -i '/\* soft nofile 65535/d' $LIMITS_CONF
sed -i '/\* hard nofile 65535/d' $LIMITS_CONF

if [ -f /etc/rc.local ]; then
    sed -i '/transparent_hugepage/d' /etc/rc.local
fi

# 清理环境变量残留
sed -i "\#export PATH=\$PATH:$INSTALL_DIR/bin#d" ~/.bashrc 2>/dev/null

echo -e "\n${C_GREEN}======================================================================${C_RESET}"
echo -e "${C_GREEN}✅ 卸载完成！Redis 已从当前服务器上完全清除，系统环境复原成功。${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}\n"