import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// OTA 更新服务（启动时检查 + 手动检查 + 下载速度显示）。
class OtaService {
  static const String _releaseUrl =
      'https://api.github.com/repos/xmfx11/emby-player/releases/latest';

  /// GitHub 下载加速镜像（按顺序尝试）。
  static const List<String> _mirrors = [
    'https://ghproxy.com/',
    'https://gh.api.99988866.xyz/',
    'https://github.moeyy.xyz/',
  ];

  static String? _cachedApkUrl;

  /// 启动时检查更新，有新版本则弹窗。
  static Future<void> checkOnStartup(BuildContext context) async {
    final info = await _checkUpdate();
    if (info == null || !context.mounted) return;
    _showUpdateDialog(context, info);
  }

  /// 手动检查更新（设置页调用）。
  static Future<void> checkManual(BuildContext context) async {
    final info = await _checkUpdate();
    if (!context.mounted) return;
    if (info != null) {
      _showUpdateDialog(context, info);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版本')),
      );
    }
  }

  static Future<OtaInfo?> _checkUpdate() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final response = await dio.get(_releaseUrl);
      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? 'v1.0.0';
      final assets = data['assets'] as List<dynamic>? ?? [];
      String? apkUrl;
      int? size;
      for (final a in assets) {
        final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          size = a['size'] as int?;
          break;
        }
      }
      if (apkUrl == null) return null;

      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      final latestVersion = tagName.replaceAll('v', '');

      if (_compareVersion(latestVersion, currentVersion) > 0) {
        _cachedApkUrl = apkUrl;
        return OtaInfo(version: latestVersion, apkUrl: apkUrl, size: size ?? 0);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static void _showUpdateDialog(BuildContext context, OtaInfo info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('版本 ${info.version}（${info.sizeText}），是否下载更新？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadWithSpeed(context, info);
            },
            child: const Text('下载更新'),
          ),
        ],
      ),
    );
  }

  /// 下载对话框（显示实时速度和进度）。
  static void _downloadWithSpeed(BuildContext context, OtaInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        double progress = 0;
        String speed = '0 KB/s';
        String status = '连接中…';
        var started = false;

        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            if (!started) {
              started = true;
              _downloadWithMirror(info, (p, s, st) {
                setLocalState(() {
                  progress = p;
                  speed = s;
                  status = st;
                });
              });
            }
            return AlertDialog(
              title: const Text('正在下载更新…'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text('${(progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    speed,
                    style: TextStyle(
                        fontSize: 13, color: Theme.of(ctx).colorScheme.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(status, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 下载（支持镜像回退），实时回调速度和状态。
  static Future<void> _downloadWithMirror(
      OtaInfo info, void Function(double, String, String) onProgress) async {
    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}/emby-player-update.apk';

    // 先尝试直连，再尝试镜像
    final urls = [info.apkUrl];
    for (final mirror in _mirrors) {
      urls.add('$mirror${info.apkUrl}');
    }

    for (final url in urls) {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 30),
        ));

        int lastReceived = 0;
        final lastTime = DateTime.now();

        await dio.download(url, path, onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final elapsed = now.difference(lastTime).inMilliseconds;
          if (elapsed > 500) {
            final bytesPerSec = (received - lastReceived) * 1000.0 / elapsed;
            final speedText = _formatSpeed(bytesPerSec);
            final p = total > 0 ? received / total : 0.0;
            final totalText = total > 0 ? _formatSize(total) : '?';

            onProgress(p, '$speedText / $totalText',
                url == info.apkUrl ? '直连下载' : '镜像加速中');
          }
        });

        await Process.run('am', [
          'start',
          '-a',
          'android.intent.action.VIEW',
          '-d',
          'file://$path',
          '-t',
          'application/vnd.android.package-archive',
        ]);
        return;
      } catch (e) {
        onProgress(0, '重试中…', '切换节点…');
        continue;
      }
    }

    onProgress(0, '下载失败', '请检查网络后重试');
  }

  static String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec > 1024 * 1024) {
      return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSec > 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }

  static String _formatSize(int bytes) {
    if (bytes > 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  static int _compareVersion(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList();
    final bParts = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av - bv;
    }
    return 0;
  }
}

class OtaInfo {
  final String version;
  final String apkUrl;
  final int size;

  OtaInfo({required this.version, required this.apkUrl, required this.size});

  String get sizeText => size > 1024 * 1024
      ? '${(size / 1024 / 1024).toStringAsFixed(1)}MB'
      : '${(size / 1024).toStringAsFixed(0)}KB';
}
