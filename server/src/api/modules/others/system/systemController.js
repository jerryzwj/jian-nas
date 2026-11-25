/**
 * 系统信息相关：给客户端/网页在"登录前"拿到本机可直连的地址清单。
 *
 * 场景：客户端先用中继（Cloudflare 隧道 / 公网 IPv6）连上，如果能直连内网或
 * OpenP2P 虚拟网段（10.10.10.x），就应该切过去，速度和稳定性都更好。
 * 真实内网（192.168/172.16-31）与 P2P 网段分开返回，客户端自行决定优先顺序。
 *
 * 注意：本接口不鉴权（登录页需要），因此只返回地址与端口，不返回任何账号/文件信息。
 */
const os = require('os');
const NetUtil = require('../../../../utils/netUtil');
const tableConfig = require('../../../../db/table/tableConfig');

const IPV4_PRIVATE = /^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)/;
const P2P_TUN = /^10\.10\.10\./;

class SystemController {
  /** GET /api/system/lan-addresses */
  async lanAddresses(req, res) {
    const all = NetUtil.getIPv4Addresses() || [];
    const mesh = all.filter((ip) => P2P_TUN.test(String(ip)));
    const lan = all
      .filter((ip) => IPV4_PRIVATE.test(String(ip)) && !P2P_TUN.test(String(ip)))
      .sort((a, b) => {
        const a192 = /^192\.168\./.test(String(a)) ? 0 : 1;
        const b192 = /^192\.168\./.test(String(b)) ? 0 : 1;
        return a192 - b192;
      });

    let httpPort = '';
    let httpsPort = '';
    try {
      httpPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTP);
      httpsPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTPS);
    } catch {}

    let tunnelDomain = '';
    try {
      const cfg = require('../../../../services/cloudflareTunnelService').loadConfig();
      if (cfg && cfg.enabled && cfg.hostname) tunnelDomain = cfg.hostname;
    } catch {}

    return res.status(200).json({
      success: true,
      hostname: os.hostname(),
      serverId: process.env.SERVER_ID || '',
      httpPort: httpPort ? String(httpPort) : '',
      httpsPort: httpsPort ? String(httpsPort) : '',
      lanIpv4List: lan,
      meshIpv4List: mesh,
      tunnelIpv4: mesh.length ? String(mesh[0]) : '',
      tunnelDomain,
    });
  }
}

module.exports = SystemController;
