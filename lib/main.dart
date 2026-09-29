import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
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
    // 界面提示「详情见 logs 目录」，启动时就把文件 sink 挂上，
    // 否则用户按提示去找，目录永远是空的。
    LogUtil.attachFileSink(
        p.join(await DataDirService.instance.dataDir, 'logs'));
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

/// 系统自带文案（返回、复制、取消等）的本地化配置，[MediaShelfApp] 用这套。
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// 界面文案以中文为主，英文兜底。
const List<Locale> appSupportedLocales = <Locale>[Locale('zh'), Locale('en')];

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
      // 不加这段的话，返回、复制、取消这些系统自带的提示一律是英文
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appSupportedLocales,
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
              '启动失败：\n\n$message\n\n'
              '详情见应用数据目录下的 logs/ 文件夹'
              '（启动失败发生在数据目录就绪之前时，只有控制台输出）。',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
