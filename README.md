# 简·NAS 源码（私有）

去会员化改造后的 NasCab 服务端（Electron）与配套安卓客户端（Flutter）源码。**私有仓库**，仅仓库所有者可见；对外开放的只有 `jian-apps` 里的 Release 二进制。

## 目录

```
server/    服务端改造源码（Electron）
  src/         业务代码：api / config / db / ipc / services / ui / utils / workers
  language/    13 种语言的文案
  package.json 依赖与入口（main: src/main_nascab_os.js）
client/    安卓客户端源码（Flutter）
  lib/         Dart 源码
  android/     原生壳、签名（nascab-custom.jks，alias nascab）
  packages/    本地 path 依赖
  web/         Web 端入口
tools/     图标生成脚本与素材（gen_icons.py / preview_icon.py / custom_index.html / 图标源图）
```

## 服务端改造点（相对官方 1.2.5）

| 位置 | 改动 |
|---|---|
| `server/src/services/cloudflareAuth.js` | 凭证收敛：`cfFetch` / `resolveZone` / `resolveZoneByHostname` / `normalizeHostname` |
| `server/src/services/cloudflareDdnsService.js` | DDNS 彻底独立：用户自备 Token + 完整域名，三层反查 Zone，支持 proxied 小云朵 |
| `server/src/services/cloudflareTunnelService.js` | `refreshHealth()` 读 Cloudflare 侧 `status` + `connections`，15s 缓存；stderr 降级为 lastLog |
| `server/src/api/modules/others/tunnel/tunnelController.js` | `getStatus` 改 await 异步健康检查 |
| `server/src/ipc/uiIpcHandlers.js` | `tunnel:getStatus` 同步异步化 |
| `server/src/ui/index.html`、`server/src/ui/tunnelSettings.js` | 去掉凭证输入，只留子域名 / 状态；标题「简·NAS 服务端」 |

去会员化：会员校验相关分支移除，账号 / 相册 / 影音 / 文件 / 快速分享全部本地可用。

## 客户端改造点（1.2.14+34）

| 位置 | 改动 |
|---|---|
| `lib/utils/user_agent_util.dart` | UA 产品名固定 ASCII `JianNAS` + 非 ASCII 净化，修中文应用名导致 HTTP 头非法 |
| `lib/core/api/api_parts/api_controller_failover.dart` | `_failoverScheme` 改由端口决定协议（6789→http / 6799→https），修局域网切换 TLS 失败 |
| `lib/utils/lan_jump.dart`（+ `_stub` / `_web`） | Web 端整页跳转局域网地址（浏览器禁止 https 页静默请求 http 内网） |
| `lib/modules/auth/views/server_list/server_item_view.dart` | 服务器卡新增「局域网直连」提示行 |
| `lib/modules/service/service_main/view/service_ddns_view.dart` | DDNS 页重写：完整域名 + 必填 Token + proxied + 状态卡 |
| `lib/modules/service/service_main/view/parts/service_cf_tunnel_card.dart` | 隧道卡改用 health / connections 判定，不再误报异常 |
| `lib/modules/settings/views/settings_view.dart` | 隧道状态文案与卡片瘦身 |
| `lib/main.dart`、`lib/utils/app_window_title.dart`、`lib/desktop/desktop_tray_io.dart`、13 个 `lib/core/languages/*.dart`、`android/AndroidManifest.xml` | 品牌化「简·NAS」+ 图标 |

## 构建

服务端（Windows x64）：

```powershell
# 依赖安装（electron 与原生模块）
cd server
npm install

# 绿色版：用官方 Electron 壳 + 本目录 app 源码目录直接组装
# 注意删除 resources\app-update.yml，否则会被官方自动更新覆盖
```

客户端（Android arm64）：

```powershell
. D:\toolchain\env.ps1
cd client
flutter build apk --release --target-platform android-arm64
```

Flutter 3.38.10 / JDK17 / SDK 在 `D:\Android\Sdk`，签名 `android/nascab-custom.jks`（alias `nascab`）。

## 发布物（公开）

- Release：https://github.com/jerryzwj/jian-apps/releases/tag/nas-v1.2.5
- 发布站：https://apps.wenjun.eu.org

二进制里有官方 NasCab 的 Electron 运行时与第三方库，源码仅做本地化改造，不再分发原始 asar。
