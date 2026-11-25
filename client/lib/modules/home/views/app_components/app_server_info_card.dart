import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app_home_controller.dart';
import '../components/user_info_dialog.dart';
import 'app_wallpaper_picker_view.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../core/api/api_controller.dart';
import '../../../message/views/message_center_view.dart';
import '../../../../utils/device_utils.dart';

/// 顶部服务器信息条（精简版）
/// 原版是「大图标 + 三行文字 + 分割线 + 独立通知行」约 200px，
/// 这里压成单行：图标 · 主机名 / 连接通道 · 通知铃铛 · 换壁纸
class AppServerInfoCard extends StatelessWidget {
  final AppHomeController controller;
  final EdgeInsetsGeometry? margin;

  const AppServerInfoCard({super.key, required this.controller, this.margin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget _buildIcon() {
      return Obx(() {
        final server = controller.currentServer;
        final platform = server?.serverPlatform.toLowerCase() ?? 'linux';
        String iconPath = 'assets/home/server_linux.png';
        if (platform.contains('win')) {
          iconPath = 'assets/home/server_windows.png';
        }
        if (platform.contains('mac') || platform.contains('darwin')) {
          iconPath = 'assets/home/server_mac.png';
        }
        return Image.asset(
          iconPath,
          width: 26,
          height: 26,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.dns, size: 26, color: theme.colorScheme.onSurface),
        );
      });
    }

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Get.dialog(const UserInfoDialog()),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _buildIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Obx(() {
                  final server = controller.currentServer;
                  final user = CurrentUserController.instance.current;
                  final api = ApiController.instance;
                  api.connectChannelRevision.value;
                  final channelValue = api.connectChannelDisplayValue;
                  final unknown = 'home_unknown'.tr;
                  final name =
                      '${server?.getPlatformFriendlyName() ?? unknown} · ${server == null ? 'home_server_default'.tr : server.displayHostName}';
                  final userText = user?.username ?? unknown;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$name · $userText',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          if (DeviceUtils.isMobile) ...[
                            if (api.connectChannelRefreshing.value)
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.colorScheme.onSurface,
                                  ),
                                ),
                              )
                            else
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => api.refreshConnectChannel(),
                                child: Icon(
                                  Icons.refresh,
                                  size: 11,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              channelValue,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.75),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
              ),
              // 通知：未读时铃铛右上角加小红点，点击进消息中心
              Obx(() {
                final hasMsg = controller.serverMessage.value.isNotEmpty;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 34, minHeight: 34),
                      icon: Icon(
                        Icons.notifications_none,
                        size: 20,
                        color: theme.colorScheme.onSurface,
                      ),
                      tooltip: 'home_no_message'.tr,
                      onPressed: () => Get.to(
                        () => MessageCenterView(showAppBar: DeviceUtils.isMobile),
                      ),
                    ),
                    if (hasMsg)
                      Positioned(
                        right: 6,
                        top: 5,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              }),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Icon(
                  Icons.wallpaper_outlined,
                  color: theme.colorScheme.onSurface,
                  size: 18,
                ),
                tooltip: 'home_desktop_change_wallpaper'.tr,
                onPressed: () {
                  final size = MediaQuery.sizeOf(context);
                  Get.dialog(
                    Dialog(
                      insetPadding: EdgeInsets.zero,
                      backgroundColor: theme.scaffoldBackgroundColor,
                      child: Container(
                        width: size.width,
                        height: size.height,
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const AppWallpaperPickerView(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}
