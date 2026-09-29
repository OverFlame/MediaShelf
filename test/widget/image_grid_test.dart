import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:mediashelf/db/database.dart';
import 'package:mediashelf/db/folder_dao.dart';
import 'package:mediashelf/db/media_dao.dart';
import 'package:mediashelf/db/work_dao.dart';
import 'package:mediashelf/services/data_dir_service.dart';
import 'package:mediashelf/services/thumbnail_cache.dart';
import 'package:mediashelf/state/app_state.dart';
import 'package:mediashelf/state/player_controller.dart';
import 'package:mediashelf/theme/app_theme.dart';
import 'package:mediashelf/widgets/image_grid.dart';
import '../support/test_env.dart';


/// 1×1 的合法 PNG，给缩略图生成器一张能真解码的原图。
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 图片网格的界面交互测试。
///
/// 全部走真实手势。落库与缩略图生成走 sqflite/文件系统的真实 I/O，在 widget
/// 测试的假时钟里不会自己完成，所以写完库后用 [settleIo] 交替让出事件循环。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory albumDir;
  late Database db;
  late PlayerController player;
  late AppState app;
  late int albumId;

  /// 相册里三张图：1、2 没有别名，3 有别名「封面丙」。
  late List<int> imageIds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('mediashelf_image_grid');
    albumDir = await Directory(p.join(tmp.path, 'media', '相册')).create(recursive: true);
    PathProviderPlatform.instance =
        FakePathProvider(p.join(tmp.path, 'support'));
    DataDirService.instance.resetCache();
    await DatabaseManager.instance.close();
    await DatabaseManager.instance.init();
    db = DatabaseManager.instance.db;
    // thumbPath() 在 init() 之前会抛 LateInitializationError
    await ThumbnailService.instance
        .init(cacheDir: p.join(tmp.path, 'thumbs'));

    final work = await WorkDao(db).create('图片库', library: 'image');
    final album = await FolderDao(db)
        .create('相册', workId: work.id, library: 'image');
    albumId = album.id!;
    await FolderDao(db).addPath(albumId, albumDir.path);

    imageIds = [];
    final names = ['a.png', 'b.png', 'c.png'];
    for (var i = 0; i < names.length; i++) {
      final file = File(p.join(albumDir.path, names[i]));
      await file.writeAsBytes(_pngBytes);
      final id = await MediaDao(db).insertRow({
        'path': file.path,
        'media_type': 'image',
        'filename': names[i],
        'added_at': 1000 + i,
        'alias': i == 2 ? '封面丙' : null,
      });
      imageIds.add(id);
    }

    player = PlayerController();
    app = AppState(player: player);
    await app.init();
  });

  tearDown(() async {
    await DatabaseManager.instance.close();
    await tmp.delete(recursive: true);
  });

  Future<void> pumpGrid(WidgetTester tester) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<AppState>.value(value: app),
        ],
        child: const MaterialApp(home: Scaffold(body: ImageGrid())),
      ),
    );
  }

  /// runAsync 让真实 I/O 跑完，pump 让假时钟里的回调接着走。一次不够。
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// 进入相册（走真实 AppState 导航，属真实 I/O）
  Future<void> enterAlbum(WidgetTester tester) async {
    await tester.runAsync(() => app.enterFolder(albumId));
  }

  Finder tile(int id) => find.byKey(ValueKey('image-tile-$id'));

  testWidgets('网格按 app.images 渲染磁贴，标题别名优先', (tester) async {
    await enterAlbum(tester);
    await pumpGrid(tester);
    await settleIo(tester);

    expect(app.images.length, 3);
    for (final id in imageIds) {
      expect(tile(id), findsOneWidget);
    }
    // 无别名 → 显示文件名
    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('b.png'), findsOneWidget);
    // 有别名 → 只显示别名，不再显示文件名
    expect(find.text('封面丙'), findsOneWidget);
    expect(find.text('c.png'), findsNothing);
  });

  testWidgets('单击单选，Ctrl 加选，Shift 区间选', (tester) async {
    await enterAlbum(tester);
    await pumpGrid(tester);
    await settleIo(tester);

    // 磁贴同时挂了 onTap/onDoubleTap，单击要等双击判定超时才会派发
    Future<void> click(int id) async {
      await tester.tap(tile(id));
      await tester.pump(const Duration(milliseconds: 350));
    }

    // 单击第一张 → 单选
    await click(imageIds[0]);
    expect(app.selectedId, imageIds[0]);
    expect(app.selectedIds, {imageIds[0]});

    // Ctrl+单击第二张 → 加选
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await click(imageIds[1]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(app.selectedIds, {imageIds[0], imageIds[1]});

    // Shift+单击第三张 → 从锚点(第二张)到第三张的区间
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await click(imageIds[2]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(app.selectedIds, {imageIds[0], imageIds[1], imageIds[2]});
  });

  testWidgets('双击磁贴调用 openViewer 并把起始索引设为该图', (tester) async {
    await enterAlbum(tester);
    await pumpGrid(tester);
    await settleIo(tester);

    expect(app.showViewer, isFalse);

    await tester.tap(tile(imageIds[1]));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(tile(imageIds[1]));
    // 第二次按下会起一个双击判定定时器，pump 过去免得测试结束时报 pending timer
    await tester.pump(const Duration(milliseconds: 400));

    expect(app.showViewer, isTrue);
    expect(app.viewerIndex, 1);
    expect(app.viewerImages.length, 3);
  });

  testWidgets('空列表显示空态文案，不抛异常', (tester) async {
    // 不进入任何文件夹：中间栏既没有文件夹也没有图片
    await pumpGrid(tester);
    await settleIo(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('这里还没有内容'), findsOneWidget);
    expect(find.text('点下面的按钮添加图片文件夹'), findsOneWidget);
  });

  Future<void> pumpGridWithTheme(WidgetTester tester, ThemeData theme) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<AppState>.value(value: app),
        ],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: ImageGrid()),
        ),
      ),
    );
  }

  testWidgets('卡片底色跟着主题走：浅色下不再用深色 surface', (tester) async {
    await enterAlbum(tester);
    await pumpGridWithTheme(tester, AppColors.lightThemeData);
    await settleIo(tester);

    Color cardColor(int id) => ((tester.widget<Container>(find
                .descendant(of: tile(id), matching: find.byType(Container))
                .first))
            .decoration as BoxDecoration)
        .color!;

    expect(cardColor(imageIds[0]), AppColors.surfaceLight,
        reason: '浅色主题下卡片不能还是硬编码的深色 surface');

    await pumpGridWithTheme(tester, AppColors.darkThemeData);
    await settleIo(tester);
    expect(cardColor(imageIds[0]), AppColors.surface,
        reason: '深色主题保持原样');
  });
}
