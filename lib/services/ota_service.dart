import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:workmanager/workmanager.dart';

/// 后台更新检查任务名。
const String _updateTaskName = 'com.emby.emby_player.ota_check';

/// OTA 更新服务。
class OtaService {
  static const String _releaseUrl =
      'https://api.github.com/repos/your-repo/emby-player/releases/latest';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// 初始化通知渠道（Android 13+ 必须）。
  static Future<void> initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(const InitializationSettings(android: android));
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// 注册后台定时检查（每 6 小时）。
  static Future<void> scheduleBackgroundCheck() async {
    await Workmanager().initialize(_callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      _updateTaskName,
      _updateTaskName,
      frequency: const Duration(hours: 6),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  /// 后台任务入口（顶层函数）。
  @pragma('vm:entry-point')
  static void _callbackDispatcher() {
    Workmanager().executeTask((taskName, inputData) async {
      if (taskName == _updateTaskName) {
        final info = await checkUpdate();
        if (info != null) {
          await _showUpdateNotification(info);
        }
      }
      return Future.value(true);
    });
  }

  /// 显示更新通知。
  static Future<void> _showUpdateNotification(OtaInfo info) async {
    const android = AndroidNotificationDetails(
      'ota_channel',
      '版本更新',
      channelDescription: 'Emby Player 版本更新提醒',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _notifications.show(
      0,
      '发现新版本 ${info.version}',
      '点击下载更新（${info.sizeText}）',
      const NotificationDetails(android: android),
    );
  }

  /// 检查更新，返回更新信息或 null。
  static Future<OtaInfo?> checkUpdate() async {
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
        return OtaInfo(
          version: latestVersion,
          apkUrl: apkUrl,
          size: size ?? 0,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 下载并安装 APK。
  static Future<void> downloadAndInstall(
    String url,
    void Function(double) onProgress,
  ) async {
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

  /// 启动时检查更新（无通知，仅在主页弹窗）。
  static Future<void> checkOnStartup(BuildContext context) async {
    final info = await checkUpdate();
    if (info == null || !context.mounted) return;
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
              _showDownloadDialog(context, info);
            },
            child: const Text('下载更新'),
          ),
        ],
      ),
    );
  }

  static void _showDownloadDialog(BuildContext context, OtaInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        double progress = 0;
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            downloadAndInstall(info.apkUrl, (p) {
              setLocalState(() => progress = p);
            });
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
}

class OtaInfo {
  final String version;
  final String apkUrl;
  final int size;

  OtaInfo({required this.version, required this.apkUrl, required this.size});

  String get sizeText =>
      size > 1024 * 1024
          ? '${(size / 1024 / 1024).toStringAsFixed(1)}MB'
          : '${(size / 1024).toStringAsFixed(0)}KB';
}
