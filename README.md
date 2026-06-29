# LinuxShell

Linux 服务端组件一键编译安装脚本集合，支持 Source Compile，自动处理依赖和系统调优。

## 目录

```
├── nginx/   Nginx 源码编译安装（交互式 / 静默双模式）
├── redis/   Redis 源码编译安装（单机 / 集群）
└── cpolar/  cpolar 内网穿透工具安装
```

## 环境要求

- 基于 systemd 的 Linux 发行版（Ubuntu/Debian/CentOS/RHEL 等）
- root 权限（脚本内置权限检查）
- 网络连接（需下载源码包）

## 使用示例

```bash
# 交互式安装 Nginx（可自由勾选模块）
sudo ./nginx/nginx.sh

# 生产环境静默安装 Nginx 并绑定域名
sudo ./nginx/nginx.sh --profile prod --domain example.com --auto

# 安装 Redis 单机版
sudo ./redis/redis.sh

# 安装 Redis 集群
sudo ./redis/redis.sh -m cluster -p MyStrongPassword

# 安装内网穿透工具
./cpolar/cpolar.sh
```

## License

[MIT](LICENSE)
