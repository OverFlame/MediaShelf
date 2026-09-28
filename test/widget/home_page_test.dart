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
import 'package:mediashelf/db/tag_dao.dart';
import 'package:mediashelf/db/work_dao.dart';
import 'package:mediashelf/pages/home_page.dart';
import 'package:mediashelf/services/data_dir_service.dart';
import 'package:mediashelf/services/settings_service.dart';
import 'package:mediashelf/services/thumbnail_cache.dart';
import 'package:mediashelf/state/app_state.dart';
import 'package:mediashelf/state/player_controller.dart';
import 'package:mediashelf/widgets/folder_panel.dart';
import 'package:mediashelf/widgets/image_detail.dart';
import 'package:mediashelf/widgets/image_grid.dart';
import 'package:mediashelf/widgets/tag_panel.dart';
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
  late int videoFolderId;
  late int videoId;

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

    // 视频作品 + 一个带路径的视频虚拟文件夹 + 一个真实视频文件
    videoWorkId = (await WorkDao(db).create('视频库', library: 'video')).id!;
    final filmDir = await Directory(p.join(tmp.path, 'media', '片库'))
        .create(recursive: true);
    final clip = File(p.join(filmDir.path, 'a.mp4'));
    await clip.writeAsBytes(const <int>[0, 0, 0, 24]);
    final film = await FolderDao(db)
        .create('片库', workId: videoWorkId, library: 'video');
    videoFolderId = film.id!;
    await FolderDao(db).addPath(videoFolderId, filmDir.path);
    videoId = await MediaDao(db).insertRow({
      'path': clip.path,
      'media_type': 'video',
      'filename': 'a.mp4',
      'added_at': 2000,
    });

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
    expect(find.byKey(ValueKey('folder-tile-$albumFolderId')), findsNothing,
        reason: '作品层直接平铺媒体，入口文件夹不再多画一层同名磁贴');
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
    // 三个库各看各的：音频库不再混进图片、视频作品
    expect(find.byKey(ValueKey('work-card-$imageWorkId')), findsNothing);
  });

  testWidgets('视频库：文件夹面板与视频作品网格', (tester) async {
    await pumpHome(tester);
    await switchLibrary(tester, kVideoLibrary);

    expect(find.byType(FolderPanel), findsOneWidget);
    expect(find.text('全部视频'), findsOneWidget);
    expect(find.byKey(ValueKey('work-card-$videoWorkId')), findsOneWidget);
    expect(find.byKey(ValueKey('work-card-$audioWorkId')), findsNothing);
  });

  testWidgets('视频库：作品层平铺视频，进虚拟文件夹后也能列出本层视频', (tester) async {
    await pumpHome(tester);
    await switchLibrary(tester, kVideoLibrary);

    await tester.tap(find.byKey(ValueKey('work-card-$videoWorkId')));
    await tester.pump();
    await settleIo(tester);

    expect(find.byType(ImageGrid), findsOneWidget);
    expect(find.byKey(ValueKey('video-tile-$videoId')), findsOneWidget,
        reason: '作品层直接平铺作品里的视频');
    expect(find.byKey(ValueKey('folder-tile-$videoFolderId')), findsNothing,
        reason: '入口文件夹与作品同名，不再多画一层磁贴');

    // 左栏树进虚拟文件夹：视频库也要按 MediaType.video 查本层媒体
    await tester.tap(find.byKey(ValueKey('folder-$videoFolderId')));
    await tester.pump();
    await settleIo(tester);

    expect(app.currentFolderId, videoFolderId);
    expect(find.byKey(ValueKey('video-tile-$videoId')), findsOneWidget,
        reason: '文件夹层要能列出本层视频，而不是走曲目查询');
  });

  testWidgets('视频库：工具栏给标签筛选，卡片菜单能给视频打标签', (tester) async {
    late Tag trip;
    await tester.runAsync(() async {
      trip = await TagDao(db).insert(const Tag(name: '旅行', color: '#89b4fa'));
      // setUp 里的 init 已经读过标签，这里补一次，界面才看得到新标签
      await app.loadTags();
    });
    await pumpHome(tester);
    await switchLibrary(tester, kVideoLibrary);

    // 工具栏入口此前只给图片库，视频库现在也有
    await tester.tap(find.byKey(const ValueKey('video-toolbar-tags')));
    await tester.pumpAndSettle();
    expect(find.text('全部作品'), findsNothing,
        reason: '筛选对话框只给标签区，不露音频专用的导入与作品集');
    expect(find.text('搜索标签...'), findsOneWidget, reason: '筛选对话框应已打开');
    expect(find.text('选择包含音频的文件夹'), findsNothing,
        reason: '筛选对话框不露音频专用的导入段');
    expect(find.text('还没有标签'), findsNothing);

    // 命名空间为空的标签排在列表最后，懒构建下要先搜索
    await tester.enterText(find.byType(TextField).last, '旅行');
    await tester.pumpAndSettle();
    final tagRow = find.widgetWithText(InkWell, '旅行');
    expect(tagRow, findsOneWidget, reason: '搜索后标签行应可见');
    await tester.tap(tagRow);
    await tester.pumpAndSettle();
    expect(app.tagFilter.andTagIds, contains(trip.id));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('搜索标签...'), findsNothing, reason: '筛选对话框应已关闭');

    // 视频卡片的「标签...」走同一条 media_tags 通道
    await tester.tap(find.byKey(ValueKey('work-card-$videoWorkId')));
    await tester.pump();
    await settleIo(tester);
    // 磁贴上挂着双击手势，单击要等双击判定超时（约 300ms）后才发出
    await tester.tap(find.byKey(ValueKey('video-menu-$videoId')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('video-tags-menu-$videoId')));
    await tester.pump();
    // 打标签入口要先读一次已有标签（真实 I/O），再弹对话框
    await settleIo(tester);
    expect(find.text('为视频选择标签'), findsOneWidget);

    await tester.tap(find.text('旅行'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await settleIo(tester);

    final tags =
        await tester.runAsync(() => TagDao(db).getTagsForTrack(videoId));
    expect(tags!.map((t) => t.name).toList(), ['旅行']);
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

  testWidgets('图片库多选：长按进多选，全选后批量移除记录', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);
    await tester.tap(find.byKey(ValueKey('work-card-$imageWorkId')));
    await tester.pump();
    await settleIo(tester);

    expect(app.visualSelectionMode, isFalse);
    expect(find.byKey(const ValueKey('selection-select-all')), findsNothing,
        reason: '没有选中项时不显示选择条');

    // 长按磁贴进多选
    await tester.longPress(tile(imageIds.first));
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.visualSelectionMode, isTrue);
    expect(app.selectedIds, contains(imageIds.first));

    // 多选模式下单击是勾选，不打开查看器
    await tester.tap(tile(imageIds[1]));
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.showViewer, isFalse);
    expect(app.selectedIds, containsAll(imageIds));

    // 作品层 AppState 的 images 是空的（媒体行由 ImageGrid 自己查），
    // 「全选」要靠界面登记的可见项，不能把已选清空。
    expect(app.images, isEmpty);
    await tester.tap(find.byKey(const ValueKey('selection-select-all')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(app.selectedIds, containsAll(imageIds));

    await tester.tap(find.byKey(const ValueKey('selection-delete')));
    await settleIo(tester);
    expect(find.textContaining('从软件里移除选中的 2 项'), findsOneWidget);
    expect(find.textContaining('磁盘上的文件不会被删除'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '移除'));
    await settleIo(tester);

    for (final id in imageIds) {
      expect(tile(id), findsNothing, reason: '移除后网格里不该留着磁贴');
    }
    expect(app.visualSelectionMode, isFalse, reason: '删空后退出多选');
    final left = await tester
        .runAsync(() => MediaDao(db).queryByDirs([albumDir.path]));
    expect(left, isEmpty, reason: '库里只剩空结果');
    for (final name in ['a.png', 'b.png']) {
      expect(File(p.join(albumDir.path, name)).existsSync(), isTrue,
          reason: '移除记录不动磁盘文件');
    }
  });

  testWidgets('图片库左栏：文件夹 / 标签两个页签可切换', (tester) async {
    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);

    // 默认是文件夹页签
    expect(find.byType(FolderPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('image-left-tab-folders')), findsOneWidget);
    expect(find.byKey(const ValueKey('image-left-tab-tags')), findsOneWidget);

    // 切到标签页签：换成标签面板，文件夹面板让位
    await tester.tap(find.byKey(const ValueKey('image-left-tab-tags')));
    await tester.pump();
    await settleIo(tester);

    expect(find.byType(TagPanel), findsOneWidget, reason: '图片库也要有标签栏');
    expect(find.byType(FolderPanel), findsNothing);
    expect(find.byKey(const ValueKey('tag-expand-all')), findsOneWidget);

    // 视频库同样有两个页签，且各自记住自己的选择
    await switchLibrary(tester, kVideoLibrary);
    expect(find.byType(FolderPanel), findsOneWidget, reason: '视频库默认文件夹页签');
    await tester.tap(find.byKey(const ValueKey('video-left-tab-tags')));
    await tester.pump();
    await settleIo(tester);
    expect(find.byType(TagPanel), findsOneWidget);

    await switchLibrary(tester, kImageLibrary);
    expect(find.byType(TagPanel), findsOneWidget,
        reason: '回到图片库时保持上次选的标签页签');

    // 音频库没有文件夹页签，左栏直接就是标签面板
    await switchLibrary(tester, kAudioLibrary);
    expect(find.byType(TagPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-left-tab-tags')), findsNothing);
  });

  testWidgets('视觉库排序菜单：选反序后网格顺序真的跟着变', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);
    await tester.tap(find.byKey(ValueKey('work-card-$imageWorkId')));
    await tester.pump();
    await settleIo(tester);

    double xOf(int id) => tester.getTopLeft(tile(id)).dx;
    expect(
      xOf(imageIds[0]),
      lessThan(xOf(imageIds[1])),
      reason: '默认自然序 a.png 在前',
    );

    // 工具栏的排序入口：四个字段 + 反序
    await tester.tap(find.byKey(const ValueKey('image-toolbar-sort')));
    await tester.pumpAndSettle();
    expect(find.text('文件名'), findsOneWidget);
    expect(find.text('修改时间'), findsOneWidget);
    expect(find.text('文件大小'), findsOneWidget);
    expect(find.text('加入时间'), findsOneWidget);

    await tester.tap(find.text('改为降序'));
    await tester.pumpAndSettle();
    await settleIo(tester);

    expect(app.visualSortDescending, isTrue);
    expect(SettingsService.instance.imageSortDescending, isTrue, reason: '要落盘');
    expect(
      xOf(imageIds[0]),
      greaterThan(xOf(imageIds[1])),
      reason: '反序后 b.png 在前',
    );

    // 视频库有自己的排序入口
    await switchLibrary(tester, kVideoLibrary);
    expect(
      find.byKey(const ValueKey('video-toolbar-sort')),
      findsOneWidget,
      reason: '视频库也要能排序',
    );
  });

  testWidgets('视觉库工具栏：窄窗口下不会 RenderFlex 溢出', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpHome(tester);
    await switchLibrary(tester, kImageLibrary);

    // 500 是工具栏收进「更多」菜单的阈值，排序按钮加进来后阈值附近最容易溢出
    for (final width in [420.0, 440.0, 500.0, 560.0, 820.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pump();
      await settleIo(tester);
      expect(tester.takeException(), isNull, reason: '$width 宽下工具栏不该溢出');
    }
  });
}
