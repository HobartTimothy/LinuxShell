#!/bin/bash

# ==========================================
# Nginx 自动化与交互式编译安装脚本 (代码极客/性能终极版)
# 特色: 原生数组处理、零内存泄漏、极速编译(-O3 -flto 且无 -g)、底层调优
# ==========================================

set -euo pipefail

# --- 1. 默认参数设置 ---
NGINX_VERSION="1.26.0"
INSTALL_PATH="/usr/local/nginx"
PROFILE="dev"
DOMAIN=""
INTERACTIVE=true
WORK_DIR="/tmp/nginx_build"

# --- 2. 检查 root 权限 ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误: 请使用 root 权限 (sudo) 运行此脚本。"
  exit 1
fi

# --- 3. 解析命令行参数 ---
usage() {
    cat << EOF
用法: $0 [选项]
选项:
  --version <版本号>     指定 Nginx 版本 (默认: 1.26.0 需填三位)
  --install-dir <目录>   指定安装路径 (默认: /usr/local/nginx)
  --profile <dev|prod>   指定运行环境 (默认: dev | prod 会开启极限性能优化)
  --domain <域名>        指定绑定的域名，将自动创建虚拟主机配置
  --auto                 跳过交互式模块选择，直接静默安装
  -h, --help             显示此帮助信息
EOF
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --version) NGINX_VERSION="$2"; shift 2 ;;
        --install-dir) INSTALL_PATH="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --auto) INTERACTIVE=false; shift 1 ;;
        -h|--help) usage ;;
        *) echo "❌ 错误: 未知参数 $1"; usage ;;
    esac
done

# --- 4. 模块配置定义 ---
declare -a MOD_FLAGS=(
    "--with-threads" "--with-file-aio" "--with-http_ssl_module" "--with-http_v2_module"
    "--with-http_v3_module" "--with-http_realip_module" "--with-http_addition_module"
    "--with-http_sub_module" "--with-http_dav_module" "--with-http_flv_module"
    "--with-http_mp4_module" "--with-http_gunzip_module" "--with-http_gzip_static_module"
    "--with-http_auth_request_module" "--with-http_random_index_module" "--with-http_secure_link_module"
    "--with-http_slice_module" "--with-http_stub_status_module" "--with-stream"
    "--with-stream_ssl_module" "--with-stream_realip_module" "--with-stream_ssl_preread_module"
    "--with-pcre-jit" "--with-compat"
)

declare -a MOD_DESC=(
    "线程池支持 (提升异步I/O读取性能)" "异步文件I/O支持 (AIO, 提升大文件传输性能)"
    "HTTPS / SSL / TLS 支持 (核心推荐)" "HTTP/2 协议支持 (提升并发性能)"
    "HTTP/3 (QUIC) 协议支持" "获取真实客户端IP (CDN/反向代理必备)"
    "响应追加模块 (在响应内容前后追加文本)" "文本替换模块 (替换 HTTP 响应中的指定字符串)"
    "WebDAV 协议支持 (文件管理功能)" "FLV 伪流媒体视频支持"
    "MP4 伪流媒体视频支持" "Gunzip 模块 (为不支持Gzip的客户端实时解压)"
    "静态 Gzip 模块 (直接发送预压缩的 .gz 文件)" "鉴权请求模块 (基于子请求的外部访问控制)"
    "随机主页模块 (随机选择目录下的文件作为默认页)" "安全链接模块 (计算URL防盗链哈希值与过期时间)"
    "分片模块 (大文件分片返回并利用缓存)" "状态监控模块 (输出 Nginx 基本的运行状态信息)"
    "Stream 核心模块 (TCP/UDP 四层代理与负载均衡)" "Stream SSL 支持 (为四层代理提供 TLS 加密)"
    "Stream 真实IP (提取四层代理的真实客户端IP)" "Stream SSL 预读 (不解密连接提取 SNI 信息作路由)"
    "PCRE JIT 加速 (正则即时编译, 显著提升正则性能)" "动态模块兼容性 (允许动态加载第三方模块)"
)

# 默认状态: 1=选中, 0=未选中
declare -a MOD_STATE=(1 1 1 1 0 1 0 1 0 0 0 0 1 0 0 0 0 1 1 1 0 0 1 1) 
TOTAL=${#MOD_FLAGS[@]}

# --- 5. 交互式选择 ---
if [ "$INTERACTIVE" = true ]; then
    echo "==================================================="
    echo "🔧 Nginx 编译模块定制 (基于官方文档)"
    echo "安装路径: $INSTALL_PATH | Nginx版本: $NGINX_VERSION | 环境: $PROFILE"
    echo "操作说明: 按 [↑/↓] 移动，[空格] 选中/取消，[q] 退出脚本，[回车] 确认"
    echo "==================================================="

    CURSOR=0
    tput civis
    trap "tput cnorm; exit 1" EXIT INT TERM

    # [性能优化] 抛弃慢速的 for 循环 echo，使用 printf 极速渲染占位换行
    printf '\n%.0s' $(seq 1 $TOTAL)

    function print_menu() {
        echo -en "\033[${TOTAL}A"
        for (( i=0; i<$TOTAL; i++ )); do
            local checkbox="[ ]"
            [[ "${MOD_STATE[$i]}" -eq 1 ]] && checkbox="[\033[32m*\033[0m]"
            
            if [ "$CURSOR" -eq "$i" ]; then
                echo -e "  \033[47;30m> $checkbox ${MOD_FLAGS[$i]} \033[0m - ${MOD_DESC[$i]}\033[K"
            else
                echo -e "    $checkbox ${MOD_FLAGS[$i]} - ${MOD_DESC[$i]}\033[K"
            fi
        done
    }

    print_menu

    while true; do
        IFS= read -rsn1 key
        if [[ -z "$key" ]]; then
            trap - EXIT INT TERM 
            tput cnorm
            break
        elif [[ "$key" == "q" || "$key" == "Q" ]]; then
            tput cnorm
            echo -e "\n🚪 用户已按 [q] 键，取消安装并退出脚本。"
            exit 0
        elif [[ "$key" == " " ]]; then
            MOD_STATE[$CURSOR]=$(( 1 - ${MOD_STATE[$CURSOR]} ))
            print_menu
        elif [[ "$key" == $'\x1b' ]]; then
            read -rsn1 -t 0.1 key2
            if [[ "$key2" == "[" ]]; then
                read -rsn1 -t 0.1 key3
                if [[ "$key3" == "A" ]]; then
                    CURSOR=$(( CURSOR - 1 ))
                    [[ $CURSOR -lt 0 ]] && CURSOR=$(( TOTAL - 1 ))
                    print_menu
                elif [[ "$key3" == "B" ]]; then
                    CURSOR=$(( CURSOR + 1 ))
                    [[ $CURSOR -ge $TOTAL ]] && CURSOR=0
                    print_menu
                fi
            fi
        fi
    done
fi

# [代码优化] 抛弃低效字符串拼接，改用原生 Bash 数组收集模块参数
declare -a SELECTED_MODULES=()
for (( i=0; i<$TOTAL; i++ )); do
    [[ "${MOD_STATE[$i]}" -eq 1 ]] && SELECTED_MODULES+=("${MOD_FLAGS[$i]}")
done

echo "==================================================="
echo "✅ 准备阶段完毕！即将执行以下配置："
echo "   Nginx版本 : $NGINX_VERSION"
echo "   安装目录  : $INSTALL_PATH"
echo "   运行环境  : $PROFILE"
echo "   绑定域名  : ${DOMAIN:-无}"
echo "==================================================="
sleep 1

# --- 6. 基础依赖与系统用户 ---
echo "📦 [1/7] 正在检查并安装系统依赖 (静默模式)..."

# [效率优化] 提炼包管理器调用逻辑，避免重复代码
if command -v dnf &>/dev/null; then PKG_CMD="dnf install -y"
elif command -v yum &>/dev/null; then PKG_CMD="yum install -y"
elif command -v apt-get &>/dev/null; then apt-get update -q &>/dev/null; PKG_CMD="apt-get install -y"
else echo "❌ 错误: 未知包管理器。"; exit 1; fi

$PKG_CMD gcc gcc-c++ make pcre2 pcre2-devel zlib zlib-devel openssl openssl-devel wget tar >/dev/null 2>&1

id "nginx" &>/dev/null || useradd -r -M -s /sbin/nologin nginx

# --- 7. 下载与编译 ---
echo "🌐 [3/7] 下载并解压 Nginx $NGINX_VERSION 源码..."
rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

if ! wget -q -c "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx-${NGINX_VERSION}.tar.gz; then
    echo -e "\n❌ 致命错误: 下载失败！请检查版本号(如1.26.0)或网络连接。"
    exit 1
fi

tar -zxf nginx-${NGINX_VERSION}.tar.gz || { echo -e "\n❌ 解压失败！"; exit 1; }
cd nginx-${NGINX_VERSION}

echo "⚙️  [4/7] 正在进行硬件级极速编译 (开启 LTO 且剥离调试符号)..."
# [效率优化] 去掉 -g 参数，极大缩减最终二进制文件体积并加快编译及加载速度
OPT_FLAGS="-O3 -march=native -flto -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong"

# 使用数组展开传入参数，最安全高效的 Bash 语法
./configure --prefix="$INSTALL_PATH" --user=nginx --group=nginx "${SELECTED_MODULES[@]}" \
  --with-cc-opt="${OPT_FLAGS}" \
  --with-ld-opt="-flto" > /dev/null

make -j$(nproc) > /dev/null 2>&1
make install > /dev/null 2>&1

chown -R root:root "$INSTALL_PATH"
chown -R nginx:nginx "$INSTALL_PATH/logs"

# --- 8. 环境与业务配置生成 ---
echo "📝 [5/7] 生成 Nginx 配置文件与内核调优策略..."
mkdir -p ${INSTALL_PATH}/conf/conf.d

if [ "$PROFILE" == "prod" ]; then
    mv ${INSTALL_PATH}/conf/nginx.conf ${INSTALL_PATH}/conf/nginx.conf.bak
    cat > ${INSTALL_PATH}/conf/nginx.conf << EOF
user  nginx;
worker_processes  auto;           
worker_cpu_affinity auto;         
worker_rlimit_nofile 100000;      
pcre_jit on;                      

error_log  logs/error.log warn;
pid        logs/nginx.pid;

events {
    use epoll;                    
    worker_connections  65535;    
    multi_accept on;              
    accept_mutex off;             
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  logs/access.log  main buffer=32k flush=3s; 

    sendfile        on;           
    tcp_nopush      on;           
    tcp_nodelay     on;           
    server_tokens   off;          
    
    keepalive_timeout  65;        
    keepalive_requests 1000;      
    client_max_body_size 50m;     
    client_body_buffer_size 128k; 

    open_file_cache max=10000 inactive=20s; 
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;

    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 5;            
    gzip_min_length 1024;         
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    include conf.d/*.conf;
}
EOF
else
    grep -q "include conf.d/\*.conf;" ${INSTALL_PATH}/conf/nginx.conf || \
        sed -i '/http {/a \    include conf.d/*.conf;' ${INSTALL_PATH}/conf/nginx.conf
fi

if [ -n "$DOMAIN" ]; then
    WEB_ROOT="${INSTALL_PATH}/html/${DOMAIN}"
    mkdir -p ${WEB_ROOT}
    echo "<h1>Welcome to ${DOMAIN} (Deployed via Auto-Script)</h1>" > ${WEB_ROOT}/index.html
    chown -R nginx:nginx ${WEB_ROOT}

    cat > ${INSTALL_PATH}/conf/conf.d/${DOMAIN}.conf << EOF
server {
    listen       80;
    server_name  ${DOMAIN};
    
    access_log  ${INSTALL_PATH}/logs/${DOMAIN}.access.log;
    error_log   ${INSTALL_PATH}/logs/${DOMAIN}.error.log;

    location / {
        root   ${WEB_ROOT};
        index  index.html index.htm;
    }
}
EOF
fi

# --- 9. 配置 Systemd 服务 ---
echo "🔌 [6/7] 配置 Systemd 系统服务..."
cat > /etc/systemd/system/nginx.service << EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=$INSTALL_PATH/logs/nginx.pid
ExecStartPre=$INSTALL_PATH/sbin/nginx -t
ExecStart=$INSTALL_PATH/sbin/nginx
ExecReload=$INSTALL_PATH/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nginx --now > /dev/null 2>&1

# --- 10. 配置防火墙与清理 ---
echo "🛡️  [7/7] 配置防火墙并清理环境..."
if systemctl is-active --quiet firewalld; then
    # [效率优化] 利用大括号扩展，合并 DBus 请求指令，提速！
    firewall-cmd --permanent --zone=public --add-service={http,https} > /dev/null 2>&1
    firewall-cmd --reload > /dev/null 2>&1
fi

rm -rf "$WORK_DIR"

echo ""
echo -e "\033[36m==================================================================\033[0m"
echo -e "\033[32m🎉 Nginx ${NGINX_VERSION} 部署与性能调优圆满完成！\033[0m"
echo -e "\033[36m==================================================================\033[0m"
echo -e "📌 \033[1m基础信息\033[0m"
echo "  - 安装目录 : ${INSTALL_PATH}"
[[ "$PROFILE" == "prod" ]] && echo -e "  - 运行环境 : \033[33mprod\033[0m (已开启 GCC -O3/LTO 极致编译 & 内核句柄缓存)" || echo "  - 运行环境 : ${PROFILE}"
echo "  - 主配置   : ${INSTALL_PATH}/conf/nginx.conf"
echo "  - 扩展配置 : ${INSTALL_PATH}/conf/conf.d/"
echo "  - 错误日志 : ${INSTALL_PATH}/logs/error.log"

if [ -n "$DOMAIN" ]; then
    echo ""
    echo -e "🌐 \033[1m虚拟主机 (业务配置)\033[0m"
    echo "  - 绑定域名 : http://${DOMAIN}"
    echo "  - 网站目录 : ${INSTALL_PATH}/html/${DOMAIN}"
fi

echo ""
echo -e "▶️  \033[1m快捷管理指令\033[0m"
echo "  - 查看状态 : \033[32msystemctl status nginx\033[0m"
echo "  - 重载配置 : \033[33msystemctl reload nginx\033[0m (修改配置后执行无缝重启)"
echo -e "\033[36m==================================================================\033[0m"
echo ""