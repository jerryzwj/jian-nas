/**
 * Cloudflare 公共鉴权/定位小工具
 *
 * 设计前提：用户只需要提供一枚 API Token，Account ID / Zone ID 都从 Token 反查，
 * 界面不再要求填写。
 *
 * 两种定位方式：
 *  - resolveZone(token, domain)          —— 已知根域名（隧道固定域名用这个）
 *  - resolveZoneByHostname(token, host)  —— 已知完整域名，自动推出根域名 + 相对记录名（DDNS 用这个，
 *                                           支持任意一家自己的 Cloudflare 域名）
 */
const CF_API = 'https://api.cloudflare.com/client/v4';
// 隧道的根域名固定（这是本机自用隧道的域名约定），DDNS 不使用该常量
const FIXED_DOMAIN = 'wenjunzhang.eu.org';

async function cfFetch(token, method, apiPath, body) {
  const res = await fetch(`${CF_API}${apiPath}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
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

/**
 * 规范化用户填的域名：去掉 https:// 、去掉路径和端口、统一小写、去尾部点。
 * 返回完整域名（如 home.example.com）。
 */
function normalizeHostname(input) {
  let s = String(input || '').trim().toLowerCase();
  if (!s) throw new Error('请填写要映射的域名');
  s = s.replace(/^https?:\/\//, '');
  s = s.replace(/\/.*$/, '');
  s = s.replace(/:\d+$/, '');
  s = s.replace(/^\.+|\.+$/g, '');
  if (!/^[a-z0-9\u4e00-\u9fa5]([a-z0-9\-\u4e00-\u9fa5]*)?(\.[a-z0-9\u4e00-\u9fa5]([a-z0-9\-\u4e00-\u9fa5]*)?)+$/.test(s)) {
    throw new Error(`域名格式不对：${s || '(空)'}`);
  }
  return s;
}

/**
 * 用 Token 反查 zoneId / accountId（按已知根域名）
 * 返回 { zoneId, accountId, name }
 */
async function resolveZone(token, domain = FIXED_DOMAIN) {
  if (!token) throw new Error('缺少 Cloudflare API Token');
  const r = await cfFetch(token, 'GET', `/zones?name=${encodeURIComponent(domain)}`);
  if (r.status !== 200 || !r.json || !r.json.success) {
    throw new Error(`Token 无效或无 Zone 读取权限：${cfErrorText(r.json)}`);
  }
  const list = r.json.result || [];
  const zone = list.find((z) => z.name === domain) || list[0];
  if (!zone || !zone.id) throw new Error(`Token 下找不到域名 ${domain} 的 Zone`);
  return {
    zoneId: zone.id,
    accountId: (zone.account && zone.account.id) || '',
    name: zone.name,
  };
}

/**
 * 已知完整域名，反查所在 Zone，并算出相对记录名。
 * 例：hostname = home.example.com，zone = example.com → recordName = home
 *      hostname = example.com，zone = example.com      → recordName = ''（根域名）
 * 返回 { zoneId, accountId, name, hostname, recordName, root }
 */
async function resolveZoneByHostname(token, input) {
  if (!token) throw new Error('缺少 Cloudflare API Token');
  const hostname = normalizeHostname(input);

  // 1) 先按完整域名精确查一次（用户填了根域名时最快）
  let zone = null;
  const direct = await cfFetch(token, 'GET', `/zones?name=${encodeURIComponent(hostname)}`);
  if (direct.status === 200 && direct.json && direct.json.success) {
    zone = (direct.json.result || []).find((z) => z.name === hostname) || null;
  }

  // 2) 逐级剥掉最左边的标签再查
  if (!zone) {
    const labels = hostname.split('.');
    for (let i = 1; i < labels.length - 1; i += 1) {
      const candidate = labels.slice(i).join('.');
      const r = await cfFetch(token, 'GET', `/zones?name=${encodeURIComponent(candidate)}`);
      if (r.status === 200 && r.json && r.json.success) {
        const hit = (r.json.result || []).find((z) => z.name === candidate);
        if (hit) {
          zone = hit;
          break;
        }
      }
    }
  }

  // 3) 兜底：列出 Token 下所有 Zone，取最长匹配后缀
  if (!zone) {
    const list = await cfFetch(token, 'GET', '/zones?per_page=100');
    if (list.status !== 200 || !list.json || !list.json.success) {
      throw new Error(`Token 无效或无 Zone 读取权限：${cfErrorText(list.json)}`);
    }
    const zones = (list.json.result || [])
      .filter((z) => z && z.name && hostname.endsWith(`.${String(z.name).toLowerCase()}`))
      .sort((a, b) => String(b.name).length - String(a.name).length);
    zone = zones[0] || null;
    if (!zone) throw new Error(`这枚 Token 下没有能解析 ${hostname} 的域名（确认域名属于该账号，且 Token 有 Zone:Read 权限）`);
  }

  const zoneName = String(zone.name).toLowerCase();
  const recordName = hostname === zoneName ? '' : hostname.slice(0, hostname.length - zoneName.length - 1);
  return {
    zoneId: zone.id,
    accountId: (zone.account && zone.account.id) || '',
    name: zone.name,
    root: zone.name,
    hostname,
    recordName,
  };
}

module.exports = { CF_API, FIXED_DOMAIN, cfFetch, cfErrorText, resolveZone, resolveZoneByHostname, normalizeHostname };
