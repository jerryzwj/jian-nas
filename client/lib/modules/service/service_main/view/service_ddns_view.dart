import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../base/components/custom_glass_card.dart';
import '../../../settings/service/ddns_api_service.dart';
import '../../../../utils/toast_util.dart';
import '../controller/service_main_controller.dart';

/// 服务模块 · DDNS（独立功能，与内网穿透完全无关）
///
/// 用户自备两样东西：
///  1. 自己的 Cloudflare API Token（Zone:Read + DNS:Edit）
///  2. 自己要映射的域名（完整域名，例如 home.example.com）
/// Account ID / Zone ID 由 Token 自动反查，这里不填、也不回显任何凭证。
class ServiceDdnsView extends StatefulWidget {
  final ServiceMainController controller;
  final bool showTitle;

  const ServiceDdnsView({
    super.key,
    required this.controller,
    this.showTitle = true,
  });

  @override
  State<ServiceDdnsView> createState() => _ServiceDdnsViewState();
}

class _ServiceDdnsViewState extends State<ServiceDdnsView> {
  final _tokenCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController(text: '5');

  bool _loading = false;
  bool _enabled = false;
  bool _hasToken = false;
  bool _showToken = false;
  bool _showAdvanced = false;
  bool _enableV4 = true;
  bool _enableV6 = true;
  bool _proxied = false;
  String _hostname = '';
  String _zoneName = '';
  String _ipv4 = '';
  String _ipv6 = '';
  String _lastRun = '';
  String _lastError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _hostCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final resp = await DdnsApiService.instance.getStatus();
      final data = resp.data;
      if (!resp.success || data == null || !mounted) return;
      setState(() {
        _hostCtrl.text = (data['hostname'] ?? '').toString();
        _hostname = _hostCtrl.text;
        _zoneName = (data['zoneName'] ?? '').toString();
        _intervalCtrl.text = (data['intervalMin'] ?? 5).toString();
        _enabled = data['enabled'] == true;
        _hasToken = data['hasToken'] == true;
        _enableV4 = data['enableV4'] != false;
        _enableV6 = data['enableV6'] != false;
        _proxied = data['proxied'] == true;
        _ipv4 = (data['lastIpv4'] ?? '').toString();
        _ipv6 = (data['lastIpv6'] ?? '').toString();
        _lastRun = (data['lastRunAt'] ?? '').toString();
        _lastError = (data['lastError'] ?? '').toString();
        if (_hasToken) _showToken = false;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      ToastUtil.show('请填写要映射的域名');
      return;
    }
    if (!_hasToken && _tokenCtrl.text.trim().isEmpty) {
      ToastUtil.show('请先填写你自己的 Cloudflare API Token');
      return;
    }
    setState(() => _loading = true);
    try {
      final resp = await DdnsApiService.instance.save(<String, dynamic>{
        'hostname': host,
        'enableV4': _enableV4,
        'enableV6': _enableV6,
        'proxied': _proxied,
        'intervalMin': int.tryParse(_intervalCtrl.text.trim()) ?? 5,
        if (_tokenCtrl.text.trim().isNotEmpty) 'apiToken': _tokenCtrl.text.trim(),
      });
      if (!mounted) return;
      _tokenCtrl.clear();
      await _load();
      ToastUtil.show(
        resp.success ? (resp.message ?? '已启用') : (resp.message ?? '启用失败'),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disable() async {
    setState(() => _loading = true);
    try {
      final resp = await DdnsApiService.instance.disable();
      if (!mounted) return;
      await _load();
      ToastUtil.show(resp.success ? 'DDNS 已停用' : (resp.message ?? '停用失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runNow() async {
    setState(() => _loading = true);
    try {
      final resp = await DdnsApiService.instance.runNow();
      if (!mounted) return;
      await _load();
      ToastUtil.show(
        resp.success ? '同步完成' : (resp.message ?? '同步失败'),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statusRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部状态横幅：一眼看出 DDNS 是否正常运行
  Widget _buildStatusBanner() {
    final theme = Theme.of(context);
    final bool ok = _enabled && _hasToken && _hostname.isNotEmpty;
    final Color color;
    final String text;
    if (ok) {
      color = const Color(0xFF2EA043);
      text = 'DDNS 正常运行';
    } else if (_enabled) {
      color = const Color(0xFFD29922);
      text = '已启用，但 Token 或域名不完整';
    } else {
      color = theme.colorScheme.onSurfaceVariant;
      text = 'DDNS 未启用';
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
          if (_hostname.isNotEmpty)
            Flexible(
              child: Text(
                _hostname,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

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
              if (widget.showTitle) ...[
                Text(
                  'DDNS',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '把本机公网 IP 自动写进你自己的 Cloudflare 域名解析（独立功能，与内网穿透无关）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _buildStatusBanner(),
              const SizedBox(height: 12),
              CustomGlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _hostCtrl,
                        enabled: !_loading,
                        keyboardType: TextInputType.url,
                        onChanged: (v) => setState(() => _hostname = v.trim()),
                        decoration: InputDecoration(
                          labelText: '要映射的域名',
                          hintText: '例如 home.example.com',
                          helperText: '填完整域名即可，根域名和记录名会自动判断；支持你账号下任意 Cloudflare 域名',
                          helperMaxLines: 2,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (_hasToken && !_showToken)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: Color(0xFF2EA043),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cloudflare Token 已配置（不回显）',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => setState(() => _showToken = true),
                              child: const Text('更换'),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: _tokenCtrl,
                          enabled: !_loading,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Cloudflare API Token',
                            hintText: '你自己的 Token，只填一次',
                            helperText: 'Cloudflare 后台「我的个人资料 → API 令牌」创建，权限勾 Zone:Read + DNS:Edit',
                            helperMaxLines: 2,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: _loading ? null : _save,
                          child: const Text('启用 / 保存'),
                        ),
                        OutlinedButton(
                          onPressed: _loading ? null : _runNow,
                          child: const Text('立即同步'),
                        ),
                        OutlinedButton(
                          onPressed: _loading ? null : _disable,
                          child: const Text('停用'),
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(
                                    () => _showAdvanced = !_showAdvanced,
                                  ),
                          child: Text(_showAdvanced ? '收起高级' : '高级设置'),
                        ),
                      ],
                    ),
                    if (_showAdvanced) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _intervalCtrl,
                              enabled: !_loading,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: '同步间隔',
                                suffixText: '分钟',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('同步 IPv4（A 记录）'),
                        value: _enableV4,
                        onChanged: _loading
                            ? null
                            : (v) => setState(() => _enableV4 = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('同步 IPv6（AAAA 记录）'),
                        subtitle: const Text('需要本机有可用公网 IPv6 出网'),
                        value: _enableV6,
                        onChanged: _loading
                            ? null
                            : (v) => setState(() => _enableV6 = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('走 Cloudflare 代理（小云朵）'),
                        subtitle: const Text('开启后记录变为 proxied，走 CF 边缘；纯 DDNS 一般不用开'),
                        value: _proxied,
                        onChanged: _loading
                            ? null
                            : (v) => setState(() => _proxied = v),
                      ),
                    ],
                    if (_loading) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CustomGlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前状态',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _statusRow('解析域名', _hostname),
                    _statusRow('所属 Zone', _zoneName),
                    _statusRow('公网 IPv4', _ipv4),
                    _statusRow('公网 IPv6', _ipv6),
                    _statusRow('上次同步', _lastRun),
                    if (_lastError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '最近错误：$_lastError',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
