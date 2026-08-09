import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/emby_models.dart';
import '../services/emby_client.dart';
import '../services/server_manager.dart';

/// 当前活跃的 Emby 服务器配置。
///
/// 内存中持有当前登录的服务器，[restore] 在应用启动时从
/// [ServerManager] 恢复上次会话；登录成功后由 [LoginNotifier] 调用
/// [setAndPersist] 写入；登出时调用 [logout] 清除。
final activeServerProvider =
    NotifierProvider<ActiveServerNotifier, EmbyServer?>(
  ActiveServerNotifier.new,
);

class ActiveServerNotifier extends Notifier<EmbyServer?> {
  @override
  EmbyServer? build() => null;

  /// 从本地存储恢复上次活跃的服务器配置。
  Future<void> restore() async {
    state = await ServerManager.instance.getActiveServer();
  }

  /// 设置当前活跃服务器并持久化。
  Future<void> setAndPersist(EmbyServer server) async {
    await ServerManager.instance.addServer(server);
    await ServerManager.instance.setActiveServer(server.id);
    state = server;
  }

  /// 登出当前服务器：从本地存储移除并清空内存状态。
  Future<void> logout() async {
    final current = state;
    if (current != null) {
      await ServerManager.instance.removeServer(current.id);
    }
    state = null;
  }
}

/// 当前可用的 [EmbyClient] 实例。
///
/// 派生自 [activeServerProvider]：当活跃服务器为 `null`（未登录）时
/// 返回 `null`，否则根据服务器配置构造一个新的客户端。
final embyClientProvider = Provider<EmbyClient?>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) return null;
  return EmbyClient(server);
});

/// 所有已保存的服务器列表。
///
/// 监听 [activeServerProvider] 以便在登录/登出后自动刷新列表。
final serversListProvider = FutureProvider<List<EmbyServer>>((ref) async {
  ref.watch(activeServerProvider);
  return ServerManager.instance.getServers();
});

/// 登录流程状态。
///
/// 通过 [login] 方法触发登录，状态在 [AsyncLoading] / [AsyncData] /
/// [AsyncError] 之间切换。登录成功时会自动设置 [activeServerProvider]，
/// 从而驱动根路由切换到首页。
final loginProvider =
    AsyncNotifierProvider<LoginNotifier, void>(LoginNotifier.new);

class LoginNotifier extends AsyncNotifier<void> {
  @override
  void build() {}

  /// 使用服务器地址、用户名、密码登录。
  ///
  /// 成功后构造 [EmbyServer] 并持久化为活跃服务器。
  Future<void> login(String url, String username, String password) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() async {
      final deviceId = const Uuid().v4();
      final authResult =
          await EmbyClient.login(url, username, password, deviceId);
      final user = authResult.user;
      if (user == null) {
        throw StateError('登录响应缺少用户信息');
      }
      final server = EmbyServer(
        id: user.id,
        url: url,
        name: user.name,
        userId: user.id,
        token: authResult.accessToken,
        deviceId: deviceId,
        username: username,
      );
      await ref.read(activeServerProvider.notifier).setAndPersist(server);
    });
  }
}
