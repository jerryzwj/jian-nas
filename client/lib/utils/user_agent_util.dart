import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'cache_manager.dart';

class UserAgentUtil {
  static String? _cachedUserAgent;
  static Map<String, String>? _cachedPlatformInfo;

  /// HTTP 头只允许 ASCII 可打印字符。
  /// 应用显示名是「简·NAS」，若直接拿去拼 User-Agent，
  /// dart:io 会抛 Invalid HTTP header field value，所有请求都发不出去
  /// （表现就是"该服务器不是有效的 NasCab 服务器"）。这里固定用 ASCII 标识。
  static const String _productName = 'JianNAS';

  static String _asciiSafe(String input) {
    return input.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }

  /// 获取User-Agent字符串
  /// 格式: JianNAS/Version+Build (Platform; OS Version; Device Model)
  static Future<String> getUserAgent() async {
    if (_cachedUserAgent != null) {
      return _cachedUserAgent!;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      final buildNumber = packageInfo.buildNumber;

      final info = await _getPlatformInfo();
      final platformInfo = info['platform'] ?? 'Unknown';
      final osVersion = info['osVersion'] ?? 'Unknown';
      final deviceModel = info['deviceModel'] ?? 'Unknown';

      // 构建User-Agent
      // JianNAS/1.2.11+31 (Android; 12; Google Pixel 6)
      final raw =
          '$_productName/$version+$buildNumber ($platformInfo; $osVersion; $deviceModel)';
      final clean = _asciiSafe(raw).trim();
      _cachedUserAgent = clean.isNotEmpty ? clean : '$_productName/$version+$buildNumber';
    } catch (e) {
      print('Error generating User-Agent: $e');
      _cachedUserAgent = '${_productName}Client/Unknown';
    }

    return _cachedUserAgent!;
  }

  static Future<Map<String, String>> _getPlatformInfo() async {
    if (_cachedPlatformInfo != null) {
      return _cachedPlatformInfo!;
    }

    String platformInfo = 'Unknown';
    String osVersion = 'Unknown';
    String deviceModel = 'Unknown';

    final deviceInfo = DeviceInfoPlugin();

    if (kIsWeb) {
      final webBrowserInfo = await deviceInfo.webBrowserInfo;
      platformInfo = 'Web';
      osVersion = webBrowserInfo.userAgent ?? '';
      deviceModel = webBrowserInfo.browserName.toString();
    } else {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        platformInfo = 'Android';
        osVersion = androidInfo.version.release;
        deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        platformInfo = 'iOS';
        osVersion = iosInfo.systemVersion;
        deviceModel = iosInfo.name;
      } else if (Platform.isMacOS) {
        final macOsInfo = await deviceInfo.macOsInfo;
        platformInfo = 'macOS';
        osVersion =
            '${macOsInfo.majorVersion}.${macOsInfo.minorVersion}.${macOsInfo.patchVersion}';
        deviceModel = macOsInfo.model;
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        platformInfo = 'Windows';
        osVersion = '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}';
        deviceModel = 'PC';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        platformInfo = 'Linux';
        osVersion = linuxInfo.versionId ?? '';
        deviceModel = linuxInfo.name;
      }
    }

    _cachedPlatformInfo = {
      'platform': platformInfo,
      'osVersion': osVersion,
      'deviceModel': deviceModel,
    };
    return _cachedPlatformInfo!;
  }

  static Future<String> _getOrCreateStorageId() async {
    final cache = CacheManager();
    final existing = cache.getString(CacheKeys.deviceFingerprintSeed);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final id = const Uuid().v4();
    await cache.setString(CacheKeys.deviceFingerprintSeed, id);
    return id;
  }

  static Future<String> getOrCreatePersistentDeviceId() async {
    return await _getOrCreateStorageId();
  }

  static String getOrCreateVideoPlayerDeviceIdSync() {
    final cache = CacheManager();
    final existing = cache.getString(CacheKeys.videoPlayerDeviceId);
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();
    final id = const Uuid().v4();
    cache.setString(CacheKeys.videoPlayerDeviceId, id);
    return id;
  }

  static Future<Map<String, dynamic>> getDeviceFingerprintPayload() async {
    final userAgent = await getUserAgent();
    final info = await _getPlatformInfo();
    final locale = PlatformDispatcher.instance.locale.toLanguageTag();
    final now = DateTime.now();
    final storageId = await _getOrCreateStorageId();
    final deviceName = '${info['platform'] ?? ''} ${info['deviceModel'] ?? ''}'
        .trim();

    return {
      'user_agent': userAgent,
      'platform': info['platform'],
      'os_version': info['osVersion'],
      'device_model': info['deviceModel'],
      'device_name': deviceName,
      'language': locale,
      'timezone_offset': now.timeZoneOffset.inMinutes,
      'timezone_name': now.timeZoneName,
      'storage_id': storageId,
      'storage_type': 'shared_preferences',
    };
  }
}
