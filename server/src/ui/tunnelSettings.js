// ── Cloudflare 隧道设置（内嵌 cloudflared） ──────────────────────────────
// 凭证（API Token / Account / Zone）只保存在配置文件，界面不提供编辑入口，
// 这里只负责：填子域名、检测占用、启停、看运行状态。
const cfSubdomainInput = document.getElementById('cf-subdomain');
const cfDomainSuffix = document.getElementById('cf-domain-suffix');
const cfTunnelTip = document.getElementById('cf-tunnel-tip');
const cfOpenBtn = document.getElementById('cf-open-btn');

let cfFixedDomain = 'wenjunzhang.eu.org';

function cfTip(text, isError = false) {
  if (!cfTunnelTip) return;
  cfTunnelTip.textContent = text || '';
  cfTunnelTip.style.color = isError ? '#ff7b7b' : '';
}

function cfRefreshSuffix() {
  if (cfDomainSuffix) cfDomainSuffix.textContent = `.${cfFixedDomain}`;
}

async function cfLoadStatus() {
  if (!cfSubdomainInput || !window.electronAPI || !window.electronAPI.getTunnelStatus) return;
  const s = await window.electronAPI.getTunnelStatus();
  if (!s || !s.success) return;
  cfFixedDomain = s.fixedDomain || s.domain || cfFixedDomain;
  cfSubdomainInput.value = s.subdomain || '';
  cfRefreshSuffix();

  const hint = document.getElementById('cf-subdomain');
  if (hint) {
    hint.placeholder = s.hasToken ? '子域名，如 nascab' : '服务端未配置 Cloudflare API Token';
  }
  const enableBtn = document.getElementById('cf-enable-btn');
  if (enableBtn) enableBtn.disabled = !s.hasToken;

  if (s.enabled && s.running) {
    cfTip(`正常运行：${s.url}${s.lastService ? ` → ${s.lastService}` : ''}`, false);
  } else if (s.enabled && !s.running) {
    cfTip(`已启用但进程未运行${s.lastError ? `：${s.lastError}` : ''}`, true);
  } else if (s.hostname) {
    cfTip(`已停用（记录保留：${s.hostname}）`, false);
  } else if (!s.hasToken) {
    cfTip('服务端还没配 Cloudflare API Token', true);
  }
  if (cfOpenBtn) {
    cfOpenBtn.style.display = s.hostname ? '' : 'none';
    cfOpenBtn.dataset.url = s.url || '';
  }
}

if (cfSubdomainInput) {
  cfSubdomainInput.addEventListener('input', cfRefreshSuffix);

  if (cfOpenBtn) {
    cfOpenBtn.addEventListener('click', (e) => {
      e.preventDefault();
      const url = cfOpenBtn.dataset.url;
      if (url) window.electronAPI.openLink(url);
    });
  }

  const checkBtn = document.getElementById('cf-check-sub-btn');
  if (checkBtn) {
    checkBtn.addEventListener('click', async () => {
      const sub = cfSubdomainInput.value.trim();
      if (!sub) return cfTip('请先填写子域名', true);
      cfTip('检测中…');
      const r = await window.electronAPI.checkTunnelSubdomain(sub);
      if (!r || !r.success) return cfTip((r && r.message) || '检测失败', true);
      if (r.available) {
        cfTip(`${r.hostname} 可用${r.owned ? '（当前隧道已占用，可继续使用）' : ''}`, false);
      } else {
        cfTip(r.message || '该子域名已被占用', true);
      }
    });
  }

  const enableBtn = document.getElementById('cf-enable-btn');
  if (enableBtn) {
    enableBtn.addEventListener('click', async () => {
      const sub = cfSubdomainInput.value.trim();
      if (!sub) return cfTip('请先填写子域名', true);
      cfTip('正在创建隧道 / 写入 DNS / 启动 cloudflared…');
      const r = await window.electronAPI.enableTunnel({ subdomain: sub });
      if (!r || !r.success) {
        cfTip((r && r.message) || '启用失败', true);
        showToast((r && r.message) || '启用失败', 'error');
        return;
      }
      cfTip(`已启用：${r.url}`, false);
      if (cfOpenBtn) {
        cfOpenBtn.style.display = '';
        cfOpenBtn.dataset.url = r.url;
      }
      showToast('隧道已启用', 'success');
    });
  }

  const disableBtn = document.getElementById('cf-disable-btn');
  if (disableBtn) {
    disableBtn.addEventListener('click', async () => {
      const r = await window.electronAPI.disableTunnel();
      if (r && r.success) {
        cfTip('已停用（DNS 记录保留，重新启用即可复用）', false);
        if (cfOpenBtn) cfOpenBtn.style.display = 'none';
        showToast('隧道已停用', 'success');
      } else {
        cfTip((r && r.message) || '停用失败', true);
      }
    });
  }

  cfLoadStatus();
}
