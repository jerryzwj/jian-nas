import 'package:web/web.dart' as web;

/// 把浏览器顶层导航到局域网地址。
/// 顶层跳转（location 赋值）不受"HTTPS 页面不能加载 HTTP 子资源"的混合内容拦截，
/// 这是从公网域名页面切到内网直连唯一可靠的方式（飞牛那种做法本质也是整页跳）。
bool jumpToLanOrigin(String url) {
  try {
    web.window.location.href = url;
    return true;
  } catch (_) {
    return false;
  }
}

String? currentWebOrigin() {
  try {
    return web.window.location.origin;
  } catch (_) {
    return null;
  }
}
