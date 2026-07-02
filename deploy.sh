#!/bin/bash
# ============================================
# MathMate 自动部署脚本
# 阿里云 ECS + Nginx + Let's Encrypt
# ============================================

set -e  # 遇到错误立即退出

# ============================================
# 配置变量（请根据实际情况修改）
# ============================================
DOMAIN="mathmate.top"
EMAIL="your-email@example.com"  # 用于 Let's Encrypt 通知
WEB_ROOT="/var/www/mathmate"
FLUTTER_WEB_BUILD="/var/www/mathmate/app"
REPO_URL="https://github.com/mzk-C4/mathmate.git"
NGINX_CONF="/etc/nginx/sites-available/mathmate"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# 1. 系统更新与基础工具安装
# ============================================
install_base() {
    log_info "更新系统并安装基础工具..."

    # 检测系统类型
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt update && apt upgrade -y
        apt install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm zip unzip
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        yum update -y
        yum install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm zip unzip
    else
        log_error "不支持的系统类型"
        exit 1
    fi

    # 安装 PM2（用于 Node.js 进程管理）
    npm install -g pm2

    log_info "基础工具安装完成"
}

# ============================================
# 2. 配置防火墙
# ============================================
setup_firewall() {
    log_info "配置防火墙..."

    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw --force enable
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
    else
        log_warn "未检测到防火墙，跳过配置"
    fi

    log_info "防火墙配置完成"
}

# ============================================
# 3. 创建网站目录结构
# ============================================
setup_directories() {
    log_info "创建网站目录结构..."

    mkdir -p $WEB_ROOT
    mkdir -p $FLUTTER_WEB_BUILD
    mkdir -p /var/log/mathmate
    mkdir -p /etc/mathmate

    log_info "目录结构创建完成"
}

# ============================================
# 5. 安装 Node.js 依赖
# ============================================
install_node_dependencies() {
    log_info "安装 Node.js 依赖..."

    cd $WEB_ROOT
    npm install express

    log_info "Node.js 依赖安装完成"
}

# ============================================
# 6. 部署静态网站
# ============================================
deploy_website() {
    log_info "部署静态网站..."

    # 从当前目录复制文件到网站目录
    cp -r $WEB_ROOT/../index.html $WEB_ROOT/
    cp -r $WEB_ROOT/../tech.html $WEB_ROOT/
    cp -r $WEB_ROOT/../favicon.svg $WEB_ROOT/
    cp -r $WEB_ROOT/../robots.txt $WEB_ROOT/
    cp -r $WEB_ROOT/../sitemap.xml $WEB_ROOT/

    # 复制 images 目录
    if [ -d "$WEB_ROOT/../images" ]; then
        cp -r $WEB_ROOT/../images $WEB_ROOT/
    fi

    # 复制 Node.js 文件
    cp -r $WEB_ROOT/../proxy_server.js $WEB_ROOT/
    cp -r $WEB_ROOT/../ecosystem.config.js $WEB_ROOT/
    cp -r $WEB_ROOT/../package.json $WEB_ROOT/

    log_info "静态网站部署完成"
}

# ============================================
# 7. 构建 Flutter Web 应用
# ============================================
build_flutter_web() {
    log_info "构建 Flutter Web 应用..."

    # 检查 Flutter 环境
    if ! command -v flutter &> /dev/null; then
        log_warn "Flutter 未安装，跳过构建"

        # 提供 Flutter 安装指引
        cat > /etc/mathmate/flutter-install.txt << 'EOF'
Flutter 安装方法：
1. 下载 Flutter SDK:
   cd /opt
   wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz
   tar xf flutter_linux_3.24.5-stable.tar.xz

2. 配置环境变量（添加到 ~/.bashrc）:
   export PATH="$PATH:/opt/flutter/bin"
   export FLUTTER_ROOT=/opt/flutter

3. 验证安装:
   flutter doctor
EOF
        return
    fi

    # 拉取 MathMate 项目
    if [ -d "/tmp/mathmate-app" ]; then
        cd /tmp/mathmate-app
        git pull
    else
        git clone $REPO_URL /tmp/mathmate-app
        cd /tmp/mathmate-app
    fi

    # 构建 Web 应用
    flutter config --enable-web
    flutter pub get
    flutter build web --release

    # 复制构建产物
    rm -rf $FLUTTER_WEB_BUILD/*
    cp -r build/web/* $FLUTTER_WEB_BUILD/

    log_info "Flutter Web 应用构建完成"
}

# ============================================
# 6. 配置 Nginx
# ============================================
setup_nginx() {
    log_info "配置 Nginx..."

    # 创建 Nginx 配置
    cat > $NGINX_CONF << 'EOF'
# ============================================
# MathMate 官网 Nginx 配置
# ============================================

# 上游 Node.js API 代理服务器
upstream mathmate_api {
    server 127.0.0.1:3001;
    keepalive 64;
}

# HTTP 重定向到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name mathmate.top www.mathmate.top;

    # Let's Encrypt 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # 重定向到 HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS 主配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name mathmate.top www.mathmate.top;

    # ============================================
    # SSL 证书配置（Let's Encrypt）
    # ============================================
    ssl_certificate /etc/letsencrypt/live/mathmate.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mathmate.top/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/mathmate.top/chain.pem;

    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # ============================================
    # 安全头
    # ============================================
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https:; connect-src 'self' https://api.mathmate.top; frame-src 'self' https://player.bilibili.com;" always;

    # ============================================
    # Gzip 压缩
    # ============================================
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/rss+xml font/truetype font/opentype application/vnd.ms-fontobject image/svg+xml;
    gzip_disable "msie6";

    # ============================================
    # 静态网站根目录
    # ============================================
    root /var/www/mathmate;
    index index.html index.htm;

    # ============================================
    # 日志
    # ============================================
    access_log /var/log/nginx/mathmate-access.log;
    error_log /var/log/nginx/mathmate-error.log;

    # ============================================
    # 主站路由
    # ============================================
    location / {
        try_files $uri $uri/ /index.html;
    }

    # ============================================
    # 技术详解页面
    # ============================================
    location /tech {
        try_files $uri $uri/ /tech.html;
    }

    # ============================================
    # Flutter Web 应用
    # ============================================
    location /app {
        alias /var/www/mathmate/app;
        try_files $uri $uri/ /index.html;

        # Flutter Web 特殊缓存配置
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # ============================================
    # API 代理
    # ============================================
    location /api/ {
        proxy_pass http://mathmate_api;
        proxy_http_version 1.1;

        # WebSocket 支持（用于 SSE 流式响应）
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 超时配置（AI 推理可能需要较长时间）
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;

        # 缓冲区配置
        proxy_buffering off;
        proxy_cache off;
    }

    # ============================================
    # 静态资源缓存
    # ============================================
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # ============================================
    # 图片缓存
    # ============================================
    location /images/ {
        expires 90d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # ============================================
    # 隐藏 Nginx 版本
    # ============================================
    server_tokens off;
}
EOF

    # 创建符号链接
    ln -sf $NGINX_CONF /etc/nginx/sites-enabled/mathmate

    # 测试配置
    nginx -t

    log_info "Nginx 配置完成"
}

# ============================================
# 7. 申请 Let's Encrypt SSL 证书
# ============================================
setup_ssl() {
    log_info "配置 Let's Encrypt SSL..."

    # 创建临时目录
    mkdir -p /var/www/html/.well-known/acme-challenge

    # 申请证书
    certbot certonly --webroot \
        -w /var/www/html \
        -d $DOMAIN \
        -d www.$DOMAIN \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --non-interactive

    # 设置自动续期
    (crontab -l 2>/dev/null | grep -v certbot; echo "0 0 * * 0 certbot renew --quiet --deploy-hook 'nginx -s reload'") | crontab -

    log_info "SSL 证书配置完成"
}

# ============================================
# 8. 启动服务
# ============================================
start_services() {
    log_info "启动服务..."

    # 启动 Nginx
    systemctl enable nginx
    systemctl restart nginx

    log_info "服务启动完成"
    log_info "网站访问地址: https://$DOMAIN"
}

# ============================================
# 主流程
# ============================================
main() {
    log_info "开始 MathMate 自动部署..."

    install_base
    setup_firewall
    setup_directories
    deploy_website
    install_node_dependencies
    build_flutter_web
    setup_nginx
    setup_ssl
    start_services

    log_info "=========================================="
    log_info "部署完成！"
    log_info "官网: https://$DOMAIN"
    log_info "Flutter 应用: https://$DOMAIN/app"
    log_info "=========================================="
}

# 执行主流程
main
