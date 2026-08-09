import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// OTA 更新服务（启动时检查 + 手动检查）。
class OtaService {
  static const String _releaseUrl =
      'https://api.github.com/repos/xmfx11/emby-player/releases/latest';

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
              _downloadUpdate(context, info);
            },
            child: const Text('下载更新'),
          ),
        ],
      ),
    );
  }

  static void _downloadUpdate(BuildContext context, OtaInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        double progress = 0;
        var started = false;
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            if (!started) {
              started = true;
              _doDownload(info.apkUrl, (p) => setLocalState(() => progress = p));
            }
            return AlertDialog(
              title: const Text('正在下载更新…'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _doDownload(
      String url, void Function(double) onProgress) async {
    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}/emby-player-update.apk';
    final dio = Dio();
    await dio.download(url, path, onReceiveProgress: (received, total) {
      if (total > 0) onProgress(received / total);
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
