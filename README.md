# MathMate 官网 + Flutter Web

完整的 MathMate 官网部署方案，包含：

## 文件说明

- `index.html` - 官网主页（产品展示）
- `tech.html` - 技术详解页面
- `deploy.sh` - 一键自动部署脚本
- `proxy_server.js` - API 代理服务器（隐藏 API Key）
- `.env.template` - 环境变量模板
- `ecosystem.config.js` - PM2 进程管理配置
- `images/` - 网站图片资源

## 快速部署

### 方式一：一键部署（推荐）

```bash
# 上传到服务器后
chmod +x deploy.sh
sudo ./deploy.sh
```

### 方式二：手动部署

```bash
# 1. 安装依赖
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx nodejs npm git

# 2. 安装 PM2
npm install -g pm2

# 3. 复制网站文件
sudo mkdir -p /var/www/mathmate
sudo cp -r ./* /var/www/mathmate/

# 4. 配置环境变量
cd /var/www/mathmate
cp .env.template .env
nano .env  # 填入你的 API Key

# 5. 安装 Node.js 依赖
npm install express

# 6. 启动 API 代理
pm2 start ecosystem.config.js

# 7. 配置 Nginx（见下方）

# 8. 申请 SSL 证书
sudo certbot --nginx -d mathmate.top -d www.mathmate.top
```

## Nginx 配置要点

关键配置已包含在 `deploy.sh` 中，手动配置时注意：

1. **HTTPS 重定向** - HTTP 自动跳转 HTTPS
2. **API 代理** - `/api/*` 代理到 Node.js 服务器
3. **Flutter Web** - `/app` 路径指向 Flutter 构建产物
4. **SPA 支持** - 所有路由回退到 index.html
5. **安全头** - HSTS、CSP、X-Frame-Options 等
6. **SSE 支持** - WebSocket 升级（用于 Qwen 流式响应）

## 目录结构

```
/var/www/mathmate/
├── index.html           # 官网主页
├── tech.html            # 技术详解
├── favicon.svg          # 网站图标
├── robots.txt           # 爬虫规则
├── images/              # 图片资源
├── app/                 # Flutter Web 应用
│   ├── index.html
│   ├── main.dart.js
│   └── assets/
├── proxy_server.js      # API 代理服务器
├── ecosystem.config.js  # PM2 配置
└── .env                 # 环境变量（含 API Key）
```

## API 代理

`proxy_server.js` 提供以下代理端点：

- `/api/deepseek/*` → DeepSeek API
- `/api/volc/*` → 火山引擎 API
- `/api/qwen/*` → Qwen API（支持 SSE 流式）
- `/health` → 健康检查

## 环境变量

复制 `.env.template` 为 `.env` 并填入：

```
DEEPSEEK_API_KEY=sk-xxxxx
VOLC_API_KEY=xxxxx
QWEN_API_KEY=sk-xxxxx
```

## Flutter Web 部署

在 MathMate 项目根目录执行：

```bash
# 构建 Flutter Web
flutter build web --release

# 复制到服务器
scp -r build/web/* user@mathmate.top:/var/www/mathmate/app/
```

## 访问地址

- 官网: https://mathmate.top
- 技术详解: https://mathmate.top/tech
- Flutter 应用: https://mathmate.top/app
- API 代理: https://mathmate.top/api/*

## 维护命令

```bash
# 查看 PM2 状态
pm2 status

# 查看日志
pm2 logs mathmate-api

# 重启服务
pm2 restart mathmate-api

# 重启 Nginx
sudo nginx -s reload

# 续期 SSL 证书
sudo certbot renew
```

## 开源协议

MIT License
