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
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, DELETE');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Request-ID');
    res.header('Access-Control-Expose-Headers', 'X-Request-ID');
    if (req.method === 'OPTIONS') {
        return res.sendStatus(200);
    }
    next();
});

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
