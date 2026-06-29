#!/bin/bash

# ==============================================================================
# Redis 自动化安装与极致性能调优脚本 (生产级/支持单机与集群)
# ==============================================================================

MODE="standalone"
PASSWORD="RedisPassword123"
VERSION="7.2.4"
INSTALL_DIR="/usr/local/redis"
CLUSTER_PORTS=(7001 7002 7003 7004 7005 7006)

C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

usage() {
    echo -e "${C_CYAN}使用方法:${C_RESET} $0 [选项]"
    echo -e "  -m, --mode      运行模式: ${C_YELLOW}'standalone'${C_RESET} 或 ${C_YELLOW}'cluster'${C_RESET}. 默认: standalone"
    echo -e "  -p, --password  设置 Redis 全局访问密码. 默认: RedisPassword123"
    echo -e "  -v, --version   指定 Redis 版本号. 默认: 7.2.4"
    echo -e "  -d, --dir       指定 Redis 安装根目录. 默认: /usr/local/redis"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--mode) MODE="$2"; shift ;;
        -p|--password) PASSWORD="$2"; shift ;;
        -v|--version) VERSION="$2"; shift ;;
        -d|--dir) INSTALL_DIR="$2"; shift ;;
        -h|--help) usage ;;
        *) echo -e "${C_RED}未知参数: $1${C_RESET}"; usage ;;
    esac
    shift
done

if [ "$(id -u)" != "0" ]; then
   echo -e "${C_RED}错误: 此脚本必须以 root 权限运行 (sudo)。${C_RESET}" 1>&2
   exit 1
fi

echo -e "${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_GREEN}🚀 启动 Redis $VERSION 极致性能部署计划${C_RESET}"
echo -e " 模式: ${C_YELLOW}$MODE${C_RESET} | 目录: ${C_YELLOW}$INSTALL_DIR${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}"

# 1. 极限系统内核与物理环境优化
optimize_system() {
    echo -e "${C_CYAN}[1/4] 正在执行 Linux 内核极限调优...${C_RESET}"
    
    local SYSCTL_CONF="/etc/sysctl.conf"
    local LIMITS_CONF="/etc/security/limits.conf"

    # 清理旧配置
    sed -i '/vm.overcommit_memory/d' $SYSCTL_CONF
    sed -i '/net.core.somaxconn/d' $SYSCTL_CONF
    sed -i '/vm.swappiness/d' $SYSCTL_CONF

    # 写入新内核参数 (加入 swappiness 和 65535 列队)
    cat <<EOF >> $SYSCTL_CONF
vm.overcommit_memory = 1
net.core.somaxconn = 65535
vm.swappiness = 1
EOF
    sysctl -p >/dev/null 2>&1

    # 彻底禁用 THP (消除内存写入延迟放大)
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo never > /sys/kernel/mm/transparent_hugepage/enabled
        if [ -f /etc/rc.local ]; then
            grep -q "transparent_hugepage" /etc/rc.local || echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
            chmod +x /etc/rc.local
        fi
    fi

    # 拔高文件描述符到 65535
    sed -i '/nofile 65535/d' $LIMITS_CONF
    echo -e "* soft nofile 65535\n* hard nofile 65535" >> $LIMITS_CONF
    ulimit -n 65535
}

# 2. 自动化依赖与指定分配器编译
install_and_compile() {
    echo -e "${C_CYAN}[2/4] 正在检查依赖并使用 jemalloc 多核编译源码...${C_RESET}"
    
    if command -v yum >/dev/null 2>&1; then
        yum install -y gcc make wget pkg-config tcl >/dev/null 2>&1
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update >/dev/null 2>&1
        apt-get install -y gcc make wget pkg-config tcl >/dev/null 2>&1
    else
        echo -e "${C_RED}错误: 未找到受支持的包管理器。${C_RESET}"
        exit 1
    fi

    cd /tmp
    if [ ! -f "redis-${VERSION}.tar.gz" ]; then
        wget -q https://download.redis.io/releases/redis-${VERSION}.tar.gz
    fi
    tar -xzf redis-${VERSION}.tar.gz
    cd redis-${VERSION}
    
    CORES=$(nproc 2>/dev/null || echo 2)
    echo -e "🔥 已启用 $CORES 线程并行编译..."
    
    # 【优化点】显式指定使用 jemalloc 内存分配器减少碎片
    make -j"${CORES}" MALLOC=jemalloc >/dev/null 2>&1
    make PREFIX=${INSTALL_DIR} install >/dev/null 2>&1
    
    mkdir -p ${INSTALL_DIR}/bin
    cp src/redis-cli src/redis-server src/redis-benchmark ${INSTALL_DIR}/bin/
}

# 3. 单机版环境配置
setup_standalone() {
    echo -e "${C_CYAN}[3/4] 正在注入极限性能配置文件...${C_RESET}"
    mkdir -p ${INSTALL_DIR}/{conf,data,logs}
    
    cat <<EOF > ${INSTALL_DIR}/conf/redis.conf
# 基础网络 (对齐内核的 65535)
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 65535
timeout 300
tcp-keepalive 300

# 进程与路径
daemonize yes
pidfile ${INSTALL_DIR}/redis.pid
logfile "${INSTALL_DIR}/logs/redis.log"
dir ${INSTALL_DIR}/data

# 鉴权
requirepass ${PASSWORD}
masterauth ${PASSWORD}

# 内存管理策略
maxmemory 2gb
maxmemory-policy allkeys-lru

# 纯后台释放(防阻塞)
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

# IO 多线程处理网络请求
io-threads-do-reads yes
io-threads 4

# 【核心性能优化】持久化与 I/O 调优
appendonly yes
appendfsync everysec
# 在后台重写 AOF 时，暂停磁盘同步，保障此时的高峰期写入性能
no-appendfsync-on-rewrite yes
aof-use-rdb-preamble yes
# 关闭单独的 RDB 生成，依赖 AOF 混合模式即可，减少 CPU 消耗
save ""
EOF

    cat <<EOF > /etc/systemd/system/redis.service
[Unit]
Description=Redis Server (Performance Tuned)
After=network.target
[Service]
Type=forking
ExecStart=${INSTALL_DIR}/bin/redis-server ${INSTALL_DIR}/conf/redis.conf
ExecStop=${INSTALL_DIR}/bin/redis-cli -p 6379 -a ${PASSWORD} shutdown
PIDFile=${INSTALL_DIR}/redis.pid
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now redis >/dev/null 2>&1
    echo -e "${C_CYAN}[4/4] 极限优化版单机 Redis 已启动。${C_RESET}"
}

# 4. 集群版配置
setup_cluster() {
    echo -e "${C_CYAN}[3/4] 正在配置高性能分布式伪集群 (并发拉起)...${C_RESET}"
    
    for PORT in "${CLUSTER_PORTS[@]}"; do
        NODE_DIR="${INSTALL_DIR}/cluster/${PORT}"
        mkdir -p ${NODE_DIR}/{conf,data,logs}
        
        cat <<EOF > ${NODE_DIR}/conf/redis.conf
bind 0.0.0.0
protected-mode yes
port ${PORT}
tcp-backlog 65535
timeout 300
tcp-keepalive 300

daemonize yes
pidfile ${NODE_DIR}/redis_${PORT}.pid
logfile "${NODE_DIR}/logs/redis_${PORT}.log"
dir ${NODE_DIR}/data

requirepass ${PASSWORD}
masterauth ${PASSWORD}

maxmemory-policy allkeys-lru
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes
io-threads-do-reads yes
io-threads 4

appendonly yes
appendfsync everysec
no-appendfsync-on-rewrite yes
aof-use-rdb-preamble yes
save ""

cluster-enabled yes
cluster-config-file nodes-${PORT}.conf
cluster-node-timeout 5000
EOF

        cat <<EOF > /etc/systemd/system/redis-${PORT}.service
[Unit]
Description=Redis Cluster Node ${PORT}
After=network.target
[Service]
Type=forking
ExecStart=${INSTALL_DIR}/bin/redis-server ${NODE_DIR}/conf/redis.conf
ExecStop=${INSTALL_DIR}/bin/redis-cli -p ${PORT} -a ${PASSWORD} shutdown
PIDFile=${NODE_DIR}/redis_${PORT}.pid
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now redis-${PORT} >/dev/null 2>&1 &
    done
    
    wait 
    echo -e "${C_CYAN}[4/4] 正在执行集群槽位分片...${C_RESET}"
    
    CLUSTER_NODES=""
    for PORT in "${CLUSTER_PORTS[@]}"; do
        CLUSTER_NODES="$CLUSTER_NODES 127.0.0.1:${PORT}"
    done
    
    echo "yes" | ${INSTALL_DIR}/bin/redis-cli -a ${PASSWORD} --cluster create $CLUSTER_NODES --cluster-replicas 1 >/dev/null 2>&1
}

optimize_system
install_and_compile

if [ "$MODE" = "standalone" ]; then
    setup_standalone
elif [ "$MODE" = "cluster" ]; then
    setup_cluster
fi

# 终端图形化日志汇总输出
echo -e "\n${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_GREEN}✅ 恭喜！Redis 生产部署与深度调优已全部达成！${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}"
echo -e " 🚀 ${C_BOLD}部署模式${C_RESET} : ${C_YELLOW}${MODE}${C_RESET}"
echo -e " 📂 ${C_BOLD}命令路径${C_RESET} : ${C_YELLOW}${INSTALL_DIR}/bin/redis-cli${C_RESET}"
echo -e " 🔑 ${C_BOLD}全局密码${C_RESET} : ${C_YELLOW}${PASSWORD}${C_RESET}"

echo -e "${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e " 🛠️  ${C_BOLD}服务管理规范命令 (Systemctl)${C_RESET}"
if [ "$MODE" = "standalone" ]; then
    echo -e "    查看状态 : ${C_GREEN}systemctl status redis${C_RESET}"
    echo -e "    关停服务 : ${C_YELLOW}systemctl stop redis${C_RESET}"
    echo -e "    重启服务 : ${C_YELLOW}systemctl restart redis${C_RESET}"
    echo -e " 🔌 ${C_BOLD}一键连接验证${C_RESET} : ${C_GREEN}${INSTALL_DIR}/bin/redis-cli -a ${PASSWORD} ping${C_RESET}"
elif [ "$MODE" = "cluster" ]; then
    FIRST_PORT=${CLUSTER_PORTS[0]}
    echo -e "    查看状态 : ${C_GREEN}systemctl status redis-${FIRST_PORT}${C_RESET} (支持7001-7006)"
    echo -e "    批量关停 : ${C_YELLOW}systemctl stop redis-{7001..7006}${C_RESET}"
    echo -e "    批量重启 : ${C_YELLOW}systemctl restart redis-{7001..7006}${C_RESET}"
    echo -e " 🔌 ${C_BOLD}集群连接验证${C_RESET} : ${C_GREEN}${INSTALL_DIR}/bin/redis-cli -c -p ${FIRST_PORT} -a ${PASSWORD}${C_RESET}"
fi

echo -e "${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e " 💡 ${C_BOLD}环境变量配置建议${C_RESET} : 您可以通过运行下方命令将其快速注入系统全局变量中："
echo -e "               ${C_YELLOW}echo 'export PATH=\$PATH:${INSTALL_DIR}/bin' >> ~/.bashrc && source ~/.bashrc${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}\n"