// 平台无关的「跳到局域网地址」入口。
// Web 上直接把浏览器顶层导航到 http://内网IP:端口（顶层跳转不受混合内容拦截）；
// 非 Web（App）返回 false，交给 ApiController 的自动切换通道处理。
export 'lan_jump_stub.dart' if (dart.library.html) 'lan_jump_web.dart';
