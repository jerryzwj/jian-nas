import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../../utils/lan_jump.dart';
import '../../service/auth_api_service.dart';
import '../../../../core/api/api_controller.dart';
import '../../beans/server_info_bean.dart';
import '../../service/response/login_response.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../service/server_storage_service.dart';
import 'package:NasCabOS/core/routes/app_routes.dart';
import '../../../home/views/components/session_wallpaper_background.dart';
import 'login_twofa_dialog.dart';
import '../../../../core/config/nascab_endpoints.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/utils/same_machine_checker_stub.dart'
    if (dart.library.html) '../../../../core/utils/same_machine_checker_web.dart';

class LoginController extends GetxController {
  final username = ''.obs;
  final password = ''.obs;
  final isLoading = false.obs;
  final welcomeTitle = ''.obs;
  final isCompanySite = false.obs;
  final showPairCodeInput = false.obs;
  final isPairCodeConnecting = false.obs;
  final connectedHostName = ''.obs;
  final formKey = GlobalKey<FormState>();

  /// 登录页"局域网直连"提示：从公网/中继域名进来时，若能直连内网或 P2P 网段，
  /// 给出一个可点的一键切换地址（仅 Web 端展示，App 由 failover 自动处理）
  final lanDirectUrl = ''.obs;
  final lanDirectLabel = ''.obs;

  bool _loginInProgress = false;

  bool _isCompanySiteHost(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    if (h == 'nas.cab') return true;
    return h.endsWith('.nas.cab');
  }

  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
  late final TextEditingController pairCodeController;

  @override
  void onInit() {
    super.onInit();
    usernameController = TextEditingController();
    passwordController = TextEditingController();
    pairCodeController = TextEditingController();

    usernameController.addListener(() {
      username.value = usernameController.text;
    });
    passwordController.addListener(() {
      password.value = passwordController.text;
    });

    final host = Uri.base.host;
    isCompanySite.value = kIsWeb && _isCompanySiteHost(host);
    showPairCodeInput.value = isCompanySite.value;

    // 公司站点（如 nas.cab）不请求 loginConfig 和 isNasCabServer，避免 404
    if (!isCompanySite.value) {
      _loadLoginConfig();
      _checkServerInitStatusOnInit();
      _loadLanDirect();
    }
  }

  /// 询问服务端有哪些可直连地址，优先 OpenP2P 虚拟网段（10.10.10.x），
  /// 其次真实局域网；当前已在某个内网地址上访问时不提示。
  Future<void> _loadLanDirect() async {
    if (!kIsWeb) return;
    try {
      final origin = Uri.base.origin;
      final resp = await http
          .get(Uri.parse('$origin/api/system/lan-addresses'))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      if (data is! Map) return;

      final rawPort = (data['httpPort'] ?? '').toString().trim();
      final port = rawPort.isNotEmpty ? rawPort : '6789';
      List<String> toList(dynamic v) =>
          (v is List) ? v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() : <String>[];
      final mesh = toList(data['meshIpv4List']);
      final lan = toList(data['lanIpv4List']);
      final currentHost = Uri.base.host;

      for (final ip in [...mesh, ...lan]) {
        if (ip == currentHost) continue;
        lanDirectUrl.value = 'http://$ip:$port';
        lanDirectLabel.value = mesh.contains(ip) ? '$ip（P2P 直连）' : '$ip（局域网）';
        return;
      }
    } catch (_) {
      // 忽略：拿不到就不提示
    }
  }

  void jumpToLan() {
    final url = lanDirectUrl.value.trim();
    if (url.isEmpty) return;
    jumpToLanOrigin(url);
  }

  Future<void> _loadLoginConfig() async {
    if(!kIsWeb){
      return;
    }
    try {
      final resp = await AuthApiService.instance.getLoginConfig();
      if (!resp.success) return;
      final data = resp.data ?? const {};
      final raw = data['welcomeText'];
      final text = raw is String ? raw.trim() : '';
      if (text.isNotEmpty) {
        welcomeTitle.value = text;
        update();
      }
    } catch (_) {}
  }

  Future<void> handleLogin() async {
    if (isLoading.value) return;
    if (!formKey.currentState!.validate()) {
      return;
    }
    isLoading.value = true;
    try {
      //设置基础请求url为地址栏的url
      final baseUrl = ApiController.instance.baseUrl;
      ApiController.instance.setBaseUrl(baseUrl);
      print("baseUrl:$baseUrl");
      final status = await AuthApiService.instance.checkServerStatus(true);
      if (!status.isNasCabServer) {
        _showErrorDialog('server_connect_fail'.tr);
        return;
      }
      final hasSuperAdmin = status.serverData?['hasSuperAdmin'] ?? false;
      if (!hasSuperAdmin) {
        final serverItemForInit = ServerInfoBean(
          serverId: status.serverData?['serverId'] ?? '',
          serverUrl: baseUrl,
          serverName: 'NasCabServer',
          serverHost: Uri.parse(baseUrl).host,
          serverPortHttp: status.serverData?['httpPort']?.toString() ?? '',
          serverPortHttps: status.serverData?['httpsPort']?.toString() ?? '',
          serverHostName: status.serverData?['hostname'] ?? 'unknown',
          serverPlatform: status.serverData?['platform'] ?? 'unknown',
          isAutoScanned: false,
          isLocalServer: false,
        );
        DialogUtil.showConfirmDialog(
          title: 'server_init'.tr,
          content: 'server_init_content'.tr,
          onConfirm: () => _goToAdminCreate(serverItemForInit),
          confirmText: 'ok'.tr,
          cancelText: '',
          barrierDismissible: false,
        );
        return;
      }

      final serverItem = ServerInfoBean(
        serverId:
            status.serverData?['serverId'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        serverUrl: baseUrl,
        serverName: 'NasCabServer',
        serverHost: Uri.parse(baseUrl).host,
        serverPortHttp: '',
        serverPortHttps: '',
        serverHostName: status.serverData?['hostname'] ?? 'unknow',
        serverPlatform: status.serverData?['platform'] ?? 'unknow',
        isAutoScanned: false,
        isLocalServer: false,
        username: username.value,
        password: password.value,
      );
      await loginToServer(serverItem);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> connectP2pByPairCode() async {
    if (isPairCodeConnecting.value) return;
    final code = pairCodeController.text.trim();
    final validationError = ApiController.validatePairCodeText(code);
    if (validationError != null) {
      _showErrorDialog(validationError);
      return;
    }

    isPairCodeConnecting.value = true;
    DialogUtil.showLoading(message: 'server_connecting'.tr);
    try {
      final status = await ApiController.instance
          .connectP2pByPairCodeAndCheckServerStatus(
            code,
            timeout: const Duration(seconds: 5),
          );
      if (!status.success || !status.isNasCabServer) {
        _showErrorDialog('server_connect_fail'.tr);
        return;
      }
      final hostname = (status.serverData?['hostname']?.toString() ?? '')
          .trim();
      connectedHostName.value = hostname.isEmpty ? 'unknown' : hostname;
      update();
    } catch (e) {
      _showErrorDialog(ApiController.formatP2pConnectError(e));
    } finally {
      DialogUtil.dismissLoading(force: true);
      isPairCodeConnecting.value = false;
    }
  }

  void _goToAdminCreate(ServerInfoBean serverItem) {
    print("_goToAdminCreate:_goToAdminCreate");
    Get.toNamed(AppRoutes.adminCreate, arguments: serverItem);
  }

  Future<void> _checkServerInitStatusOnInit() async {
    final baseUrl = ApiController.instance.baseUrl;
    ApiController.instance.setBaseUrl(baseUrl);
    final status = await AuthApiService.instance.checkServerStatus(false);
    if (!status.success || !status.isNasCabServer) {
      return;
    }
    final hasSuperAdmin = status.serverData?['hasSuperAdmin'] ?? false;
    if (!hasSuperAdmin) {
      final serverItemForInit = ServerInfoBean(
        serverId: status.serverData?['serverId'] ?? '',
        serverUrl: baseUrl,
        serverName: 'NasCabServer',
        serverHost: Uri.parse(baseUrl).host,
        serverPortHttp: status.serverData?['httpPort']?.toString() ?? '',
        serverPortHttps: status.serverData?['httpsPort']?.toString() ?? '',
        serverHostName: status.serverData?['hostname'] ?? 'unknown',
        serverPlatform: status.serverData?['platform'] ?? 'unknown',
        isAutoScanned: false,
        isLocalServer: false,
      );
      DialogUtil.showConfirmDialog(
        title: 'server_init'.tr,
        content: 'server_init_content'.tr,
        onConfirm: () => _goToAdminCreate(serverItemForInit),
        confirmText: 'ok'.tr,
        cancelText: '',
        barrierDismissible: false,
      );
    }
  }

  /// 登录到服务器
  Future<void> loginToServer(ServerInfoBean serverItem) async {
    if (_loginInProgress) return;
    _loginInProgress = true;
    final ownsLoadingState = !isLoading.value;
    if (ownsLoadingState) isLoading.value = true;
    // 显示loading
    DialogUtil.showLoadingDialog(
      message: 'auth_login_loading'.tr,
      barrierDismissible: false,
    );
    try {
      // 设置API基础URL
      ApiController.instance.setBaseUrl(serverItem.serverUrl);
      final loginResult = await AuthApiService.instance.loginToServer(
        serverItem,
      );
      // 关闭loading对话框
      Get.back();
      if (loginResult.success) {
        if (loginResult.twoFactorRequired == true &&
            (loginResult.tempToken ?? '').isNotEmpty) {
          if (ownsLoadingState) isLoading.value = false;
          _showTwofaDialog(serverItem, loginResult.tempToken!);
          return;
        }
        // 登录成功，更新服务器信息
          await _handleLoginSuccess(serverItem, loginResult);
      } else {
        if (loginResult.code == 999) {
          // 密码错误，弹出带输入框的密码输入框
          _showPasswordInputDialog(serverItem);
        } else {
          _showErrorDialog('${loginResult.message}');
        }
      }
    } catch (e) {
      // 关闭loading对话框
      Get.back();
      _showErrorDialog('${'auth_login_failure'.tr}: $e');
    } finally {
      _loginInProgress = false;
      if (ownsLoadingState) isLoading.value = false;
    }
  }

  Future<void> _handleLoginSuccess(
    ServerInfoBean serverItem,
    LoginResponse loginResult,
  ) async {
    serverItem.accessToken = loginResult.accessToken;
    serverItem.serverId = loginResult.serverId ?? 'unknown';
    serverItem.serverPlatform = loginResult.platform ?? 'unknown';
    serverItem.serverHostName = loginResult.hostname ?? 'unknown';
    final ch = loginResult.customHostname?.trim();
    serverItem.customHostname =
        (ch == null || ch.isEmpty) ? null : ch;
    serverItem.refreshToken = loginResult.refreshToken;
    serverItem.serverPortHttp = loginResult.httpPort?.toString() ?? '';
    serverItem.serverPortHttps = loginResult.httpsPort?.toString() ?? '';
    final pair = (loginResult.pairCode ?? '').trim();
    if (pair.isNotEmpty) {
      serverItem.pairCode = pair;
    }
    final lan = (loginResult.lanIpv4 ?? '').trim();
    if (lan.isNotEmpty) {
      serverItem.lanIpv4 = lan;
      serverItem.lanHttpPort = loginResult.httpPort?.toString() ?? '';
      serverItem.lanHttpsPort = loginResult.httpsPort?.toString() ?? '';
    }
    serverItem.isP2p =
        serverItem.serverUrl.trim().isEmpty &&
        (serverItem.pairCode ?? '').trim().isNotEmpty;
    await ServerStorageService.addServer(serverItem);
    ApiController.instance.setAuthInfo(
      serverId: serverItem.serverId,
      accessToken: loginResult.accessToken!,
      refreshToken: loginResult.refreshToken!,
      expiresIn: loginResult.expiresIn!,
      shellSupported: loginResult.shellSupported ?? false,
      httpsPort: loginResult.httpsPort?.toString(),
      serverPlatform: loginResult.platform ?? serverItem.serverPlatform,
      serverVersion: loginResult.serverVersion,
      serverHostname: loginResult.hostname ?? serverItem.serverHostName,
      customHostname: serverItem.customHostname,
    );

    // 异步检测客户端与服务器是否在同一台机器
    unawaited(_checkAndSetSameMachine(
      serverItem.serverId,
      serverItem.serverHostName,
      serverItem.lanIpv4,
    ));

    print('login_controller 服务器登录成功: ${loginResult.toString()}');

    // 通知浏览器表单提交成功，触发 Chrome 的密码保存提示
    TextInput.finishAutofillContext();

    await SessionWallpaperBackground.preloadForCurrentSession();
    Get.offAllNamed(AppRoutes.home);
  }

  void _showTwofaDialog(ServerInfoBean serverItem, String tempToken) {
    if (Get.overlayContext == null) return;
    showDialog(
      context: Get.overlayContext!,
      barrierDismissible: false,
      builder: (_) => TwofaCodeDialog(
        onVerify: (code) {
          Get.back();
          _submitTwoFactor(serverItem, tempToken, code);
        },
      ),
    );
  }

  Future<void> _submitTwoFactor(
    ServerInfoBean serverItem,
    String tempToken,
    String code,
  ) async {
    DialogUtil.showLoadingDialog(
      message: 'auth_login_loading'.tr,
      barrierDismissible: false,
    );
    try {
      final verifyResult = await AuthApiService.instance.verifyTwoFactorLogin(
        tempToken: tempToken,
        code: code,
      );
      Get.back();
      if (!verifyResult.success) {
        _showErrorDialog(verifyResult.message ?? 'auth_login_failure'.tr);
        return;
      }
      await _handleLoginSuccess(serverItem, verifyResult);
    } catch (e) {
      Get.back();
      _showErrorDialog('${'auth_login_failure'.tr}: $e');
    }
  }

  /// 显示密码输入对话框
  void _showPasswordInputDialog(ServerInfoBean serverItem) {
    DialogUtil.showPasswordInputDialog(
      title: 'auth_password_error'.tr,
      message: 'auth_password_error_message'.tr,
      hintText: 'auth_password_hint'.tr,
      onConfirm: (String newPassword) {
        // 更新服务器对象的密码
        serverItem.password = newPassword;
        // 重新调用登录函数
        loginToServer(serverItem);
      },
    );
  }

  static final Uri _forgotPasswordHelpUri = Uri.parse(
    '${NasCabEndpoints.websiteBaseUrl}/others/helpFindPwd.html',
  );

  /// 忘记密码：打开官网帮助页，不再进入应用内找回流程
  Future<void> goToRecover() async {
    try {
      if (await canLaunchUrl(_forgotPasswordHelpUri)) {
        await launchUrl(
          _forgotPasswordHelpUri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        ToastUtil.show('operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('network_failure'.tr);
    }
  }

  void _showErrorDialog(String message) {
    if (Get.overlayContext == null) return;
    DialogUtil.showErrorDialog(
      message: message,
      title: 'auth_login_failure'.tr,
    );
  }

  @override
  void onClose() {
    usernameController.dispose();
    passwordController.dispose();
    pairCodeController.dispose();
    super.onClose();
  }

  /// 探测 127.0.0.1:6789 的本机服务 serverId，失败返回 null
  Future<String?> _probeLocalhostServerId() async {
    try {
      // 临时切到 localhost 仅改内存态、不触发 connectChannelRevision，
      // 避免壁纸等 URL 驱动组件在探测窗口内用临时地址重建请求；
      // whenComplete 保证探测异常时也恢复，且恢复自带一次 revision 通知
      final restoreBaseUrl = ApiController.instance
          .overrideBaseUrlTemporarily(AppConfig.localhostBaseUrl);
      final serverStatus = await AuthApiService.instance
          .checkServerStatus(
            false,
            timeout: const Duration(seconds: 2),
            maxRetries: 0,
          )
          .whenComplete(restoreBaseUrl);
      if (serverStatus.isNasCabServer) {
        final id = (serverStatus.serverData?['serverId'] ?? '').toString();
        print('[SameMachine/Login] 127.0.0.1 探测成功, serverId=$id');
        return id;
      }
      print('[SameMachine/Login] 127.0.0.1 探测失败: isNasCabServer=false');
    } catch (e) {
      print('[SameMachine/Login] 127.0.0.1 探测异常: $e');
    }
    return null;
  }

  /// 检测客户端与已登录的服务器是否在同一台机器上运行
  Future<void> _checkAndSetSameMachine(
    String serverId,
    String hostname,
    String? lanIpv4,
  ) async {
    print('[SameMachine/Login] === 开始同机检测 ===');
    print(
      '[SameMachine/Login] 入参 serverId=$serverId, hostname=$hostname, lanIpv4=$lanIpv4',
    );

    // 1. 尝试 127.0.0.1 探测
    final localId = await _probeLocalhostServerId();
    if (localId != null && localId.isNotEmpty) {
      final same = localId == serverId;
      print(
        '[SameMachine/Login] serverId 比对: localId=$localId, loggedInId=$serverId, same=$same',
      );
      ApiController.instance.setSameMachine(same);
      return;
    }

    // 2. localhost 不可达，Web 端对比浏览器 hostname
    if (kIsWeb) {
      final browserHostname = getLocalBrowserHostname();
      print('[SameMachine/Login] Web fallback: browserHostname=$browserHostname');
      if (browserHostname.isNotEmpty) {
        final same =
            browserHostname == hostname ||
            browserHostname == (lanIpv4 ?? '') ||
            browserHostname == 'localhost' ||
            browserHostname == '127.0.0.1';
        print(
          '[SameMachine/Login] Web hostname 比对: browser=$browserHostname, serverHostname=$hostname, lanIpv4=${lanIpv4 ?? 'null'}, same=$same',
        );
        ApiController.instance.setSameMachine(same);
        return;
      }
    }

    // 3. 无法判定
    print('[SameMachine/Login] 无法判定，设为 false');
    ApiController.instance.setSameMachine(false);
  }
}
