# 🚀 MathMate 部署完全指南

本指南提供三种部署方式，适合不同需求：
- **方式一**：自动部署脚本（最快，5 分钟完成）
- **方式二**：手动分步部署（完全控制，适合学习）
- **方式三**：Docker 部署（容器化，适合生产环境）

---

## 📋 部署前准备

### 服务器要求
- **操作系统**：Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- **内存**：建议 ≥ 2GB
- **硬盘**：建议 ≥ 20GB
- **网络**：开放 22、80、443 端口

### 域名要求
- 域名已解析到服务器 IP
- 支持的域名：`mathmate.top` 和 `www.mathmate.top`

### API Key 准备
- [ ] DeepSeek API Key
- [ ] 火山引擎 API Key
- [ ] Qwen API Key

---

## 方式一：自动部署脚本 ⚡（推荐）

### 第 1 步：上传文件到服务器

**方法 A：使用 SCP（Git Bash / PowerShell）**
```bash
# 在本地执行
cd D:/projects/MathMate-Website
scp -r * root@your-server-ip:/tmp/mathmate-website/
```

**方法 B：使用 SFTP 工具**
- 使用 WinSCP、FileZilla 或 MobaXterm
- 将 `MathMate-Website` 目录所有文件上传到 `/tmp/mathmate-website/`

**方法 C：直接在服务器下载**
```bash
ssh root@your-server-ip
cd /tmp
wget https://github.com/mzk-C4/mathmate/archive/refs/heads/main.zip
unzip main.zip
mv mathmate-Main/MathMate-Website mathmate-website
```

### 第 2 步：SSH 连接服务器

```bash
ssh root@your-server-ip
```

### 第 3 步：执行快速部署

```bash
# 进入目录
cd /tmp/mathmate-website

# 给予执行权限
chmod +x quick-deploy.sh

# 执行部署（全自动）
sudo ./quick-deploy.sh
```

### 第 4 步：配置 API Key

```bash
# 复制模板
sudo cp /var/www/mathmate/.env.template /var/www/mathmate/.env

# 编辑配置
sudo nano /var/www/mathmate/.env
```

填入以下内容：
```bash
VOLC_API_KEY=你的火山引擎密钥
VOLC_MODEL_ID=ep-xxxxxxxxxxxx
VOLC_OCR_MODEL_ID=ep-xxxxxxxxxxxx
VIVO_API_KEY=你的Qwen密钥
```

保存：`Ctrl+O` → `Enter` → `Ctrl+X`

### 第 5 步：启动 API 代理

```bash
cd /var/www/mathmate
sudo pm2 start ecosystem.config.js
sudo pm2 save
```

### 第 6 步：验证部署

```bash
# 检查 Nginx
curl -I https://mathmate.top

# 检查 API
curl https://mathmate.top/api/health

# 应该返回：
# {"status":"ok",...}
```

### ✅ 部署完成！

访问以下地址验证：
- 官网: https://mathmate.top
- 技术详解: https://mathmate.top/tech.html
- Flutter 应用: https://mathmate.top/app（需单独部署）

---

## 方式二：手动分步部署 🔧

### 第 1 步：更新系统

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt upgrade -y
```

**CentOS/RHEL:**
```bash
sudo yum update -y
```

### 第 2 步：安装基础软件

**Ubuntu/Debian:**
```bash
sudo apt install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm zip unzip ufw
```

**CentOS/RHEL:**
```bash
sudo yum install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm zip unzip
```

### 第 3 步：安装 PM2

```bash
npm install -g pm2
```

### 第 4 步：配置防火墙

```bash
# Ubuntu
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
```

### 第 5 步：创建目录结构

```bash
sudo mkdir -p /var/www/mathmate
sudo mkdir -p /var/www/mathmate/app
sudo mkdir -p /var/www/mathmate/images
sudo mkdir -p /var/log/mathmate
```

### 第 6 步：复制网站文件

```bash
# 假设文件已上传到 /tmp/mathmate-website
sudo cp -r /tmp/mathmate-website/* /var/www/mathmate/

# 设置权限
sudo chown -R www-data:www-data /var/www/mathmate
sudo chmod -R 755 /var/www/mathmate
```

### 第 7 步：安装 Node.js 依赖

```bash
cd /var/www/mathmate
npm install express
```

### 第 8 步：配置环境变量

```bash
sudo cp .env.template .env
sudo nano .env
```

### 第 9 步：配置 Nginx

```bash
sudo cp /var/www/mathmate/nginx.conf /etc/nginx/sites-available/mathmate 2>/dev/null || true

# 手动创建 Nginx 配置（见下文）
sudo nano /etc/nginx/sites-available/mathmate
```

**Nginx 配置文件内容：**
```nginx
server {
    listen 80;
    server_name mathmate.top www.mathmate.top;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name mathmate.top www.mathmate.top;

    ssl_certificate /etc/letsencrypt/live/mathmate.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mathmate.top/privkey.pem;

    root /var/www/mathmate;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/mathmate /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
```

### 第 10 步：申请 SSL 证书

```bash
sudo mkdir -p /var/www/html/.well-known/acme-challenge
sudo certbot --nginx -d mathmate.top -d www.mathmate.top
```

### 第 11 步：启动服务

```bash
# 启动 Nginx
sudo systemctl enable nginx
sudo systemctl restart nginx

# 启动 API 代理
cd /var/www/mathmate
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

---

## 方式三：Docker 部署 🐳

### 第 1 步：安装 Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

### 第 2 步：创建 docker-compose.yml

```bash
nano /var/www/mathmate/docker-compose.yml
```

```yaml
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ./:/usr/share/nginx/html:ro
    depends_on:
      - api

  api:
    image: node:18-alpine
    working_dir: /app
    volumes:
      - ./proxy_server.js:/app/proxy_server.js:ro
      - ./.env:/app/.env:ro
    command: node proxy_server.js
    environment:
      - PORT=3001
      - NODE_ENV=production
```

### 第 3 步：启动 Docker

```bash
cd /var/www/mathmate
docker-compose up -d
```

---

## 🔧 服务管理命令

### Nginx

```bash
# 查看状态
sudo systemctl status nginx

# 重启
sudo systemctl restart nginx

# 重新加载配置
sudo nginx -s reload

# 查看日志
sudo tail -f /var/log/nginx/mathmate-error.log
```

### PM2（API 代理）

```bash
# 查看所有服务
pm2 status

# 查看日志
pm2 logs mathmate-api

# 重启
pm2 restart mathmate-api

# 停止
pm2 stop mathmate-api

# 删除并重启
pm2 delete mathmate-api
pm2 start ecosystem.config.js
```

### SSL 证书

```bash
# 查看证书状态
sudo certbot certificates

# 手动续期
sudo certbot renew

# 强制续期
sudo certbot renew --force-renewal
```

---

## 📱 Flutter Web 部署（可选）

### 方法 A：在服务器上构建

```bash
# 安装 Flutter
cd /opt
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz
sudo tar xf flutter_linux_3.24.5-stable.tar.xz
export PATH="$PATH:/opt/flutter/bin"

# 拉取项目
cd /tmp
git clone https://github.com/mzk-C4/mathmate.git
cd mathmate

# 构建并部署
flutter pub get
flutter build web --release
sudo rm -rf /var/www/mathmate/app/*
sudo cp -r build/web/* /var/www/mathmate/app/
```

### 方法 B：本地构建后上传

```bash
# 在本地执行
cd D:/projects/MathMate
flutter build web --release

# 上传到服务器
scp -r build/web/* root@your-server-ip:/var/www/mathmate/app/
```

---

## ⚠️ 常见问题排查

### 问题 1：502 Bad Gateway

**原因**：API 代理未启动或端口被占用

**解决**：
```bash
# 检查 PM2 状态
pm2 status

# 检查端口
sudo lsof -i :3001

# 重启 API
pm2 restart mathmate-api
```

### 问题 2：SSL 证书申请失败

**原因**：域名未解析或防火墙阻止

**解决**：
```bash
# 检查域名解析
nslookup mathmate.top

# 检查防火墙
sudo ufw status

# 手动申请证书
sudo certbot certonly --standalone -d mathmate.top -d www.mathmate.top
```

### 问题 3：API 返回 404

**原因**：环境变量未配置

**解决**：
```bash
# 检查 .env 文件
cat /var/www/mathmate/.env

# 重新配置
sudo nano /var/www/mathmate/.env
pm2 restart mathmate-api
```

---

## 📊 部署验证清单

- [ ] 网站可访问：https://mathmate.top
- [ ] HTTPS 正常（浏览器显示锁图标）
- [ ] 技术页面可访问：https://mathmate.top/tech.html
- [ ] API 健康检查：https://mathmate.top/api/health
- [ ] PM2 进程运行正常
- [ ] Nginx 配置无错误
- [ ] SSL 证书有效期正常

---

## 🎯 部署后优化

### 性能优化

```bash
# 开启 HTTP/2
# 已在 Nginx 配置中默认开启

# 配置缓存
# 已在 Nginx 配置中设置静态资源 30 天缓存
```

### 监控设置

```bash
# 安装监控工具
npm install -g pm2-logrotate

# 配置日志轮转
pm2 install pm2-logrotate
```

### 备份设置

```bash
# 创建备份脚本
cat > /etc/cron.daily/backup-mathmate.sh << 'EOF'
#!/bin/bash
tar -czf /backup/mathmate-$(date +%Y%m%d).tar.gz /var/www/mathmate
EOF

chmod +x /etc/cron.daily/backup-mathmate.sh
```

---

## 📞 获取帮助

遇到问题？
1. 查看 [GitHub Issues](https://github.com/mzk-C4/mathmate/issues)
2. 查看 [技术文档](https://mathmate.top/tech.html)
3. 提交新的 Issue

---

**部署完成后，你的 MathMate 官网将在 https://mathmate.top 上线！🎉**
