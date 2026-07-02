#!/bin/bash
# ============================================
# MathMate 快速部署脚本
# 适用于 Ubuntu 20.04+ / Debian 11+
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# ============================================
# 检测系统
# ============================================
detect_system() {
    log_step "检测系统类型..."

    if [ -f /etc/debian_version ]; then
        SYSTEM="debian"
        log_info "检测到 Debian/Ubuntu 系统"
    elif [ -f /etc/redhat-release ]; then
        SYSTEM="redhat"
        log_info "检测到 CentOS/RHEL 系统"
    else
        log_error "不支持的系统类型"
        exit 1
    fi
}

# ============================================
# 更新系统并安装依赖
# ============================================
install_dependencies() {
    log_step "更新系统并安装依赖..."

    if [ "$SYSTEM" = "debian" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt update -qq
        apt upgrade -y -qq
        apt install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm zip unzip ufw
    else
        yum update -y -qq
        yum install -y curl wget git nginx certbot python3-certbot-nginx nodejs npm zip unzip
    fi

    # 安装 PM2
    npm install -g pm2 --silent

    log_info "依赖安装完成"
}

# ============================================
# 配置防火墙
# ============================================
setup_firewall() {
    log_step "配置防火墙..."

    if command -v ufw &> /dev/null; then
        ufw --force enable
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw deny 3001/tcp
        log_info "UFW 防火墙配置完成"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        log_info "Firewalld 防火墙配置完成"
    else
        log_warn "未检测到防火墙，跳过配置"
    fi
}

# ============================================
# 创建目录结构
# ============================================
setup_directories() {
    log_step "创建目录结构..."

    mkdir -p /var/www/mathmate
    mkdir -p /var/www/mathmate/app
    mkdir -p /var/www/mathmate/images
    mkdir -p /var/log/mathmate
    mkdir -p /etc/mathmate

    log_info "目录结构创建完成"
}

# ============================================
# 复制文件
# ============================================
copy_files() {
    log_step "复制网站文件..."

    # 假设脚本在网站目录中执行
    if [ -f "./index.html" ]; then
        cp -r ./* /var/www/mathmate/
        log_info "文件复制完成"
    else
        log_warn "未找到 index.html，请确保在正确的目录中执行此脚本"
        log_info "或手动将 MathMate-Website 目录的内容复制到 /var/www/mathmate/"
    fi

    # 设置权限
    chown -R www-data:www-data /var/www/mathmate
    chmod -R 755 /var/www/mathmate
}

# ============================================
# 安装 Node.js 依赖
# ============================================
install_node_deps() {
    log_step "安装 Node.js 依赖..."

    cd /var/www/mathmate
    npm install express --silent

    log_info "Node.js 依赖安装完成"
}

# ============================================
# 配置 Nginx
# ============================================
setup_nginx() {
    log_step "配置 Nginx..."

    cat > /etc/nginx/sites-available/mathmate << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name mathmate.top www.mathmate.top;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name mathmate.top www.mathmate.top;

    ssl_certificate /etc/letsencrypt/live/mathmate.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mathmate.top/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/mathmate.top/chain.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

    root /var/www/mathmate;
    index index.html;

    gzip on;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /tech {
        try_files $uri $uri/ /tech.html;
    }

    location /app {
        alias /var/www/mathmate/app;
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
EOF

    ln -sf /etc/nginx/sites-available/mathmate /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    nginx -t
    log_info "Nginx 配置完成"
}

# ============================================
# 申请 SSL 证书
# ============================================
setup_ssl() {
    log_step "申请 Let's Encrypt SSL 证书..."

    mkdir -p /var/www/html/.well-known/acme-challenge

    # 这里使用 --nginx 模式，会自动配置 Nginx
    # 如果申请失败，请手动运行: certbot --nginx -d mathmate.top -d www.mathmate.top
    certbot --nginx -d mathmate.top -d www.mathmate.top --non-interactive --agree-tos --email your-email@example.com || log_warn "SSL 证书申请可能失败，请稍后手动运行 certbot"

    # 设置自动续期
    (crontab -l 2>/dev/null | grep -v certbot; echo "0 0 * * 0 certbot renew --quiet --deploy-hook 'nginx -s reload'") | crontab -

    log_info "SSL 证书配置完成"
}

# ============================================
# 启动服务
# ============================================
start_services() {
    log_step "启动服务..."

    # 启动 Nginx
    systemctl enable nginx
    systemctl restart nginx

    # 启动 API 代理（如果环境变量已配置）
    if [ -f "/var/www/mathmate/.env" ]; then
        cd /var/www/mathmate
        pm2 start ecosystem.config.js || pm2 start proxy_server.js --name mathmate-api
        pm2 save
        pm2 startup
        log_info "API 代理已启动"
    else
        log_warn "未找到 .env 文件，API 代理未启动"
        log_info "请先配置 /var/www/mathmate/.env 文件"
    fi

    log_info "服务启动完成"
}

# ============================================
# 显示部署结果
# ============================================
show_result() {
    log_info "=========================================="
    log_info "部署完成！"
    log_info "=========================================="
    echo ""
    log_info "访问地址："
    echo "  官网: https://mathmate.top"
    echo "  技术详解: https://mathmate.top/tech.html"
    echo "  Flutter 应用: https://mathmate.top/app"
    echo "  API 健康检查: https://mathmate.top/api/health"
    echo ""
    log_info "常用命令："
    echo "  查看日志: tail -f /var/log/nginx/mathmate-error.log"
    echo "  重启 Nginx: systemctl restart nginx"
    echo "  PM2 状态: pm2 status"
    echo "  PM2 日志: pm2 logs mathmate-api"
    echo ""
    if [ ! -f "/var/www/mathmate/.env" ]; then
        log_warn "⚠️  还需配置 API 代理："
        log_warn "1. 编辑 /var/www/mathmate/.env 文件"
        log_warn "2. 填入你的 API Key"
        log_warn "3. 运行: cd /var/www/mathmate && pm2 start ecosystem.config.js"
    fi
    log_info "=========================================="
}

# ============================================
# 主流程
# ============================================
main() {
    log_info "开始 MathMate 快速部署..."
    echo ""

    detect_system
    install_dependencies
    setup_firewall
    setup_directories
    copy_files
    install_node_deps
    setup_nginx
    setup_ssl
    start_services
    show_result
}

# 执行主流程
main
