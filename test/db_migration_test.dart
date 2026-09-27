import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mediashelf/db/media_dao.dart';
import 'package:mediashelf/db/tables.dart';
import 'package:mediashelf/db/tag_dao.dart';
import 'package:mediashelf/db/track_dao.dart';
import 'package:mediashelf/db/work_dao.dart';
import 'package:mediashelf/utils/filter_expression.dart';

/// 建一个空的 v5 库。
///
/// v5 是合并后的第一版结构，老库不做就地升级（走第 8 节的导入流程），
/// 所以这里直接从 Tables.createStatements 建库，不再模拟 v2 -> v4 的旧链路。
Future<Database> openV5(String path) async {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: Tables.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: (db, version) async {
        for (final sql in Tables.createStatements) {
          await db.execute(sql);
        }
      },
    ),
  );
}

void main() {
  sqfliteFfiInit();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mediashelf_v5');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('v5 建库：media 四值、library 约束、路径唯一与过渡视图', () async {
    final db = await openV5('${dir.path}/v5.db');

    // ── 表与视图分离：tracks / images 是只读视图，不是表 ──
    final objs = await db.rawQuery(
        "SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view')");
    final tables = objs
        .where((r) => r['type'] == 'table')
        .map((r) => r['name'])
        .toSet();
    final views =
        objs.where((r) => r['type'] == 'view').map((r) => r['name']).toSet();
    expect(
        tables,
        containsAll([
          'works',
          'media',
          'folders',
          'folder_paths',
          'tags',
          'media_tags',
          'folder_tags',
          'play_history',
        ]));
    expect(tables, isNot(contains('tracks')));
    expect(tables, isNot(contains('images')));
    expect(views, {'tracks', 'images'});

    // ── media_type 四个值都能落库，第五个被 CHECK 挡掉 ──
    for (final type in MediaType.allValues) {
      await db.insert('media', {
        'path': '/m/$type.bin',
        'media_type': type,
        'filename': '$type.bin',
        'added_at': 1,
      });
    }
    expect(await db.query('media'), hasLength(4));
    await expectLater(
      db.insert('media', {
        'path': '/m/other.bin',
        'media_type': 'document',
        'filename': 'other.bin',
        'added_at': 1,
      }),
      throwsA(anything),
    );

    // ── works.library 只认 audio / video ──
    await db.insert('works',
        {'name': '专辑', 'library': 'audio', 'sort_order': 0, 'created_at': 1});
    await db.insert('works',
        {'name': '剧集', 'library': 'video', 'sort_order': 0, 'created_at': 1});
    await expectLater(
      db.insert('works',
          {'name': '图集', 'library': 'image', 'sort_order': 0, 'created_at': 1}),
      throwsA(anything),
    );

    // ── folders.library 只认 audio / image / video ──
    await db.insert('folders',
        {'name': '根', 'parent': null, 'library': 'audio', 'work_id': null});
    await expectLater(
      db.insert('folders', {
        'name': '字幕根',
        'parent': null,
        'library': 'subtitle',
        'work_id': null,
      }),
      throwsA(anything),
    );

    // ── media.path 唯一：同一个文件不会进两行 ──
    await expectLater(
      db.insert('media', {
        'path': '/m/audio.bin',
        'media_type': 'audio',
        'filename': 'audio.bin',
        'added_at': 2,
      }),
      throwsA(anything),
    );

    expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
    await db.close();
  });

  test('folder_paths 默认 recursive=1，唯一索引挡住重复路径', () async {
    final db = await openV5('${dir.path}/paths.db');
    await db.insert('folders', {'name': '根', 'library': 'audio'});
    await db
        .insert('folder_paths', {'folder_id': 1, 'path': '/m/x', 'recursive': 1});
    await db.insert('folder_paths', {'folder_id': 1, 'path': '/m/set'});
    final loose = (await db.query('folder_paths',
            where: 'path = ?', whereArgs: ['/m/set']))
        .single;
    expect(loose['recursive'], 1, reason: 'v5 起 folder_paths 默认递归');

    final dup = await db.insert(
        'folder_paths', {'folder_id': 1, 'path': '/m/x', 'recursive': 0},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    expect(dup, 0, reason: 'INSERT OR IGNORE 不该再插一行');
    expect(await db.query('folder_paths'), hasLength(2));

    await db.insert('folders', {'name': '另一个根', 'library': 'audio'});
    final other = await db.insert(
        'folder_paths', {'folder_id': 2, 'path': '/m/x'},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    expect(other, greaterThan(0), reason: '唯一约束只约束 (folder_id, path) 组合');
    await db.close();
  });

  test('MediaDao 补全 ext 与 name_lower，视图按类型分流', () async {
    final db = await openV5('${dir.path}/media.db');
    final media = MediaDao(db);

    await media.insertRow({
      'path': '/m/Album/A.MP3',
      'media_type': 'audio',
      'filename': 'A.MP3',
      'added_at': 1,
    });
    await media.insertRow({
      'path': '/m/Album/p.png',
      'media_type': 'image',
      'filename': 'p.png',
      'added_at': 1,
    });

    final item = await media.getByPath('/m/Album/A.MP3');
    expect(item, isNotNull);
    expect(item!.ext, '.mp3', reason: 'ext 统一小写且带点');
    expect(item.nameLower, '/m/album/a.mp3');
    expect(item.mediaType, MediaType.audio);

    expect(await db.query('tracks'), hasLength(1));
    expect((await db.query('images')).single['filename'], 'p.png');
    await expectLater(
      db.insert('tracks', {'path': '/x', 'filename': 'x', 'added_at': 1}),
      throwsA(anything),
      reason: '视图只读，写入必须走 media 表',
    );

    expect(await media.count(type: MediaType.audio), 1);
    expect(await media.count(), 2);
    expect(await media.existingPaths(['/m/Album/A.MP3', '/nope'],
        type: MediaType.audio), {'/m/Album/A.MP3'});
    expect(await media.existingPaths(['/m/Album/p.png'],
        type: MediaType.audio), isEmpty, reason: '类型不匹配不算已入库');

    // 文件删除：外键级联清掉标签关联与播放历史
    final imageId = (await media.getByPath('/m/Album/p.png'))!.id!;
    final tagId = await db.insert('tags', {'namespace': 'general', 'name': '风景'});
    await db
        .insert('media_tags', {'media_id': imageId, 'tag_id': tagId});
    await db.insert(
        'play_history', {'media_id': imageId, 'played_at': 10});
    await media.deleteByPaths(['/m/Album/p.png'], type: MediaType.image);
    expect(await db.query('media_tags'), isEmpty);
    expect(await db.query('play_history'), isEmpty);
    await db.close();
  });

  test('规则标签翻成列条件，普通标签仍走 media_tags', () async {
    final db = await openV5('${dir.path}/rules.db');
    final media = MediaDao(db);
    final tags = TagDao(db);
    final tracks = TrackDao(db);

    final a1 = await tracks.insert(
        TrackItem(path: '/m/a1.mp3', filename: 'a1.mp3', addedAt: 1));
    final a2 = await tracks.insert(
        TrackItem(path: '/m/a2.flac', filename: 'a2.flac', addedAt: 1));
    await media.insertRow({
      'path': '/m/p.png',
      'media_type': 'image',
      'filename': 'p.png',
      'added_at': 1,
    });

    // ── 翻译：kind 只看四个媒体类型，ext 只认字母数字且补点 ──
    expect(TagDao.ruleTagSql(TagRef('kind:audio')), "media_type = 'audio'");
    expect(TagDao.ruleTagSql(TagRef('kind:AUDIO')), "media_type = 'audio'");
    expect(TagDao.ruleTagSql(TagRef('ext:VTT')), "ext = '.vtt'");
    expect(TagDao.ruleTagSql(TagRef('ext:.flac')), "ext = '.flac'");
    expect(TagDao.ruleTagSql(TagRef('kind:document')), isNull);
    expect(TagDao.ruleTagSql(TagRef('ext:a b')), isNull);
    expect(TagDao.ruleTagSql(TagRef('general:纯音乐')), isNull);
    expect(TagDao.ruleTagSql(TagRef('kind:audio', quoted: true)), isNull,
        reason: '带引号的是普通标签名，不是规则');

    // ── 求值：音频筛选永远只看 audio，图片行不会混进来 ──
    expect(await tags.getTrackIdsByExpression('kind:audio', []), {a1, a2});
    expect(await tags.getTrackIdsByExpression('ext:mp3', []), {a1});
    expect(await tags.getTrackIdsByExpression('kind:audio&&ext:flac', []),
        {a2});
    expect(await tags.getTrackIdsByExpression('kind:audio&&!ext:mp3', []),
        {a2});
    expect(await tags.getTrackIdsByExpression('kind:image', []), isEmpty);

    // ── 普通标签仍然走 media_tags ──
    final fav = await tags.insert(const Tag(name: '收藏'));
    await tags.addTagToTrack(a2, fav.id!);
    expect(await tags.getTrackIdsByExpression('收藏', [fav]), {a2});
    expect(await tags.getTrackIdsByExpression('kind:audio&&收藏', [fav]),
        {a2});

    // ── 规则标签的定义行可以补齐，重复调用不产生重复行 ──
    await tags.ensureRuleTags(extNames: ['.mp3', 'vtt']);
    await tags.ensureRuleTags(extNames: ['.mp3', 'vtt']);
    final kinds = await tags.listByNamespace(TagDao.kindNamespace);
    final exts = await tags.listByNamespace(TagDao.extNamespace);
    expect(kinds.map((t) => t.name).toSet(), MediaType.allValues.toSet());
    expect(exts.map((t) => t.name).toSet(), {'mp3', 'vtt'});
    await db.close();
  });

  test('WorkDao.delete 在一个事务里摘归属并删作品', () async {
    final db = await openV5('${dir.path}/delete.db');

    final dao = WorkDao(db);
    final work = await dao.create('待删专辑');
    await db.insert('folders',
        {'name': '根', 'parent': null, 'work_id': work.id, 'library': 'audio'});
    await db.insert('folders',
        {'name': '子', 'parent': 1, 'work_id': work.id, 'library': 'audio'});

    await dao.delete(work.id!);

    expect(await dao.getById(work.id!), isNull, reason: '作品应已删除');
    final folders = await db.query('folders');
    expect(folders.length, 2, reason: '文件夹不该被删，只该摘归属');
    for (final f in folders) {
      expect(f['work_id'], isNull);
    }

    await db.close();
  });
}
