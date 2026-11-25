const ddnsService = require('../../../../services/cloudflareDdnsService');

/**
 * Cloudflare DDNS（A / AAAA），不依赖 NasCab 会员
 */
class DdnsController {
  async getStatus(req, res) {
    try {
      return res.json({ success: true, data: ddnsService.getStatus() });
    } catch (e) {
      return res.json({ success: false, message: String((e && e.message) || e) });
    }
  }

  async save(req, res) {
    try {
      const r = await ddnsService.enable(req.body || {});
      return res.json(r);
    } catch (e) {
      return res.json({ success: false, message: String((e && e.message) || e) });
    }
  }

  async disable(req, res) {
    try {
      return res.json(ddnsService.disable());
    } catch (e) {
      return res.json({ success: false, message: String((e && e.message) || e) });
    }
  }

  async runNow(req, res) {
    try {
      const r = await ddnsService.runOnce('api');
      return res.json({ success: r.success, message: r.message, data: ddnsService.getStatus(), result: r });
    } catch (e) {
      return res.json({ success: false, message: String((e && e.message) || e) });
    }
  }
}

module.exports = DdnsController;
