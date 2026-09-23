#!/bin/bash
# ============================================
# MathMate 本地一键部署脚本（安全版本）
# 不含任何硬编码密钥，通过 scp 上传 .env 文件
# ============================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}========================================${NC}\n${BLUE}[STEP]${NC} $1\n${BLUE}========================================${NC}"; }

# ============================================
# 配置（无密钥）
# ============================================
SERVER_IP="47.94.83.150"
SSH_USER="root"
SSH_KEY="C:/Users/MZK/.ssh/mathmate_server"
LOCAL_DIR="D:/projects/MathMate-Website"
ENV_SOURCE="D:/projects/MathMate/.env"
REMOTE_DIR="/tmp/mathmate-website"

SSH_CMD="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30 $SSH_USER@$SERVER_IP"
SCP_CMD="scp -i $SSH_KEY -o StrictHostKeyChecking=no"

# ============================================
# 步骤 1：测试连接
# ============================================
step1() {
    log_step "步骤 1/6：测试 SSH 连接"
    if $SSH_CMD "hostname" > /dev/null 2>&1; then
        log_info "✅ SSH 连接成功"
        $SSH_CMD "echo '  主机名:' \$(hostname); echo '  系统:' \$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)"
    else
        log_error "❌ SSH 连接失败"
        exit 1
    fi
}

# ============================================
# 步骤 2：上传网站文件
# ============================================
step2() {
    log_step "步骤 2/6：上传网站文件"
    $SSH_CMD "mkdir -p $REMOTE_DIR/images /var/www/mathmate/app /var/www/mathmate/images /var/log/mathmate"
    cd "$LOCAL_DIR"
    log_info "上传 HTML 和配置文件..."
    $SCP_CMD index.html tech.html favicon.svg robots.txt sitemap.xml \
             proxy_server.js ecosystem.config.js package.json \
             $SSH_USER@$SERVER_IP:$REMOTE_DIR/ 2>&1 | grep -v "^$" || true
    log_info "上传 images 目录..."
    $SCP_CMD -r images $SSH_USER@$SERVER_IP:$REMOTE_DIR/ 2>&1 | grep -v "^$" || true
    log_info "✅ 文件上传完成"
}

# ============================================
# 步骤 3：安装系统依赖
# ============================================
step3() {
    log_step "步骤 3/6：安装系统依赖"
    $SSH_CMD 'export DEBIAN_FRONTEND=noninteractive
apt update -qq 2>&1 | tail -1
apt install -y -qq nginx certbot python3-certbot-nginx nodejs npm curl git > /dev/null 2>&1
npm install -g pm2 --silent 2>/dev/null
echo "  Nginx: \$(nginx -v 2>&1)"
echo "  Node: \$(node --version 2>/dev/null)"
echo "  PM2: \$(pm2 --version 2>/dev/null | head -1)"
echo "[INFO] ✅ 依赖安装完成"'
}

# ============================================
# 步骤 4：部署网站文件
# ============================================
step4() {
    log_step "步骤 4/6：部署网站到 /var/www/mathmate"
    $SSH_CMD 'cp -r /tmp/mathmate-website/* /var/www/mathmate/ 2>/dev/null
cd /var/www/mathmate && npm install express --silent 2>/dev/null
chown -R www-data:www-data /var/www/mathmate 2>/dev/null || true
chmod -R 755 /var/www/mathmate
echo "[INFO] ✅ 网站部署完成"'
}

# ============================================
# 步骤 5：配置 Nginx
# ============================================
step5() {
    log_step "步骤 5/6：配置 Nginx"
    $SSH_CMD 'mkdir -p /var/www/html/.well-known/acme-challenge /etc/nginx/sites-enabled
cat > /etc/nginx/sites-available/mathmate << "NGINXEOF"
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name mathmate.top www.mathmate.top _;
    root /var/www/mathmate;
    index index.html index.htm;

    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { try_files $uri $uri/ /index.html; }
    location /tech { try_files $uri $uri/ /tech.html; }
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
NGINXEOF
ln -sf /etc/nginx/sites-available/mathmate /etc/nginx/sites-enabled/mathmate
rm -f /etc/nginx/sites-enabled/default
nginx -t 2>&1
systemctl restart nginx && systemctl enable nginx
echo "[INFO] ✅ Nginx 配置完成"'
}

# ============================================
# 步骤 6：上传 .env 并启动 API（密钥通过文件传输）
# ============================================
step6() {
    log_step "步骤 6/6：上传 .env 并启动 API 代理"

    if [ ! -f "$ENV_SOURCE" ]; then
        log_error "❌ 未找到 .env 文件: $ENV_SOURCE"
        exit 1
    fi

    log_info "通过 scp 上传 .env 文件（密钥不出现在命令行）..."
    $SCP_CMD "$ENV_SOURCE" $SSH_USER@$SERVER_IP:/var/www/mathmate/.env

    log_info "添加 Web 代理专用配置..."
    $SSH_CMD 'cat >> /var/www/mathmate/.env << "ENVAPPEND"

# Web 代理配置
PORT=3001
NODE_ENV=production
ENVAPPEND
chmod 600 /var/www/mathmate/.env
echo "[INFO] ✅ .env 配置完成"

# 启动 API 代理
cd /var/www/mathmate
pm2 delete mathmate-api 2>/dev/null || true
pm2 start ecosystem.config.js 2>&1 | tail -5
pm2 save 2>/dev/null
pm2 startup systemd -u root --hp /root 2>&1 | tail -2
echo "[INFO] ✅ API 代理已启动"

# 申请 SSL 证书（如果域名已解析）
echo "[INFO] 尝试申请 SSL 证书..."
certbot --nginx -d mathmate.top -d www.mathmate.top --non-interactive --agree-tos --email admin@mathmate.top 2>&1 | tail -5 || echo "[WARN] SSL 申请失败（域名可能未解析），稍后可手动申请"'
}

# ============================================
# 验证
# ============================================
verify() {
    log_step "验证部署"
    $SSH_CMD 'echo "=== 服务状态 ==="
systemctl is-active nginx | xargs echo "Nginx:"
pm2 list 2>/dev/null | grep -E "mathmate|App|name"
echo ""
echo "=== 端口监听 ==="
ss -tlnp 2>/dev/null | grep -E ":(80|443|3001)" || echo "端口检查完成"
echo ""
echo "=== API 测试 ==="
curl -s http://127.0.0.1:3001/health 2>/dev/null | head -3 || echo "API 正在启动中..."'
}

# ============================================
# 完成
# ============================================
done_msg() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎉 MathMate 部署完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "访问地址："
    echo "  🌐 http://47.94.83.150"
    echo "  🌐 https://mathmate.top（需域名解析）"
    echo "  📖 http://47.94.83.150/tech.html"
    echo ""
}

# 主流程
case "${1:-all}" in
    1|test) step1 ;;
    2|upload) step2 ;;
    3|deps) step3 ;;
    4|deploy) step4 ;;
    5|nginx) step5 ;;
    6|api) step6 ;;
    verify) verify ;;
    all)
        echo -e "${GREEN}🚀 MathMate 自动部署${NC}"
        step1
        step2
        step3
        step4
        step5
        step6
        verify
        done_msg
        ;;
    *) echo "用法: $0 [1|2|3|4|5|6|verify|all]" ;;
esac
