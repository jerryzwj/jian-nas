import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../modules/base/components/custom_glass_card.dart';
import '../../../../../modules/settings/service/tunnel_api_service.dart';
import '../../../../../utils/toast_util.dart';

/// 服务模块「内网穿透」里的 Cloudflare 隧道卡片。
///
/// 凭证（API Token / Account / Zone）只存在于服务端配置文件，
/// 界面不展示、不允许修改，避免误操作或明文外泄；这里只负责
/// 「选一个子域名」+「看隧道是否正常跑着」。
class ServiceCfTunnelCard extends StatefulWidget {
  const ServiceCfTunnelCard({super.key});

  @override
  State<ServiceCfTunnelCard> createState() => _ServiceCfTunnelCardState();
}

class _ServiceCfTunnelCardState extends State<ServiceCfTunnelCard> {
  static const String _rootDomain = 'wenjunzhang.eu.org';

  final _subCtrl = TextEditingController();

  bool _loading = false;
  bool _enabled = false;
  bool _running = false;
  bool _hasToken = false;
  int _connections = 0;
  String _health = 'unknown';
  String _url = '';
  String _hostname = '';
  String _root = _rootDomain;
  String _tip = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final resp = await TunnelApiService.instance.getStatus();
      final data = resp.data;
      if (!resp.success || data == null || !mounted) return;
      final err = (data['lastError'] ?? '').toString();
      final health = (data['health'] ?? 'unknown').toString();
      final connections = (data['connections'] is num)
          ? (data['connections'] as num).toInt()
          : 0;
      final processRunning = data['processRunning'] == true;
      final running = data['running'] == true;
      final enabled = data['enabled'] == true;
      setState(() {
        _subCtrl.text = (data['subdomain'] ?? '').toString();
        _root = (data['fixedDomain'] ?? data['domain'] ?? _rootDomain).toString();
        _enabled = enabled;
        _running = running;
        _hasToken = data['hasToken'] == true;
        _health = health;
        _connections = connections;
        _url = (data['url'] ?? '').toString();
        _hostname = (data['hostname'] ?? '').toString();
        if (!enabled) {
          _tip = _url.isNotEmpty
              ? '已停用（DNS 记录保留：$_url）'
              : (!_hasToken ? '服务端还没配 Cloudflare API Token' : '');
        } else if (health == 'healthy') {
          _tip = '';
        } else if (health == 'degraded' && connections > 0) {
          _tip = '已连上 Cloudflare（部分边缘节点波动，不影响访问）';
        } else if (processRunning && (health == 'down' || health == 'inactive' || health == 'unknown')) {
          _tip = 'cloudflared 进程在跑，正在和 Cloudflare 边缘握手…（首连通常 10-30 秒）';
        } else if (!processRunning && !running) {
          _tip = 'cloudflared 未在运行，将自动重试${err.isEmpty ? '' : '：$err'}';
        } else {
          _tip = '';
        }
      });
    } catch (_) {}
  }

  Future<void> _checkSubdomain() async {
    final sub = _subCtrl.text.trim();
    if (sub.isEmpty) {
      ToastUtil.show('请先填写子域名');
      return;
    }
    setState(() => _loading = true);
    try {
      final resp = await TunnelApiService.instance.checkSubdomain(sub);
      final data = resp.data;
      if (!mounted) return;
      if (!resp.success || data == null) {
        setState(() => _tip = resp.message ?? '检测失败');
        return;
      }
      final available = data['available'] == true;
      final hostname = (data['hostname'] ?? '').toString();
      setState(() {
        _tip = available
            ? '$hostname 可用${data['owned'] == true ? '（当前隧道已占用）' : ''}'
            : (data['message'] ?? '$hostname 已被占用').toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enable() async {
    final sub = _subCtrl.text.trim();
    if (sub.isEmpty) {
      ToastUtil.show('请填写子域名');
      return;
    }
    setState(() => _loading = true);
    try {
      final resp = await TunnelApiService.instance.enable(<String, dynamic>{
        'subdomain': sub,
      });
      if (!mounted) return;
      if (!resp.success) {
        setState(() => _tip = resp.message ?? '启用失败');
        ToastUtil.show(resp.message ?? '启用失败');
        return;
      }
      await _load();
      final u = (resp.data?['url'] ?? '').toString();
      ToastUtil.show(u.isEmpty ? '隧道已启用' : '隧道已启用：$u');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disable() async {
    setState(() => _loading = true);
    try {
      final resp = await TunnelApiService.instance.disable();
      if (!mounted) return;
      if (!resp.success) {
        ToastUtil.show(resp.message ?? '停用失败');
        return;
      }
      await _load();
      ToastUtil.show('隧道已停用');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 状态横幅：以 Cloudflare 侧真实连接状态为准，不再只看本地进程
  Widget _buildStatusBanner() {
    final theme = Theme.of(context);
    final ok = _enabled && _running;
    final Color color;
    final String text;
    if (ok) {
      color = const Color(0xFF2EA043);
      text = _health == 'degraded' ? '隧道可用（边缘部分波动）' : '隧道正常运行';
    } else if (_enabled) {
      color = const Color(0xFFD29922);
      text = '已启用，正在连接 Cloudflare';
    } else {
      color = theme.colorScheme.onSurfaceVariant;
      text = '隧道未启用';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (ok && _connections > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '$_connections 连接',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          if (_hostname.isNotEmpty && ok)
            Icon(
              Icons.open_in_new,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = _hasToken && !_loading;

    return CustomGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.cloud_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloudflare 隧道（内嵌 cloudflared）',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '无需另装客户端，随服务自动拉起；改名只影响子域名，DNS 会自动跟着变。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatusBanner(),
          if (_tip.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _tip,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _enabled && !_running
                    ? const Color(0xFFD29922)
                    : theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          if (_hostname.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              _url,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _subCtrl,
              enabled: canEdit,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '子域名',
                hintText: '如 nas',
                helperText: '完整域名：'
                    '${_subCtrl.text.trim().isEmpty ? '____' : _subCtrl.text.trim()}'
                    '.$_root',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _loading ? null : _checkSubdomain,
                child: const Text('检测占用'),
              ),
              FilledButton(
                onPressed: canEdit ? _enable : null,
                child: const Text('启用 / 保存'),
              ),
              OutlinedButton(
                onPressed: _loading ? null : _disable,
                child: const Text('停用'),
              ),
              if (_url.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final uri = Uri.tryParse(_url);
                    if (uri == null) return;
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                  child: const Text('打开公网地址'),
                ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}
