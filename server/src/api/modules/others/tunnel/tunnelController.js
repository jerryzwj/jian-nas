const tunnelService = require('../../../../services/cloudflareTunnelService');

/**
 * Cloudflare 隧道管理（供手机端 / 桌面端设置页调用）
 */
class TunnelController {
  async getStatus(req, res) {
    try {
      const st = await tunnelService.getStatus();
      return res.json({ success: true, data: st });
    } catch (e) {
      return res.json({ success: false, message: e && e.message ? String(e.message) : String(e) });
    }
  }

  async checkSubdomain(req, res) {
    try {
      const sub = (req.body && req.body.subdomain) || (req.query && req.query.subdomain) || '';
      const r = await tunnelService.checkSubdomain(sub);
      return res.json(r);
    } catch (e) {
      return res.json({ success: false, message: e && e.message ? String(e.message) : String(e) });
    }
  }

  async enable(req, res) {
    try {
      const body = req.body || {};
      // 端口以本次请求实际命中的监听端口为准，避免配置里写死
      let port = '';
      const host = String(req.headers.host || '');
      const m = host.match(/:(\d+)$/);
      if (m) port = m[1];
      if (!port) {
        try {
          const initUtil = require('../../../../initUtil');
          if (initUtil && initUtil.expressHttpPort) port = String(initUtil.expressHttpPort);
        } catch {}
      }
      if (!port) port = String(body.httpPort || process.env.EXPRESS_HTTP_PORT || 6789);
      const r = await tunnelService.enable({ ...body, httpPort: port });
      return res.json(r);
    } catch (e) {
      return res.json({ success: false, message: e && e.message ? String(e.message) : String(e) });
    }
  }

  async disable(req, res) {
    try {
      return res.json(tunnelService.disable());
    } catch (e) {
      return res.json({ success: false, message: e && e.message ? String(e.message) : String(e) });
    }
  }
}

module.exports = TunnelController;
