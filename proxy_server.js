/**
 * ============================================
 * MathMate API 代理服务器
 * ============================================
 * 用途：代理 Flutter Web 应用的 AI API 请求
 * 隐藏真实 API Key，提供安全隔离
 *
 * 运行：node proxy_server.js
 * PM2 守护：pm2 start proxy_server.js --name mathmate-api
 * ============================================
 */

const express = require('express');
const http = require('http');
const https = require('https');
const url = require('url');
const crypto = require('crypto');
const fs = require('fs');

// ============================================
// 配置
// ============================================
const CONFIG = {
    PORT: process.env.PORT || 3001,
    // 从环境变量读取真实 API Key
    DEEPSEEK_API_KEY: process.env.DEEPSEEK_API_KEY || '',
    DEEPSEEK_API_URL: process.env.DEEPSEEK_API_URL || 'https://api.deepseek.com/v1',
    VOLC_API_KEY: process.env.VOLC_API_KEY || '',
    VOLC_API_URL: process.env.VOLC_API_URL || 'https://ark.cn-beijing.volces.com/api/v3',
    QWEN_API_KEY: process.env.QWEN_API_KEY || '',
    QWEN_API_URL: process.env.QWEN_API_URL || 'https://dashscope.aliyuncs.com/api/v1',
    AUTH_SECRET_FILE: process.env.AUTH_SECRET_FILE || '/opt/mathmate/auth_secret.txt',
    RATE_LIMIT_PER_MINUTE: Math.max(1, parseInt(process.env.RATE_LIMIT_PER_MINUTE || '60', 10) || 60),
    ALLOWED_ORIGINS: (process.env.ALLOWED_ORIGINS || 'https://mathmate.top,https://www.mathmate.top')
        .split(',').map(value => value.trim()).filter(Boolean),
};

// ============================================
// 创建 Express 应用
// ============================================
const app = express();

// 中间件
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// CORS 头
app.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin && CONFIG.ALLOWED_ORIGINS.includes(origin)) {
        res.header('Access-Control-Allow-Origin', origin);
        res.header('Vary', 'Origin');
    }
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, DELETE');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-MathMate-Token, X-Request-ID');
    res.header('Access-Control-Expose-Headers', 'X-Request-ID');
    if (req.method === 'OPTIONS') {
        return res.sendStatus(200);
    }
    next();
});

let cachedSecret = null;
function getAuthSecret() {
    if (cachedSecret) return cachedSecret;
    try {
        cachedSecret = fs.readFileSync(CONFIG.AUTH_SECRET_FILE, 'utf8').trim();
    } catch (_) {
        return null;
    }
    return cachedSecret || null;
}

function verifyAuthToken(token) {
    try {
        const secret = getAuthSecret();
        if (!secret || !token) return null;
        const parts = token.split('.');
        if (parts.length !== 3) return null;
        const signature = crypto.createHmac('sha256', secret)
            .update(`${parts[0]}.${parts[1]}`).digest('base64url');
        const expected = Buffer.from(signature);
        const actual = Buffer.from(parts[2]);
        if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) return null;
        const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
        if (!payload.uid || !Number.isInteger(payload.exp) || payload.exp <= Math.floor(Date.now() / 1000)) return null;
        return payload;
    } catch (_) {
        return null;
    }
}

const requestWindows = new Map();
function requireAuthenticatedUser(req, res, next) {
    const bearer = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const token = req.headers['x-mathmate-token'] || bearer;
    const user = verifyAuthToken(token);
    if (!user) return res.status(401).json({ error: '请先登录或登录已过期' });

    const now = Date.now();
    const key = `${user.uid}:${req.ip}`;
    const current = requestWindows.get(key);
    if (!current || now - current.startedAt >= 60000) {
        requestWindows.set(key, { startedAt: now, count: 1 });
    } else if (++current.count > CONFIG.RATE_LIMIT_PER_MINUTE) {
        return res.status(429).json({ error: '请求过于频繁，请稍后再试' });
    }
    req.authUser = user;
    next();
}

app.use(['/api/deepseek', '/api/volc', '/api/qwen'], requireAuthenticatedUser);

// 请求日志
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] ${req.method} ${req.path}`);
    next();
});

// ============================================
// 健康检查
// ============================================
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        services: {
            deepseek: !!CONFIG.DEEPSEEK_API_KEY,
            volc: !!CONFIG.VOLC_API_KEY,
            qwen: !!CONFIG.QWEN_API_KEY,
        }
    });
});

// ============================================
// DeepSeek API 代理
// ============================================
app.all('/api/deepseek/*', (req, res) => {
    const targetPath = req.path.replace('/api/deepseek', '');
    const targetUrl = `${CONFIG.DEEPSEEK_API_URL}${targetPath}`;

    proxyRequest(req, res, targetUrl, {
        'Authorization': `Bearer ${CONFIG.DEEPSEEK_API_KEY}`,
        'Content-Type': 'application/json',
    });
});

// ============================================
// 火山引擎 API 代理
// ============================================
app.all('/api/volc/*', (req, res) => {
    const targetPath = req.path.replace('/api/volc', '');
    const targetUrl = `${CONFIG.VOLC_API_URL}${targetPath}`;

    proxyRequest(req, res, targetUrl, {
        'Authorization': `Bearer ${CONFIG.VOLC_API_KEY}`,
        'Content-Type': 'application/json',
    });
});

// ============================================
// Qwen API 代理（支持 SSE）
// ============================================
app.all('/api/qwen/*', async (req, res) => {
    const targetPath = req.path.replace('/api/qwen', '');
    const targetUrl = `${CONFIG.QWEN_API_URL}${targetPath}`;

    // SSE 流式响应处理
    if (req.body && req.body.stream === true) {
        proxySSE(req, res, targetUrl, {
            'Authorization': `Bearer ${CONFIG.QWEN_API_KEY}`,
            'Content-Type': 'application/json',
        });
    } else {
        proxyRequest(req, res, targetUrl, {
            'Authorization': `Bearer ${CONFIG.QWEN_API_KEY}`,
            'Content-Type': 'application/json',
        });
    }
});

// ============================================
// 通用代理函数
// ============================================
function proxyRequest(req, res, targetUrl, headers) {
    const parsedUrl = url.parse(targetUrl);
    const options = {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port || (parsedUrl.protocol === 'https:' ? 443 : 80),
        path: parsedUrl.path,
        method: req.method,
        headers: {
            ...headers,
            ...(req.body ? { 'Content-Length': Buffer.byteLength(JSON.stringify(req.body)) } : {}),
        },
    };

    const proxyReq = (parsedUrl.protocol === 'https:' ? https : http).request(options, (proxyRes) => {
        // 复制响应头
        Object.keys(proxyRes.headers).forEach(key => {
            res.setHeader(key, proxyRes.headers[key]);
        });

        // 管道响应
        proxyRes.pipe(res);
    });

    proxyReq.on('error', (err) => {
        console.error('代理请求错误:', err);
        res.status(500).json({ error: '代理请求失败', message: err.message });
    });

    // 发送请求体
    if (req.body) {
        proxyReq.write(JSON.stringify(req.body));
    }
    proxyReq.end();
}

// ============================================
// SSE 流式代理（用于 Qwen）
// ============================================
async function proxySSE(req, res, targetUrl, headers) {
    try {
        const response = await fetch(targetUrl, {
            method: req.method,
            headers: headers,
            body: JSON.stringify(req.body),
        });

        // 设置 SSE 响应头
        res.setHeader('Content-Type', 'text/event-stream');
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');
        res.setHeader('X-Accel-Buffering', 'no'); // 禁用 Nginx 缓冲

        // 管道 SSE 数据流
        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            const chunk = decoder.decode(value, { stream: true });
            res.write(chunk);
        }

        res.end();
    } catch (error) {
        console.error('SSE 代理错误:', error);
        res.status(500).json({ error: 'SSE 代理失败', message: error.message });
    }
}

// ============================================
// 404 处理
// ============================================
app.use((req, res) => {
    res.status(404).json({
        error: '未找到请求的 API 端点',
        path: req.path,
        available_endpoints: ['/api/deepseek/*', '/api/volc/*', '/api/qwen/*', '/health']
    });
});

// ============================================
// 错误处理
// ============================================
app.use((err, req, res, next) => {
    console.error('服务器错误:', err);
    res.status(500).json({
        error: '服务器内部错误',
        message: err.message
    });
});

// ============================================
// 启动服务器
// ============================================
const server = app.listen(CONFIG.PORT, () => {
    console.log('==========================================');
    console.log('MathMate API 代理服务器');
    console.log('运行中:', `http://127.0.0.1:${CONFIG.PORT}`);
    console.log('配置的 API 端点:');
    console.log(`  - DeepSeek: /api/deepseek/*`);
    console.log(`  - 火山引擎: /api/volc/*`);
    console.log(`  - Qwen: /api/qwen/*`);
    console.log('==========================================');
});

// 优雅关闭
process.on('SIGTERM', () => {
    console.log('收到 SIGTERM 信号，关闭服务器...');
    server.close(() => {
        console.log('服务器已关闭');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('\n收到 SIGINT 信号，关闭服务器...');
    server.close(() => {
        console.log('服务器已关闭');
        process.exit(0);
    });
});

module.exports = app;
