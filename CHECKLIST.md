# ✅ MathMate 部署执行清单

## 📋 部署前准备

### 服务器信息
- [ ] 服务器 IP: _______________
- [ ] 域名: mathmate.top
- [ ] 域名已解析到服务器 IP
- [ ] SSH 访问权限已确认

### API Key 准备
- [ ] DeepSeek API Key
- [ ] 火山引擎 API Key
- [ ] Qwen API Key

---

## 🚀 部署步骤

### 第一步：上传文件到服务器

**方式 A：使用 SCP（推荐）**
```bash
# 在本地 Windows PowerShell 或 Git Bash 中执行
cd D:/projects/MathMate-Website
scp -r * root@your-server-ip:/tmp/mathmate-website/
```

**方式 B：使用 SFTP 工具**
- 使用 WinSCP、FileZilla 或 MobaXterm
- 将 `MathMate-Website` 目录下所有文件上传到服务器的 `/tmp/mathmate-website/`

**方式 C：直接在服务器上 Git Clone**
```bash
ssh root@your-server-ip
cd /tmp
git clone https://github.com/mzk-C4/mathmate.git
cp -r mathmate/MathMate-Website/* /tmp/mathmate-website/
```

---

### 第二步：SSH 连接服务器

```bash
ssh root@your-server-ip
```

---

### 第三步：移动文件并设置权限

```bash
# 创建网站目录
sudo mkdir -p /var/www/mathmate
sudo mkdir -p /var/log/mathmate

# 复制文件
sudo cp -r /tmp/mathmate-website/* /var/www/mathmate/

# 设置权限
sudo chown -R www-data:www-data /var/www/mathmate
sudo chmod -R 755 /var/www/mathmate

# 进入目录
cd /var/www/mathmate
```

---

### 第四步：配置环境变量

```bash
# 复制模板
sudo cp .env.template .env

# 编辑并填入真实 API Key
sudo nano .env
```

**填入以下内容：**
```bash
DEEPSEEK_API_KEY=sk-你的DeepSeek密钥
DEEPSEEK_API_URL=https://api.deepseek.com/v1
VOLC_API_KEY=你的火山引擎密钥
VOLC_API_URL=https://ark.cn-beijing.volces.com/api/v3
QWEN_API_KEY=sk-你的Qwen密钥
QWEN_API_URL=https://dashscope.aliyuncs.com/api/v1
PORT=3001
NODE_ENV=production
```

保存：`Ctrl+O` → `Enter` → `Ctrl+X`

---

### 第五步：执行部署脚本

```bash
# 给予执行权限
sudo chmod +x deploy.sh

# 执行部署（全程自动化）
sudo ./deploy.sh
```

**脚本将自动完成：**
- ✅ 系统更新和基础工具安装
- ✅ 防火墙配置
- ✅ 目录结构创建
- ✅ Nginx 配置
- ✅ SSL 证书申请
- ✅ 服务启动

---

### 第六步：安装 Node.js 依赖并启动 API 代理

```bash
cd /var/www/mathmate

# 安装 Express
npm install express

# 启动 API 代理
pm2 start ecosystem.config.js

# 保存 PM2 配置
pm2 save

# 设置开机自启
pm2 startup
```

---

### 第七步：验证部署

```bash
# 检查 Nginx 状态
sudo systemctl status nginx

# 检查 PM2 状态
pm2 status

# 测试 API 健康检查
curl https://mathmate.top/api/health
```

---

## 🌐 访问地址

部署完成后，访问以下地址验证：

- [ ] 官网: https://mathmate.top
- [ ] 技术详解: https://mathmate.top/tech.html
- [ ] API 健康检查: https://mathmate.top/api/health
- [ ] Flutter 应用: https://mathmate.top/app/（需单独部署）

---

## 📱 Flutter Web 部署（可选）

如果你想在官网集成 Flutter Web 应用：

### 1. 在服务器上安装 Flutter

```bash
# 下载 Flutter SDK
cd /opt
sudo wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz
sudo tar xf flutter_linux_3.24.5-stable.tar.xz

# 配置环境变量
export PATH="$PATH:/opt/flutter/bin"
echo 'export PATH="$PATH:/opt/flutter/bin"' | sudo tee -a /etc/bash.bashrc

# 验证安装
flutter doctor
```

### 2. 克隆并构建 MathMate

```bash
# 克隆项目
cd /tmp
git clone https://github.com/mzk-C4/mathmate.git
cd mathmate

# 安装依赖
flutter pub get

# 构建 Web 应用
flutter build web --release

# 部署到网站目录
sudo rm -rf /var/www/mathmate/app/*
sudo cp -r build/web/* /var/www/mathmate/app/

# 设置权限
sudo chown -R www-data:www-data /var/www/mathmate/app
```

### 3. 配置 Flutter 环境变量

```bash
# 在 MathMate 项目根目录创建 .env.web
cd /tmp/mathmate
nano .env.web
```

```bash
# 指向 API 代理
API_BASE_URL=https://mathmate.top/api
DEEPSEEK_API_KEY=web-proxy
VOLC_API_KEY=web-proxy
QWEN_API_KEY=web-proxy
```

保存后重新构建：

```bash
flutter build web --release --dart-define=.env.web
sudo cp -r build/web/* /var/www/mathmate/app/
```

---

## 🔧 服务管理命令

### Nginx 管理

```bash
# 查看状态
sudo systemctl status nginx

# 重启
sudo systemctl restart nginx

# 重新加载配置
sudo nginx -s reload

# 查看日志
sudo tail -f /var/log/nginx/mathmate-access.log
```

### PM2 管理

```bash
# 查看所有服务
pm2 status

# 查看日志
pm2 logs mathmate-api

# 重启服务
pm2 restart mathmate-api

# 停止服务
pm2 stop mathmate-api

# 删除并重新启动
pm2 delete mathmate-api
pm2 start ecosystem.config.js
```

### SSL 证书管理

```bash
# 查看证书状态
sudo certbot certificates

# 手动续期
sudo certbot renew

# 强制续期
sudo certbot renew --force-renewal
```

---

## ⚠️ 常见问题排查

### 问题 1: SSL 证书申请失败

**解决方案：**
```bash
# 检查域名解析
nslookup mathmate.top

# 确保防火墙开放 80/443 端口
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 手动申请证书
sudo certbot certonly --standalone -d mathmate.top -d www.mathmate.top
```

### 问题 2: API 代理启动失败

**解决方案：**
```bash
# 检查 Node.js 版本
node --version  # 需要 >= 16.0.0

# 检查端口占用
sudo lsof -i :3001

# 查看详细日志
pm2 logs mathmate-api --lines 100

# 检查环境变量
cat /var/www/mathmate/.env
```

### 问题 3: 502 Bad Gateway

**解决方案：**
```bash
# 检查 API 代理是否运行
pm2 status

# 测试本地 API
curl http://127.0.0.1:3001/health

# 检查 Nginx 配置
sudo nginx -t

# 重启服务
pm2 restart mathmate-api
sudo nginx -s reload
```

### 问题 4: Flutter Web 404

**解决方案：**
```bash
# 检查目录权限
ls -la /var/www/mathmate/app/

# 修复权限
sudo chown -R www-data:www-data /var/www/mathmate
sudo chmod -R 755 /var/www/mathmate
```

---

## 📊 监控与日志

### 日志位置

| 服务 | 日志位置 |
|------|---------|
| Nginx 访问日志 | `/var/log/nginx/mathmate-access.log` |
| Nginx 错误日志 | `/var/log/nginx/mathmate-error.log` |
| PM2 日志 | `/var/log/mathmate/pm2-*.log` |
| 系统日志 | `/var/log/syslog` |

### 实时监控

```bash
# 综合监控（同时查看 Nginx + PM2）
sudo tail -f /var/log/nginx/mathmate-access.log & pm2 logs mathmate-api
```

---

## 🎯 部署完成后检查清单

- [ ] 网站可访问: https://mathmate.top
- [ ] HTTPS 正常工作（浏览器显示锁图标）
- [ ] 技术页面可访问: https://mathmate.top/tech.html
- [ ] API 健康检查返回 200: https://mathmate.top/api/health
- [ ] PM2 进程运行正常
- [ ] Nginx 配置测试通过
- [ ] SSL 证书有效期正常
- [ ] 防火墙规则正确配置
- [ ] 环境变量正确设置

---

## 📞 获取帮助

如果遇到问题：
1. 查看 `DEPLOYMENT.md` 详细文档
2. 检查服务日志
3. 访问 GitHub: https://github.com/mzk-C4/mathmate

---

部署完成后，你的 MathMate 官网将在 https://mathmate.top 上线！🎉
