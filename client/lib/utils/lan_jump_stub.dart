/// 非 Web 平台：没有浏览器可跳，直接返回 false。
bool jumpToLanOrigin(String url) => false;

/// 非 Web 平台拿不到浏览器 origin。
String? currentWebOrigin() => null;
