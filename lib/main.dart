import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'db/database.dart';
import 'pages/home_page.dart';
import 'services/data_dir_service.dart';
import 'services/media_bridge.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';
import 'state/player_controller.dart';
import 'theme/app_theme.dart';
import 'utils/log_util.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 捕获未处理异常，避免启动失败时直接白屏
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logError('FlutterError', details.exceptionAsString(), details.stack?.toString());
  };

  try {
    await DataDirService.instance.init();
    await SettingsService.instance.init();
    await DatabaseManager.instance.init();

    final player = PlayerController();
    final appState = AppState(player: player);
    await appState.init();

    await MediaBridge.instance.init(player, appState);
    unawaited(MediaBridge.instance.ensureNotificationPermission());

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: player),
        ],
        child: const MediaShelfApp(),
      ),
    );
  } catch (e, st) {
    logError('Main', '启动失败', '$e\n$st');
    runApp(_ErrorApp(message: '$e'));
  }
}

class MediaShelfApp extends StatelessWidget {
  const MediaShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<AppState>().themeMode;
    return MaterialApp(
      title: 'MediaShelf',
      debugShowCheckedModeBanner: false,
      theme: AppColors.lightThemeData,
      darkTheme: AppColors.darkThemeData,
      themeMode: themeMode,
      home: const HomePage(),
    );
  }
}

/// 启动失败时显示的页面，替代白屏，便于定位问题
class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              '启动失败：\n\n$message',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
