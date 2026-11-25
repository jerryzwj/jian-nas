import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

/// Cloudflare 隧道（服务端内嵌 cloudflared）设置接口
class TunnelApiService extends BaseApiService {
  static TunnelApiService get instance => Get.find<TunnelApiService>();

  Future<ApiResponse<Map<String, dynamic>>> getStatus() {
    return apiGet<Map<String, dynamic>>('/api/tunnel/status');
  }

  Future<ApiResponse<Map<String, dynamic>>> checkSubdomain(String subdomain) {
    return apiPost<Map<String, dynamic>>(
      '/api/tunnel/checkSubdomain',
      body: {'subdomain': subdomain},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> enable(Map<String, dynamic> body) {
    return apiPost<Map<String, dynamic>>(
      '/api/tunnel/enable',
      body: body,
      showLoading: true,
      loadingMsg: 'loading'.tr,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> disable() {
    return apiPost<Map<String, dynamic>>(
      '/api/tunnel/disable',
      showLoading: true,
      loadingMsg: 'loading'.tr,
    );
  }
}
