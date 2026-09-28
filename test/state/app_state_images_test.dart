import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mediashelf/db/database.dart';
import 'package:mediashelf/db/folder_dao.dart';
import 'package:mediashelf/db/media_dao.dart';
import 'package:mediashelf/db/tag_dao.dart';
import 'package:mediashelf/db/track_dao.dart';
import 'package:mediashelf/db/work_dao.dart';
import 'package:mediashelf/services/data_dir_service.dart';
import 'package:mediashelf/services/settings_service.dart';
import 'package:mediashelf/state/app_state.dart';
import 'package:mediashelf/state/player_controller.dart';

/// 把 getApplicationSupportDirectory() 指到临时目录。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late WorkDao workDao;
  late FolderDao folderDao;
  late MediaDao mediaDao;
  late TagDao tagDao;
  late TrackDao trackDao;
  late String photoDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mediashelf_images');
    PathProviderPlatform.instance =
        _FakePathProvider(p.join(tmp.path, 'support'));
    DataDirService.instance.resetCache();
    SettingsService.instance.resetForTest();
    await DatabaseManager.instance.close();
    await DatabaseManager.instance.init();

    final db = DatabaseManager.instance.db;
    workDao = WorkDao(db);
    folderDao = FolderDao(db);
    mediaDao = MediaDao(db);
    tagDao = TagDao(db);
    trackDao = TrackDao(db);
    photoDir = p.join(tmp.path, 'photos');
  });

  tearDown(() async {
    await DatabaseManager.instance.close();
    await tmp.delete(recursive: true);
  });

  Future<void> settle([int ms = 400]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// 造一个图片库作品 + 一个挂到 [photoDir] 的文件夹，返回 (work, folder)。
  Future<(Work, VirtualFolder)> makeImageLibrary() async {
    final work = await workDao.create('图库', library: 'image');
    final folder = await folderDao.create('照片',
        workId: work.id, library: 'image');
    await folderDao.addPath(folder.id!, photoDir);
    return (work, folder);
  }

  /// 往图片库插入一张图，返回落库后的行（含 id）。
  Future<MediaItem> addImage(String name, {String? alias}) async {
    final path = p.join(photoDir, name);
    await mediaDao.insertRow(MediaItem(
      path: path,
      filename: name,
      mediaType: MediaType.image,
      addedAt: 0,
      width: 100,
      height: 80,
      alias: alias,
    ).toMap());
    return (await mediaDao.getByPath(path))!;
  }

  test('图片库走图片查询，音频库仍走曲目查询（_loadCenter 分流）', () async {
    final (imgWork, imgFolder) = await makeImageLibrary();
    await addImage('b.jpg');
    await addImage('a.jpg');

    final audioWork = await workDao.create('曲库', library: 'audio');
    final audioFolder = await folderDao.create('专辑',
        workId: audioWork.id, library: 'audio');
    final audioDirPath = p.join(tmp.path, 'music');
    await folderDao.addPath(audioFolder.id!, audioDirPath);
    await trackDao.insert(TrackItem(
        path: p.join(audioDirPath, 'x.mp3'), filename: 'x.mp3', addedAt: 0));

    final app = AppState(player: PlayerController());

    await app.enterWork(imgWork.id!);
    expect(app.isImageLibrary, isTrue);
    await app.enterFolder(imgFolder.id!);
    await settle();

    expect(app.images.map((i) => i.filename).toList(), ['a.jpg', 'b.jpg'],
        reason: '图片库文件夹应平铺本层图片，按自然顺序');
    expect(app.totalCount, 2);
    expect(app.tracks, isEmpty, reason: '图片上下文不应填曲目列表');

    await app.enterWork(audioWork.id!);
    expect(app.isImageLibrary, isFalse);
    await app.enterFolder(audioFolder.id!);
    await settle();

    expect(app.tracks.map((t) => t.filename).toList(), ['x.mp3']);
    expect(app.images, isEmpty, reason: '音频上下文不应填图片列表');
    expect(app.totalCount, 0);
  });

  test('图片标签筛选（AND）只保留命中图片', () async {
    final (work, folder) = await makeImageLibrary();
    final a = await addImage('a.jpg');
    await addImage('b.jpg');
    final tag = await tagDao.insert(Tag(name: '风景'));
    await tagDao.addTagToImage(a.id!, tag.id!);

    final app = AppState(player: PlayerController());
    await app.enterWork(work.id!);
    await app.enterFolder(folder.id!);
    await settle();
    expect(app.images.length, 2);

    app.toggleAndFilter(tag.id!);
    await settle();

    expect(app.images.map((i) => i.filename).toList(), ['a.jpg']);
    expect(app.activeTagIds, {tag.id!});
    expect((await app.getImageTags(a.id!)).map((t) => t.name), ['风景']);
  });

  test('多选、范围选择与清空', () async {
    final (work, folder) = await makeImageLibrary();
    for (var i = 0; i < 5; i++) {
      await addImage('img_$i.jpg');
    }

    final app = AppState(player: PlayerController());
    await app.enterWork(work.id!);
    await app.enterFolder(folder.id!);
    await settle();

    final ids = app.images.map((i) => i.id!).toList();
    expect(ids.length, 5);

    app.selectImage(ids[1]);
    expect(app.selectedId, ids[1]);
    expect(app.selectedImage?.filename, 'img_1.jpg');
    expect(app.selectedIds, {ids[1]});

    app.toggleSelect(ids[3]);
    expect(app.selectedIds, {ids[1], ids[3]});
    expect(app.isSelected(ids[3]), isTrue);

    app.clearSelection();
    expect(app.selectedIds, isEmpty);
    expect(app.selectedId, isNull);
    expect(app.selectedImage, isNull);

    // 范围选择：锚点 ids[0]，扩到 ids[3] 应含中间两张
    app.toggleSelect(ids[0]);
    app.rangeSelect(ids[3]);
    expect(app.selectedIds, {ids[0], ids[1], ids[2], ids[3]});
  });

  test('查看器前后翻页到边界不越界', () async {
    final (work, folder) = await makeImageLibrary();
    for (var i = 0; i < 3; i++) {
      await addImage('img_$i.jpg');
    }

    final app = AppState(player: PlayerController());
    await app.enterWork(work.id!);
    await app.enterFolder(folder.id!);
    await settle();

    app.openViewer(app.images, 1);
    expect(app.showViewer, isTrue);
    expect(app.viewerImages.length, 3);
    expect(app.viewerImage?.filename, 'img_1.jpg');

    app.navigateViewer(-1);
    expect(app.viewerIndex, 0);
    app.navigateViewer(-1);
    expect(app.viewerIndex, 0, reason: '已在第一张，向前翻应不动');

    app.navigateViewer(1);
    app.navigateViewer(1);
    expect(app.viewerIndex, 2);
    app.navigateViewer(1);
    expect(app.viewerIndex, 2, reason: '已在最后一张，向后翻应不动');

    app.openViewer(app.images, 99);
    expect(app.viewerIndex, 2, reason: '起始索引越界应 clamp 到末张');

    app.closeViewer();
    expect(app.showViewer, isFalse);
    expect(app.viewerImages, isEmpty);
    expect(app.viewerImage, isNull);

    // 空列表不应崩：MediaShelf 版比 PV2 多了一条空判断
    app.openViewer(const [], 0);
    expect(app.showViewer, isTrue);
    expect(app.viewerIndex, 0);
    expect(app.viewerImage, isNull);
  });

  test('视图设置落盘后能读回，且按范围收敛', () async {
    final app = AppState(player: PlayerController());
    await app.setGridColumns(6);
    await app.setViewMode('list');
    await app.setCacheSizeMB(1024);

    expect(app.gridColumns, 6);
    expect(app.viewMode, 'list');
    expect(app.cacheSizeMB, 1024);

    // 读回：清掉内存后从 settings.json 重新加载
    final ss = SettingsService.instance;
    await ss.init();
    final app2 = AppState(player: PlayerController());
    await app2.loadSettings();
    await app2.loadCoverCacheLimit();

    expect(app2.gridColumns, 6);
    expect(app2.viewMode, 'list');
    expect(app2.cacheSizeMB, 1024);
    expect(ss.gridColumns, 6);
    expect(ss.viewMode, 'list');
    expect(ss.coverCacheLimitMB, 1024);

    // clamp：列数 2..10，未知 viewMode 归一为 grid
    await app.setGridColumns(99);
    expect(app.gridColumns, 10);
    await app.setGridColumns(0);
    expect(app.gridColumns, 2);
    await app.setViewMode('weird');
    expect(app.viewMode, 'grid');
  });
}
