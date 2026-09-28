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
import 'package:mediashelf/services/thumbnail_cache.dart';
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
  Future<MediaItem> addImage(
    String name, {
    String? alias,
    int addedAt = 0,
    int? size,
    int? mtime,
  }) async {
    final path = p.join(photoDir, name);
    await mediaDao.insertRow(MediaItem(
      path: path,
      filename: name,
      mediaType: MediaType.image,
      addedAt: addedAt,
      fileSize: size,
      fileMtime: mtime,
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

  test('视频库文件夹层按视频类型装填，默认排除筛选不会把视频滤掉', () async {
    final videoDir =
        await Directory(p.join(tmp.path, 'video')).create(recursive: true);
    final videoWork = await workDao.create('片库', library: 'video');
    final videoFolder = await folderDao.create('片库',
        workId: videoWork.id, library: 'video');
    await folderDao.addPath(videoFolder.id!, videoDir.path);
    const rows = <(String, MediaType)>[
      ('a.mp4', MediaType.video),
      ('b.jpg', MediaType.image),
    ];
    for (final (name, type) in rows) {
      await mediaDao.insertRow(MediaItem(
        path: p.join(videoDir.path, name),
        filename: name,
        mediaType: type,
        addedAt: 0,
      ).toMap());
    }

    final app = AppState(player: PlayerController());
    // init() 会装标签并套用「字幕」默认排除筛选，筛选路径也要按视频类型查
    await app.init();
    await app.enterWork(videoWork.id!);
    expect(app.isVisualLibrary, isTrue);
    await app.enterFolder(videoFolder.id!);
    await settle();

    expect(app.images.map((i) => i.filename).toList(), ['a.mp4'],
        reason: '视频库只平铺视频；同一目录里的图片行不进来');
    expect(app.tracks, isEmpty, reason: '视频上下文不应填曲目列表');

    // 搜索同样按视频类型查：以前视频库的搜索落在曲目查询上，永远搜不到
    app.setSearchQuery('a.mp4');
    await settle();
    expect(app.images.map((i) => i.filename).toList(), ['a.mp4'],
        reason: '视频库搜索走 media 表的视频类型');
    app.setSearchQuery('');
    await settle();
  });

  test('视频打标签后能被标签筛选命中，也能被 NOT 排除', () async {
    final clipDir =
        await Directory(p.join(tmp.path, 'clips')).create(recursive: true);
    final work = await workDao.create('片库', library: 'video');
    final folder =
        await folderDao.create('片库', workId: work.id, library: 'video');
    await folderDao.addPath(folder.id!, clipDir.path);
    final tagged = await mediaDao.insertRow(MediaItem(
      path: p.join(clipDir.path, 'a.mp4'),
      filename: 'a.mp4',
      mediaType: MediaType.video,
      addedAt: 0,
    ).toMap());
    await mediaDao.insertRow(MediaItem(
      path: p.join(clipDir.path, 'b.mp4'),
      filename: 'b.mp4',
      mediaType: MediaType.video,
      addedAt: 1,
    ).toMap());
    final tag = await tagDao.insert(Tag(name: '旅行'));

    final app = AppState(player: PlayerController());
    await app.init();
    // 视频与图片共用 media_tags，打标签走 media id
    await app.setMediaTags(tagged, [tag]);
    expect((await app.getTagsForMedia(tagged)).map((t) => t.name), ['旅行']);

    await app.enterWork(work.id!);
    await app.enterFolder(folder.id!);
    await settle();
    expect(app.images.length, 2);

    app.toggleAndFilter(tag.id!);
    await settle();
    expect(app.images.map((i) => i.filename).toList(), ['a.mp4'],
        reason: 'AND 筛选要按 MediaType.video 查 media_tags');

    app.toggleAndFilter(tag.id!);
    app.toggleNotFilter(tag.id!);
    await settle();
    expect(app.images.map((i) => i.filename).toList(), ['b.mp4'],
        reason: 'NOT 筛选要能排除带标签的视频');
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

  test('视觉库排序：默认自然序，可切大小/修改时间/加入时间与反序', () async {
    final (work, folder) = await makeImageLibrary();
    // 文件名故意让「字符串序」与自然序相反（"10" < "2"），三个字段各给不同值
    await addImage('10.jpg', size: 100, mtime: 300, addedAt: 30);
    await addImage('2.jpg', size: 300, mtime: 100, addedAt: 10);
    await addImage('1.jpg', size: 200, mtime: 200, addedAt: 20);

    final app = AppState(player: PlayerController());
    await app.enterWork(work.id!);
    await app.enterFolder(folder.id!);
    await settle();

    List<String> names() => app.images.map((i) => i.filename).toList();

    expect(app.visualSortKey, 'name');
    expect(app.visualSortDescending, isFalse);
    expect(names(), [
      '1.jpg',
      '2.jpg',
      '10.jpg',
    ], reason: '默认自然序：sort_key 补零后 2 排在 10 前面');

    await app.setVisualSortKey('size');
    await settle();
    expect(names(), ['10.jpg', '1.jpg', '2.jpg'], reason: '按文件大小升序');

    await app.setVisualSortDescending(true);
    await settle();
    expect(names(), ['2.jpg', '1.jpg', '10.jpg'], reason: '反序');

    await app.setVisualSortKey('mtime');
    await settle();
    expect(names(), [
      '10.jpg',
      '1.jpg',
      '2.jpg',
    ], reason: '降序还开着：mtime 300/200/100');

    await app.setVisualSortDescending(false);
    await app.setVisualSortKey('added');
    await settle();
    expect(names(), ['2.jpg', '1.jpg', '10.jpg'], reason: '加入时间升序');

    // 落盘：设置项写进 SettingsService，重开也能读回
    expect(SettingsService.instance.imageSortKey, 'added');
    expect(SettingsService.instance.imageSortDescending, isFalse);
    final app2 = AppState(player: PlayerController());
    await app2.loadSettings();
    expect(app2.visualSortKey, 'added');
    expect(app2.visualSortDescending, isFalse);

    // 视频库单存一份，互不干扰
    expect(SettingsService.instance.videoSortKey, 'name');
    await SettingsService.instance.setVideoSortKey('mtime');
    expect(SettingsService.instance.videoSortKey, 'mtime');
    expect(SettingsService.instance.imageSortKey, 'added');

    // 未知字段被忽略，不会把界面带进无排序状态
    await app.setVisualSortKey('nonsense');
    expect(app.visualSortKey, 'added');
  });

  test('查看器翻页时「图片详情」跟着走', () async {
    final (work, folder) = await makeImageLibrary();
    for (var i = 0; i < 3; i++) {
      await addImage('img_$i.jpg');
    }

    final app = AppState(player: PlayerController());
    await app.enterWork(work.id!);
    await app.enterFolder(folder.id!);
    await settle();

    app.openViewer(app.images, 1);
    expect(app.selectedImage?.filename, 'img_1.jpg', reason: '打开查看器即选中当前页');

    app.navigateViewer(1);
    expect(
      app.selectedImage?.filename,
      'img_2.jpg',
      reason: '详情面板读的是 selectedImage，不同步就会停在上一次选中的图',
    );
    expect(app.selectedId, app.images[2].id);

    app.navigateViewer(-1);
    expect(app.selectedImage?.filename, 'img_1.jpg');
  });

  test('AppState.init() 初始化缩略图服务（回归：漏掉这步一张缩略图都不出）', () async {
    ThumbnailService.instance.resetForTest();
    expect(ThumbnailService.instance.isInitialized, isFalse);

    final app = AppState(player: PlayerController());
    await app.init();

    expect(ThumbnailService.instance.isInitialized, isTrue);
    expect(
      ThumbnailService.instance.cacheDir,
      contains('thumbnails'),
      reason: '缓存目录跟着数据目录走',
    );
    expect(Directory(ThumbnailService.instance.cacheDir).existsSync(), isTrue);
  });
}
