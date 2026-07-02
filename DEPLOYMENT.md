# MathMate 部署指南

阿里云 ECS + Nginx + Let's Encrypt + Node.js 完整部署方案

## 系统要求

- 操作系统：Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- 域名：已解析到服务器 IP（mathmate.top 和 www.mathmate.top）
- 内存：建议 ≥ 2GB
- 硬盘：建议 ≥ 20GB

## 快速开始

### 1. 连接服务器

```bash
ssh root@your-server-ip
```

### 2. 下载部署脚本

```bash
# 创建目录
mkdir -p /opt/mathmate
cd /opt/mathmate

# 上传网站文件（使用 scp 或 sftp）
# 从本地上传
scp -r D:/projects/MathMate-Website/* root@your-server-ip:/opt/mathmate/

# 或在服务器上下载
wget https://github.com/mzk-C4/mathmate/archive/refs/heads/main.zip
unzip main.zip
```

### 3. 执行一键部署

```bash
cd /opt/mathmate
chmod +x deploy.sh
sudo ./deploy.sh
```

### 4. 配置环境变量

```bash
# 复制模板
cp .env.template .env

# 编辑并填入真实 API Key
nano .env
```

```bash
# .env 内容示例
DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxx
VOLC_API_KEY=xxxxxxxxxxxxxxxx
QWEN_API_KEY=sk-xxxxxxxxxxxxxxxx
```

### 5. 重启服务

```bash
# 重启 API 代理
pm2 restart mathmate-api

# 重启 Nginx
sudo nginx -s reload
```

## 手动部署（可选）

### A. 安装系统依赖

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm zip unzip
```

**CentOS/RHEL:**
```bash
sudo yum update -y
sudo yum install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm zip unzip
```

### B. 安装 PM2

```bash
npm install -g pm2
```

### C. 安装 Node.js 依赖

```bash
cd /var/www/mathmate
npm install express
```

### D. 配置 Nginx

```bash
# 复制配置
sudo cp nginx.conf /etc/nginx/sites-available/mathmate

# 启用配置
sudo ln -s /etc/nginx/sites-available/mathmate /etc/nginx/sites-enabled/

# 测试配置
sudo nginx -t

# 重启 Nginx
sudo systemctl restart nginx
```

### E. 申请 SSL 证书

```bash
sudo certbot --nginx -d mathmate.top -d www.mathmate.top
```

### F. 启动 API 代理

```bash
cd /var/www/mathmate
pm2 start ecosystem.config.js
pm2 save
```

## Flutter Web 部署

### 1. 安装 Flutter

```bash
# 下载 Flutter SDK
cd /opt
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz
tar xf flutter_linux_3.24.5-stable.tar.xz

# 配置环境变量
export PATH="$PATH:/opt/flutter/bin"
echo 'export PATH="$PATH:/opt/flutter/bin"' >> ~/.bashrc

# 验证安装
flutter doctor
```

### 2. 克隆 MathMate 项目

```bash
cd /tmp
git clone https://github.com/mzk-C4/mathmate.git
cd mathmate
```

### 3. 构建并部署

```bash
# 安装依赖
flutter pub get

# 构建 Web 应用
flutter build web --release

# 复制到网站目录
sudo rm -rf /var/www/mathmate/app/*
sudo cp -r build/web/* /var/www/mathmate/app/

# 设置权限
sudo chown -R www-data:www-data /var/www/mathmate
```

### 4. 配置 Web 环境变量

在 Flutter 项目中创建 `.env.web`:

```bash
# MathMate 项目根目录
cd /tmp/mathmate
nano .env.web
```

```ini
# API 配置（指向代理服务器）
API_BASE_URL=https://mathmate.top/api
DEEPSEEK_API_KEY=web-proxy
VOLC_API_KEY=web-proxy
QWEN_API_KEY=web-proxy
```

## 目录结构

```
/opt/mathmate/                          # 部署目录
├── index.html                          # 官网主页
├── tech.html                           # 技术详解
├── favicon.svg                          # 网站图标
├── robots.txt                          # 爬虫规则
├── sitemap.xml                         # 站点地图
├── images/                             # 图片资源
├── deploy.sh                           # 部署脚本
├── proxy_server.js                     # API 代理服务器
├── ecosystem.config.js                 # PM2 配置
├── package.json                        # Node.js 依赖
├── .env.template                       # 环境变量模板
└── README.md                           # 部署说明

/var/www/mathmate/                      # Nginx 网站目录
├── index.html                          # 官网主页
├── tech.html                           # 技术详解
├── favicon.svg                          # 网站图标
├── robots.txt                          # 爬虫规则
├── sitemap.xml                         # 站点地图
├── images/                             # 图片资源
├── app/                                # Flutter Web 应用
│   ├── index.html
│   ├── main.dart.js
│   ├── assets/
│   └── ...
├── proxy_server.js                     # API 代理服务器
├── ecosystem.config.js                 # PM2 配置
├── package.json                        # Node.js 依赖
├── .env                                # 生产环境变量
└── node_modules/                       # Node.js 依赖

/etc/nginx/
├── sites-available/
│   └── mathmate                        # Nginx 配置
└── sites-enabled/
    └── mathmate -> ../sites-available/mathmate

/etc/letsencrypt/live/mathmate.top/    # SSL 证书
├── fullchain.pem
├── privkey.pem
└── chain.pem

~/.pm2/                                # PM2 配置
└── dump.pm2                            # 进程列表备份
```

## 服务管理

### Nginx

```bash
# 查看状态
sudo systemctl status nginx

# 重启
sudo systemctl restart nginx

# 重新加载配置
sudo nginx -s reload

# 查看日志
sudo tail -f /var/log/nginx/mathmate-access.log
sudo tail -f /var/log/nginx/mathmate-error.log
```

### PM2（API 代理）

```bash
# 查看状态
pm2 status

# 查看日志
pm2 logs mathmate-api

# 重启服务
pm2 restart mathmate-api

# 停止服务
pm2 stop mathmate-api

# 删除服务
pm2 delete mathmate-api

# 保存配置
pm2 save

# 开机自启
pm2 startup
```

### SSL 证书

```bash
# 手动续期
sudo certbot renew

# 强制续期
sudo certbot renew --force-renewal

# 查看证书状态
sudo certbot certificates
```

## 访问地址

- 官网: https://mathmate.top
- 技术详解: https://mathmate.top/tech.html
- Flutter 应用: https://mathmate.top/app/
- API 健康检查: https://mathmate.top/api/health
- API 端点: https://mathmate.top/api/deepseek/*, /api/volc/*, /api/qwen/*

## 监控与日志

### 日志位置

- Nginx 访问日志: `/var/log/nginx/mathmate-access.log`
- Nginx 错误日志: `/var/log/nginx/mathmate-error.log`
- PM2 日志: `/var/log/mathmate/pm2-*.log`
- 系统日志: `/var/log/syslog`

### 健康检查

```bash
# API 代理健康检查
curl https://mathmate.top/api/health

# 响应示例
{
  "status": "ok",
  "timestamp": "2026-07-02T10:00:00.000Z",
  "uptime": 3600,
  "services": {
    "deepseek": true,
    "volc": true,
    "qwen": true
  }
}
```

## 常见问题

### 1. SSL 证书申请失败

```bash
# 检查域名解析
nslookup mathmate.top

# 检查防火墙
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 手动申请证书
sudo certbot certonly --standalone -d mathmate.top -d www.mathmate.top
```

### 2. API 代理无法启动

```bash
# 检查环境变量
pm2 logs mathmate-api

# 检查端口占用
sudo lsof -i :3001

# 检查 Node.js 版本
node --version  # 需要 >= 16.0.0
```

### 3. Flutter Web 无法访问

```bash
# 检查目录权限
sudo ls -la /var/www/mathmate/app/

# 修复权限
sudo chown -R www-data:www-data /var/www/mathmate
sudo chmod -R 755 /var/www/mathmate
```

### 4. Nginx 配置错误

```bash
# 测试配置
sudo nginx -t

# 查看错误日志
sudo tail -f /var/log/nginx/error.log

# 恢复默认配置
sudo nginx -s reload
```

## 性能优化

### 1. 开启 HTTP/2

Nginx 配置已包含 `http2` 参数，自动启用。

### 2. Gzip 压缩

Nginx 配置已包含 Gzip，自动压缩文本资源。

### 3. 静态资源缓存

Nginx 配置已设置合理的缓存策略：
- JS/CSS: 30 天
- 图片: 90 天
- Flutter 资源: 1 年

### 4. CDN（可选）

推荐使用阿里云 CDN 加速静态资源：

```bash
# 在阿里云控制台
# 1. 添加加速域名: mathmate.top
# 2. 源站设置: 你的服务器 IP
# 3. 缓存配置: 参考 Nginx 配置
```

## 安全加固

### 1. 配置防火墙

```bash
# Ubuntu (UFW)
sudo ufw enable
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw deny 3001/tcp  # 禁止直接访问 API 端口
```

### 2. 限制 SSH 访问

```bash
# 禁用密码登录，仅允许密钥
sudo nano /etc/ssh/sshd_config
# 设置: PasswordAuthentication no

# 重启 SSH
sudo systemctl restart sshd
```

### 3. 定期更新系统

```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# CentOS/RHEL
sudo yum update -y
```

## 备份与恢复

### 备份

```bash
# 备份网站文件
sudo tar -czf mathmate-backup-$(date +%Y%m%d).tar.gz /var/www/mathmate

# 备份 Nginx 配置
sudo tar -czf nginx-backup-$(date +%Y%m%d).tar.gz /etc/nginx

# 备份 PM2 配置
pm2 save
```

### 恢复

```bash
# 恢复网站文件
sudo tar -xzf mathmate-backup-20260702.tar.gz -C /

# 恢复 Nginx 配置
sudo tar -xzf nginx-backup-20260702.tar.gz -C /
```

## 联系支持

如遇到部署问题，请联系：

- GitHub: https://github.com/mzk-C4/mathmate
- Email: your-email@example.com
