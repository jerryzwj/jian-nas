/**
 * 生成"内置隧道凭证"文件（server/src/config/builtinSecret.js）
 *
 * 用法：
 *   node tools/make_builtin_secret.js <目标 server 目录> <Cloudflare API Token>
 * 或：
 *   $env:CF_API_TOKEN='<token>'; node tools/make_builtin_secret.js <目标 server 目录>
 *
 * 说明：Token 用 AES-256-GCM 加密后存放，密钥拆成三段常量，安装包里没有明文。
 * 注意：这个生成出来的文件不要提交到任何仓库（.gitignore 已忽略）。
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const target = process.argv[2] || path.join(__dirname, '..', 'server');
const token = (process.argv[3] || process.env.CF_API_TOKEN || '').trim();
if (!token) {
  console.error('缺少 Token：请作为第 2 个参数传入，或设置环境变量 CF_API_TOKEN');
  process.exit(1);
}

const seg1 = crypto.randomBytes(16).toString('hex');
const seg2 = crypto.randomBytes(16).toString('hex');
const seg3arr = Array.from(crypto.randomBytes(8));
const key = crypto.createHash('sha256').update(seg1 + seg2 + Buffer.from(seg3arr).toString('hex')).digest();

const iv = crypto.randomBytes(12);
const c = crypto.createCipheriv('aes-256-gcm', key, iv);
const ct = Buffer.concat([c.update(token, 'utf8'), c.final()]);
const blob = Buffer.concat([iv, c.getAuthTag(), ct]).toString('base64');

const b = Buffer.from(blob, 'base64');
const d = crypto.createDecipheriv('aes-256-gcm', key, b.subarray(0, 12));
d.setAuthTag(b.subarray(12, 28));
if (Buffer.concat([d.update(b.subarray(28)), d.final()]).toString('utf8') !== token) {
  console.error('自校验失败，已中止');
  process.exit(1);
}

const file = `/**
 * 内置边缘凭证：仅在「配置文件里没有 apiToken」时启用，用来让新装的机器开箱即可开隧道。
 * 存放形式：AES-256-GCM 密文，密钥由下面三处常量派生，安装包里没有任何明文 Token。
 * DDNS 不走这里，仍使用用户自己在 DDNS 页填的 Token。
 * 本文件由 tools/make_builtin_secret.js 生成，请勿提交仓库。
 */
const crypto = require('crypto');

// 内部缓存盐（勿改）
const K_SALT_A = '${seg1}';
// 通道标识（勿改）
const K_SALT_B = '${seg2}';
// 版本指纹（勿改）
const K_FINGERPRINT = [${seg3arr.join(',')}];

const BLOB = '${blob}';

let cache = null;

function deriveKey() {
  const fp = Buffer.from(K_FINGERPRINT).toString('hex');
  return crypto.createHash('sha256').update(K_SALT_A + K_SALT_B + fp).digest();
}

function getApiToken() {
  if (cache !== null) return cache;
  try {
    const buf = Buffer.from(BLOB, 'base64');
    const iv = buf.subarray(0, 12);
    const tag = buf.subarray(12, 28);
    const data = buf.subarray(28);
    const d = crypto.createDecipheriv('aes-256-gcm', deriveKey(), iv);
    d.setAuthTag(tag);
    cache = Buffer.concat([d.update(data), d.final()]).toString('utf8').trim() || '';
  } catch (e) {
    cache = '';
  }
  return cache;
}

function hasApiToken() {
  return !!getApiToken();
}

module.exports = { getApiToken, hasApiToken };
`;

const out = path.join(target, 'src', 'config', 'builtinSecret.js');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, file, 'utf8');
console.log('已生成：' + out + '（token 长度 ' + token.length + '）');
