import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/server_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/ota_service.dart';

/// Material 3 亮色主题。
final ThemeData _lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.light,
  ),
);

/// Material 3 深色主题。
final ThemeData _darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark,
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 OTA 通知和后台检查
  await OtaService.initNotifications();
  OtaService.scheduleBackgroundCheck(); // fire-and-forget

  // 提前创建容器并恢复上次会话，避免在首帧闪烁登录页。
  final container = ProviderContainer();
  await container.read(activeServerProvider.notifier).restore();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Emby Player',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ThemeMode.system,
      home: const _Root(),
    );
  }
}

/// 根路由：根据登录状态在登录页与首页之间切换。
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(activeServerProvider);
    if (server == null) {
      return const LoginScreen();
    }
    return const HomeScreen();
  }
}
