import 'package:flutter/material.dart';

import 'parts/service_cf_tunnel_card.dart';

/// 服务模块 · 内网穿透（Cloudflare 隧道）
class ServiceTunnelView extends StatelessWidget {
  final bool showTitle;

  const ServiceTunnelView({super.key, this.showTitle = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showTitle) ...[
                Text(
                  '内网穿透',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '用 Cloudflare 隧道把本机服务暴露到公网，无需公网 IP、无需另装客户端',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              const ServiceCfTunnelCard(),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '使用说明',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. API Token 需具备 Zone·DNS·Edit 与 Account·Cloudflare Tunnel·Edit 权限。\n'
                        '2. 子域名与根域名拼成完整域名（如 nascab.wenjunzhang.eu.org），保存前会先查重。\n'
                        '3. 隧道随服务启动自动拉起，更换 HTTP 端口后会自动同步指向新端口。\n'
                        '4. 同一根域名下不同电脑用不同子域名即可并存，互不冲突。\n'
                        '5. 停用仅关闭进程，DNS 记录保留，重新启用可复用同一域名。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
