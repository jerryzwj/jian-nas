import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

/// Cloudflare DDNS（A / AAAA）接口，不依赖 NasCab 会员
class DdnsApiService extends BaseApiService {
  static DdnsApiService get instance => Get.find<DdnsApiService>();

  Future<ApiResponse<Map<String, dynamic>>> getStatus() {
    return apiGet<Map<String, dynamic>>('/api/ddns/status');
  }

  Future<ApiResponse<Map<String, dynamic>>> save(Map<String, dynamic> body) {
    return apiPost<Map<String, dynamic>>(
      '/api/ddns/save',
      body: body,
      showLoading: true,
      loadingMsg: 'loading'.tr,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> disable() {
    return apiPost<Map<String, dynamic>>(
      '/api/ddns/disable',
      showLoading: true,
      loadingMsg: 'loading'.tr,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> runNow() {
    return apiPost<Map<String, dynamic>>(
      '/api/ddns/run',
      showLoading: true,
      loadingMsg: 'loading'.tr,
    );
  }
}
