/**
 * 简·NAS · Cloudflare DDNS（独立功能，与内网穿透完全无关）
 *
 * 设计口径（按用户要求）：
 *  - 用户自备一枚 Cloudflare API Token（权限：Zone:Read + DNS:Edit）
 *  - 用户自备要映射的域名（完整域名，可以是自己的任意 CF 域名，例：home.example.com）
 *  - Account ID / Zone ID 由 Token 按域名自动反查，界面不填
 *  - 不读取、不继承内网穿透的 Token / 域名，两条链路互不影响
 *  - 自动取本机公网 IPv4 / IPv6，更新对应 A / AAAA 记录；定时轮询，IP 不变不写
 *
 * 配置存放：<userData>/cloudflare_ddns.json
 */
const fs = require('fs');
const path = require('path');

let Logger = null;
try {
  Logger = require('../utils/logger');
} catch {
  Logger = {
    info: (...a) => console.log('[CF-DDNS]', ...a),
    error: (...a) => console.error('[CF-DDNS]', ...a),
  };
}

const {
  CF_API,
  cfFetch: cfFetchAuth,
  cfErrorText,
  resolveZoneByHostname,
  normalizeHostname,
} = require('./cloudflareAuth');

const DEFAULTS = {
  enabled: false,
  // 用户自己的凭证与目标域名（两者都由用户提供）
  apiToken: '',
  hostname: '',
  // 由 Token 反查得到，仅供内部使用，不回显
  zoneId: '',
  accountId: '',
  zoneName: '',
  recordName: '',
  enableV4: true,
  enableV6: true,
  proxied: false,
  intervalMin: 5,
  lastIpv4: '',
  lastIpv6: '',
  lastRunAt: '',
  lastError: '',
};

let timer = null;
let running = false;

function configUtil() {
  return require('../config/config');
}

function configPath() {
  try {
    return path.join(configUtil().getUserDataPath(), 'cloudflare_ddns.json');
  }
  catch {
    return path.join(process.env.APPDATA || __dirname, 'nascab_os_server', 'cloudflare_ddns.json');
  }
}

function loadConfig() {
  try {
    const raw = fs.readFileSync(configPath(), 'utf8');
    return { ...DEFAULTS, ...JSON.parse(raw) };
  } catch {
    return { ...DEFAULTS };
  }
}

function saveConfig(cfg) {
  try {
    fs.mkdirSync(path.dirname(configPath()), { recursive: true });
    fs.writeFileSync(configPath(), JSON.stringify(cfg, null, 2), 'utf8');
  } catch (e) {
    Logger.error('保存 DDNS 配置失败', e && e.message);
  }
}

function nowText() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function cfFetch(method, apiPath, cfg, body) {
  return cfFetchAuth(cfg.apiToken, method, apiPath, body);
}

/**
 * 校验并补全凭证：
 *  - Token 必须由用户自己提供（缺了直接报"请填写你自己的 Cloudflare API Token"）
 *  - 域名必须由用户自己提供（完整域名）
 *  - Zone / Account 用 Token 按该域名反查；域名换了会重新反查
 */
async function ensureCredentials(cfg) {
  if (!cfg.apiToken) {
    throw new Error('请先填写你自己的 Cloudflare API Token（Zone:Read + DNS:Edit 权限）');
  }
  if (!cfg.hostname) {
    throw new Error('请填写要映射的域名（完整域名，例如 home.example.com）');
  }
  const hostname = normalizeHostname(cfg.hostname);
  cfg.hostname = hostname;

  const zoneName = String(cfg.zoneName || '').toLowerCase();
  const needResolve =
    !cfg.zoneId || !zoneName || !(hostname === zoneName || hostname.endsWith(`.${zoneName}`));

  if (needResolve) {
    const z = await resolveZoneByHostname(cfg.apiToken, hostname);
    cfg.zoneId = z.zoneId;
    cfg.accountId = z.accountId || cfg.accountId || '';
    cfg.zoneName = z.name;
    cfg.recordName = z.recordName;
  } else {
    cfg.recordName = hostname === zoneName ? '' : hostname.slice(0, hostname.length - zoneName.length - 1);
    cfg.zoneName = zoneName;
  }
  return cfg;
}

async function fetchText(url, timeoutMs = 8000) {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ac.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const text = (await res.text()).trim();
    return text;
  } finally {
    clearTimeout(t);
  }
}

async function getPublicIPv4() {
  const list = [
    'https://ipv4.icanhazip.com',
    'https://api-ipv4.ip.sb/ip',
    'http://ip.3322.net',
    'https://api.ipify.org',
  ];
  let lastErr = '';
  for (const url of list) {
    try {
      const ip = await fetchText(url);
      if (/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) return ip;
    } catch (e) {
      lastErr = e && e.message;
    }
  }
  throw new Error(`获取公网 IPv4 失败${lastErr ? `：${lastErr}` : ''}`);
}

async function getPublicIPv6() {
  const list = [
    'https://api6.ipify.org',
    'https://ipv6.icanhazip.com',
    'https://api-ipv6.ip.sb/ip',
  ];
  let lastErr = '';
  for (const url of list) {
    try {
      const ip = await fetchText(url);
      if (ip && ip.includes(':') && /^[0-9a-fA-F:]+$/.test(ip)) return ip;
    } catch (e) {
      lastErr = e && e.message;
    }
  }
  throw new Error(`获取公网 IPv6 失败${lastErr ? `：${lastErr}` : ''}`);
}

async function upsertRecord(cfg, type, hostname, content) {
  const q = `/zones/${cfg.zoneId}/dns_records?type=${type}&name=${encodeURIComponent(hostname)}`;
  const found = await cfFetch('GET', q, cfg);
  if (found.status !== 200 || !found.json || !found.json.success) {
    throw new Error(`查询 ${type} 记录失败：${cfErrorText(found.json)}`);
  }
  const records = found.json.result || [];
  const existing = records.find((r) => r.type === type && r.name === hostname);
  const body = {
    type,
    name: hostname,
    content,
    ttl: 60,
    proxied: !!cfg.proxied,
  };
  if (existing) {
    if (String(existing.content) === String(content) && existing.proxied === !!cfg.proxied) {
      return { changed: false, id: existing.id };
    }
    const upd = await cfFetch('PUT', `/zones/${cfg.zoneId}/dns_records/${existing.id}`, cfg, body);
    if (!upd.json || !upd.json.success) throw new Error(`更新 ${type} 记录失败：${cfErrorText(upd.json)}`);
    return { changed: true, id: existing.id };
  }
  const add = await cfFetch('POST', `/zones/${cfg.zoneId}/dns_records`, cfg, body);
  if (!add.json || !add.json.success) throw new Error(`创建 ${type} 记录失败：${cfErrorText(add.json)}`);
  return { changed: true, id: add.json.result && add.json.result.id };
}

/**
 * 执行一次同步；返回 { success, ipv4, ipv6, messages }
 */
async function runOnce(reason = 'manual') {
  if (running) return { success: false, message: '正在同步中' };
  running = true;
  const cfg = loadConfig();
  const messages = [];
  let ok = false;
  let lastError = '';
  try {
    await ensureCredentials(cfg);
    const hostname = cfg.hostname;
    let ipv4 = '';
    let ipv6 = '';

    if (cfg.enableV4 !== false) {
      try {
        ipv4 = await getPublicIPv4();
        const r = await upsertRecord(cfg, 'A', hostname, ipv4);
        cfg.lastIpv4 = ipv4;
        messages.push(`A ${hostname} → ${ipv4} ${r.changed ? '已更新' : '未变化'}`);
        ok = true;
      } catch (e) {
        lastError = e && e.message ? e.message : String(e);
        messages.push(`IPv4 失败：${lastError}`);
      }
    }

    if (cfg.enableV6 !== false) {
      try {
        ipv6 = await getPublicIPv6();
        const r = await upsertRecord(cfg, 'AAAA', hostname, ipv6);
        cfg.lastIpv6 = ipv6;
        messages.push(`AAAA ${hostname} → ${ipv6} ${r.changed ? '已更新' : '未变化'}`);
        ok = true;
      } catch (e) {
        if (!lastError) lastError = e && e.message ? e.message : String(e);
        messages.push(`IPv6 失败：${e && e.message ? e.message : String(e)}`);
      }
    }

    cfg.lastRunAt = nowText();
    cfg.lastError = lastError;
    saveConfig(cfg);
    if (ok) Logger.info(`[CF-DDNS] ${reason} 同步完成：${messages.join(' / ')}`);
    else Logger.error(`[CF-DDNS] ${reason} 同步失败：${lastError}`);
    return { success: ok, ipv4, ipv6, hostname, messages, message: ok ? '同步完成' : lastError };
  } catch (e) {
    const err = e && e.message ? e.message : String(e);
    cfg.lastError = err;
    cfg.lastRunAt = nowText();
    saveConfig(cfg);
    Logger.error(`[CF-DDNS] ${reason} 异常：${err}`);
    return { success: false, message: err };
  } finally {
    running = false;
  }
}

function intervalMs(cfg) {
  const m = Math.max(1, Number(cfg.intervalMin) || 5);
  return m * 60 * 1000;
}

function schedule(cfg) {
  clearTimer();
  timer = setInterval(() => {
    const cur = loadConfig();
    if (!cur.enabled) {
      clearTimer();
      return;
    }
    runOnce('timer').catch(() => {});
  }, intervalMs(cfg));
  if (timer.unref) timer.unref();
}

function clearTimer() {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
}

function getStatus() {
  const cfg = loadConfig();
  const hostname = cfg.hostname || '';
  return {
    enabled: !!cfg.enabled,
    // 凭证不回显明文，只回是否已配置（且只认 DDNS 自己的 Token）
    hasToken: !!cfg.apiToken,
    configured: !!(cfg.apiToken && cfg.hostname),
    hostname,
    recordName: cfg.recordName || '',
    zoneName: cfg.zoneName || '',
    // 兼容旧字段名，客户端改版前不至于报空
    domain: cfg.zoneName || '',
    fixedDomain: cfg.zoneName || '',
    url: hostname ? `http://${hostname}` : '',
    enableV4: cfg.enableV4 !== false,
    enableV6: cfg.enableV6 !== false,
    proxied: !!cfg.proxied,
    intervalMin: cfg.intervalMin || 5,
    lastIpv4: cfg.lastIpv4 || '',
    lastIpv6: cfg.lastIpv6 || '',
    lastRunAt: cfg.lastRunAt || '',
    lastError: cfg.lastError || '',
    running: !!timer,
  };
}

/**
 * 启用/保存。只接受用户自己提供的 Token 与完整域名；
 * Account / Zone 由 Token 自动反查，前端不传也不采信。
 */
async function enable(body = {}) {
  const base = loadConfig();
  const apiToken = String(body.apiToken || '').trim();
  const rawHost =
    body.hostname !== undefined
      ? body.hostname
      : body.domain !== undefined
        ? body.domain
        : body.subdomain !== undefined && base.zoneName
          ? `${body.subdomain}.${base.zoneName}`
          : base.hostname || '';

  let hostname;
  try {
    hostname = normalizeHostname(rawHost);
  } catch (e) {
    return { success: false, message: e && e.message ? e.message : String(e) };
  }

  const enableV4 = body.enableV4 !== undefined ? body.enableV4 !== false : base.enableV4 !== false;
  const enableV6 = body.enableV6 !== undefined ? body.enableV6 !== false : base.enableV6 !== false;
  if (!enableV4 && !enableV6) {
    return { success: false, message: 'A 与 AAAA 至少要启用一个' };
  }

  const tokenChanged = !!apiToken && apiToken !== base.apiToken;

  const cfg = {
    ...base,
    enabled: true,
    // 只有用户显式填写才覆盖；留空表示沿用上一次保存的自己的 Token
    apiToken: apiToken || base.apiToken || '',
    hostname,
    // Token 变了或域名换了，旧的反查结果不可信，清掉重算
    zoneId: tokenChanged ? '' : base.zoneId || '',
    zoneName: tokenChanged ? '' : base.zoneName || '',
    accountId: tokenChanged ? '' : base.accountId || '',
    recordName: '',
    enableV4,
    enableV6,
    proxied:
      body.proxied !== undefined ? body.proxied === true : base.proxied === true,
    intervalMin: Math.max(1, Number(body.intervalMin) || base.intervalMin || 5),
  };

  try {
    await ensureCredentials(cfg);
  } catch (e) {
    return { success: false, message: e && e.message ? e.message : String(e) };
  }

  // 保存前确认 Token 对该 Zone 有读权限
  const zone = await cfFetch('GET', `/zones/${cfg.zoneId}`, cfg);
  if (zone.status !== 200 || !zone.json || !zone.json.success) {
    return { success: false, message: `Token 无法访问域名 ${cfg.hostname} 所在的 Zone：${cfErrorText(zone.json)}` };
  }

  saveConfig(cfg);
  schedule(cfg);
  const result = await runOnce('enable');
  return {
    success: result.success,
    message: result.success ? 'DDNS 已启用' : result.message,
    hostname,
    zoneName: cfg.zoneName,
    ...result,
    ...getStatus(),
  };
}

function disable() {
  const cfg = loadConfig();
  cfg.enabled = false;
  saveConfig(cfg);
  clearTimer();
  return { success: true, message: 'DDNS 已停用', ...getStatus() };
}

function syncAndStart() {
  const cfg = loadConfig();
  if (!cfg.enabled) {
    clearTimer();
    return;
  }
  schedule(cfg);
  runOnce('startup').catch(() => {});
  Logger.info('[CF-DDNS] 已按配置启动定时同步');
}

module.exports = {
  getStatus,
  enable,
  disable,
  runOnce,
  syncAndStart,
  loadConfig,
};
