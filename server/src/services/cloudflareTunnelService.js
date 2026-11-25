/**
 * Cloudflare Tunnel 内嵌服务（本地自用改造）
 *
 * 目标：
 *  - 随 NasCab 主进程自动拉起 cloudflared，不需要用户另外装/启动隧道
 *  - 子域名可自定义；保存前检测 DNS 占用，多机安装各自用一个隧道，避免互相覆盖
 *  - 端口变更自动同步：ingress 的 service 端口始终对齐当前 httpPort
 *
 * 配置存放：<userData>/cloudflare_tunnel.json
 */
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

let Logger = null;
try {
  Logger = require('../utils/logger');
} catch {
  Logger = {
    info: (...a) => console.log('[CF-Tunnel]', ...a),
    error: (...a) => console.error('[CF-Tunnel]', ...a),
  };
}

const { FIXED_DOMAIN, resolveZone } = require('./cloudflareAuth');

const CF_API = 'https://api.cloudflare.com/client/v4';
const DEFAULTS = {
  enabled: false,
  accountId: '',
  apiToken: '',
  zoneId: '',
  domain: '',
  subdomain: '',
  tunnelId: '',
  tunnelToken: '',
  tunnelName: '',
  hostname: '',
  lastService: '',
};

let child = null;
let restartTimer = null;
let stopping = false;
let lastError = '';
let lastLog = '';
let currentService = '';
// Cloudflare 侧的真实连接状态（权威判断依据，避免只看本地进程导致误报）
// connectors = 去重后的 client_id 数量，即"有几台设备连在这条隧道上"（单台 cloudflared 的 4 条连接共用一个 client_id）
let remoteHealth = { status: 'unknown', connections: 0, connectors: 0, checkedAt: 0, error: '' };
let healthBusy = false;
// 多 connector 首次出现的时刻：重启服务端时旧连接要几十秒才被回收，稳定 60 秒以上才算真冲突
let conflictSince = 0;

function configUtil() {
  return require('../config/config');
}

function configPath() {
  try {
    return path.join(configUtil().getUserDataPath(), 'cloudflare_tunnel.json');
  } catch {
    return path.join(process.env.APPDATA || __dirname, 'nascab_os_server', 'cloudflare_tunnel.json');
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
    const next = { ...cfg };
    // 内置凭证只活在内存里，绝不写回配置文件（避免明文落到磁盘）
    if (next.__builtinToken) next.apiToken = '';
    delete next.__builtinToken;
    fs.mkdirSync(path.dirname(configPath()), { recursive: true });
    fs.writeFileSync(configPath(), JSON.stringify(next, null, 2), 'utf8');
  } catch (e) {
    Logger.error('保存隧道配置失败', e && e.message);
  }
}

function cloudflaredPath() {
  const candidates = [];
  try {
    const { app } = require('electron');
    candidates.push(path.join(path.dirname(app.getPath('exe')), 'cloudflared', 'cloudflared.exe'));
  } catch {}
  if (process.resourcesPath) candidates.push(path.join(process.resourcesPath, '..', 'cloudflared', 'cloudflared.exe'));
  candidates.push(path.join(__dirname, '..', '..', 'cloudflared', 'cloudflared.exe'));
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

async function cfFetch(method, apiPath, cfg, body) {
  const res = await fetch(`${CF_API}${apiPath}`, {
    method,
    headers: {
      Authorization: `Bearer ${cfg.apiToken}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try {
    json = await res.json();
  } catch {
    json = null;
  }
  return { status: res.status, json };
}

function cfErrorText(json) {
  if (!json) return '未知错误';
  if (Array.isArray(json.errors) && json.errors.length) {
    return json.errors.map((e) => `${e.code || ''} ${e.message || ''}`.trim()).join('; ');
  }
  return '未知错误';
}

function slug(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 20);
}

// 每台机器唯一的身份键：优先 Windows MachineGuid（不依赖业务数据，换机/拷配置都不会重复），
// 取不到时回退主机名。用它给隧道命名，两台电脑就不会共用同一条隧道。
let cachedMachineKey = '';
function machineKey() {
  if (cachedMachineKey) return cachedMachineKey;
  try {
    const { execFileSync } = require('child_process');
    const out = execFileSync('reg', ['query', 'HKLM\\SOFTWARE\\Microsoft\\Cryptography', '/v', 'MachineGuid'], {
      encoding: 'utf8',
      windowsHide: true,
    });
    const m = out.match(/([0-9a-fA-F]{8})-[0-9a-fA-F]{4}/);
    if (m) {
      cachedMachineKey = m[1].toLowerCase();
      return cachedMachineKey;
    }
  } catch {
    /* 非 Windows 或无权限，走主机名 */
  }
  try {
    cachedMachineKey = slug(require('os').hostname()) || 'host';
  } catch {
    cachedMachineKey = 'host';
  }
  return cachedMachineKey;
}

function machineTunnelName() {
  return `nascab-${machineKey()}`;
}

function assertSubdomain(sub) {
  const s = String(sub || '').trim().toLowerCase();
  if (!s) throw new Error('子域名不能为空');
  if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.?)$/.test(s)) throw new Error('子域名只能包含字母、数字和连字符');
  return s.replace(/\.$/, '');
}

/**
 * 配置文件没有 apiToken 时，注入内置凭证（加密存放，只在内存里用）。
 * 用户自己在 json 里填了 Token 就以用户的为准。
 */
function withToken(cfg) {
  if (!cfg.apiToken) {
    try {
      const builtin = require('../config/builtinSecret');
      const t = builtin.getApiToken();
      if (t) {
        cfg.apiToken = t;
        cfg.__builtinToken = true;
      }
    } catch {
      /* 内置凭证损坏时退回"未配置" */
    }
  }
  return cfg;
}

/**
 * 确保凭证可用：配置文件有 Token 用配置的，没有就用内置的；
 * Account ID / Zone ID 缺失时用 Token 自动反查（界面不再让用户填）。
 */
async function ensureCredentials(cfg) {
  withToken(cfg);
  if (!cfg.apiToken) {
    throw new Error(
      '服务端没有可用的 Cloudflare API Token（配置文件和内置凭证都为空）',
    );
  }
  if (!cfg.zoneId || !cfg.accountId) {
    const resolved = await resolveZone(cfg.apiToken, FIXED_DOMAIN);
    cfg.zoneId = cfg.zoneId || resolved.zoneId;
    cfg.accountId = cfg.accountId || resolved.accountId;
  }
  if (!cfg.accountId) {
    throw new Error('Token 无法识别账号 ID，请确认 Token 具备 Zone:Read 权限');
  }
  return cfg;
}

/** 检查子域名是否可用（DNS 记录层面） */
async function checkSubdomain(input) {
  const cfg = loadConfig();
  cfg.domain = FIXED_DOMAIN;
  try {
    await ensureCredentials(cfg);
  } catch (e) {
    return { success: false, message: e.message };
  }
  let sub;
  try {
    sub = assertSubdomain(input);
  } catch (e) {
    return { success: false, message: e.message };
  }
  const hostname = `${sub}.${cfg.domain}`;
  const r = await cfFetch('GET', `/zones/${cfg.zoneId}/dns_records?name=${encodeURIComponent(hostname)}`, cfg);
  if (r.status !== 200 || !r.json || !r.json.success) {
    return { success: false, message: `查询失败：${cfErrorText(r.json)}` };
  }
  const records = r.json.result || [];
  if (!records.length) return { success: true, hostname, available: true };
  const owned = records.find((rec) => rec.type === 'CNAME' && String(rec.content).includes(String(cfg.tunnelId).slice(0, 8)));
  if (owned) return { success: true, hostname, available: true, owned: true };
  return {
    success: true,
    hostname,
    available: false,
    message: `已被占用：${records[0].type} ${records[0].name} → ${records[0].content}`,
  };
}

async function ensureTunnel(cfg) {
  // 隧道名一律按本机身份生成，不沿用配置里可能来自别的机器的 tunnelName；
  // 这样两台电脑各查各的名字，查不到就各自新建，永远不会复用同一条。
  const name = machineTunnelName();
  const list = await cfFetch('GET', `/accounts/${cfg.accountId}/cfd_tunnel?name=${encodeURIComponent(name)}&is_deleted=false`, cfg);
  if (list.status !== 200 || !list.json || !list.json.success) {
    throw new Error(`列隧道失败：${cfErrorText(list.json)}`);
  }
  const found = (list.json.result || []).find((t) => t.name === name);
  if (found) {
    const tok = await cfFetch('GET', `/accounts/${cfg.accountId}/cfd_tunnel/${found.id}/token`, cfg);
    if (tok.json && tok.json.success) {
      cfg.tunnelId = found.id;
      cfg.tunnelToken = tok.json.result;
      cfg.tunnelName = name;
      return cfg;
    }
    throw new Error(`取隧道 token 失败：${cfErrorText(tok.json)}`);
  }
  const created = await cfFetch('POST', `/accounts/${cfg.accountId}/cfd_tunnel`, cfg, { name, config_src: 'cloudflare' });
  if (!created.json || !created.json.success) {
    throw new Error(`创建隧道失败：${cfErrorText(created.json)}`);
  }
  const id = created.json.result.id;
  const tok = await cfFetch('GET', `/accounts/${cfg.accountId}/cfd_tunnel/${id}/token`, cfg);
  if (!tok.json || !tok.json.success) throw new Error(`取隧道 token 失败：${cfErrorText(tok.json)}`);
  cfg.tunnelId = id;
  cfg.tunnelToken = tok.json.result;
  cfg.tunnelName = name;
  return cfg;
}

async function ensureDns(cfg, hostname) {
  const existing = await cfFetch('GET', `/zones/${cfg.zoneId}/dns_records?name=${encodeURIComponent(hostname)}`, cfg);
  if (existing.status !== 200 || !existing.json || !existing.json.success) {
    throw new Error(`查 DNS 失败：${cfErrorText(existing.json)}`);
  }
  const records = existing.json.result || [];
  const target = `${cfg.tunnelId}.cfargotunnel.com`;
  if (!records.length) {
    const created = await cfFetch('POST', `/zones/${cfg.zoneId}/dns_records`, cfg, {
      type: 'CNAME',
      name: hostname,
      content: target,
      proxied: true,
      ttl: 1,
    });
    if (!created.json || !created.json.success) {
      const err = cfErrorText(created.json);
      if (/81057|already exists|已被占用/i.test(err)) {
        throw Object.assign(new Error(`子域名 ${hostname} 已被其他记录占用，请换一个`), { code: 'SUBDOMAIN_TAKEN' });
      }
      throw new Error(`创建 DNS 失败：${err}`);
    }
    return;
  }
  const owned = records.find((r) => String(r.content) === target);
  if (!owned) {
    throw Object.assign(new Error(`子域名 ${hostname} 已被占用（${records[0].type} → ${records[0].content}），请换一个`), {
      code: 'SUBDOMAIN_TAKEN',
    });
  }
  if (!owned.proxied) {
    await cfFetch('PATCH', `/zones/${cfg.zoneId}/dns_records/${owned.id}`, cfg, { proxied: true });
  }
}

async function applyIngress(cfg, hostname, httpPort) {
  const service = `http://127.0.0.1:${httpPort}`;
  const body = {
    config: {
      ingress: [{ hostname, service }, { service: 'http_status:404' }],
    },
  };
  const r = await cfFetch('PUT', `/accounts/${cfg.accountId}/cfd_tunnel/${cfg.tunnelId}/configurations`, cfg, body);
  if (!r.json || !r.json.success) throw new Error(`写入 ingress 失败：${cfErrorText(r.json)}`);
  currentService = service;
  cfg.lastService = service;
  return service;
}

function stopProcess() {
  stopping = true;
  if (restartTimer) {
    clearTimeout(restartTimer);
    restartTimer = null;
  }
  if (child && !child.killed) {
    try {
      child.kill();
    } catch {}
  }
  child = null;
}

function startProcess(cfg) {
  stopProcess();
  stopping = false;
  const exe = cloudflaredPath();
  if (!fs.existsSync(exe)) {
    lastError = `找不到 cloudflared：${exe}`;
    Logger.error(lastError);
    return false;
  }
  if (!cfg.tunnelToken) {
    lastError = '隧道 token 为空，请重新保存配置';
    return false;
  }
  try {
    child = spawn(exe, ['tunnel', 'run', '--protocol', 'http2', '--token', cfg.tunnelToken], {
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.on('data', (d) => {
      const s = String(d).trim();
      if (s) Logger.info(`[cloudflared] ${s.slice(0, 400)}`);
    });
    child.stderr.on('data', (d) => {
      const s = String(d).trim();
      if (s) {
        // cloudflared 把大量正常心跳/重连日志也打到 stderr，
        // 这里只留作日志参考，绝不当作"故障"塞进 lastError（之前正是它导致假异常）
        lastLog = s.slice(0, 300);
        Logger.info(`[cloudflared] ${lastLog}`);
      }
    });
    child.on('exit', (code) => {
      Logger.info(`[cloudflared] 退出 code=${code}`);
      child = null;
      remoteHealth = { status: 'unknown', connections: 0, checkedAt: 0, error: '' };
      if (stopping) return;
      // 异常退出自动重连
      lastError = `cloudflared 已退出（code=${code}），5 秒后自动重连`;
      restartTimer = setTimeout(() => {
        const latest = loadConfig();
        if (latest.enabled) startProcess(latest);
      }, 5000);
    });
    lastError = '';
    Logger.info(`[cloudflared] 已拉起 pid=${child.pid} service=${currentService}`);
    return true;
  } catch (e) {
    lastError = e && e.message ? e.message : String(e);
    Logger.error('拉起 cloudflared 失败', lastError);
    return false;
  }
}

/** 启用/更新配置：校验 → 建隧道 → 建 DNS → 写 ingress → 起进程 */
async function enable(payload) {
  const base = loadConfig();
  const p = payload || {};
  // 凭证只在配置文件里维护，界面传什么都不采信（避免误操作/明文外泄）
  const cfg = {
    ...base,
    ...DEFAULTS,
    // 保留已保存的机密字段
    accountId: base.accountId,
    apiToken: base.apiToken,
    zoneId: base.zoneId,
    tunnelId: base.tunnelId,
    tunnelToken: base.tunnelToken,
    tunnelName: base.tunnelName,
    domain: FIXED_DOMAIN,
    subdomain: p.subdomain !== undefined ? p.subdomain : base.subdomain,
  };
  try {
    await ensureCredentials(cfg);
    const sub = assertSubdomain(cfg.subdomain);
    const hostname = `${sub}.${cfg.domain}`;

    const verify = await cfFetch('GET', `/zones/${cfg.zoneId}`, cfg);
    if (verify.status !== 200 || !verify.json || !verify.json.success) {
      return { success: false, message: `Token 无权限或 Zone 不对：${cfErrorText(verify.json)}` };
    }

    await ensureTunnel(cfg);
    // 子域名唯一性：已被别的隧道或别的记录占用时，不改写 DNS，直接让用户换一个
    if (!p.allowTakeover) {
      const probe = await cfFetch('GET', `/zones/${cfg.zoneId}/dns_records?name=${encodeURIComponent(hostname)}`, cfg);
      if (probe.status === 200 && probe.json && probe.json.success) {
        const records = probe.json.result || [];
        const mine = String(cfg.tunnelId).slice(0, 8);
        const mineRecord = records.find((x) => x.type === 'CNAME' && String(x.content).includes(mine));
        if (records.length && !mineRecord) {
          const other = records[0];
          const otherTunnel = other.type === 'CNAME' ? String(other.content).split('.')[0].slice(0, 8) : other.content;
          return {
            success: false,
            code: 'HOSTNAME_TAKEN',
            message: `子域名 ${hostname} 已被占用（${other.type} → ${otherTunnel}），不是本机的隧道。请换一个子域名，例如 ${sub}-2。`,
          };
        }
      }
    }
    await ensureDns(cfg, hostname);

    const httpPort = payload && payload.httpPort ? String(payload.httpPort) : String(currentService.replace(/[^0-9]/g, '') || 6789);
    await applyIngress(cfg, hostname, httpPort);

    cfg.subdomain = sub;
    cfg.hostname = hostname;
    cfg.enabled = true;
    saveConfig(cfg);
    startProcess(cfg);
    return { success: true, hostname, url: `https://${hostname}`, tunnelId: cfg.tunnelId };  } catch (e) {
    lastError = e && e.message ? e.message : String(e);
    saveConfig({ ...cfg, enabled: false });
    return { success: false, message: lastError, code: e && e.code };
  }
}

function disable() {
  const cfg = loadConfig();
  cfg.enabled = false;
  saveConfig(cfg);
  stopProcess();
  return { success: true };
}

/** 端口变了就同步 ingress 并重启进程 */
async function syncAndStart(httpPort) {
  const cfg = loadConfig();
  if (!cfg.enabled || !cfg.tunnelId || !cfg.tunnelToken) {
    Logger.info('[cloudflared] 隧道未启用，跳过');
    return { success: false, skipped: true };
  }
  try {
    const wanted = `http://127.0.0.1:${httpPort}`;
    if (cfg.lastService !== wanted) {
      await applyIngress(cfg, cfg.hostname || `${cfg.subdomain}.${cfg.domain}`, httpPort);
      cfg.lastService = wanted;
      saveConfig(cfg);
      Logger.info(`[cloudflared] ingress 端口已同步为 ${httpPort}`);
    } else {
      currentService = wanted;
    }
    startProcess(cfg);
    return { success: true, hostname: cfg.hostname };
  } catch (e) {
    lastError = e && e.message ? e.message : String(e);
    Logger.error('[cloudflared] 启动同步失败', lastError);
    return { success: false, message: lastError };
  }
}

/**
 * 查 Cloudflare 侧隧道真实状态：GET /accounts/{acc}/cfd_tunnel/{id} → status + connections
 * healthy = 已连接边缘并被判定可用；degraded = 部分边缘连不上；down/inactive = 没连上
 * 15 秒缓存，避免每次刷界面都打接口。
 */
async function refreshHealth(force = false) {
  const cfg = withToken(loadConfig());
  if (!cfg.enabled || !cfg.apiToken || !cfg.accountId || !cfg.tunnelId) {
    remoteHealth = { status: 'inactive', connections: 0, connectors: 0, checkedAt: Date.now(), error: '' };
    return remoteHealth;
  }
  if (!force && Date.now() - remoteHealth.checkedAt < 15000) return remoteHealth;
  if (healthBusy) return remoteHealth;
  healthBusy = true;
  try {
    const r = await cfFetch('GET', `/accounts/${cfg.accountId}/cfd_tunnel/${cfg.tunnelId}`, cfg);
    if (r.status === 200 && r.json && r.json.success && r.json.result) {
      const t = r.json.result;
      const conns = Array.isArray(t.connections) ? t.connections : [];
      // 同一台机器的 cloudflared 多条连接共用 client_id；不同机器 client_id 不同。
      // 去重后 >1 就说明有别的设备也连着这条隧道（流量会被随机分流），必须告警。
      const clients = new Set(conns.map((c) => c && c.client_id).filter(Boolean));
      const ips = new Set(conns.map((c) => c && c.origin_ip).filter(Boolean));
      remoteHealth = {
        status: t.status || 'unknown',
        connections: conns.length,
        connectors: clients.size || (conns.length ? 1 : 0),
        originIps: ips.size,
        checkedAt: Date.now(),
        error: '',
      };
      if (clients.size > 1) {
        if (!conflictSince) conflictSince = Date.now();
      } else {
        conflictSince = 0;
      }
    } else {
      remoteHealth = { status: 'unknown', connections: 0, connectors: 0, originIps: 0, checkedAt: Date.now(), error: cfErrorText(r.json) };
    }
  } catch (e) {
    remoteHealth = {
      status: 'unknown',
      connections: 0,
      connectors: 0,
      originIps: 0,
      checkedAt: Date.now(),
      error: (e && e.message ? e.message : String(e)).slice(0, 200),
    };
  } finally {
    healthBusy = false;
  }
  return remoteHealth;
}

async function getStatus() {
  const cfg = withToken(loadConfig());
  await refreshHealth().catch(() => {});
  const processRunning = !!child && !child.killed && child.exitCode === null;
  const health = cfg.enabled ? remoteHealth.status : 'inactive';
  // 以 Cloudflare 侧状态为主：healthy 或 degraded 但仍有连接，就算"能用的"
  const online = health === 'healthy' || (health === 'degraded' && remoteHealth.connections > 0);
  const connectors = cfg.enabled ? (remoteHealth.connectors || 0) : 0;
  const originIps = cfg.enabled ? (remoteHealth.originIps || 0) : 0;
  // 同一条隧道被多台机器同时连接：每台各 4 条连接，请求会在机器之间随机分流（静默串台）
  // 稳定超过 60 秒才算，避开重启后旧连接尚未回收的瞬态
  const conflict = connectors > 1 && conflictSince > 0 && Date.now() - conflictSince >= 60000;
  let conflictHint = '';
  if (conflict) {
    conflictHint =
      originIps > 1
        ? `检测到 ${connectors} 个 cloudflared 连接源来自 ${originIps} 个不同出口，说明另一台设备也连着这条隧道（${cfg.hostname || ''}），访问会随机落到不同机器，数据会对不上。请只让一台开隧道，或给另一台换独立子域名。`
        : `检测到本机有 ${connectors} 个 cloudflared 进程同时连这条隧道（多为服务端重启后的残留进程）。不影响使用，重启服务端即可清掉。`;
  }
  return {
    enabled: !!cfg.enabled,
    running: processRunning || online,
    processRunning,
    health,
    connections: remoteHealth.connections,
    connectors,
    originIps,
    conflict,
    conflictHint,
    healthError: remoteHealth.error || '',
    hostname: cfg.hostname || '',
    url: cfg.hostname ? `https://${cfg.hostname}` : '',
    // 根域名固定，只允许改子域名
    domain: FIXED_DOMAIN,
    fixedDomain: FIXED_DOMAIN,
    subdomain: cfg.subdomain || '',
    // 凭证不回显明文，只回是否已配置
    hasAccount: !!cfg.accountId,
    hasZone: !!cfg.zoneId,
    hasToken: !!cfg.apiToken,
    tunnelName: machineTunnelName(),
    lastService: cfg.lastService || '',
    lastError,
    lastLog,
  };
}

module.exports = {
  loadConfig,
  saveConfig,
  getStatus,
  checkSubdomain,
  enable,
  disable,
  syncAndStart,
  stop: stopProcess,
};
