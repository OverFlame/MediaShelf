import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite/sqflite.dart';

import 'package:mediashelf/db/database.dart';
import 'package:mediashelf/db/folder_dao.dart';
import 'package:mediashelf/db/tag_dao.dart';
import 'package:mediashelf/db/track_dao.dart';
import 'package:mediashelf/services/data_dir_service.dart';
import 'package:mediashelf/state/app_state.dart';
import 'package:mediashelf/state/player_controller.dart';

/// 把 getApplicationSupportDirectory() 指到临时目录。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// 数据库一致性回归测试（报告第 16、19、20 项）。
///
/// 三个用例都按「旧实现必须失败」设计：
/// 旧 `getByPath` 不带 ORDER BY，同一个路径挂两个文件夹时返回哪一行由扫描顺序决定；
/// 旧 `deleteFolder` 只删文件夹行，落在里面的曲目变成搜得到、树里进不去的孤儿；
/// 旧批量打标签逐条 await，中途失败会留下半截关联。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Database db;
  late AppState state;
  late FolderDao folders;
  late TrackDao tracks;
  late TagDao tags;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audioshelf_consistency');
    PathProviderPlatform.instance =
        _FakePathProvider(p.join(tmp.path, 'support'));
    DataDirService.instance.resetCache();
    await DatabaseManager.instance.close();
    await DatabaseManager.instance.init();
    db = DatabaseManager.instance.db;
    folders = FolderDao(db);
    tracks = TrackDao(db);
    tags = TagDao(db);
    state = AppState(player: PlayerController());
    await state.init();
  });

  tearDown(() async {
    await DatabaseManager.instance.close();
    await tmp.delete(recursive: true);
  });

  Future<void> addTrack(String path) async {
    await tracks.insert(TrackItem(
      path: path,
      filename: p.basename(path),
      addedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<List<String>> allTrackPaths() async {
    final all = await tracks.queryAll();
    return all.map((t) => t.path).toList()..sort();
  }

  test('外键约束是开着的，下面的事务用例都靠它', () async {
    final row = await db.rawQuery('PRAGMA foreign_keys');
    expect(row.first.values.first, 1);
  });

  test('同一个路径挂在两个文件夹上时，getByPath 返回 id 最小的那个', () async {
    final low = await folders.create('先建的'); // id 1
    final high = await folders.create('后建的'); // id 2

    // 故意先插 id 大的那条 folder_paths：不给 ORDER BY 时它就更可能被 first 取到。
    await folders.addPath(high.id!, '/m/shared');
    await folders.addPath(low.id!, '/m/shared');

    final hit = await folders.getByPath('/m/shared');

    expect(hit, isNotNull);
    expect(hit!.id, low.id,
        reason: '导入时命中的文件夹必须稳定，不能由 SQLite 扫描顺序决定');
    expect(hit.name, '先建的');
  });

  test('删除文件夹时，只清理不再被别的文件夹覆盖的曲目', () async {
    final album = await folders.create('专辑');
    await folders.addPath(album.id!, '/m/album');
    final sub = await folders.create('子目录', parentId: album.id);
    await folders.addPath(sub.id!, '/m/album/sub');

    await addTrack('/m/album/1.mp3');
    await addTrack('/m/album/sub/2.mp3');

    await state.deleteFolder(album.id!);

    expect(await allTrackPaths(), ['/m/album/sub/2.mp3'],
        reason: '1.mp3 已失联要清掉，2.mp3 还被子文件夹的路径覆盖，必须留下');
    expect((await folders.getById(sub.id!))!.parentId, isNull,
        reason: '子文件夹上移为根级');
    expect(await folders.getPaths(album.id!), isEmpty,
        reason: '被删文件夹的路径映射应被 CASCADE 清掉');
    expect((await tracks.queryAll()).length, 1);
  });

  test('删除没有子文件夹的文件夹，其下曲目全部移出曲库', () async {
    final solo = await folders.create('独苗');
    await folders.addPath(solo.id!, '/m/solo');
    await addTrack('/m/solo/a.mp3');
    await addTrack('/m/solo/b.mp3');

    await state.deleteFolder(solo.id!);

    expect(await allTrackPaths(), isEmpty,
        reason: '没有别的路径能覆盖它们，留着就是孤儿行');
  });

  test('批量打标签中途失败会整体回滚', () async {
    await addTrack('/m/t/1.mp3');
    await addTrack('/m/t/2.mp3');
    final ok = await tags.insert(const Tag(name: '纯音乐'));
    // 不存在于 tags 表，插入 media_tags 时触发外键失败。
    const bogus = Tag(id: 999999, name: '不存在的标签');

    await expectLater(
      state.addTagsToTracks([1, 2], [ok, bogus]),
      throwsA(anything),
    );

    expect(await db.query('media_tags'), isEmpty,
        reason: '逐条 commit 的旧写法会留下 (track 1, 纯音乐) 这半条');
  });

  test('批量摘标签一次事务处理多条曲目', () async {
    await addTrack('/m/t/1.mp3');
    await addTrack('/m/t/2.mp3');
    final tag = await tags.insert(const Tag(name: '纯音乐'));

    await state.addTagsToTracks([1, 2], [tag]);
    expect((await db.query('media_tags')).length, 2);

    await state.removeTagsFromTracks([1, 2], [tag]);
    expect(await db.query('media_tags'), isEmpty);
  });

  test('文件夹递归打标签走同一批事务方法，且写到子文件夹曲目', () async {
    final root = await folders.create('合集');
    await folders.addPath(root.id!, '/m/set');
    await addTrack('/m/set/1.mp3');
    final tag = await tags.insert(const Tag(name: '收藏'));

    await state.addTagsToFolder(root.id!, [tag], recursive: true);

    final rows = await db.query('media_tags');
    expect(rows.length, 1);
    expect(rows.first['tag_id'], tag.id);
    expect((await db.query('folder_tags')).length, 1);
  });
}
