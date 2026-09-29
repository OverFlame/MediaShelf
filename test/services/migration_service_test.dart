import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mediashelf/db/tables.dart';
import 'package:mediashelf/services/migration_service.dart';

import 'migration_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String srcA;
  late String srcB;
  late String dst;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mediashelf_migrate');
    srcA = '${dir.path}/audioshelf.db';
    srcB = '${dir.path}/pv2.db';
    dst = '${dir.path}/mediashelf.db';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// 造好两个完整老库。
  Future<void> buildBoth({String? extraTrackPath}) async {
    final a = await openOldDb(srcA, audioShelfTables);
    await seedAudioShelf(a, extraTrackPath: extraTrackPath);
    await a.close();
    final b = await openOldDb(srcB, pictureViewerTables);
    await seedPictureViewer(b);
    await b.close();
  }

  MigrationService service({bool overwrite = false, bool backup = false}) =>
      MigrationService(
        factory: databaseFactoryFfi,
        backupOldDbs: backup,
        overwriteDst: overwrite,
      );

  Future<Database> openDst() => databaseFactoryFfi.openDatabase(dst,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false));

  Future<List<Map<String, Object?>>> rows(
      Database db, String table, {List<String>? columns}) async {
    return db.query(table, columns: columns, orderBy: 'id');
  }

  test('两个老库并成一个库：行数、库归属、父子重映射与标签合并', () async {
    await buildBoth();

    final report = await service()
        .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);

    // AudioShelf 2 条 tags + PictureViewer2 1 条 → 收藏合并后还剩 2 条
    expect(report.rowCount('tags'), 2);
    expect(report.rowCount('works'), 1);
    expect(report.rowCount('folders'), 6);
    expect(report.rowCount('folder_paths'), 6);
    expect(report.rowCount('folder_tags'), 2);
    expect(report.rowCount('media'), 5);
    expect(report.rowCount('media_tags'), 4);
    expect(report.rowCount('play_history'), 1);
    expect(report.duplicatePaths, isEmpty);
    expect(report.skippedTables, isEmpty);

    final db = await openDst();
    try {
      // ── folders：两棵树各带自己的 library，父子关系跟着映射走 ──
      final byLibrary = <String, int>{};
      for (final row in await rows(db, 'folders', columns: ['library'])) {
        final key = '${row['library']}';
        byLibrary[key] = (byLibrary[key] ?? 0) + 1;
      }
      expect(byLibrary, {'audio': 3, 'image': 3});

      final parents = await db.rawQuery('''
        SELECT f.name AS name, p.name AS parent, f.library AS library
        FROM folders f INNER JOIN folders p ON p.id = f.parent
        WHERE f.name IN ('第1卷', '第1话')
      ''');
      final parentMap = <String, String>{
        for (final row in parents) '${row['name']}': '${row['parent']}',
      };
      expect(parentMap['第1卷'], '某系列');
      expect(parentMap['第1话'], '画集');

      // 音频侧节点挂在作品上，图片侧作品列为空
      final workIds = await db.rawQuery(
          "SELECT DISTINCT work_id FROM folders WHERE library = 'audio'");
      expect(workIds.length, 1);
      expect(workIds.first['work_id'], isNotNull);
      final imageWork = await db.rawQuery(
          "SELECT work_id FROM folders WHERE library = 'image'");
      expect(imageWork.every((row) => row['work_id'] == null), isTrue);

      // ── media：类型按扩展名判，ext 与 name_lower 派生 ──
      final media = await rows(db, 'media',
          columns: ['path', 'media_type', 'ext', 'name_lower']);
      expect(media.length, 5);
      final wav = media.firstWhere(
          (row) => '${row['path']}' == '/m/某系列/第2卷/b.WAV');
      expect(wav['media_type'], 'audio');
      expect(wav['ext'], '.wav');
      expect(wav['name_lower'], '/m/某系列/第2卷/b.wav');
      final png = media.firstWhere(
          (row) => '${row['path']}' == '/m/画集/第1话/002.PNG');
      expect(png['media_type'], 'image');
      expect(png['ext'], '.png');

      // 图片侧字段跟着过来
      final image = await db.rawQuery(
          "SELECT width, height, hash, note, alias FROM media WHERE path = '/m/画集/第1话/001.jpg'");
      expect(image.first['width'], 800);
      expect(image.first['height'], 1200);
      expect(image.first['hash'], 'hash-1');
      expect(image.first['note'], '首刷');
      expect(image.first['alias'], '封面');

      // ── 标签合并：两边同名的收藏只剩一条，两边的关联都指向它 ──
      final tags = await rows(db, 'tags', columns: ['namespace', 'name']);
      expect(tags.length, 2);
      final favorite = await db.rawQuery(
          "SELECT id FROM tags WHERE namespace = 'general' AND name = '收藏'");
      final favoriteId = favorite.first['id'];
      final linked = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM media_tags WHERE tag_id = ?', <Object?>[favoriteId]);
      // 音频侧两条 + 图片侧一条，都挂在合并后的同一条收藏上
      expect(linked.first['n'], 3);
      final kindTag = await db.rawQuery(
          "SELECT id FROM tags WHERE namespace = 'kind' AND name = 'audio'");
      final kindLinked = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM media_tags WHERE tag_id = ?',
          <Object?>[kindTag.first['id']]);
      expect(kindLinked.first['n'], 1);

      // ── play_history 的 track_id 换成新的 media_id ──
      final history = await db.rawQuery('''
        SELECT m.path AS path, h.played_at AS played_at
        FROM play_history h INNER JOIN media m ON m.id = h.media_id
      ''');
      expect(history.length, 1);
      expect(history.first['path'], '/m/某系列/第2卷/b.WAV');
      expect(history.first['played_at'], 3000);

      // ── folder_paths 的 folder_id 也换成了新 id ──
      final paths = await db.rawQuery('''
        SELECT f.library AS library, COUNT(*) AS n
        FROM folder_paths fp INNER JOIN folders f ON f.id = fp.folder_id
        GROUP BY f.library
      ''');
      final pathMap = <String, int>{
        for (final row in paths) '${row['library']}': row['n'] as int,
      };
      expect(pathMap, {'audio': 3, 'image': 3});
    } finally {
      await db.close();
    }
  });

  test('老库缺表或整个缺失：跳过并写日志，不中断迁移', () async {
    final a = await openOldDb(srcA, audioShelfTables,
        only: <String>['works', 'folders', 'folder_paths', 'tracks']);
    await a.insert('works', <String, Object?>{
      'id': 1,
      'name': '纯音频',
      'sort_order': 0,
      'created_at': 1,
    });
    await a.insert('folders',
        <String, Object?>{'id': 1, 'name': '纯音频', 'parent': null, 'work_id': 1});
    await a.insert('folder_paths',
        <String, Object?>{'folder_id': 1, 'path': '/m/纯音频', 'recursive': 1});
    await a.insert('tracks', <String, Object?>{
      'id': 1,
      'path': '/m/纯音频/a.mp3',
      'filename': 'a.mp3',
      'added_at': 2,
    });
    await a.close();
    // 图片老库整个不存在。

    final report = await service()
        .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);

    expect(report.skippedTables,
        containsAll(<String>['tags', 'folder_tags', 'track_tags', 'play_history']));
    expect(report.rowCount('media'), 1);
    expect(report.rowCount('folders'), 1);
    expect(
        report.notes.any((note) => note.contains('PictureViewer2 老库不存在')), isTrue);

    final db = await openDst();
    try {
      expect((await rows(db, 'media')).length, 1);
    } finally {
      await db.close();
    }
  });

  test('两个老库出现同一个 path：保留先到者并记进 duplicatePaths', () async {
    await buildBoth(extraTrackPath: '/m/画集/第1话/001.jpg');

    final report = await service()
        .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);

    expect(report.duplicatePaths, <String>['/m/画集/第1话/001.jpg']);
    expect(report.rowCount('media'), 4);
    expect(report.notes.any((note) => note.contains('保留先到者')), isTrue);
    // 源库记为音频、扩展名判成图片，要留下日志
    expect(report.notes.any((note) => note.contains('media_type 按扩展名判成 image')),
        isTrue);

    final db = await openDst();
    try {
      final row = await db.rawQuery(
          "SELECT media_type FROM media WHERE path = '/m/画集/第1话/001.jpg'");
      expect(row.single['media_type'], 'image');
      expect((await rows(db, 'media')).length, 4);
    } finally {
      await db.close();
    }
  });

  test('覆盖目标库之前先把它备份下来', () async {
    await buildBoth();
    await service().run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);
    final before = await File(dst).readAsBytes();

    final report = await service(overwrite: true)
        .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);

    expect(report.notes.any((n) => n.contains('目标库已备份到')), isTrue,
        reason: 'overwrite 会把目标库整个删掉，删之前必须留一份');
    final backupDirs = Directory(dir.path)
        .listSync()
        .whereType<Directory>()
        .where((d) => p.basename(d.path).startsWith('migration-backup-'))
        .toList();
    expect(backupDirs, isNotEmpty);
    final copies = backupDirs
        .expand((d) => d.listSync())
        .whereType<File>()
        .where((f) => p.basename(f.path) == p.basename(dst))
        .toList();
    expect(copies, isNotEmpty);
    expect(await copies.last.readAsBytes(), before);
  });

  test('目标库已有数据时中止，传 overwrite 才覆盖', () async {
    await buildBoth();

    final first = await service()
        .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);
    expect(first.rowCount('media'), 5);

    await expectLater(
      service().run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst),
      throwsA(isA<StateError>()),
    );

    final third = await service(overwrite: true)
        .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);
    expect(third.rowCount('media'), 5);

    final db = await openDst();
    try {
      // 覆盖后没有重复行
      expect((await rows(db, 'media')).length, 5);
      expect((await rows(db, 'tags')).length, 2);
    } finally {
      await db.close();
    }
  });

  test('迁移前把老库备份到 migration-backup-<时间戳>', () async {
    await buildBoth();

    final report = await service(backup: true)
        .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);

    expect(report.backupDir, isNotNull);
    final backups = Directory(dir.path)
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.contains('migration-backup-'))
        .toList();
    expect(backups.length, 1);
    final names = backups.single.listSync().map((e) => e.path.split('/').last).toSet();
    expect(names, containsAll(<String>['audioshelf.db', 'pv2.db']));
    // 老库本身没被动过
    expect(File(srcA).existsSync(), isTrue);
    expect(File(srcB).existsSync(), isTrue);
  });

  /// 造一个 v7 结构的目标库：先按当前建表语句建满，再拆掉 v8 补的两列、
  /// v9 补的播放位置列与 reading_progress，最后把 user_version 退回 7。
  Future<void> buildV7Dst() async {
    final db = await databaseFactoryFfi.openDatabase(
      dst,
      options: OpenDatabaseOptions(
        version: Tables.version,
        onCreate: (db, version) async {
          for (final sql in Tables.createStatements) {
            await db.execute(sql);
          }
        },
      ),
    );
    await db.execute('DROP INDEX IF EXISTS idx_media_subtitle_of');
    await db.execute('ALTER TABLE media DROP COLUMN subtitle_of');
    await db.execute('ALTER TABLE media DROP COLUMN is_default_subtitle');
    await db.execute('ALTER TABLE media DROP COLUMN play_position_ms');
    await db.execute('DROP TABLE IF EXISTS reading_progress');
    expect(await _userVersion(db), Tables.version,
        reason: '建出来时是当前版本号，下面才退到 7 造旧结构');
    await db.execute('PRAGMA user_version = 7');
    await db.close();
  }

  test('目标库已是 v7 结构时：迁移要把它补到 v8，不能只把版本号抬上去', () async {
    await buildBoth();
    await buildV7Dst();

    await service().run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);

    final db = await openDst();
    try {
      expect(await _userVersion(db), Tables.version);
      final columns = await _columns(db, 'media');
      expect(
          columns,
          containsAll(<String>[
            'subtitle_of',
            'is_default_subtitle',
            'play_position_ms',
          ]),
          reason: '迁移服务自己开的库也要跑 v8 与 v9 的 ALTER TABLE，'
              '否则库被盖上当前版本号、结构却停在 v7，应用再打开时不会补');
      expect(await _tableNames(db), contains('reading_progress'));
    } finally {
      await db.close();
    }
  });

  test('老库迁移过来的字幕与阅读进度相关表可用（v8 结构完整）', () async {
    await buildBoth();
    await buildV7Dst();

    await service().run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);

    final db = await openDst();
    try {
      // 结构齐了才能查：缺列时这两条都会抛 no such column。
      expect(await db.rawQuery('SELECT COUNT(*) c FROM reading_progress'),
          hasLength(1));
      expect(
          await db.rawQuery(
              'SELECT id FROM media WHERE is_default_subtitle = 0 LIMIT 1'),
          isNotNull);
    } finally {
      await db.close();
    }
  });
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.first.values.first as int?) ?? -1;
}

Future<List<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toList();
}

Future<List<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
  return rows.map((r) => r['name'] as String).toList();
}
