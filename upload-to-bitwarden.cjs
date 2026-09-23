#!/usr/bin/env node
/**
 * upload-to-bitwarden.cjs
 * 把 MathMate 生产 API key（DeepSeek / 火山方舟 / Qwen）从服务器 .env 读出，
 * 存入 Bitwarden vault —— 每个服务商一条 login item。
 *
 * 安全设计：
 *  - .env 内容经 stdin 读入，脚本绝不打印任何密钥明文（只打印创建结果 / 条目名）。
 *  - 不把密钥写入任何文件。
 *  - 需要先： bw login  以及  export BW_SESSION="$(bw unlock --raw)"
 *
 * 用法：
 *   ssh -i ~/.ssh/mathmate_server root@mathmate.top 'cat /var/www/mathmate/.env' \
 *     | node upload-to-bitwarden.cjs
 */
const { execSync } = require('child_process');
const fs = require('fs');

const SESSION = process.env.BW_SESSION;
if (!SESSION) {
  console.error('✗ 未检测到 BW_SESSION。请先执行：  bw login   然后   export BW_SESSION="$(bw unlock --raw)"');
  process.exit(1);
}

// 1. 从 stdin 读 .env（密钥不进命令行参数、不落盘）
let envText = '';
try {
  envText = fs.readFileSync(0, 'utf8');
} catch (_) {
  console.error('✗ 没有 stdin。请用：  ssh ... "cat /var/www/mathmate/.env" | node upload-to-bitwarden.cjs');
  process.exit(2);
}

// 2. 解析 KEY=VALUE（去引号、跳过注释）
const env = {};
for (const raw of envText.split(/\r?\n/)) {
  const line = raw.trim();
  if (!line || line.startsWith('#')) continue;
  const eq = line.indexOf('=');
  if (eq < 0) continue;
  const k = line.slice(0, eq).trim();
  let v = line.slice(eq + 1).trim();
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
  env[k] = v;
}

// 3. 三个服务商（与 proxy_server.js 一致）
const JOBS = [
  { name: 'MathMate · DeepSeek API', key: 'DEEPSEEK_API_KEY', uri: 'https://api.deepseek.com/v1' },
  { name: 'MathMate · 火山方舟 API', key: 'VOLC_API_KEY',     uri: 'https://ark.cn-beijing.volces.com/api/v3' },
  { name: 'MathMate · Qwen API',     key: 'QWEN_API_KEY',     uri: 'https://dashscope.aliyuncs.com/api/v1' },
];

const run = (args, input) => execSync(`bw ${args}`, {
  encoding: 'utf8', input, stdio: ['pipe', 'pipe', 'pipe'], env: process.env,
});

let ok = 0;
for (const j of JOBS) {
  const val = env[j.key];
  if (!val || !val.trim()) { console.log(`✗ ${j.name} — .env 中 ${j.key} 缺失或为空`); continue; }
  const item = {
    type: 1,
    name: j.name,
    notes: `${j.key} — MathMate proxy_server.js (mathmate.top)`,
    login: { username: '', password: val, uris: [{ uri: j.uri }] },
  };
  try {
    const encoded = run('encode', JSON.stringify(item)).trim();
    const out = run('create item', encoded);
    const id = (out.match(/"id"\s*:\s*"([^"]+)"/) || [])[1];
    console.log(`✓ ${j.name}  (id: ${id || '?'})`);
    ok++;
  } catch (e) {
    const msg = (e.stderr && e.stderr.toString().trim()) || e.message;
    console.log(`✗ ${j.name} — ${msg.split('\n')[0]}`);
  }
}

console.log(`\n已创建 ${ok}/${JOBS.length} 条。`);

// 4. 验证（只列名称，不含密钥）
try {
  const list = run('list items');
  const names = [...list.matchAll(/"name"\s*:\s*"(MathMate[^"]*)"/g)].map(m => m[1]);
  if (names.length) console.log('vault 现有相关条目:', [...new Set(names)].join(' | '));
} catch (_) { /* list 非关键，忽略 */ }
