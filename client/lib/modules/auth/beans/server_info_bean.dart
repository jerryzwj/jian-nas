/// 服务器信息数据模型（包含登录信息）
class ServerInfoBean {
  String serverId;
  String serverUrl;
  String? userInputUrl;
  String? lanIpv4;
  /// 服务端回报的全部局域网 IPv4（按服务端排序，真实内网在前，P2P 隧道网段在后）
  List<String> lanIpv4List;
  /// 服务端出口公网 IPv4（直连探测用）
  String? publicIpv4;
  /// OpenP2P TUN 网段地址（如 10.10.10.2），作为内建 P2P 之前的软隧道一层
  String? tunnelIpv4;
  /// 服务端内嵌 Cloudflare 隧道的公网域名（外网引导入口）
  String? tunnelDomain;
  /// 服务端全局 IPv6（直连探测用）
  String? publicIpv6;
  String? lanHttpPort;
  String? lanHttpsPort;
  String serverName;
  String serverHost;
  String serverPortHttp;
  String serverPortHttps;
  String serverHostName;

  /// 服务端配置的自定义主机名（登录接口返回，优先用于展示）
  String? customHostname;
  String serverPlatform;
  bool isAutoScanned;
  bool isLocalServer;
  bool isP2p;
  String? pairCode;
  String? username;
  String? password;
  String? accessToken;
  String? refreshToken;
  DateTime? lastLoginTime;
  bool needInputPwdEveryTime; // 是否每次登录都需要输入密码

  /// 服务器级「远程连接偏好」：是否 P2P 中继优先（false=P2P 直连优先，默认）
  bool p2pRelayPreferred;

  /// 是否在应用启动时自动登录（所有服务器全局互斥，同一时间仅一个可为 true）
  bool autoLoginOnStartup;
  ServerInfoBean({
    required this.serverId,
    required this.serverUrl,
    this.userInputUrl,
    this.lanIpv4,
    this.lanIpv4List = const [],
    this.publicIpv4,
    this.tunnelIpv4,
    this.tunnelDomain,
    this.publicIpv6,
    this.lanHttpPort,
    this.lanHttpsPort,
    required this.serverName,
    required this.serverHost,
    required this.serverPortHttp,
    required this.serverPortHttps,
    required this.serverHostName,
    this.customHostname,
    required this.serverPlatform,
    required this.isAutoScanned,
    this.isLocalServer = false,
    this.isP2p = false,
    this.pairCode,
    this.username,
    this.password,
    this.accessToken,
    this.refreshToken,
    this.lastLoginTime,
    this.needInputPwdEveryTime = false,
    this.p2pRelayPreferred = false,
    this.autoLoginOnStartup = false,
  });

  bool get hasPairCode => (pairCode ?? '').trim().isNotEmpty;
  bool get hasDirectUrl => serverUrl.trim().isNotEmpty;

  /// 列表等 UI 展示用主机名：自定义优先，否则为系统 hostname
  String get displayHostName {
    final c = (customHostname ?? '').trim();
    if (c.isNotEmpty) return c;
    return serverHostName;
  }

  String getPlatformFriendlyName() {
    switch (serverPlatform) {
      case 'linux':
        return 'Linux';
      case 'win32':
        return 'Windows';
      case 'darwin':
        return 'Mac OS';
      default:
        return serverPlatform;
    }
  }

  /// 转换为JSON格式
  Map<String, dynamic> toJson() {
    return {
      'serverId': serverId,
      'serverUrl': serverUrl,
      'userInputUrl': userInputUrl,
      'lanIpv4': lanIpv4,
      'lanIpv4List': lanIpv4List,
      'publicIpv4': publicIpv4,
      'tunnelIpv4': tunnelIpv4,
      'tunnelDomain': tunnelDomain,
      'publicIpv6': publicIpv6,
      'lanHttpPort': lanHttpPort,
      'lanHttpsPort': lanHttpsPort,
      'serverName': serverName,
      'serverHost': serverHost,
      'serverPortHttp': serverPortHttp,
      'serverPortHttps': serverPortHttps,
      'serverHostName': serverHostName,
      'customHostname': customHostname,
      'serverPlatform': serverPlatform,
      'isAutoScanned': isAutoScanned,
      'isLocalServer': isLocalServer,
      'isP2p': isP2p,
      'pairCode': pairCode,
      'username': username,
      'password': password,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'lastLoginTime': lastLoginTime?.toIso8601String(),
      'needInputPwdEveryTime': needInputPwdEveryTime,
      'p2pRelayPreferred': p2pRelayPreferred,
      'autoLoginOnStartup': autoLoginOnStartup,
    };
  }

  /// 从JSON格式创建ServerInfoBean
  factory ServerInfoBean.fromJson(Map<String, dynamic> json) {
    final rawPair = json['pairCode']?.toString();
    final rawUrl = (json['serverUrl'] ?? '').toString();
    final computedIsP2p =
        rawUrl.trim().isEmpty && (rawPair ?? '').trim().isNotEmpty;
    return ServerInfoBean(
      serverId: json['serverId'] ?? '',
      serverUrl: json['serverUrl'] ?? '',
      userInputUrl: json['userInputUrl']?.toString(),
      lanIpv4: json['lanIpv4']?.toString(),
      lanIpv4List: () {
        final raw = json['lanIpv4List'];
        if (raw is List) {
          return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        }
        final single = json['lanIpv4']?.toString().trim();
        return (single != null && single.isNotEmpty) ? <String>[single] : const <String>[];
      }(),
      publicIpv4: () {
        final raw = json['publicIpv4']?.toString().trim();
        return (raw != null && raw.isNotEmpty) ? raw : null;
      }(),
      tunnelIpv4: () {
        final raw = json['tunnelIpv4']?.toString().trim();
        return (raw != null && raw.isNotEmpty) ? raw : null;
      }(),
      tunnelDomain: () {
        final raw = json['tunnelDomain']?.toString().trim();
        return (raw != null && raw.isNotEmpty) ? raw : null;
      }(),
      publicIpv6: () {
        final raw = json['publicIpv6']?.toString().trim();
        return (raw != null && raw.isNotEmpty) ? raw : null;
      }(),
      lanHttpPort: json['lanHttpPort']?.toString(),
      lanHttpsPort: json['lanHttpsPort']?.toString(),
      serverName: json['serverName'] ?? '',
      serverHost: json['serverHost'] ?? '',
      serverPortHttp: json['serverPortHttp'] ?? '',
      serverPortHttps: json['serverPortHttps'] ?? '',
      serverHostName: json['serverHostName'] ?? '',
      customHostname: () {
        final raw = json['customHostname']?.toString().trim();
        if (raw == null || raw.isEmpty) return null;
        return raw;
      }(),
      serverPlatform: json['serverPlatform'] ?? 'unknown',
      isAutoScanned: json['isAutoScanned'] ?? false,
      isLocalServer: json['isLocalServer'] ?? false,
      isP2p: json['isP2p'] ?? computedIsP2p,
      pairCode: rawPair,
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      accessToken: json['accessToken'],
      refreshToken: json['refreshToken'],
      lastLoginTime: json['lastLoginTime'] != null
          ? DateTime.parse(json['lastLoginTime'])
          : null,
      needInputPwdEveryTime: json['needInputPwdEveryTime'] == true,
      p2pRelayPreferred: json['p2pRelayPreferred'] == true,
      autoLoginOnStartup: json['autoLoginOnStartup'] == true,
    );
  }
  @override
  String toString() {
    return 'ServerInfoBean{serverId: $serverId, serverUrl: $serverUrl, userInputUrl: $userInputUrl, lanIpv4: $lanIpv4, lanHttpPort: $lanHttpPort, lanHttpsPort: $lanHttpsPort, serverName: $serverName, serverHost: $serverHost, serverPortHttp: $serverPortHttp, serverPortHttps: $serverPortHttps, serverHostName: $serverHostName, serverPlatform: $serverPlatform, isAutoScanned: $isAutoScanned, isLocalServer: $isLocalServer, isP2p: $isP2p, pairCode: $pairCode, username: $username, password: $password, accessToken: $accessToken, refreshToken: $refreshToken, lastLoginTime: $lastLoginTime, needInputPwdEveryTime: $needInputPwdEveryTime}';
  }
}
