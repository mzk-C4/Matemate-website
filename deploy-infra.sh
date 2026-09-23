#!/bin/bash
# ============================================
# MathMate 基础设施部署（无密钥部分）
# 包含：SSH测试、文件上传、依赖安装、Nginx、SSL
# ============================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}========================================${NC}\n${BLUE}[STEP]${NC} $1\n${BLUE}========================================${NC}"; }

SERVER_IP="47.94.83.150"
SSH_USER="root"
SSH_KEY="C:/Users/MZK/.ssh/mathmate_server"
LOCAL_DIR="D:/projects/MathMate-Website"
REMOTE_DIR="/tmp/mathmate-website"

SSH_CMD="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30 $SSH_USER@$SERVER_IP"
SCP_CMD="scp -i $SSH_KEY -o StrictHostKeyChecking=no -r"

# ============================================
# 步骤 1：测试连接
# ============================================
log_step "步骤 1/5：测试 SSH 连接"
$SSH_CMD "hostname && echo OK" && log_info "✅ 连接成功" || { log_error "❌ 连接失败"; exit 1; }

# ============================================
# 步骤 2：上传文件
# ============================================
log_step "步骤 2/5：上传部署文件"
$SSH_CMD "mkdir -p $REMOTE_DIR"
cd "$LOCAL_DIR"
log_info "上传 HTML 和配置文件..."
$SCP_CMD index.html tech.html favicon.svg robots.txt sitemap.xml \
         proxy_server.js ecosystem.config.js package.json \
         .env.template quick-deploy.sh \
         $SSH_USER@$SERVER_IP:$REMOTE_DIR/ 2>&1 | tail -3
log_info "上传 images 目录..."
$SSH_CMD "mkdir -p $REMOTE_DIR/images"
$SCP_CMD images $SSH_USER@$SERVER_IP:$REMOTE_DIR/ 2>&1 | tail -3
log_info "✅ 文件上传完成"

# ============================================
# 步骤 3：安装依赖
# ============================================
log_step "步骤 3/5：安装系统依赖"
$SSH_CMD 'export DEBIAN_FRONTEND=noninteractive; apt update -qq 2>&1 | tail -1; apt install -y -qq nginx certbot python3-certbot-nginx nodejs npm curl git > /dev/null 2>&1; npm install -g pm2 --silent 2>/dev/null; echo "[INFO] 依赖安装完成"; nginx -v 2>&1; node --version; pm2 --version 2>/dev/null | head -1'

# ============================================
# 步骤 4：部署网站文件
# ============================================
log_step "步骤 4/5：部署网站到 /var/www/mathmate"
$SSH_CMD 'mkdir -p /var/www/mathmate/app /var/www/mathmate/images /var/log/mathmate
cp -r /tmp/mathmate-website/* /var/www/mathmate/ 2>/dev/null || true
cd /var/www/mathmate && npm install express --silent 2>/dev/null || true
chown -R www-data:www-data /var/www/mathmate 2>/dev/null || true
chmod -R 755 /var/www/mathmate
ls /var/www/mathmate/ | head -20
echo "[INFO] ✅ 网站部署完成"'

# ============================================
# 步骤 5：配置 Nginx + 申请 SSL
# ============================================
log_step "步骤 5/5：配置 Nginx 并申请 SSL 证书"

$SSH_CMD 'set -e
# 创建 HTTP 版本 Nginx 配置（用于申请 SSL）
mkdir -p /var/www/html/.well-known/acme-challenge
cat > /etc/nginx/sites-available/mathmate << "NGINX_EOF"
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name mathmate.top www.mathmate.top _;

    root /var/www/mathmate;
    index index.html index.htm;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /tech {
        try_files $uri $uri/ /tech.html;
    }

    location /app {
        alias /var/www/mathmate/app;
        try_files $uri $uri/ /app/index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
        proxy_buffering off;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/mathmate /etc/nginx/sites-enabled/mathmate
rm -f /etc/nginx/sites-enabled/default
nginx -t 2>&1
systemctl restart nginx
systemctl enable nginx
echo "[INFO] ✅ Nginx HTTP 配置完成"'

echo ""
echo "============================================"
echo "🎉 基础设施部署完成！"
echo "============================================"
echo ""
echo "现在可以通过 IP 访问（HTTP）："
echo "  http://47.94.83.150"
echo ""
echo "下一步需要："
echo "  1. 配置 API 密钥（用 scp 上传 .env）"
echo "  2. 启动 API 代理"
echo "  3. 申请 SSL 证书（需要域名解析生效）"
