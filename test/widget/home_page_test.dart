import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
import 'package:mediashelf/pages/home_page.dart';
import 'package:mediashelf/services/data_dir_service.dart';
import 'package:mediashelf/services/thumbnail_cache.dart';
import 'package:mediashelf/state/app_state.dart';
import 'package:mediashelf/state/player_controller.dart';
import 'package:mediashelf/widgets/folder_panel.dart';
import 'package:mediashelf/widgets/image_detail.dart';
import 'package:mediashelf/widgets/image_grid.dart';
import 'package:mediashelf/widgets/works_grid.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// 目录选择打桩：一律当作用户取消，不弹真实对话框、不碰平台通道。
/// 用例只验证「按钮点得动、点了不抛异常」，不验证真的导入。
class _FakeFilePicker extends FilePickerPlatform {
  int directoryCalls = 0;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    directoryCalls++;
    return null;
  }
}

/// 主界面（HomePage）的库切换与图片/视频库面板用例。
///
/// 全程用 `tester.tap` 点真实按钮。sqflite ffi 在独立 isolate 上跑，
/// testWidgets 里必须用 `tester.runAsync` 包住建库与造数据（见 [settleIo]）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

  late Directory tmp;
  late Directory albumDir;
  late Database db;
  late PlayerController player;
  late AppState app;
  late _FakeFilePicker picker;

  late int audioWorkId;
  late int imageWorkId;
  late int albumFolderId;
  late List<int> imageIds;
  late int videoWorkId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('mediashelf_home_page');
    albumDir = await Directory(p.join(tmp.path, 'media', '相册'))
        .create(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(p.join(tmp.path, 'support'));
    DataDirService.instance.resetCache();
    await DatabaseManager.instance.close();
    await DatabaseManager.instance.init();
    db = DatabaseManager.instance.db;
    await ThumbnailService.instance
        .init(cacheDir: p.join(tmp.path, 'thumbs'));
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;

    // 音频作品（切回音频库时要能看到它）
    audioWorkId = (await WorkDao(db).create('音频库', library: 'audio')).id!;

    // 视频作品 + 一个视频虚拟文件夹（文件夹面板才有「全部视频」这一层）
    videoWorkId = (await WorkDao(db).create('视频库', library: 'video')).id!;
    await FolderDao(db).create('片库', workId: videoWorkId, library: 'video');

    // 图片作品 + 一个带路径的虚拟文件夹 + 两张真实图片
    imageWorkId = (await WorkDao(db).create('图片库', library: 'image')).id!;
    final album = await FolderDao(db)
        .create('相册', workId: imageWorkId, library: 'image');
    albumFolderId = album.id!;
    await FolderDao(db).addPath(albumFolderId, albumDir.path);

    imageIds = [];
    for (final name in ['a.png', 'b.png']) {
      final f = File(p.join(albumDir.path, name));
      await f.writeAsBytes(pngBytes);
      imageIds.add(await MediaDao(db).insertRow({
        'path': f.path,
        'media_type': 'image',
        'filename': name,
        'added_at': 1000 + imageIds.length,
      }));
    }

    player = PlayerController();
    app = AppState(player: player);
    await app.init();
  });

  tearDown(() async {
    await DatabaseManager.instance.close();
    await tmp.delete(recursive: true);
  });

  /// 界面回调里的真实 I/O 要交替让出事件循环：runAsync 让真实 I/O 跑完，
  /// pump 让假时钟里的回调接着往下走。
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<AppState>.value(value: app),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await settleIo(tester);
  }

  /// 点顶部库切换条
  Future<void> switchLibrary(WidgetTester tester, String lib) async {
    await tester.tap(find.byKey(ValueKey('library-tab-$lib')));
    await tester.pump();
    await settleIo(tester);
  }

  Finder tile(int id) => find.byKey(ValueKey('image-tile-$id'));

  testWidgets('切到图片库：出现文件夹面板与作品网格', (tester) async {
    await pumpHome(tester);

    // 初始在音频库：标签面板 + 全部作品
    expect(find.byType(WorksGrid), findsOneWidget);
    expect(find.byKey(ValueKey('work-card-$audioWorkId')), findsOneWidget);
    expect(find.byType(FolderPanel), findsNothing);

    await switchLibrary(tester, kImageLibrary);

    expect(find.byType(FolderPanel), findsOneWidget);
    expect(find.text('全部图片'), findsOneWidget);
    expect(find.byType(WorksGrid), findsOneWidget);
    // 只列图片作品，音频作品不出现
    expect(find.byKey(ValueKey('work-card-$imageWorkId')), findsOneWidget);
    expect(find.byKey(ValueKey('work-card-$audioWorkId')), findsNothing);
  });

  testWidgets('进入图片作品后网格渲染出图片磁贴', (tester) async {
    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);

    await tester.tap(find.byKey(ValueKey('work-card-$imageWorkId')));
    await tester.pump();
    await settleIo(tester);

    expect(find.byType(ImageGrid), findsOneWidget);
    for (final id in imageIds) {
      expect(tile(id), findsOneWidget, reason: '作品层就该看到作品里的图片');
    }
    expect(find.byKey(ValueKey('folder-tile-$albumFolderId')), findsOneWidget);
  });

  testWidgets('双击磁贴后 showViewer 为真', (tester) async {
    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);
    await tester.tap(find.byKey(ValueKey('work-card-$imageWorkId')));
    await tester.pump();
    await settleIo(tester);

    expect(app.showViewer, isFalse);
    final id = imageIds.first;
    await tester.tap(tile(id));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(tile(id));
    await tester.pump(const Duration(milliseconds: 400));

    expect(app.showViewer, isTrue);
    expect(app.viewerImage?.id, id);

    app.closeViewer();
    await tester.pumpAndSettle();
  });

  testWidgets('图片库能打开单图详情面板', (tester) async {
    // 详情面板占 320 宽，窗口要给够，否则工具栏会走紧凑模式
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);
    await tester.tap(find.byKey(ValueKey('work-card-$imageWorkId')));
    await tester.pump();
    await settleIo(tester);

    expect(find.byType(ImageDetail), findsNothing);
    await tester.tap(find.byKey(const ValueKey('image-toolbar-detail')));
    await tester.pump();
    await settleIo(tester);
    expect(find.byType(ImageDetail), findsOneWidget);
  });

  testWidgets('切回音频库后音频作品网格仍在', (tester) async {
    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);
    expect(find.byKey(ValueKey('work-card-$imageWorkId')), findsOneWidget);

    await switchLibrary(tester, kAudioLibrary);

    expect(find.byType(WorksGrid), findsOneWidget);
    expect(find.byType(FolderPanel), findsNothing);
    expect(find.byKey(ValueKey('work-card-$audioWorkId')), findsOneWidget);
    // 音频库沿用「列出全部作品」的既有行为
    expect(find.byKey(ValueKey('work-card-$imageWorkId')), findsOneWidget);
  });

  testWidgets('视频库：文件夹面板与视频作品网格', (tester) async {
    await pumpHome(tester);
    await switchLibrary(tester, kVideoLibrary);

    expect(find.byType(FolderPanel), findsOneWidget);
    expect(find.text('全部视频'), findsOneWidget);
    expect(find.byKey(ValueKey('work-card-$videoWorkId')), findsOneWidget);
    expect(find.byKey(ValueKey('work-card-$audioWorkId')), findsNothing);
  });

  testWidgets('图片库空态出现「添加文件夹」入口，点击不抛异常', (tester) async {
    // 清空作品，模拟全新的图片库
    await tester.runAsync(() async {
      for (final w in await WorkDao(db).listAll()) {
        await WorkDao(db).delete(w.id!);
      }
      await app.refresh();
    });
    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);

    expect(find.text('还没有图片作品'), findsOneWidget);
    final addButtons = find.text('添加文件夹');
    expect(addButtons, findsWidgets);

    await tester.tap(find.byKey(const ValueKey('works-empty-add-folder')));
    await tester.pump();
    await settleIo(tester);

    expect(picker.directoryCalls, 1, reason: '应该真的走到目录选择入口');
    expect(tester.takeException(), isNull);
  });
}
