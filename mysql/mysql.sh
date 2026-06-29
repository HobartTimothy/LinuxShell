#!/bin/bash

# ==========================================
# MySQL 8.0 生产级自动化部署与优化脚本
# 适用系统: Ubuntu, Debian, CentOS (8+), Rocky/AlmaLinux
# ==========================================

# --- 1. 用户配置区 ---
ROOT_PASSWORD="YourStrongPassword123!"

# --- 颜色输出配置 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

# --- 2. 前置检查 ---
if [ "$EUID" -ne 0 ]; then
  log_error "请使用 sudo 或 root 用户运行此脚本。"
  exit 1
fi

if ss -tuln | grep -q ":3306 "; then
  log_error "端口 3306 已被占用，请检查是否已运行 MySQL 或其他服务。"
  exit 1
fi

if command -v mysql >/dev/null 2>&1; then
  log_error "检测到系统中已安装 MySQL 命令，为防止覆盖数据，脚本已中止。"
  exit 1
fi

# --- 3. 动态计算缓冲池大小 (总内存的 50%) ---
# 获取物理内存大小 (单位: MB)
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
# 计算 50% 内存，并确保至少分配 128MB
BUFFER_POOL_MB=$(( TOTAL_MEM_MB / 2 ))
if [ "$BUFFER_POOL_MB" -lt 128 ]; then 
    BUFFER_POOL_MB=128
fi
log_info "系统总内存: ${TOTAL_MEM_MB}MB, 将分配 ${BUFFER_POOL_MB}MB 给 InnoDB 缓冲池。"

# --- 4. 系统环境检测与安装 ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    log_error "无法读取 /etc/os-release，无法确定操作系统。"
    exit 1
fi

log_info "正在为您配置 $OS 环境..."

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    PKG_MANAGER="apt-get"
    SVC_NAME="mysql"
    CONF_DIR="/etc/mysql/mysql.conf.d"
    
    export DEBIAN_FRONTEND=noninteractive
    $PKG_MANAGER update -qq
    $PKG_MANAGER install -y mysql-server -qq

elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" || "$OS" == "rhel" ]]; then
    PKG_MANAGER=$(command -v dnf || command -v yum)
    SVC_NAME="mysqld"
    CONF_DIR="/etc/my.cnf.d"
    
    $PKG_MANAGER install -y mysql-server -q
else
    log_error "暂不支持自动配置操作系统: $OS"
    exit 1
fi

log_success "MySQL 软件包安装完成。"

# --- 5. 优化 MySQL 配置 ---
log_info "写入性能优化参数..."
mkdir -p $CONF_DIR
CONF_FILE="$CONF_DIR/mysqld_custom.cnf"

cat <<EOF > $CONF_FILE
[mysqld]
# 网络配置
bind-address = 0.0.0.0
# 性能调优
max_connections = 500
innodb_buffer_pool_size = ${BUFFER_POOL_MB}M
innodb_log_file_size = 256M
# 日志配置
slow_query_log = 1
long_query_time = 2
EOF

systemctl enable --now $SVC_NAME >/dev/null 2>&1
systemctl restart $SVC_NAME

# --- 6. 智能等待服务启动 ---
log_info "等待 MySQL 服务就绪..."
for i in {1..15}; do
    if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 2
    if [ "$i" -eq 15 ]; then
        log_error "MySQL 服务启动超时，请检查系统日志 (journalctl -xe)。"
        exit 1
    fi
done

# --- 7. 账号配置与安全加固 ---
log_info "初始化密码、开启远程登录并进行安全加固..."

mysql -u root <<EOF
-- 1. 修改本地 root 密码
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${ROOT_PASSWORD}';

-- 2. 创建/更新远程 root 用户
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${ROOT_PASSWORD}';
ALTER USER 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- 3. 安全加固 (移除匿名用户和测试数据库)
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- 4. 刷新权限
FLUSH PRIVILEGES;
EOF
log_success "数据库权限及安全加固配置完成。"

# --- 8. 防火墙配置 ---
log_info "配置防火墙端口..."
if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then
    ufw allow 3306/tcp >/dev/null
    log_success "UFW 防火墙已开放 3306 端口。"
elif command -v firewall-cmd > /dev/null && systemctl is-active --quiet firewalld; then
    firewall-cmd --zone=public --add-port=3306/tcp --permanent >/dev/null
    firewall-cmd --reload >/dev/null
    log_success "Firewalld 防火墙已开放 3306 端口。"
else
    log_warn "未检测到活跃的本地防火墙。请确保云服务器安全组已放行 3306 端口。"
fi

echo -e "\n=========================================="
log_success "🎉 MySQL 生产级安装与配置圆满完成！"
echo -e "  📌 操作系统: ${YELLOW}$OS${NC}"
echo -e "  📌 缓冲池大小: ${YELLOW}${BUFFER_POOL_MB}MB${NC}"
echo -e "  📌 默认用户名: ${YELLOW}root${NC}"
echo -e "  📌 连接密  码: ${YELLOW}${ROOT_PASSWORD}${NC}"
echo -e "==========================================\n"