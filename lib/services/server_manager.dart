import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/emby_models.dart';

/// Emby 服务器配置管理器（单例）。
///
/// 使用 [SharedPreferences] 持久化多个 [EmbyServer] 配置。
/// - 服务器列表存储于 key `emby_servers`（JSON 字符串）。
/// - 当前活跃服务器 Id 存储于 key `emby_active_server`。
class ServerManager {
  ServerManager._();

  static final ServerManager _instance = ServerManager._();

  /// 获取单例实例。
  static ServerManager get instance => _instance;

  static const String _serversKey = 'emby_servers';
  static const String _activeServerKey = 'emby_active_server';

  SharedPreferences? _prefs;

  /// 获取（必要时初始化）SharedPreferences 实例并缓存。
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 添加或更新服务器配置。
  ///
  /// 若已存在相同 [EmbyServer.id] 的配置，则覆盖更新；否则追加。
  /// 若当前没有活跃服务器，则自动将新增服务器设为活跃。
  Future<void> addServer(EmbyServer server) async {
    final prefs = await _getPrefs();
    final servers = await getServers();

    final index = servers.indexWhere((s) => s.id == server.id);
    if (index >= 0) {
      servers[index] = server;
    } else {
      servers.add(server);
    }
    await _writeServers(prefs, servers);

    // 首次添加时自动设为活跃。
    final activeId = prefs.getString(_activeServerKey);
    if (activeId == null || activeId.isEmpty) {
      await prefs.setString(_activeServerKey, server.id);
    }
  }

  /// 删除指定服务器。
  ///
  /// 若删除的正是当前活跃服务器，则在剩余服务器中自动选择第一个作为活跃；
  /// 若已无任何服务器，则清除活跃标记。
  Future<void> removeServer(String serverId) async {
    final prefs = await _getPrefs();
    final servers = await getServers();
    servers.removeWhere((s) => s.id == serverId);
    await _writeServers(prefs, servers);

    final activeId = prefs.getString(_activeServerKey);
    if (activeId == serverId) {
      if (servers.isNotEmpty) {
        await prefs.setString(_activeServerKey, servers.first.id);
      } else {
        await prefs.remove(_activeServerKey);
      }
    }
  }

  /// 获取所有已保存的服务器列表。
  Future<List<EmbyServer>> getServers() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_serversKey);
    if (raw == null || raw.isEmpty) return <EmbyServer>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <EmbyServer>[];
      return decoded
          .map((e) => EmbyServer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 数据损坏时返回空列表，避免崩溃。
      return <EmbyServer>[];
    }
  }

  /// 获取当前活跃服务器配置；若未设置或不存在则返回 null。
  Future<EmbyServer?> getActiveServer() async {
    final activeId = await _getActiveServerId();
    if (activeId == null || activeId.isEmpty) return null;

    final servers = await getServers();
    for (final s in servers) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  /// 设置当前活跃服务器。
  ///
  /// 该服务器必须已存在于列表中，否则抛出 [ArgumentError]。
  Future<void> setActiveServer(String serverId) async {
    final prefs = await _getPrefs();
    final servers = await getServers();
    final exists = servers.any((s) => s.id == serverId);
    if (!exists) {
      throw ArgumentError('服务器不存在: $serverId');
    }
    await prefs.setString(_activeServerKey, serverId);
  }

  /// 清除所有服务器配置与活跃标记。
  Future<void> clearAll() async {
    final prefs = await _getPrefs();
    await prefs.remove(_serversKey);
    await prefs.remove(_activeServerKey);
    _prefs = null;
  }

  // -------------------------------------------------------------------------
  // 内部辅助
  // -------------------------------------------------------------------------

  Future<String?> _getActiveServerId() async {
    final prefs = await _getPrefs();
    return prefs.getString(_activeServerKey);
  }

  Future<void> _writeServers(
    SharedPreferences prefs,
    List<EmbyServer> servers,
  ) async {
    final raw = jsonEncode(servers.map((s) => s.toJson()).toList());
    await prefs.setString(_serversKey, raw);
  }
}
